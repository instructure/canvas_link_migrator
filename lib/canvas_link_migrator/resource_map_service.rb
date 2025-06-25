# frozen_string_literal: true

#
# Copyright (C) 2023 - present Instructure, Inc.
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
module CanvasLinkMigrator
  # This class encapsulates the logic to retrieve metadata (for various types of assets)
  # given a migration id. This particular implementation relies on the migration object Canvas
  # creates
  #
  # Each function returns exactly one id (if available), and nil if an id
  # cannot be resolved
  #
  class ResourceMapService
    attr_reader :migration_data

    def initialize(migration_data)
      @migration_data = migration_data
    end

    def resources
      migration_data["resource_mapping"] || {}
    end

    ### Overwritable methods
    def supports_embedded_images
      false
    end

    def fix_relative_urls?
      true
    end

    def process_domain_substitutions(url)
      url
    end

    def context_hosts
      migration_data["destination_hosts"]
    end

    def attachment_path_id_lookup
      migration_data["attachment_path_id_lookup"]
    end

    def root_folder_name
      migration_data["destination_root_folder"]
    end
    ### End of Ovewritable methods

    # Returns the path for the context, for a course, it should return something like
    # "courses/1"
    def context_path
      "/courses/#{migration_data["destination_course"]}"
    end

    # Looks up a wiki page slug for a migration id
    def convert_wiki_page_migration_id_to_slug(migration_id)
      resources.dig("wiki_pages", migration_id, "destination", "url") || resources.dig("pages", migration_id, "destination", "url")
    end

    # looks up a discussion topic
    def convert_discussion_topic_migration_id(migration_id)
      dt_id = resources.dig("discussion_topics", migration_id, "destination", "id")
      # the /discusson_topic url scheme is used for annnouncments as well.
      # we'll check both here
      dt_id || convert_announcement_migration_id(migration_id)
    end

    def convert_announcement_migration_id(migration_id)
      resources.dig("announcements", migration_id, "destination", "id")
    end

    def convert_context_module_tag_migration_id(migration_id)
      resources.dig("module_items", migration_id, "destination", "id")
    end

    def convert_attachment_migration_id(migration_id)
      resources.dig("files", migration_id, "destination")&.slice("id", "uuid")&.values
    end

    def media_map
      @media_map ||= resources["files"]&.each_with_object({}) do |(_mig_id, file), map|
        media_id = file.dig("source", "media_entry_id") if file.is_a?(Hash)
        next unless media_id
        map[media_id] = file
      end
    end

    def convert_attachment_media_id(media_id)
      media_map&.dig(media_id, "destination")&.slice("id", "uuid")&.values
    end

    def convert_migration_id(type, migration_id)
      type = "modules" if type == "context_modules"
      id = if CanvasLinkMigrator::LinkParser::KNOWN_REFERENCE_TYPES.include? type
             resources.dig(type, migration_id, "destination", "id")
           end
      return id if id.present?
      # the /discusson_topic url scheme is used for annnouncments as well.
      # we'll check both here
      convert_announcement_migration_id(migration_id) if type == "discussion_topics"
    end

    def lookup_attachment_by_migration_id(migration_id)
      resources.dig("files", migration_id, "destination")
    end
  end
end
