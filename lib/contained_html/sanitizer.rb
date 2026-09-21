# frozen_string_literal: true

require "loofah"
require "crass"
require_relative "fixture_assets"
require_relative "fixture_fonts"

module ContainedHtml
  class Sanitizer
    class InvalidSource < StandardError
    end

    MAX_SOURCE_BYTES = 256 * 1024
    MAX_NODES = 4000
    MAX_DEPTH = 32
    MAX_ATTRIBUTES = 32
    MAX_CSS_BYTES = 64 * 1024
    MAX_CSS_BLOCK_BYTES = 32 * 1024
    MAX_CSS_TOKENS = 20_000
    MAX_DECLARATIONS = 1500
    MAX_RULES = 200
    MAX_VALUE_TOKENS = 256
    MAX_NUMBER = 10_000
    MAX_EMBEDDED_ASSET_BYTES = 4 * 1024 * 1024
    MAX_ASSET_USES = 64

    TAGS = %w[
      div
      span
      section
      article
      header
      footer
      main
      p
      br
      hr
      h1
      h2
      h3
      h4
      h5
      h6
      strong
      em
      b
      i
      u
      s
      small
      sub
      sup
      blockquote
      pre
      code
      ul
      ol
      li
      dl
      dt
      dd
      table
      caption
      colgroup
      col
      thead
      tbody
      tfoot
      tr
      th
      td
      details
      summary
      img
    ].to_set.freeze

    PROPERTIES = %w[
      color
      background
      background-color
      background-image
      background-size
      background-position
      background-repeat
      background-clip
      background-origin
      opacity
      font
      font-family
      font-size
      font-style
      font-weight
      font-variant
      line-height
      letter-spacing
      word-spacing
      text-align
      text-decoration
      text-decoration-color
      text-decoration-line
      text-decoration-style
      text-transform
      text-indent
      white-space
      word-break
      overflow-wrap
      vertical-align
      display
      box-sizing
      width
      min-width
      max-width
      height
      min-height
      max-height
      inline-size
      min-inline-size
      max-inline-size
      block-size
      min-block-size
      max-block-size
      margin
      margin-top
      margin-right
      margin-bottom
      margin-left
      margin-inline
      margin-block
      margin-inline-start
      margin-inline-end
      margin-block-start
      margin-block-end
      padding
      padding-top
      padding-right
      padding-bottom
      padding-left
      padding-inline
      padding-block
      padding-inline-start
      padding-inline-end
      padding-block-start
      padding-block-end
      border
      border-width
      border-style
      border-color
      border-top
      border-right
      border-bottom
      border-left
      border-inline
      border-block
      border-radius
      border-collapse
      border-spacing
      overflow
      overflow-x
      overflow-y
      flex
      flex-direction
      flex-wrap
      flex-flow
      flex-grow
      flex-shrink
      flex-basis
      align-items
      align-content
      align-self
      justify-items
      justify-content
      justify-self
      gap
      row-gap
      column-gap
      order
      grid
      grid-template
      grid-template-columns
      grid-template-rows
      grid-template-areas
      grid-auto-columns
      grid-auto-rows
      grid-auto-flow
      grid-column
      grid-row
      grid-column-start
      grid-column-end
      grid-row-start
      grid-row-end
      grid-area
      list-style-type
      list-style-position
      table-layout
      caption-side
      empty-cells
      position
      inset
      top
      right
      bottom
      left
      transform
      transform-origin
      filter
      box-shadow
      text-shadow
      outline
      outline-width
      outline-style
      outline-color
      outline-offset
    ].to_set.freeze

    FUNCTIONS = %w[
      rgb
      rgba
      hsl
      hsla
      hwb
      oklch
      oklab
      lab
      lch
      linear-gradient
      radial-gradient
      conic-gradient
      min
      max
      clamp
      minmax
      fit-content
      repeat
      var
    ].to_set.freeze
    UNITS = %w[
      px
      em
      rem
      ch
      ex
      lh
      rlh
      vw
      vh
      vmin
      vmax
      svw
      svh
      lvw
      lvh
      dvw
      dvh
      fr
      deg
      turn
      rad
    ].to_set.freeze
    IDENTIFIER = /\A(?:--[a-zA-Z][a-zA-Z0-9_-]{0,63}|-?[_a-zA-Z][_a-zA-Z0-9-]{0,63})\z/
    CUSTOM_PROPERTY = /\A--[a-zA-Z][a-zA-Z0-9_-]{0,63}\z/
    TRANSFORMS = %w[
      rotate
      rotatex
      rotatey
      skew
      skewx
      skewy
      translate
      translatex
      translatey
      scale
      scalex
      scaley
    ].to_set.freeze
    FILTERS = %w[brightness contrast saturate grayscale hue-rotate blur].to_set.freeze

    CSP = [
      "default-src 'none'",
      "script-src 'none'",
      "style-src 'unsafe-inline'",
      "img-src data:",
      "font-src 'none'",
      "media-src 'none'",
      "connect-src 'none'",
      "object-src 'none'",
      "frame-src 'none'",
      "worker-src 'none'",
      "base-uri 'none'",
      "form-action 'none'",
    ].join("; ").freeze

    BASE_STYLE = <<~CSS
      :root { color-scheme: light dark; font: 16px/1.5 system-ui, sans-serif; }
      *, *::before, *::after { box-sizing: border-box; }
      html { overflow: auto; }
      body { margin: 0; padding: 16px; overflow-wrap: anywhere; }
      pre { white-space: pre-wrap; }
      table { max-width: 100%; }
      summary { cursor: pointer; }
    CSS

    def self.render(source)
      new.render(source)
    end

    def initialize(assets: FixtureAssets.default, fonts: FixtureFonts.default)
      @assets = assets
      @fonts = fonts
    end

    def render(source)
      unless source.is_a?(String) && source.valid_encoding? && source.bytesize <= MAX_SOURCE_BYTES
        raise InvalidSource, "HTML source must be valid text no larger than 256 KiB"
      end

      @css_bytes = 0
      @declarations = 0
      @rules = 0
      @stylesheets = []
      @embedded_asset_bytes = 0
      @asset_uses = 0
      @font_values = []

      document = Loofah::HTML5::Document.new
      document.encoding = "UTF-8"
      fragment =
        Loofah::HTML5::DocumentFragment.new(
          document,
          source,
          nil,
          max_tree_depth: MAX_DEPTH,
          max_attributes: MAX_ATTRIBUTES,
        )
      if fragment.xpath(".//node()").length > MAX_NODES
        raise InvalidSource, "HTML contains too many nodes"
      end

      fragment.scrub!(Loofah::Scrubber.new(direction: :top_down) { |node| scrub_node(node) })
      font_styles = @fonts.stylesheet_for(@font_values)
      csp = font_styles.empty? ? CSP : CSP.sub("font-src 'none'", "font-src data:")

      <<~HTML
        <!doctype html>
        <html><head><meta http-equiv="Content-Security-Policy" content="#{csp}">
        <meta charset="utf-8"><meta name="referrer" content="no-referrer">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>#{BASE_STYLE}\n#{font_styles}\n#{@stylesheets.join("\n")}</style></head>
        <body>#{fragment.to_html}</body></html>
      HTML
    rescue ArgumentError => e
      raise InvalidSource, "HTML exceeds parser limits: #{e.message}"
    end

    private

    def scrub_node(node)
      return Loofah::Scrubber::CONTINUE if node.text?

      allowed_tag = TAGS.include?(node.name) || node.name == "style"
      allowed_namespace = [nil, "http://www.w3.org/1999/xhtml"].include?(node.namespace&.href)
      unless node.element? && allowed_tag && allowed_namespace
        node.remove
        return Loofah::Scrubber::STOP
      end

      if node.name == "style"
        @stylesheets << sanitize_stylesheet(node.text)
        node.remove
        return Loofah::Scrubber::STOP
      end

      if node.name == "img"
        asset = embedded_asset(node["data-contained-asset"])
        unless asset
          node.remove
          return Loofah::Scrubber::STOP
        end
      end

      node.attribute_nodes.each do |attribute|
        value = sanitize_attribute(node.name, attribute.name, attribute.value)
        attribute.remove
        node[attribute.name] = value unless value.nil? || value.empty?
      end
      if asset
        node["src"] = asset.data_uri
        node["width"] = asset.width.to_s
        node["height"] = asset.height.to_s
      end
      Loofah::Scrubber::CONTINUE
    end

    def sanitize_attribute(tag, name, value)
      case name
      when "style"
        check_css_budget(value)
        sanitize_declarations(Crass.parse_properties(value, preserve_comments: false))
      when "class", "id"
        value if value.bytesize <= 512 && value.match?(/\A[a-zA-Z0-9_\- ]+\z/)
      when "title", "aria-label"
        value if value.bytesize <= 1024
      when "alt"
        value if tag == "img" && value.bytesize <= 1024
      when "dir"
        value if %w[ltr rtl auto].include?(value)
      when "lang"
        value if value.match?(/\A[a-zA-Z]{2,8}(?:-[a-zA-Z0-9]{1,8}){0,3}\z/)
      when "open"
        "open" if tag == "details"
      when "colspan", "rowspan"
        if %w[td th].include?(tag) && value.match?(/\A\d{1,2}\z/) && value.to_i.between?(1, 12)
          value
        end
      when "scope"
        value if tag == "th" && %w[row col rowgroup colgroup].include?(value)
      when "start", "value"
        if ((name == "start" && tag == "ol") || (name == "value" && tag == "li")) &&
             value.match?(/\A-?\d{1,4}\z/)
          value
        end
      end
    end

    def check_css_budget(css)
      @css_bytes += css.bytesize
      if css.bytesize > MAX_CSS_BLOCK_BYTES || @css_bytes > MAX_CSS_BYTES
        raise InvalidSource, "CSS exceeds the size limit"
      end

      # Tokenize first so parentheses inside strings/comments cannot disguise parser recursion.
      tokens = Crass::Tokenizer.tokenize(css, preserve_comments: false)
      raise InvalidSource, "CSS contains too many tokens" if tokens.length > MAX_CSS_TOKENS
      closing_tokens = []
      tokens.each do |token|
        case token[:node]
        when :function, :"("
          closing_tokens << :")"
        when :"["
          closing_tokens << :"]"
        when :"{"
          closing_tokens << :"}"
        when :")", :"]", :"}"
          closing_tokens.pop if closing_tokens.last == token[:node]
        end
        raise InvalidSource, "CSS nesting exceeds the limit" if closing_tokens.length > 16
      end
    end

    def sanitize_stylesheet(css)
      check_css_budget(css)
      Crass
        .parse(css, preserve_comments: false)
        .filter_map do |rule|
          next unless rule[:node] == :style_rule
          @rules += 1
          raise InvalidSource, "CSS contains too many rules" if @rules > MAX_RULES
          selector = rule.dig(:selector, :value)
          unless selector && selector.bytesize <= 512 &&
                   selector.match?(/\A[a-zA-Z0-9_\-\s.#>,+~:*]+\z/)
            next
          end

          declarations = sanitize_declarations(rule[:children])
          "#{selector}{#{declarations}}" unless declarations.empty?
        end
        .join("\n")
    end

    def sanitize_declarations(nodes)
      nodes
        .filter_map do |node|
          next unless node[:node] == :property
          @declarations += 1
          if @declarations > MAX_DECLARATIONS
            raise InvalidSource, "CSS contains too many declarations"
          end

          name = node[:name]
          custom = name.match?(CUSTOM_PROPERTY)
          name = name.downcase unless custom
          next unless PROPERTIES.include?(name) || custom

          @value_tokens = 0
          value = serialize_values(node[:children], custom: custom)
          unless value && !value.strip.empty? && allowed_effect?(name, node[:children], value.strip)
            next
          end
          @font_values << value if custom || %w[font font-family].include?(name)
          "#{name}:#{value.strip}"
        end
        .join(";")
    end

    def serialize_values(tokens, depth: 0, custom: false, in_repeat: false)
      return if depth > 6

      values = tokens.map { |token| serialize_value(token, depth:, custom:, in_repeat:) }
      values.join if values.none?(&:nil?)
    end

    def serialize_value(token, depth:, custom:, in_repeat:)
      @value_tokens += 1
      return if @value_tokens > MAX_VALUE_TOKENS

      case token[:node]
      when :whitespace
        " "
      when :ident
        return unless token[:value].match?(IDENTIFIER)
        token[:value]
      when :hash
        unless token[:value].match?(/\A(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})\z/i)
          return
        end
        "##{token[:value]}"
      when :number, :percentage, :dimension
        number = token[:value]
        return unless number.is_a?(Numeric) && number.finite? && number.abs <= MAX_NUMBER
        unit = token[:node] == :percentage ? "%" : ""
        if token[:node] == :dimension
          unit = token[:unit].downcase
          return if UNITS.exclude?(unit)
        end
        "#{number}#{unit}"
      when :string
        return unless token[:value].bytesize <= 256 && token[:value].match?(/\A[a-zA-Z0-9_ .-]*\z/)
        "\"#{token[:value]}\""
      when :comma
        ","
      when :delim
        token[:value] if token[:value] == "/"
      when :function
        name = token[:name].downcase
        if name == "asset"
          return if custom || depth.positive?
          arguments = token[:value].reject { |argument| argument[:node] == :whitespace }
          return unless arguments.length == 1 && arguments.first[:node] == :string
          asset = embedded_asset(arguments.first[:value])
          return asset && "url(\"#{asset.data_uri}\")"
        end
        if TRANSFORMS.include?(name) || FILTERS.include?(name)
          return if custom || depth.positive?
          return serialize_effect(name, token[:value])
        end
        return if FUNCTIONS.exclude?(name)
        return if custom && %w[var repeat].include?(name)
        if name == "repeat"
          return if in_repeat
          arguments = token[:value].reject { |argument| argument[:node] == :whitespace }
          count = arguments.first
          unless count && count[:node] == :number && count[:type] == :integer &&
                   count[:value].between?(1, 12) && arguments[1]&.dig(:node) == :comma
            return
          end
        end
        if name == "var"
          first = token[:value].find { |argument| argument[:node] != :whitespace }
          return unless first && first[:node] == :ident && first[:value].match?(CUSTOM_PROPERTY)
        end
        arguments =
          serialize_values(
            token[:value],
            depth: depth + 1,
            custom: custom,
            in_repeat: in_repeat || name == "repeat",
          )
        "#{name}(#{arguments})" if arguments
      end
    end

    def embedded_asset(id)
      asset = @assets.fetch(id)
      return unless asset
      @asset_uses += 1
      @embedded_asset_bytes += asset.data_uri.bytesize
      if @asset_uses > MAX_ASSET_USES || @embedded_asset_bytes > MAX_EMBEDDED_ASSET_BYTES
        raise InvalidSource, "Embedded images exceed the size limit"
      end
      asset
    end

    def allowed_effect?(name, tokens, value)
      values = tokens.reject { |token| token[:node] == :whitespace }
      case name
      when "position"
        %w[static relative absolute].include?(value)
      when "transform", "filter"
        allowed = name == "transform" ? TRANSFORMS : FILTERS
        value == "none" ||
          values.all? do |token|
            token[:node] == :function && allowed.include?(token[:name].downcase)
          end
      when "box-shadow", "text-shadow"
        values.all? do |token|
          case token[:node]
          when :number, :dimension
            token[:value].abs <= 32 && (token[:node] == :number || token[:unit].downcase == "px")
          when :function
            %w[rgb rgba hsl hsla hwb oklch oklab lab lch].include?(token[:name].downcase)
          when :ident
            %w[none inset transparent currentcolor black white red green blue gray grey].include?(
              token[:value].downcase,
            )
          else
            %i[hash comma].include?(token[:node])
          end
        end
      else
        true
      end
    end

    def serialize_effect(name, tokens)
      arguments = tokens.reject { |token| token[:node] == :whitespace || token[:node] == :comma }
      return unless arguments.length.between?(1, 2)
      return if FILTERS.include?(name) && arguments.length != 1
      unless tokens.all? { |token|
               %i[whitespace comma number percentage dimension].include?(token[:node])
             }
        return
      end

      allowed =
        arguments.all? do |token|
          number = token[:value]
          next false unless number.is_a?(Numeric) && number.finite?
          unit = token[:unit]&.downcase
          if name.start_with?("rotate", "skew") || name == "hue-rotate"
            token[:node] == :dimension &&
              (
                (unit == "deg" && number.abs <= 360) || (unit == "turn" && number.abs <= 1) ||
                  (unit == "rad" && number.abs <= 6.284)
              )
          elsif name.start_with?("translate")
            (token[:node] == :number && number.zero?) ||
              (token[:node] == :dimension && unit == "px" && number.abs <= 1000) ||
              (token[:node] == :percentage && number.abs <= 100)
          elsif name.start_with?("scale")
            token[:node] == :number && number.abs <= 10
          elsif name == "blur"
            token[:node] == :dimension && unit == "px" && number.between?(0, 12)
          else
            (token[:node] == :number && number.between?(0, 2)) ||
              (token[:node] == :percentage && number.between?(0, 200))
          end
        end
      return unless allowed
      serialized = serialize_values(tokens, depth: 1)
      "#{name}(#{serialized})" if serialized
    end
  end
end
