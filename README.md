# Contained HTML for Discourse

An experimental plugin for creative HTML/CSS post layouts, rendered inside
sandboxed iframes. It is **disabled by default** and needs independent security
review before use by untrusted users.

## Authoring

Click **HTML** beside the composer's Markdown/rich-text switch on an empty post.
Write or paste HTML and CSS directly; the preview uses the same contained renderer
as the saved post. You do not need to type a wrapper or code fence.

```html
<!-- layout-height: 600 -->
<style>
  .card {
    padding: 24px;
    background: #193c35;
    color: #ffffff;
  }
</style>
<section class="card">
  <h2>Character name</h2>
  <p>A short introduction.</p>
  <details>
    <summary>History</summary>
    <p>The story so far…</p>
  </details>
</section>
```

An existing post containing one standalone layout opens in HTML mode when edited.
Click **Markdown** to return to the normal source editor. This does not change
your saved Markdown/rich-text preference. Native quote and formatting insertions
return to Markdown and place their content after the layout. Switch to Markdown
to upload files; HTML mode blocks file paste/drop and cannot start during uploads.
The native Markdown/rich-text switch remains available in HTML mode. Choosing
rich text returns to Discourse's editor, where the layout is an escaped code block.

Posts combining ordinary text with layouts, or multiple layouts, stay in Markdown
mode. Their existing `rpn-html` fences continue to work. The toggle is disabled
for these posts so it cannot replace or reinterpret surrounding content.

The plugin maintains an escaped `rpn-html` fence internally for previews, drafts,
saving and editing, choosing a longer delimiter when the source contains
backticks. The fence keeps the source escaped through Discourse's native cooker. It is an
authoring delimiter; the iframe sandbox provides the isolation boundary. The
source remains readable when the plugin is disabled or unavailable.

Frames default to 480 px tall and scroll internally. An optional leading
`<!-- layout-height: 600 -->` comment requests a height from 200 to 1600 px.
Up to three blocks are rendered per decorated post or preview, with a maximum
source size of 256 KiB per block.

Unstyled layouts use the forum's background and light/dark text defaults.
Explicit colors in a layout take precedence. Palette changes apply without
reloading the frame or resetting its open disclosures and scroll position.

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
local evaluation, then click **HTML** in an empty composer for the example above.
HTML layouts use the source editor; visual rich-text editing of their contents
and full accessibility, search, email and quote integration still need work.
This prototype does not convert existing BBCode posts.

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
