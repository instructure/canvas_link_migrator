# frozen_string_literal: true

#
# Copyright (C) 2012 - present Instructure, Inc.
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

describe CanvasLinkMigrator::ImportedHtmlConverter do
  # tests link_parser and link_resolver

  describe ".convert" do
    before do
      @path = "/courses/2/"
      @converter = CanvasLinkMigrator::ImportedHtmlConverter.new(resource_map: JSON.parse(File.read("spec/fixtures/canvas_resource_map.json")))
    end

    it "converts a wiki reference" do
      test_string = %(<a href="%24WIKI_REFERENCE%24/wiki/test-wiki-page?query=blah">Test Wiki Page</a>)
      html, bad_links = @converter.convert_exported_html(test_string)
      expect(html).to eq %(<a href="#{@path}pages/test-wiki-page?query=blah">Test Wiki Page</a>)
      expect(bad_links).to be_nil
    end

    it "converts a wiki reference with migration id" do
      test_string = %(<a href="%24WIKI_REFERENCE%24/pages/A?query=blah">Test Wiki Page</a>)
      html, bad_links = @converter.convert_exported_html(test_string)
      expect(html).to eq %(<a href="#{@path}pages/slug-a?query=blah">Test Wiki Page</a>)
      expect(bad_links).to be_nil
    end

    context "when course attachments exist" do
      subject { @converter.convert_exported_html(test_string) }

      let(:migration_id) { "E" }

      context "and a data-download-url attribute references an icon maker icon" do
        let(:test_string) do
          %(<img src="$CANVAS_COURSE_REFERENCE$/file_ref/#{migration_id}/download?download_frd=1" alt="" data-inst-icon-maker-icon="true" data-download-url="$CANVAS_COURSE_REFERENCE$/file_ref/#{migration_id}/download?download_frd=1&icon_maker_icon=1">)
        end

        it "converts data-download-url for files without appending a context" do
          html, bad_links = subject
          expect(html).to eq(
            "<img src=\"#{@path}files/5/download?download_frd=1\" alt=\"\" data-inst-icon-maker-icon=\"true\" data-download-url=\"/files/5/download?download_frd=1&icon_maker_icon=1\">"
          )
          expect(bad_links).to be_nil
        end
      end

      it "finds an attachment by migration id" do
        test_string = %{<p>This is an image: <br /><img src="%24CANVAS_OBJECT_REFERENCE%24/attachments/F" alt=":(" /></p>}
        expect(@converter.convert_exported_html(test_string)).to eq([%{<p>This is an image: <br><img src="#{@path}files/6/preview" alt=":("></p>}, nil])
      end

      it "finds an attachment by path" do
        test_string = %{<p>This is an image: <br /><img src="%24IMS_CC_FILEBASE%24/test.png" alt=":(" /></p>}

        # if there isn't a path->migration id map it'll be a relative course file path
        expect(@converter.link_resolver).to receive(:attachment_path_id_lookup).exactly(4).times.and_return({})
        html, bad_links = @converter.convert_exported_html(test_string)
        expect(html).to eq %{<p>This is an image: <br><img src="#{@path}file_contents/course%20files/test.png" alt=":("></p>}
        expect(bad_links[0]).to include({ link_type: :file, missing_url: "/courses/2/file_contents/course%20files/test.png" })

        expect(@converter.link_resolver).to receive(:attachment_path_id_lookup).twice.and_call_original
        expect(@converter.convert_exported_html(test_string)).to eq([%{<p>This is an image: <br><img src="#{@path}files/5/preview" alt=":("></p>}, nil])
      end

      it "finds an attachment by a path with a space" do
        test_string = %(<img src="subfolder/with%20a%20space/test.png" alt="nope" />)
        expect(@converter.convert_exported_html(test_string)).to eq([%(<img src="#{@path}files/6/preview" alt="nope">), nil])

        test_string = %(<img src="subfolder/with+a+space/test.png" alt="nope" />)
        expect(@converter.convert_exported_html(test_string)).to eq([%(<img src="#{@path}files/6/preview" alt="nope">), nil])
      end

      it "finds an attachment even if the link has an extraneous folder" do
        test_string = %(<img src="anotherfolder/subfolder/test.png" alt="nope" />)
        expect(@converter.convert_exported_html(test_string)).to eq([%(<img src="#{@path}files/7/preview" alt="nope">), nil])
      end

      it "finds an attachment by path if capitalization is different" do
        expect(@converter.link_resolver).to receive(:attachment_path_id_lookup).twice.and_return({ "subfolder/withCapital/test.png" => "wrong!" })
        expect(@converter.link_resolver).to receive(:attachment_path_id_lookup).twice.and_return({ "subfolder/withcapital/test.png" => "F" })

        test_string = %(<img src="subfolder/WithCapital/TEST.png" alt="nope" />)
        expect(@converter.convert_exported_html(test_string)).to eq([%(<img src="#{@path}files/6/preview" alt="nope">), nil])
      end

      it "finds an attachment with query params" do
        test_string = %(<img src="%24IMS_CC_FILEBASE%24/test.png?canvas_customaction=1&canvas_qs_customparam=1" alt="nope" />)
        expect(@converter.convert_exported_html(test_string)).to eq([%(<img src="#{@path}files/5/customaction?customparam=1" alt="nope">), nil])

        test_string = %(<img src="%24IMS_CC_FILEBASE%24/test.png?canvas_qs_customparam2=3" alt="nope" />)
        expect(@converter.convert_exported_html(test_string)).to eq([%(<img src="#{@path}files/5/preview?customparam2=3" alt="nope">), nil])

        test_string = %(<img src="%24IMS_CC_FILEBASE%24/test.png?notarelevantparam" alt="nope" />)
        expect(@converter.convert_exported_html(test_string)).to eq([%(<img src="#{@path}files/5/preview" alt="nope">), nil])
      end
    end

    it "converts picture source srcsets" do
      test_string = %(<source srcset="$CANVAS_COURSE_REFERENCE$/img.src">)
      expect(@converter.convert_exported_html(test_string)).to eq([%(<source srcset="/courses/2/img.src">), nil])
    end

    it "converts a wiki reference without $ escaped" do
      test_string = %(<a href="$WIKI_REFERENCE$/wiki/test-wiki-page?query=blah">Test Wiki Page</a>)

      expect(@converter.convert_exported_html(test_string)).to eq([%(<a href="#{@path}pages/test-wiki-page?query=blah">Test Wiki Page</a>), nil])
    end

    it "converts a wiki reference by migration id" do
      test_string = %(<a href="wiki_page_migration_id=A">Test Wiki Page</a>)

      expect(@converter.convert_exported_html(test_string)).to eq([%(<a href="#{@path}pages/slug-a">Test Wiki Page</a>), nil])
    end

    it "converts a discussion reference by migration id" do
      test_string = %(<a href="discussion_topic_migration_id=G">Test topic</a>)

      expect(@converter.convert_exported_html(test_string)).to eq([%(<a href="#{@path}discussion_topics/7">Test topic</a>), nil])
    end

    it "converts course section urls" do
      test_string = %(<a href="%24CANVAS_COURSE_REFERENCE%24/discussion_topics">discussions</a>)
      expect(@converter.convert_exported_html(test_string)).to eq([%(<a href="#{@path}discussion_topics">discussions</a>), nil])
    end

    it "leaves invalid and absolute urls alone" do
      test_string = %(<a href="stupid &^%$ url">Linkage</a><br><a href="http://www.example.com/poop">Linkage</a>)
      expect(@converter.convert_exported_html(test_string)).to eq([%(<a href="stupid &amp;^%$ url">Linkage</a><br><a href="http://www.example.com/poop">Linkage</a>), nil])
    end

    it "leaves invalid mailto addresses alone" do
      test_string = %(<a href="mailto:.">Bad mailto</a><br><a href="mailto:test@example.com">Good mailto</a>)
      expect(@converter.convert_exported_html(test_string)).to eq(
        [
          %(<a href="mailto:.">Bad mailto</a><br><a href="mailto:test@example.com">Good mailto</a>),
          nil
        ]
      )
    end

    it "recognizes and relative-ize absolute links outside the course but in one of the course's domains" do
      test_string = %(<a href="https://apple.edu/courses/123">Mine</a><br><a href="https://kiwi.edu/courses/456">Vain</a><br><a href="http://other-canvas.example.com/">Other Instance</a>)
      expect(@converter.convert_exported_html(test_string)).to eq([%(<a href="/courses/123">Mine</a><br><a href="/courses/456">Vain</a><br><a href="http://other-canvas.example.com/">Other Instance</a>), nil])
    end

    it "prepends course files for unrecognized relative urls" do
      test_string = %(<a href="/relative/path/to/file">Linkage</a>)
      html, bad_links = @converter.convert_exported_html(test_string)
      expect(html).to eq %(<a href="#{@path}file_contents/course%20files/relative/path/to/file">Linkage</a>)
      expect(bad_links.length).to eq 1
      expect(bad_links[0]).to include({ link_type: :file, missing_url: "/courses/2/file_contents/course%20files/relative/path/to/file" })

      test_string = %(<a href="relative/path/to/file">Linkage</a>)
      html, bad_links = @converter.convert_exported_html(test_string)
      expect(html).to eq %(<a href="#{@path}file_contents/course%20files/relative/path/to/file">Linkage</a>)
      expect(bad_links.length).to eq 1
      expect(bad_links[0]).to include({ link_type: :file, missing_url: "/courses/2/file_contents/course%20files/relative/path/to/file" })

      test_string = %(<a href="relative/path/to/file%20with%20space.html">Linkage</a>)
      html, bad_links = @converter.convert_exported_html(test_string)
      expect(html).to eq %(<a href="#{@path}file_contents/course%20files/relative/path/to/file%20with%20space.html">Linkage</a>)
      expect(bad_links.length).to eq 1
      expect(bad_links[0]).to include({ link_type: :file, missing_url: "/courses/2/file_contents/course%20files/relative/path/to/file%20with%20space.html" })
    end

    it "preserves media comment links" do
      test_string = <<~HTML.strip
        <p>
          with media object url: <a id="media_comment_m-stuff" class="instructure_inline_media_comment video_comment" href="/media_objects/m-stuff">this is a media comment</a>
          with file content url: <a id="media_comment_0_bq09qam2" class="instructure_inline_media_comment video_comment" href="/courses/2/file_contents/course%20files/media_objects/0_bq09qam2">this is a media comment</a>
        </p>
      HTML

      expect(@converter.convert_exported_html(test_string)).to eq([test_string, nil])
    end

    it "handles and repair half broken media links" do
      test_string = %(<p><a href="/courses/2/file_contents/%24IMS_CC_FILEBASE%24/#" class="instructure_inline_media_comment video_comment" id="media_comment_m-stuff">this is a media comment</a><br><br></p>)

      expect(@converter.convert_exported_html(test_string)).to eq([%(<p><a href="/media_objects/m-stuff" class="instructure_inline_media_comment video_comment" id="media_comment_m-stuff">this is a media comment</a><br><br></p>), nil])
    end

    it "preserves new RCE media iframes" do
      test_string = %(<iframe style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="video" src="/media_objects_iframe/m-stuff?type=video" allowfullscreen="allowfullscreen" allow="fullscreen" data-media-id="m-stuff"></iframe>)
      expect(@converter.convert_exported_html(test_string)).to eq([test_string, nil])
    end

    it "handles and repair half broken new RCE media iframes" do
      test_string = %(<iframe style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="video" src="%24IMS_CC_FILEBASE%24/#" allowfullscreen="allowfullscreen" allow="fullscreen" data-media-id="m-abcde"></iframe>)
      repaired_string = %(<iframe style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="video" src="/media_objects_iframe/m-abcde?type=video" allowfullscreen="allowfullscreen" allow="fullscreen" data-media-id="m-abcde"></iframe>)
      expect(@converter.convert_exported_html(test_string)).to eq([repaired_string, nil])
    end

    it "converts source tags to RCE media iframes" do
      test_string = %(<video style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="video" allowfullscreen="allowfullscreen" allow="fullscreen" data-media-id="m-stuff"><source src="/media_objects_iframe/m-stuff?type=video" data-media-id="m-stuff" data-media-type="video"></video>)
      converted_string = %(<iframe style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="video" allowfullscreen="allowfullscreen" allow="fullscreen" data-media-id="m-stuff" src="/media_objects_iframe/m-stuff?type=video"></iframe>)
      expect(@converter.convert_exported_html(test_string)).to eq([converted_string, nil])

      test_string = %(<audio style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="audio" data-media-id="m-stuff"><source src="/media_objects_iframe/m-stuff?type=audio" data-media-id="m-stuff" data-media-type="audio"></audio>)
      converted_string = %(<iframe style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="audio" data-media-id="m-stuff" src="/media_objects_iframe/m-stuff?type=audio"></iframe>)
      expect(@converter.convert_exported_html(test_string)).to eq([converted_string, nil])
    end

    it "converts source tags to RCE media attachment iframes" do
      test_string = %(<video style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="video" allowfullscreen="allowfullscreen" allow="fullscreen" data-media-id="m-stuff"><source src="$IMS-CC-FILEBASE$/subfolder/with a space/yodawg.mov?canvas_=1&canvas_qs_type=video&canvas_qs_amp=&canvas_qs_embedded=true&media_attachment=true" data-media-id="m-stuff" data-media-type="video"></video>)
      converted_string = %(<iframe style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="video" allowfullscreen="allowfullscreen" allow="fullscreen" data-media-id="m-yodawg" src="/media_attachments_iframe/9?type=video"></iframe>)
      expect(@converter.convert_exported_html(test_string)).to eq([converted_string, nil])

      test_string = %(<audio style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="audio" data-media-id="m-stuff"><source src="$IMS-CC-FILEBASE$/lolcat.mp3?canvas_=1&canvas_qs_type=audio&canvas_qs_amp=&canvas_qs_embedded=true&media_attachment=true" data-media-id="m-stuff" data-media-type="audio"></video>)
      converted_string = %(<iframe style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="audio" data-media-id="m-lolcat" src="/media_attachments_iframe/8?type=audio"></iframe>)
      expect(@converter.convert_exported_html(test_string)).to eq([converted_string, nil])
    end

    it "converts course copy style media attachmet iframe links" do
      test_string = %(<video style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="video" allowfullscreen="allowfullscreen" allow="fullscreen" data-media-id="m-yodawg"><source src="$CANVAS_COURSE_REFERENCE$/file_ref/I?media_attachment=true&type=video" data-media-id="m-yodawg" data-media-type="video"></video>)
      converted_string = %(<iframe style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="video" allowfullscreen="allowfullscreen" allow="fullscreen" data-media-id="m-yodawg" src="/media_attachments_iframe/9?type=video"></iframe>)
      expect(@converter.convert_exported_html(test_string)).to eq([converted_string, nil])

      test_string = %(<audio style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="audio" data-media-id="m-lolcat"><source src="$CANVAS_COURSE_REFERENCE$/file_ref/H?media_attachment=true&type=audio" data-media-id="m-lolcat" data-media-type="audio"></audio>)
      converted_string = %(<iframe style="width: 400px; height: 225px; display: inline-block;" title="this is a media comment" data-media-type="audio" data-media-id="m-lolcat" src="/media_attachments_iframe/8?type=audio"></iframe>)
      expect(@converter.convert_exported_html(test_string)).to eq([converted_string, nil])
    end

    it "converts mediahref iframes" do
      test_string = %(<iframe data-media-type="video" src="/media_objects_iframe?mediahref=$CANVAS_COURSE_REFERENCE$/file_ref/I/download" data-media-id="m-yodawg"></iframe>)
      converted_string = %(<iframe data-media-type="video" src="/media_objects_iframe?mediahref=/courses/2/files/9/download" data-media-id="m-yodawg"></iframe>)
      expect(@converter.convert_exported_html(test_string)).to eq([converted_string, nil])
    end

    it "leaves source tags without data-media-id alone" do
      test_string = %(<video style="width: 400px; height: 225px; display: inline-block;" title="this is a non-canvas video" allowfullscreen="allowfullscreen" allow="fullscreen"><source src="http://www.example.com/video.mov"></video>)
      expect(@converter.convert_exported_html(test_string)).to eq([test_string, nil])
    end

    it "only converts url params" do
      test_string = <<~HTML
        <object>
        <param name="controls" value="CONSOLE" />
        <param name="controller" value="true" />
        <param name="autostart" value="false" />
        <param name="loop" value="false" />
        <param name="src" value="%24IMS_CC_FILEBASE%24/test.mp3" />
        <EMBED name="tag"  src="%24IMS_CC_FILEBASE%24/test.mp3" loop="false" autostart="false" controller="true" controls="CONSOLE" >
        </EMBED>
        </object>
      HTML

      expect(@converter.convert_exported_html(test_string)[0]).to match(<<~HTML.strip)
        <object>
        <param name="controls" value="CONSOLE">
        <param name="controller" value="true">
        <param name="autostart" value="false">
        <param name="loop" value="false">
        <param name="src" value="/courses/2/file_contents/course%20files/test.mp3">
        <embed name="tag" src="/courses/2/file_contents/course%20files/test.mp3" loop="false" autostart="false" controller="true" controls="CONSOLE">

        </object>
      HTML
    end

    it "leaves an anchor tag alone" do
      test_string = '<p><a href="#anchor_ref">ref</a></p>'
      expect(@converter.convert_exported_html(test_string)).to eq([test_string, nil])
    end
  end
end
