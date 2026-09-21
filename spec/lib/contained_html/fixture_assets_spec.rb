# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

describe ContainedHtml::FixtureAssets do
  it "rejects missing, altered, oversized and incorrectly described packaged assets" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "assets"))
      bytes =
        Base64.decode64(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZlSAAAAAASUVORK5CYII=",
        )
      id = Digest::SHA256.hexdigest(bytes)
      path = File.join(root, "assets", "#{id}.png")
      manifest_path = File.join(root, "manifest.json")
      entry = { id: id, filename: "#{id}.png", mime: "image/png", width: 1, height: 1 }
      File.binwrite(path, bytes)

      [
        entry.merge(filename: "../../#{id}.png"),
        entry.merge(mime: "image/svg+xml"),
        entry.merge(width: 10_000),
        entry.merge(height: 0),
      ].each do |invalid_entry|
        File.write(manifest_path, { assets: [invalid_entry] }.to_json)
        expect(described_class.new(root: root).fetch(id)).to be_nil
      end

      File.write(manifest_path, { assets: [entry] }.to_json)
      File.binwrite(path, bytes + "tampered")
      expect(described_class.new(root: root).fetch(id)).to be_nil
      File.binwrite(path, bytes + ("a" * described_class::MAX_ASSET_BYTES))
      expect(described_class.new(root: root).fetch(id)).to be_nil
      File.delete(path)
      expect(described_class.new(root: root).fetch(id)).to be_nil
      expect(described_class.new(root: root).fetch("../manifest.json")).to be_nil
      ["null", "[]", "invalid JSON"].each do |invalid_manifest|
        File.write(manifest_path, invalid_manifest)
        expect(described_class.new(root: root).fetch(id)).to be_nil
      end
    end
  end

  it "rejects markup masquerading as a raster even when its registered hash matches" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "assets"))
      bytes = '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"></svg>'
      id = Digest::SHA256.hexdigest(bytes)
      File.binwrite(File.join(root, "assets", "#{id}.png"), bytes)
      File.write(
        File.join(root, "manifest.json"),
        {
          assets: [{ id: id, filename: "#{id}.png", mime: "image/png", width: 1, height: 1 }],
        }.to_json,
      )

      expect(described_class.new(root: root).fetch(id)).to be_nil
    end
  end
end
