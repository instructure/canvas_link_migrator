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

describe CanvasLinkMigrator::ResourceMapService do

  CANVAS_RESOURCE_MAP_PATH = "/home/docker/canvas_link_migrator_gem/spec/fixtures/canvas_resource_map.json"

  def service(assets = canvas_resource_map_json)
    CanvasLinkMigrator::ResourceMapService.new(assets)
  end

  def canvas_resource_map_json
    @canvas_resource_map_json ||= JSON.parse(File.read(CANVAS_RESOURCE_MAP_PATH))
  end

  shared_examples "returns nil for non-existent migration id" do |method_name|
    it "returns nil if the migration id does not exist" do
      expect(service.send(method_name, "nonexistent")).to be_nil
    end
  end

  describe ".resources" do
    it "returns the correct resource map" do
      expect(service.resources).to eq(canvas_resource_map_json.dig("resource_mapping"))
    end

    it "returns an empty hash if no resource mapping is present" do
      expect(CanvasLinkMigrator::ResourceMapService.new({}).resources).to eq({})
    end
  end

  describe ".supports_embedded_images" do
    it "returns false by default" do
      expect(service.supports_embedded_images).to be false
    end
  end

  describe ".fix_relative_urls?" do
    it "returns true by default" do
      expect(service.fix_relative_urls?).to be true
    end
  end

  describe ".process_domain_substitutions" do
    it "returns the url unchanged by default" do
      uri = "https://example.com"
      expect(service.process_domain_substitutions(uri)).to eq(uri)
    end
  end

  describe ".context_hosts" do
    it "returns the destination hosts from the migration data" do
      expect(service.context_hosts).to eq(canvas_resource_map_json["destination_hosts"])
    end
  end

  describe ".attachment_path_id_lookup" do
    it "returns the attachment path id lookup from the migration data" do
      expect(service.attachment_path_id_lookup).to eq(canvas_resource_map_json["attachment_path_id_lookup"])
    end
  end

  describe ".root_folder_name" do
    it "returns the destination root folder from the migration data" do
      expect(service.root_folder_name).to eq(canvas_resource_map_json["destination_root_folder"])
    end
  end

  describe ".context_path" do
    it "returns the context path for the course" do
      expect(service.context_path).to eq("/courses/#{canvas_resource_map_json['destination_course']}")
    end
  end

  describe ".convert_wiki_page_migration_id_to_slug" do
    it "returns the slug for a wiki page migration id" do
      migration_id = "A"
      expected_slug = "slug-a"
      expect(service.convert_wiki_page_migration_id_to_slug(migration_id)).to eq(expected_slug)
    end

    include_examples "returns nil for non-existent migration id", :convert_wiki_page_migration_id_to_slug
  end

  describe ".convert_discussion_topic_migration_id" do
    it "returns the discussion topic id for a migration id" do
      migration_id = "G"
      expected_id = "7"
      expect(service.convert_discussion_topic_migration_id(migration_id)).to eq(expected_id)
    end

    it "returns the announcement id if the discussion topic id does not exist" do
      migration_id = "H"
      expected_id = "10"
      expect(service.convert_discussion_topic_migration_id(migration_id)).to eq(expected_id)
    end

    include_examples "returns nil for non-existent migration id", :convert_discussion_topic_migration_id
  end

  describe ".convert_announcement_migration_id" do
    it "returns the announcement id for a migration id" do
      migration_id = "H"
      expected_id = "10"
      expect(service.convert_announcement_migration_id(migration_id)).to eq(expected_id)
    end

    include_examples "returns nil for non-existent migration id", :convert_announcement_migration_id
  end

  describe ".convert_module_item_migration_id" do
    it "returns the module item id for a migration id" do
      migration_id = "C"
      expected_id = "3"
      expect(service.convert_context_module_tag_migration_id(migration_id)).to eq(expected_id)
    end

    include_examples "returns nil for non-existent migration id", :convert_context_module_tag_migration_id
  end

  describe ".convert_attachment_migration_id" do
    it "returns the attachment id for a migration id" do
      migration_id = "E"
      expected_id = ["5", "u5"]
      expect(service.convert_attachment_migration_id(migration_id)).to eq(expected_id)
    end

    include_examples "returns nil for non-existent migration id", :convert_attachment_migration_id
  end

  describe ".media_map" do
    it "returns a map of media entries" do
      expected_media_map = {
        "0_bq09qam2" => {
          "destination" => {
            "id" => "6",
            "media_entry_id" => "0_bq09qam2",
            "uuid" => "u6"
          },
          "source" => {
            "id" => "4",
            "media_entry_id" => "0_bq09qam2",
            "uuid" => "u4"
          }
        }
      }
      expect(service.media_map).to include(expected_media_map)
    end

    it "returns an empty hash if no media entries are present" do
      empty_service = CanvasLinkMigrator::ResourceMapService.new({ resources: {} })
      expect(empty_service.media_map).to eq(nil)
    end
  end

  describe ".convert_attachment_media_id" do
    it "returns the attachment media id for a media entry id" do
      media_id = "0_bq09qam2"
      expected_id = ["6", "u6"]
      expect(service.convert_attachment_media_id(media_id)).to eq(expected_id)
    end

    it "returns nil if the media entry id does not exist" do
      expect(service.convert_attachment_media_id("nonexistent")).to be_nil
    end
  end

  describe ".convert_migration_id" do
    it "returns the id for a known reference type" do
      migration_id = "A"
      expected_id = "2"
      expect(service.convert_migration_id("wiki_pages", migration_id)).to eq(expected_id)
    end

    it "returns nil for an unknown reference type" do
      migration_id = "nonexistent"
      expect(service.convert_migration_id("unknown_type", migration_id)).to be_nil
    end
  end

  describe ".lookup_attachment_by_migration_id" do
    it "returns the attachment details for a migration id" do
      migration_id = "E"
      expected_attachment = {
        "id"=>"5",
        "media_entry_id"=>"m-stuff",
        "uuid"=>"u5"
      }
      expect(service.lookup_attachment_by_migration_id(migration_id)).to eq(expected_attachment)
    end

    include_examples "returns nil for non-existent migration id", :lookup_attachment_by_migration_id
  end

end
