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
#

require "spec_helper"
require "json"

describe CanvasLinkMigrator::LinkResolver do
  def resolver(assets = JSON.parse(File.read("spec/fixtures/canvas_resource_map.json")))
    CanvasLinkMigrator::LinkResolver.new(CanvasLinkMigrator::ResourceMapService.new(assets))
  end

  describe "resolve_link!" do
    it "converts wiki_pages links" do
      link = { link_type: :wiki_page, migration_id: "A", query: "?foo=bar" }
      resolver.resolve_link!(link)
      expect(link[:new_value]).to eq("/courses/2/pages/slug-a?foo=bar")
    end

    it "converts wiki_pages links with pages in resource map" do
      link = { link_type: :wiki_page, migration_id: "A", query: "?foo=bar" }
      resolver(JSON.parse(File.read("spec/fixtures/canvas_resource_map_pages.json"))).resolve_link!(link)
      expect(link[:new_value]).to eq("/courses/2/pages/slug-a?foo=bar")
    end

    it "converts module_item links" do
      link = { link_type: :module_item, migration_id: "C", query: "?foo=bar" }
      resolver.resolve_link!(link)
      expect(link[:new_value]).to eq("/courses/2/modules/items/3?foo=bar")
    end

    it "converts file_ref urls" do
      link = { link_type: :file_ref, migration_id: "F" }
      resolver.resolve_link!(link)
      expect(link[:new_value]).to eq("/courses/2/files/6/preview?verifier=u6")
    end

    it "does not suffix /preview to target blank links" do
      link = { link_type: :file_ref, target_blank: true, migration_id: "F" }
      resolver.resolve_link!(link)
      expect(link[:new_value]).to eq("/courses/2/files/6?verifier=u6")
    end

    it "does not leave a trailing slash on the url with a `canvas_` query param" do
      link = {
        link_type: :file,
        migration_id: "F",
        rel_path: "subfolder/with a space/test.png?canvas_=1&amp;amp;canvas_qs_wrap=1" }

      resolver.resolve_link!(link)

      expect(link[:new_value]).to eq("/courses/2/files/6/preview?verifier=u6&wrap=1")
    end

    it "converts attachment urls" do
      link = { link_type: :object, type: "attachments", migration_id: "E", query: "?foo=bar" }
      resolver.resolve_link!(link)
      expect(link[:new_value]).to eq("/courses/2/files/5/preview?verifier=u5")
    end

    it "converts media_attachments_iframe urls" do
      link = { link_type: :object, type: "media_attachments_iframe", migration_id: "F", query: "?foo=bar" }
      resolver.resolve_link!(link)
      expect(link[:new_value]).to eq("/media_attachments_iframe/6?foo=bar&verifier=u6")
    end

    it "converts discussion_topic links" do
      link = { link_type: :discussion_topic, migration_id: "G", query: "?foo=bar" }
      resolver.resolve_link!(link)
      expect(link[:new_value]).to eq("/courses/2/discussion_topics/7?foo=bar")
    end

    it "converts announcement links" do
      link = { link_type: :discussion_topic, migration_id: "H", query: "?foo=bar" }
      resolver.resolve_link!(link)
      expect(link[:new_value]).to eq("/courses/2/discussion_topics/10?foo=bar")
    end

    it "converts module links" do
      link = { link_type: :object, type: "modules", migration_id: "J", query: "?foo=bar" }
      resolver.resolve_link!(link)
      expect(link[:new_value]).to eq("/courses/2/modules/36?foo=bar")
    end

    it "converts other links" do
      link = { link_type: :object, type: "assignments", migration_id: "I", query: "#fie" }
      resolver.resolve_link!(link)
      expect(link[:new_value]).to eq("/courses/2/assignments/12#fie")
    end
  end

  describe "attachment_path_id_lookup_lower" do
    it "shows correct lowercase paths" do
      expect(resolver.attachment_path_id_lookup_lower).to include({ "subfolder/withcapital/test.png" => "migration_id!" })
    end
  end
end
