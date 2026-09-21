# Contained HTML for Discourse

An experimental plugin for creative HTML/CSS post layouts, rendered inside
sandboxed iframes. It is **disabled by default** and needs independent security
review before use by untrusted users.

## Authoring

Use Discourse's Markdown editor and an `rpn-html` code fence:

````markdown
Ordinary Markdown before the design.

```rpn-html
<!-- layout-height: 600 -->
<style>
.card { padding: 24px; background: #193c35; color: #ffffff; }
</style>
<section class="card">
  <h2>Character name</h2>
  <p>A short introduction.</p>
  <details><summary>History</summary><p>The story so far…</p></details>
</section>
```

Ordinary Markdown after the design.
````

The fence keeps the source escaped through Discourse's native cooker. It is an
authoring delimiter; the iframe sandbox provides the isolation boundary. The
source remains readable when the plugin is disabled or unavailable.

Frames default to 480 px tall and scroll internally. An optional leading
`<!-- layout-height: 600 -->` comment requests a height from 200 to 1600 px.
Up to three blocks are rendered per decorated post or preview, with a maximum
source size of 256 KiB per block.

## What is supported

- Restricted semantic HTML, layout containers, tables, Flexbox/Grid, inline
  styles and style blocks, colors, gradients, and native `details` disclosures.
- Bounded relative/absolute positioning, transforms, filters and shadows.
- Three licensed, packaged fonts: Bricolage Grotesque, Tilt Neon, and a renamed
  Font Awesome subset called RPN Contained Icons.
- An optional administrator-controlled registry for prevalidated PNG/WebP
  assets, including animated WebP. No example photos or forum posts are bundled.

Author JavaScript, event handlers, forms, nested frames, SVG/MathML, arbitrary
resource URLs, clickable links, CSS animations and author `@font-face` rules are
not supported. Ordinary links can remain outside the layout in normal Markdown.

## Containment

The server parses HTML with Loofah/Nokogiri and rebuilds CSS through an explicit
Crass-based allowlist. It adds a restrictive Content Security Policy. Trusted
Discourse code assigns the result only to an iframe's `srcdoc`, with an empty
`sandbox` attribute and no script, same-origin, form, popup or navigation grants.
Author markup never becomes live HTML in the surrounding forum document.

**No JavaScript executes inside the layout frame**, including plugin-owned
widget or sizing scripts. There is no message bridge or automatic frame sizing.
Rendering does not download submitted URLs or create persistent records; JSON
responses are not cached. Native CSRF/login requirements and request limits apply.

Sanitization and sandboxing provide separate protections. Browser rendering
resource exhaustion remains a concern; complexity limits are not CPU or memory
quotas. See [architecture, limits and release gates](docs/architecture.md).

## Development installation

Install the plugin into a Discourse development checkout:

```sh
cd plugins
git clone https://github.com/RpNation/discourse-contained-html.git
```

Restart Discourse, then enable the `contained_html_enabled` site setting for
local evaluation. Use the Markdown editor for the example above. Rich-editor
round trips and full accessibility, search, email and quote integration still
need work. This prototype does not convert existing BBCode posts.

The optional raster registry is empty in a fresh checkout. Its loader and the
font loader assume files prepared and reviewed by an administrator: their
hash/header checks are not validators for untrusted uploads. A production asset
pipeline still needs decoding, re-encoding, permission and privacy controls.

## Validation

From the Discourse checkout:

```sh
bin/rspec plugins/discourse-contained-html/spec
bin/qunit --standalone --target discourse-contained-html
bin/lint --fix plugins/discourse-contained-html
```

GitHub Actions uses Discourse's standard reusable plugin workflow. See
[validation notes](docs/validation.md) for automated coverage and the limits of
local browser testing.

## License

Plugin code: [GPL-3.0-or-later](LICENSE). Packaged fonts retain their own licenses;
see [third-party notices](THIRD_PARTY_NOTICES.md).
