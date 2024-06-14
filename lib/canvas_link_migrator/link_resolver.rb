# frozen_string_literal: true

#
# Copyright (C) 2015 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

require "active_support/core_ext/object"
require "addressable"
require "rack"

module CanvasLinkMigrator
  class LinkResolver
    attr_accessor :migration_id_converter

    delegate :context_path, :attachment_path_id_lookup, to: :migration_id_converter

    def initialize(migration_id_converter)
      @migration_id_converter = migration_id_converter
    end

    def resolve_links!(link_map)
      link_map.each_value do |field_links|
        field_links.each_value do |links|
          links.each do |link|
            resolve_link!(link)
          end
        end
      end
    end

    def attachment_path_id_lookup_lower
      @attachment_path_id_lookup_lower ||= attachment_path_id_lookup&.transform_keys(&:downcase)
    end

    def add_verifier_to_query(url, uuid)
      parsed_url = Addressable::URI.parse(url)
      parsed_url.query_values = (parsed_url.query_values || {}).merge("verifier" => uuid)
      parsed_url.to_s
    rescue Addressable::InvalidURIError
      url
    end

    # finds the :new_value to use to replace the placeholder
    def resolve_link!(link)
      case link[:link_type]
      when :wiki_page
        if (linked_wiki_url = @migration_id_converter.convert_wiki_page_migration_id_to_slug(link[:migration_id]))
          link[:new_value] = "#{context_path}/pages/#{linked_wiki_url}#{link[:query]}"
        end
      when :discussion_topic
        if (linked_topic_id = @migration_id_converter.convert_discussion_topic_migration_id(link[:migration_id]))
          link[:new_value] = "#{context_path}/discussion_topics/#{linked_topic_id}#{link[:query]}"
        end
      when :module_item
        if (tag_id = @migration_id_converter.convert_context_module_tag_migration_id(link[:migration_id]))
          link[:new_value] = "#{context_path}/modules/items/#{tag_id}#{link[:query]}"
        end
      when :object
        type = link[:type]
        migration_id = link[:migration_id]

        type_for_url = type
        type = "context_modules" if type == "modules"
        type = "pages" if type == "wiki"
        if type == "pages"
          query = resolve_module_item_query(nil, link[:query])
          linked_wiki_url = @migration_id_converter.convert_wiki_page_migration_id_to_slug(migration_id) || migration_id
          link[:new_value] = "#{context_path}/pages/#{linked_wiki_url}#{query}"
        elsif type == "attachments"
          att_id, uuid = @migration_id_converter.convert_attachment_migration_id(migration_id)
          if att_id
            new_url = "#{context_path}/files/#{att_id}/preview"
            new_url = add_verifier_to_query(new_url, uuid) if uuid
            link[:new_value] = new_url
          end
        elsif type == "media_attachments_iframe"
          att_id, uuid = @migration_id_converter.convert_attachment_migration_id(migration_id)
          new_url = att_id ? "/media_attachments_iframe/#{att_id}#{link[:query]}" : link[:old_value]
          new_url = add_verifier_to_query(new_url, uuid) if uuid
          link[:new_value] = new_url
        else
          object_id = @migration_id_converter.convert_migration_id(type, migration_id)
          if object_id
            query = resolve_module_item_query(nil, link[:query])
            link[:new_value] = "#{context_path}/#{type_for_url}/#{object_id}#{query}"
          end
        end
      when :media_object
        # because we actually might change the node itself
        # this part is a little trickier
        # tl;dr we've replaced the entire node with the placeholder
        # see LinkParser for details
        rel_path = link[:rel_path]
        node = Nokogiri::HTML5.fragment(link[:old_value]).children.first
        new_url = resolve_media_data(node, rel_path)
        new_url ||= resolve_relative_file_url(rel_path)

        unless new_url
          new_url = rel_path.include?("#{context_path}/file_contents") ? rel_path : missing_relative_file_url(rel_path)
          link[:missing_url] = new_url
        end
        if ["iframe", "source"].include?(node.name)
          node["src"] = new_url
        else
          node["href"] = new_url
        end
        link[:new_value] = node.to_s
      when :file
        rel_path = link[:rel_path]
        new_url = resolve_relative_file_url(rel_path)
        # leave user urls alone
        new_url ||= rel_path if is_relative_user_url(rel_path)
        unless new_url
          new_url = missing_relative_file_url(rel_path)
          link[:missing_url] = new_url
        end
        link[:new_value] = new_url
      when :file_ref
        file_id, uuid = @migration_id_converter.convert_attachment_migration_id(link[:migration_id])
        if file_id
          rest = link[:rest].presence
          rest ||= "/preview" unless link[:target_blank]

          # Icon Maker files should not have the course
          # context prepended to the URL. This prevents
          # redirects to non cross-origin friendly urls
          # during a file fetch
          new_url = if rest&.include?("icon_maker_icon=1")
                      "/files/#{file_id}#{rest}"
                    elsif link[:in_media_iframe]
                      "/media_attachments_iframe/#{file_id}#{rest}"
                    else
                      "#{context_path}/files/#{file_id}#{rest}"
                    end
          new_url = add_verifier_to_query(new_url, uuid) if uuid
          link[:new_value] = new_url
        else
          link[:missing_url] = link[:old_value].partition("$CANVAS_COURSE_REFERENCE$").last
        end
      else
        raise "unrecognized link_type (#{link[:link_type]}) in unresolved link"
      end
    end

    def resolve_module_item_query(_context, query)
      return query unless query&.include?("module_item_id=")

      original_param = query.sub("?", "").split("&").detect { |p| p.include?("module_item_id=") }
      mig_id = original_param.split("=").last
      tag_id = @migration_id_converter.convert_context_module_tag_migration_id(mig_id)
      return query unless tag_id

      new_param = "module_item_id=#{tag_id}"
      query.sub(original_param, new_param)
    end

    def missing_relative_file_url(rel_path)
      # the rel_path should already be escaped
      File.join(URI::DEFAULT_PARSER.escape("#{context_path}/file_contents/#{@migration_id_converter.root_folder_name}"), rel_path.gsub(" ", "%20"))
    end

    def find_file_in_context(rel_path)
      mig_id = nil
      # This is for backward-compatibility: canvas attachment filenames are escaped
      # with '+' for spaces and older exports have files with that instead of %20
      alt_rel_path = rel_path.tr("+", " ")
      if attachment_path_id_lookup
        mig_id ||= attachment_path_id_lookup[rel_path]
        mig_id ||= attachment_path_id_lookup[alt_rel_path]
      end
      if !mig_id && attachment_path_id_lookup_lower
        mig_id ||= attachment_path_id_lookup_lower[rel_path.downcase]
        mig_id ||= attachment_path_id_lookup_lower[alt_rel_path.downcase]
      end

      # This md5 comparison is here to handle faulty cartridges with the migration_id equivalent of an empty string
      mig_id && mig_id != "gd41d8cd98f00b204e9800998ecf8427e" && @migration_id_converter.lookup_attachment_by_migration_id(mig_id)
    end

    def resolve_relative_file_url(rel_path)
      split = rel_path.split("?")
      qs = split.pop if split.length > 1
      path = split.join("?")

      # since we can't be sure whether a ? is part of a filename or query string, try it both ways
      new_url = resolve_relative_file_url_with_qs(path, qs)
      new_url ||= resolve_relative_file_url_with_qs(rel_path, "") if qs.present?
      new_url
    end

    def resolve_relative_file_url_with_qs(rel_path, qs)
      new_url = nil
      rel_path_parts = Pathname.new(rel_path).each_filename.to_a

      # e.g. start with "a/b/c.txt" then try "b/c.txt" then try "c.txt"
      while new_url.nil? && !rel_path_parts.empty?
        sub_path = File.join(rel_path_parts)
        if (file = find_file_in_context(sub_path))
          new_url = "#{context_path}/files/#{file["id"]}"
          # support other params in the query string, that were exported from the
          # original path components and query string. see
          # CCHelper::file_query_string
          params = Rack::Utils.parse_nested_query(qs.presence || "")
          qs = []
          qs << "verifier=#{file["uuid"]}" if file["uuid"].present?
          new_action = ""
          params.each do |k, v|
            case k
            when /canvas_qs_(.*)/
              qs << "#{Rack::Utils.escape($1)}=#{Rack::Utils.escape(v)}"
            when /canvas_(.*)/
              new_action += "/#{$1}"
            end
          end
          new_url += new_action.presence || "/preview"
          new_url += "?#{qs.join("&")}" if qs.present?
        end
        rel_path_parts.shift
      end
      new_url
    end

    def media_attachment_iframe_url(file_id, uuid = nil, media_type = nil)
      url = "/media_attachments_iframe/#{file_id}?embedded=true"
      url += "&type=#{media_type}" if media_type.present?
      url += "&verifier=#{uuid}" if uuid.present?
      url
    end

    def resolve_media_data(node, rel_path)
      if rel_path && (file = find_file_in_context(rel_path[/^[^?]+/])) # strip query string for this search
        media_id = file["media_entry_id"]
        node["data-media-id"] = media_id # safe to delete?
        media_attachment_iframe_url(file["id"], file["uuid"], node["data-media-type"])
      elsif rel_path&.match(/\/media_attachments_iframe\/\d+/)
        # media attachment from another course or something
        rel_path
      elsif (file_id, uuid = @migration_id_converter.convert_attachment_media_id(node["data-media-id"]))
        file_id ? media_attachment_iframe_url(file_id, uuid, node["data-media-type"]) : nil
      elsif (file_id, uuid = @migration_id_converter.convert_attachment_media_id(rel_path.match(/media_objects(?:_iframe)?\/([^?.]+)/)&.[](1)))
        file_id ? media_attachment_iframe_url(file_id, uuid, node["data-media-type"]) : nil
      else
        node.delete("class")
        node.delete("id")
        node.delete("style")
        nil
      end
    end

    def is_relative_user_url(rel_path)
      rel_path.start_with?("/users/")
    end
  end
end
