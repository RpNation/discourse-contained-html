# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

describe ContainedHtml::Sanitizer do
  def rendered(source)
    Nokogiri.HTML5(described_class.render(source))
  end

  it "preserves layout, custom literal colors, gradients and native disclosure content" do
    document = rendered(<<~HTML)
      <style>.card { --accent: #803370; display: grid; grid-template-columns: repeat(2, 1fr); color:var(--accent); }</style>
      <section class="card" style="background:linear-gradient(45deg, #fff, rgb(20, 30, 40));padding:12px">
        <h2>Character sheet</h2><details open><summary>History</summary><p>A long story.</p></details>
      </section>
    HTML
    expect(document.at_css("section.card h2").text).to eq("Character sheet")
    expect(document.at_css("details")["open"]).to eq("open")
    expect(document.at_css("section")["style"]).to include("linear-gradient", "padding:12px")
    expect(document.at_css("style").text).to include(
      "--accent:#803370",
      "repeat(2, 1fr)",
      "var(--accent)",
    )
  end

  it "places a trusted restrictive CSP before all styles and body content" do
    document = rendered('<meta http-equiv="refresh" content="0;url=https://evil.test"><p>Hello</p>')
    first = document.at_css("head").element_children.first
    expect(first.name).to eq("meta")
    expect(first["http-equiv"]).to eq("Content-Security-Policy")
    expect(first["content"]).to include(
      "default-src 'none'",
      "script-src 'none'",
      "base-uri 'none'",
      "form-action 'none'",
    )
    expect(document.css("meta[http-equiv=refresh]")).to be_empty
    expect(document.at_css("body").text.strip).to eq("Hello")
  end

  it "removes active tags, namespaces, network elements and event attributes" do
    document = rendered(<<~HTML)
      <script>parent.pwned=true</script><iframe srcdoc="bad"></iframe>
      <form action="/logout"><input autofocus><button>Send</button></form>
      <svg><foreignObject><p>namespace trick</p></foreignObject></svg>
      <math><mi>x</mi></math><template><img src="https://evil.test"></template>
      <link rel="preload" href="https://evil.test"><img src="/logout" onerror="alert(1)">
      <object data="/admin"></object><audio src="https://evil.test"></audio>
      <a href="javascript:alert(1)" target="_top" ping="https://evil.test">Link</a>
      <div id="safe" class="card" onclick="alert(1)" data-injected="true" contenteditable="true">Allowed</div>
    HTML
    expect(document.css("body *").map(&:name)).to eq(["div"])
    expect(document.at_css("body div").attribute_nodes.map(&:name)).to contain_exactly(
      "id",
      "class",
    )
    expect(document.at_css("body").text).to include("Allowed")
    expect(document.to_html).not_to include(
      "evil.test",
      "onerror",
      "parent.pwned",
      "namespace trick",
    )
  end

  it "drops CSS resource functions even when names are escaped or nested in variables" do
    document = rendered(<<~'HTML')
      <style>@import "https://evil.test"; @font-face {src:url(https://evil.test)}
      .card { background:u\72l(https://evil.test); --image: url('/logout'); color:red; }
      </style>
      <p style="background: image-set('https://evil.test'); cursor:url(/logout); width:expression(alert(1)); --chain:var(--other); color:blue">Safe</p>
    HTML
    expect(document.at_css("style").text).to include(".card{color:red}")
    expect(document.at_css("p")["style"]).to eq("color:blue")
    expect(document.to_html).not_to include(
      "evil.test",
      "url(",
      "expression(",
      "@import",
      "@font-face",
      "--chain",
    )
  end

  it "serializes CSS strings without allowing rawtext breakouts" do
    document = rendered(<<~HTML)
      <p style="font-family: '&lt;/style&gt;&lt;script&gt;alert(1)&lt;/script&gt;';color:red">Text</p>
      <style>.x {font-family: "safe"} </style><script>alert(2)</script>
    HTML
    expect(document.css("script")).to be_empty
    expect(document.at_css("p")["style"]).to eq("color:red")
    expect(document.at_css("style").text).to include('font-family:"safe"')
  end

  it "normalizes selectors and drops at rules, large values, amplification and unapproved effects" do
    document = rendered(<<~'HTML')
      <style>\62ody {color:red} .good {color:blue}
      @keyframes a {to{opacity:0}}
      </style>
      <p style="width:999999999px;position:fixed;z-index:9999;animation:a 1s;filter:blur(20px);grid-template-columns:repeat(1000,1fr);color:green">Test</p>
      <p style="grid-template-columns:repeat(2,repeat(2,1fr));--a:var(--b);width:calc(10000px * 10000);padding:2px">Bounded</p>
    HTML
    expect(document.css("p").map { |node| node["style"] }).to eq(%w[color:green padding:2px])
    expect(document.at_css("style").text).to include(".good{color:blue}")
    expect(document.at_css("style").text).to include("body{color:red}")
    expect(document.at_css("style").text).not_to include("keyframes", '\\62ody')
  end

  it "keeps user text and classes confined to body markup" do
    document =
      rendered(
        '</body></html><div class="d-header">Header spoof</div><!-- x --><p>&lt;script&gt;</p>',
      )
    expect(document.css("html").length).to eq(1)
    expect(document.at_css("body .d-header").text).to eq("Header spoof")
    expect(document.css("script")).to be_empty
    expect(document.at_css("p").text).to eq("<script>")
    expect(document.xpath("//comment()")).to be_empty
  end

  it "keeps malformed namespace and rawtext payloads inert after browser-style reparsing" do
    payloads = [
      '<math><mtext><table><mglyph><style><!--</style><img title="--><img src=/logout onerror=alert(1)>">',
      '<svg><p><style><g title="</style><img src=/logout onerror=alert(1)>">',
      '<noscript><p title="</noscript><img src=/logout onerror=alert(1)>">',
      '<style>.x {font-family:"</style><iframe srcdoc=&quot;bad&quot;>"}</style>',
    ]

    payloads.each do |source|
      document = rendered(source)
      expect(document.css("script, iframe, img, svg, math, noscript, template")).to be_empty
      expect(document.xpath("//*[@src or @href or @srcdoc or @onerror]")).to be_empty
      expect(document.css("html").length).to eq(1)
    end
  end

  it "preserves case-sensitive custom property names while canonicalizing ordinary properties" do
    document = rendered('<p style="--Accent: #abc; COLOR: var(--Accent)">Text</p>')
    expect(document.at_css("p")["style"]).to eq("--Accent:#abc;color:var(--Accent)")
  end

  it "allows bounded decorative effects while rejecting viewport placement and expensive effects" do
    document = rendered(<<~HTML)
      <div style="position:relative;outline:2px solid #fff;box-shadow:1px 1px 3px #123;transform:skew(0deg,-15deg) rotate(-30deg) scalex(.7) rotatex(-60deg);filter:contrast(1.1) grayscale(50%) blur(2px)">Art</div>
      <p style="position:fixed;filter:blur(80px);transform:scale(10000);text-shadow:0 0 9999px red;color:blue">Rejected</p>
      <p style="--large:10000px;--effect:blur(80px);position:var(--position);filter:var(--effect);transform:translate(var(--large));box-shadow:0 0 var(--large);color:green">Variables</p>
    HTML
    expect(document.at_css("div")["style"]).to include(
      "position:relative",
      "box-shadow:1px 1px 3px #123",
      "rotatex(-60deg)",
      "blur(2px)",
    )
    expect(document.css("p").map { |node| node["style"] }).to eq(
      %w[color:blue --large:10000px;color:green],
    )
  end

  it "embeds only registered raster assets while dropping author URLs and executable attributes" do
    Dir.mktmpdir do |root|
      bytes =
        Base64.decode64(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZlSAAAAAASUVORK5CYII=",
        )
      id = Digest::SHA256.hexdigest(bytes)
      FileUtils.mkdir_p(File.join(root, "assets"))
      File.binwrite(File.join(root, "assets", "#{id}.png"), bytes)
      File.write(
        File.join(root, "manifest.json"),
        {
          assets: [{ id: id, filename: "#{id}.png", mime: "image/png", width: 1, height: 1 }],
        }.to_json,
      )
      sanitizer = described_class.new(assets: ContainedHtml::FixtureAssets.new(root: root))
      document = Nokogiri.HTML5(sanitizer.render(<<~HTML))
        <img data-contained-asset="#{id}" src="javascript:alert(1)" onload="parent.pwned=true" alt="Approved art">
        <img src="data:image/svg+xml,bad"><img data-contained-asset="#{"f" * 64}">
        <div style='background-image:asset("#{id}");color:red'>Art</div>
        <p style='background:asset("#{"f" * 64}");color:blue'>Unknown</p>
        <p style='--image:asset("#{id}");background:url(data:image/png;base64,bad);color:green'>No author URLs</p>
      HTML
      image = document.at_css("img")
      expect(document.css("img").length).to eq(1)
      expect(image["src"]).to eq("data:image/png;base64,#{Base64.strict_encode64(bytes)}")
      expect(image.attribute_nodes.map(&:name)).to contain_exactly("src", "width", "height", "alt")
      expect(document.at_css("div")["style"]).to include(
        "background-image:url(\"#{image["src"]}\")",
      )
      expect(document.css("p").map { |node| node["style"] }).to eq(%w[color:blue color:green])
      expect(document.at_css("meta")["content"]).to include("img-src data:", "script-src 'none'")
      expect {
        sanitizer.render(
          "<img data-contained-asset='#{id}'>" * (described_class::MAX_ASSET_USES + 1),
        )
      }.to raise_error(described_class::InvalidSource, "Embedded images exceed the size limit")
    end
  end

  it "rejects excessive source, node count, nesting and attributes" do
    expect { described_class.render("a" * (described_class::MAX_SOURCE_BYTES + 1)) }.to raise_error(
      described_class::InvalidSource,
    )
    expect { described_class.render("<br>" * (described_class::MAX_NODES + 1)) }.to raise_error(
      described_class::InvalidSource,
    )
    expect { described_class.render(("<div>" * 40) + "x" + ("</div>" * 40)) }.to raise_error(
      described_class::InvalidSource,
    )
    attributes = 40.times.map { |index| "data-#{index}='x'" }.join(" ")
    expect { described_class.render("<p #{attributes}>x</p>") }.to raise_error(
      described_class::InvalidSource,
    )
  end

  it "rejects CSS size and parser depth bombs before parsing CSS" do
    expect {
      described_class.render("<style>#{" " * (described_class::MAX_CSS_BLOCK_BYTES + 1)}</style>")
    }.to raise_error(described_class::InvalidSource)
    expect {
      described_class.render("<p style='color:#{"var(" * 40}red#{")" * 40}'>x</p>")
    }.to raise_error(described_class::InvalidSource)
    expect {
      described_class.render("<p style='color:#{"var(/*)*/" * 40}red#{")" * 40}'>x</p>")
    }.to raise_error(described_class::InvalidSource)
  end

  it "rejects non-string or invalid encoded source" do
    expect { described_class.render({ source: "test" }) }.to raise_error(
      described_class::InvalidSource,
    )
    expect { described_class.render("\xff".dup.force_encoding("UTF-8")) }.to raise_error(
      described_class::InvalidSource,
    )
  end
end
