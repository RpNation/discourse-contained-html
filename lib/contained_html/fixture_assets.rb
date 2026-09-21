# frozen_string_literal: true

require "base64"
require "digest"
require "json"

module ContainedHtml
  # Temporary, administrator-packaged raster fixtures; this is not an upload or URL fetcher.
  class FixtureAssets
    ROOT = File.expand_path("../../fixtures/sock-pile", __dir__)
    MAX_ASSET_BYTES = 500 * 1024
    MAX_MANIFEST_BYTES = 64 * 1024
    MAX_ASSETS = 64
    ID = /\A[0-9a-f]{64}\z/
    Asset = Struct.new(:data_uri, :width, :height, keyword_init: true)

    def self.default
      @default ||= new
    end

    def initialize(root: ROOT)
      @root = root
    end

    def fetch(id)
      return unless id.is_a?(String) && id.match?(ID)
      assets[id]
    end

    private

    def assets
      @assets ||= load_assets.freeze
    end

    def load_assets
      manifest_path = File.join(@root, "manifest.json")
      return {} unless File.file?(manifest_path) && File.size(manifest_path) <= MAX_MANIFEST_BYTES

      manifest = JSON.parse(File.read(manifest_path, MAX_MANIFEST_BYTES + 1))
      return {} unless manifest.is_a?(Hash)
      entries = manifest["assets"]
      return {} unless entries.is_a?(Array) && entries.length <= MAX_ASSETS

      entries.each_with_object({}) do |entry, result|
        next unless entry.is_a?(Hash)
        id = entry["id"]
        extension = { "image/png" => "png", "image/webp" => "webp" }[entry["mime"]]
        unless id.is_a?(String) && id.match?(ID) && extension &&
                 entry["filename"] == "#{id}.#{extension}"
          next
        end

        width, height = entry.values_at("width", "height")
        unless [width, height].all? { |dimension|
                 dimension.is_a?(Integer) && dimension.between?(1, 2048)
               } && width * height <= 4_000_000
          next
        end

        path = File.join(@root, "assets", entry["filename"])
        next unless File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_ASSET_BYTES
        bytes = File.binread(path, MAX_ASSET_BYTES + 1)
        next unless bytes.bytesize <= MAX_ASSET_BYTES && Digest::SHA256.hexdigest(bytes) == id
        next unless raster_signature?(bytes, extension)

        result[id] = Asset.new(
          data_uri: "data:#{entry["mime"]};base64,#{Base64.strict_encode64(bytes)}".freeze,
          width: width,
          height: height,
        ).freeze
      end
    rescue JSON::ParserError, TypeError, Errno::ENOENT, Errno::EACCES
      {}
    end

    def raster_signature?(bytes, extension)
      if extension == "png"
        bytes.start_with?("\x89PNG\r\n\x1a\n".b)
      else
        bytes.start_with?("RIFF") && bytes.byteslice(8, 4) == "WEBP"
      end
    end
  end
end
