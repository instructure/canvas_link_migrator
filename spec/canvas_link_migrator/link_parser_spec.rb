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

describe CanvasLinkMigrator::LinkParser do
  def parser(assets = JSON.parse(File.read("spec/fixtures/canvas_resource_map.json")))
    CanvasLinkMigrator::LinkParser.new(CanvasLinkMigrator::ResourceMapService.new(assets))
  end

  describe "convert_link" do
    it "marks target=_blank anchor tags" do
      doc = Nokogiri::HTML5.fragment("<a target=\"_blank\"></a>")
      parsed = parser.parse_url("$CANVAS_COURSE_REFERENCE$/file_ref/whatevs", doc.at_css('a'), "href")
      expect(parsed[:target_blank]).to be true
    end

    it "checks data-media-type attribute to determine in_media_iframe" do
      doc = Nokogiri::HTML5.fragment("<p><iframe data-media-type=\"video\" src=\"$CANVAS_COURSE_REFERENCE$/file_ref/whatevs\"></iframe></p>")
      parsed = parser.parse_url("$CANVAS_COURSE_REFERENCE$/file_ref/whatevs", doc.at_css('iframe'), "src")
      expect(parsed[:in_media_iframe]).to eq "video"
    end

    it "converts inner html of anchor tags when appropriate" do
      doc = Nokogiri::HTML5.fragment("<a href=\"$WIKI_REFERENCE$/pages/1\">$WIKI_REFERENCE$/pages/1</a>")
      parser.convert_link(doc.at_css('a'), "href","wiki_page", "migrationid", "")
      expect(doc.at_css('a')['href']).to include("LINK.PLACEHOLDER")
      expect(doc.at_css('a').inner_html).to include("LINK.PLACEHOLDER")
    end

    it "doesn't convert inner html of anchor tags if unnecessary" do
      doc = Nokogiri::HTML5.fragment("<a href=\"$WIKI_REFERENCE$/pages/1\">$WIKI_REFERENCE$/pages/5</a>")
      parser.convert_link(doc.at_css('a'), "href","wiki_page", "migrationid", "")
      expect(doc.at_css('a')['href']).to include("LINK.PLACEHOLDER")
      expect(doc.at_css('a').inner_html).not_to include("LINK.PLACEHOLDER")
    end

    it "doesn't convert inner html of anchor tags if unnecessary" do
      doc = Nokogiri::HTML5.fragment("<a href=\"https://what:10.1111/HFP.0b013e31828df26\">broken link</a>")
      expect{ parser.convert_link(doc.at_css('a'), "href", "wiki_page", "migrationid", "") }.not_to raise_error
    end
  end

  describe "convert" do
    it "does not change media anchor tags into iframes if they don't have inline_media_comment in the class" do
      doc = Nokogiri::HTML5.fragment(%Q(<p><a id="media_comment_m-5HHT5LqZqPf7qhEJ7PbKtehCiunxM4BB" class=" instructure_video_link instructure_file_link" title="00-Personal Intro.m4v" href="https://xu.instructure.com/courses/83206/files/12176377/download?wrap=1" target="" data-api-endpoint="https://xu.instructure.com/api/v1/courses/83206/files/12176377" data-api-returntype="File">Click here to watch personal introduction</a></p>))
      parser.convert(doc.to_html, "type", "lookup_id", "field")
      expect(doc.to_html).to match(%Q(<p><a id="media_comment_m-5HHT5LqZqPf7qhEJ7PbKtehCiunxM4BB" class=" instructure_video_link instructure_file_link" title="00-Personal Intro.m4v" href="https://xu.instructure.com/courses/83206/files/12176377/download?wrap=1" target="" data-api-endpoint="https://xu.instructure.com/api/v1/courses/83206/files/12176377" data-api-returntype="File">Click here to watch personal introduction</a></p>))
    end

    it "does not crash if it can't find a video/audio_comment class name" do
      doc = Nokogiri::HTML5.fragment(%Q(<a id="media_comment_m-4uoGqVdEqXhpqu2ZMytHSy9XMV73aQ7E" class="instructure_inline_media_comment" data-media_comment_type="video" data-alt=""></a>))
      expect{ parser.convert(doc.to_html, "type", "lookup_id", "field") }.not_to raise_error
    end
  end
end
