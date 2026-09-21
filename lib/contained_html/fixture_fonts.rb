# frozen_string_literal: true

require "base64"
require "digest"
require "json"

module ContainedHtml
  # Only administrator-packaged fonts can create @font-face rules in the child document.
  class FixtureFonts
    ROOT = File.expand_path("../../fixtures/sock-pile/fonts", __dir__)
    MAX_FONT_BYTES = 500 * 1024
    MAX_TOTAL_BYTES = 200 * 1024
    MAX_MANIFEST_BYTES = 16 * 1024
    FAMILIES = {
      "Bricolage Grotesque" => "200 800",
      "Tilt Neon" => "400",
      "RPN Contained Icons" => "900",
    }.freeze
    ID = /\A[0-9a-f]{64}\z/
    Font = Struct.new(:data_uri, :weight, keyword_init: true)

    def self.default
      @default ||= new
    end

    def initialize(root: ROOT)
      @root = root
    end

    def stylesheet_for(values)
      font_values = values.join(" ")
      fonts
        .filter_map do |family, font|
          unless font_values.match?(/(?<![a-zA-Z0-9_-])#{Regexp.escape(family)}(?![a-zA-Z0-9_-])/)
            next
          end
          "@font-face{font-family:\"#{family}\";font-style:normal;font-weight:#{font.weight};font-display:block;src:url(\"#{font.data_uri}\") format(\"woff2\")}"
        end
        .join("\n")
    end

    private

    def fonts
      @fonts ||= load_fonts.freeze
    end

    def load_fonts
      manifest_path = File.join(@root, "manifest.json")
      return {} unless File.file?(manifest_path) && File.size(manifest_path) <= MAX_MANIFEST_BYTES
      manifest = JSON.parse(File.read(manifest_path, MAX_MANIFEST_BYTES + 1))
      return {} unless manifest.is_a?(Hash)
      entries = manifest["fonts"]
      return {} unless entries.is_a?(Array) && entries.length <= FAMILIES.length

      total_bytes = 0
      entries.each_with_object({}) do |entry, result|
        next unless entry.is_a?(Hash)
        family = entry["family"]
        id = entry["id"]
        unless FAMILIES.key?(family) && entry["weight"] == FAMILIES[family] &&
                 entry["style"] == "normal" && entry["mime"] == "font/woff2" && id.is_a?(String) &&
                 id.match?(ID) && entry["filename"] == "#{id}.woff2"
          next
        end
        next if result.key?(family)

        path = File.join(@root, entry["filename"])
        next unless File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_FONT_BYTES
        bytes = File.binread(path, MAX_FONT_BYTES + 1)
        next unless bytes.bytesize <= MAX_FONT_BYTES && Digest::SHA256.hexdigest(bytes) == id
        next unless woff2_header?(bytes)
        total_bytes += bytes.bytesize
        return {} if total_bytes > MAX_TOTAL_BYTES

        result[family] = Font.new(
          data_uri: "data:font/woff2;base64,#{Base64.strict_encode64(bytes)}".freeze,
          weight: FAMILIES[family],
        ).freeze
      end
    rescue JSON::ParserError, TypeError, Errno::ENOENT, Errno::EACCES
      {}
    end

    def woff2_header?(bytes)
      bytes.bytesize >= 48 && bytes.start_with?("wOF2") &&
        bytes.byteslice(8, 4).unpack1("N") == bytes.bytesize &&
        bytes.byteslice(12, 2).unpack1("n").between?(1, 256) &&
        bytes.byteslice(16, 4).unpack1("N").between?(1, 2 * 1024 * 1024)
    end
  end
end
