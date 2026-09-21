# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

describe ContainedHtml::FixtureFonts do
  def fixture_font
    manifest = JSON.parse(File.read(File.join(described_class::ROOT, "manifest.json")))
    entry = manifest.fetch("fonts").find { |font| font["family"] == "Bricolage Grotesque" }
    [entry, File.binread(File.join(described_class::ROOT, entry.fetch("filename")))]
  end

  it "embeds only selected packaged families and leaves author font sources and active content blocked" do
    entry, bytes = fixture_font
    Dir.mktmpdir do |root|
      File.binwrite(File.join(root, entry.fetch("filename")), bytes)
      File.write(
        File.join(root, "manifest.json"),
        { fonts: [entry.merge("source_url" => "javascript:alert(1)")] }.to_json,
      )
      fonts = described_class.new(root: root)
      sanitizer = ContainedHtml::Sanitizer.new(fonts: fonts)
      document = Nokogiri.HTML5(sanitizer.render(<<~HTML))
        <style>@font-face {font-family: 'Foreign'; src:url(https://evil.test/font.woff2)}
        .text{font-family: "Bricolage Grotesque", sans-serif}</style>
        <p class="text" onmouseover="alert(1)">Fixture</p><script>alert(2)</script>
      HTML
      stylesheet = document.at_css("style").text
      expect(stylesheet.scan("@font-face").length).to eq(1)
      expect(stylesheet).to include(
        "data:font/woff2;base64,#{Base64.strict_encode64(bytes)}",
        "font-weight:200 800",
        "font-display:block",
      )
      expect(stylesheet).not_to include("evil.test", "javascript:", "Foreign")
      expect(document.at_css("meta")["content"]).to include(
        "font-src data:",
        "script-src 'none'",
        "connect-src 'none'",
      )
      expect(document.css("script, [onmouseover]")).to be_empty

      plain = Nokogiri.HTML5(sanitizer.render("<p>Ordinary text</p>"))
      expect(plain.at_css("style").text).not_to include("@font-face")
      expect(plain.at_css("meta")["content"]).to include("font-src 'none'")
    end
  end

  it "rejects mismatched hashes, paths, MIME types and unapproved font metadata" do
    entry, bytes = fixture_font
    Dir.mktmpdir do |root|
      File.binwrite(File.join(root, entry.fetch("filename")), bytes)
      invalid_entries = [
        entry.merge("id" => "f" * 64),
        entry.merge("filename" => "../../#{entry.fetch("filename")}"),
        entry.merge("mime" => "text/html"),
        entry.merge("family" => 'Bricolage Grotesque";src:url(https://evil.test)'),
        entry.merge("weight" => "100 900"),
        entry.merge("style" => "italic"),
      ]
      invalid_entries.each do |invalid_entry|
        File.write(File.join(root, "manifest.json"), { fonts: [invalid_entry] }.to_json)
        expect(described_class.new(root: root).stylesheet_for(["Bricolage Grotesque"])).to eq("")
      end

      File.write(File.join(root, "manifest.json"), { fonts: [entry] }.to_json)
      File.binwrite(File.join(root, entry.fetch("filename")), bytes + "tampered")
      expect(described_class.new(root: root).stylesheet_for(["Bricolage Grotesque"])).to eq("")
    end
  end

  it "rejects malformed font headers even when their packaged hash matches" do
    entry, = fixture_font
    Dir.mktmpdir do |root|
      bytes = "<script>parent.pwned=true</script>"
      id = Digest::SHA256.hexdigest(bytes)
      filename = "#{id}.woff2"
      File.binwrite(File.join(root, filename), bytes)
      File.write(
        File.join(root, "manifest.json"),
        { fonts: [entry.merge("id" => id, "filename" => filename)] }.to_json,
      )

      expect(described_class.new(root: root).stylesheet_for(["Bricolage Grotesque"])).to eq("")
    end
  end
end
