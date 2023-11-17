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
  def parser
    migration_query_service_mock = double()
    allow(migration_query_service_mock).to receive(:supports_embedded_images).and_return(true)
    allow(migration_query_service_mock).to receive(:fix_relative_urls?).and_return(true)
    CanvasLinkMigrator::LinkParser.new(migration_query_service_mock)
  end

  describe "convert_link" do
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
  end
end
