# Architecture and remaining work

## Security architecture

1. Discourse cooks the block as escaped code. Author markup never becomes a
   live element in the surrounding forum document.
2. A trusted decorator sends that source to a bounded JSON-only endpoint.
   Saved posts and composer previews use this same renderer.
3. The server parses HTML using Loofah/Nokogiri's HTML5 parser, applies explicit
   tag/attribute allowlists, and filters styles through a Crass-based CSS policy.
4. The server adds its own document shell and restrictive Content Security
   Policy. Author scripts, URL loads, forms, embeds and document directives are
   removed. There is no server-side fetching of submitted URLs.
5. Trusted frontend code creates an iframe with **`sandbox=""`** and assigns
   the document only to `iframe.srcdoc`. No `allow-scripts`, `allow-same-origin`,
   navigation, popup, download or form permissions are granted. Its origin is
   opaque and its CSS is confined to its own document.
6. The parent chooses a fixed, bounded frame size and displays an outer label
   and source disclosure. There is no message listener or auto-resize bridge.

HTML sanitization and iframe isolation serve different purposes. Sanitization
reduces dangerous content; the iframe provides the document and origin boundary.
CSS prefixes, Shadow DOM, `@scope`, a wrapper div, or a custom tag alone do not
meet the requirement that user styles cannot alter forum UI.

Shadow DOM scopes selectors for components but shares the page's origin and
JavaScript environment. A closed shadow root is not an access-control boundary,
and selector scoping alone does not confine painting or prevent host styling.
It can organize trusted widgets; it cannot replace the iframe sandbox here.
This remains true when author JavaScript is forbidden: CSS can still affect the
host or paint outside the component, and a missed event handler would execute
with the forum's privileges. Shadow DOM has no per-root script-disable sandbox.

**Current requirement: no JavaScript executes inside the layout frame.** This
includes both author scripts and plugin-owned scripts for widgets or sizing.
The server removes executable markup, CSP specifies `script-src 'none'`, and
the empty iframe sandbox independently denies scripts. The trusted Discourse
frontend still uses its own JavaScript to create the frame; it never evaluates
the author's source or inserts it as live markup into the forum document.

The sandbox does not provide CPU/memory quotas. HTML/CSS complexity limits reduce
abuse but do not prove resistance to every browser rendering denial of service.
Keep browsers and sanitizer dependencies patched and independently review the
implementation before making it available to untrusted users.

## Prototype policy

- Supports a restricted subset of semantic HTML, tables, layout containers,
  inline styling, style blocks, Flexbox/Grid, colors, gradients, and native
  `details`/`summary` disclosures.
- Denies author JavaScript, event handlers, forms/inputs, embedded frames,
  SVG/MathML, executable URLs, external stylesheets, imports, CSS animations, and
  CSS outside the explicit property/function policy.
- Arbitrary image/font URLs, media and clickable links are not enabled. The
  Sock Pile experiment includes a temporary administrator-packaged raster registry:
  locally supplied, decoded/re-encoded PNG/WebP images referenced by SHA256,
  never a runtime URL fetch. The third-party demo images are not distributed
  in this repository. Only registered images become data URLs; author data URLs remain denied.
  The reviewed Sims image retains its eight-frame animation without scripts.
  Packaged WOFF2 files supply Bricolage Grotesque, Tilt Neon and a renamed subset
  of Font Awesome icons. The renderer generates trusted font rules; author
  `@font-face` remains forbidden. CSP permits registered images/fonts via data
  URLs while keeping network destinations blocked.
- Relative/absolute positioning, outlines, small shadows and bounded transforms
  and filters are supported. Fixed/sticky positioning remains denied. Blur is
  capped at 12 px, shadow lengths at 32 px, and asset expansion at 4 MiB/64 uses
  per block. No iframe script or same-origin permissions were added.
- Limits input to 256 KiB per block and renders at most three blocks per
  decorated post/preview. Server parsing, DOM and CSS budgets apply separately.
- Frames default to 480 px and scroll internally. An optional leading comment
  `<!-- layout-height: 600 -->` requests a fixed height between 200 and 1600 px.
  Both server and parent renderer enforce that range; source cannot set any
  other outer-frame styles. No child script or automatic sizing bridge is used.
- No new persistent database records or source cache are created by rendering.
  Responses use `Cache-Control: no-store`; submitted source is filtered from logs.
- Rate limits apply to users (including staff) and IPs. Native site login
  requirements and CSRF protection are retained. Configure a request-body limit
  at the reverse proxy too; controller limits do not prevent upstream allocation.
- The setting `contained_html_enabled` defaults to false and is the kill switch.

The authoritative allowlists and limits are in
[`lib/contained_html/sanitizer.rb`](../lib/contained_html/sanitizer.rb).

## Work needed before a BBCode replacement

### Stored blocks and a render route

Separating layouts into a table linked to their posts is a sound production
option. Store the post ID, block position, source revision/digest, policy version,
sanitized document and plain-text fallback. Rebuild when the source or policy
changes; honor edits, deletion, exports and permission changes. Never treat an
unpredictable block ID as authorization.

The forum must check `Guardian` access to the associated post/topic before
returning a document, including for messages and restricted categories. Composer
draft previews should continue using the same sanitizer without creating public
render records. Use an authenticated JSON response with `srcdoc`, or a dedicated
renderer on a different, cookie-free site using short-lived scoped authorization.
Avoid a broadly shared parent-domain cookie. `iframe[credentialless]` can provide
extra protection where supported, but browser support is insufficient to make it
the sole cookie boundary.

For a standalone HTML render URL, send a **response-header** CSP with `sandbox`,
restricted `frame-ancestors`, scripts/objects/network blocked by default, plus
`Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`, and appropriate
private caching. These controls must apply when the URL is opened directly too.
Do not let source select response headers, the frame URL, or sandbox attributes.
A database table provides organization and versioning; it does not replace any
of these boundaries. The current prototype deliberately has no standalone HTML
route, records, or renderer cookies.

### Assets and links

The current raster/font registries are administrator-controlled packages. Their
hash, signature and header checks do not fully decode files or validate untrusted
uploads. Offline preparation must validate actual dimensions, frame counts,
decompression limits and font contents before adding a file to a manifest.

Build an approved asset pipeline on a cookie-free origin. Validate image bytes,
MIME types, dimensions and decompression limits; re-encode raster images. Use a
small approved set of hosted fonts. Admit only these asset URLs in both the
sanitizer and CSP. Do not allow arbitrary forum URLs, third-party trackers or
user `@import` rules. Any remote fetcher needs SSRF defenses, including redirect,
DNS/IP, timeout and size checks. Private-message assets must retain authorization
and must not become public through the asset service. Handle ordinary external
links outside the frame with trusted Discourse UI and validated URLs.

### Interactivity and layout

Use native disclosures and other reviewed HTML/CSS-only features. Keep the frame
origin opaque and scripts disabled. Script-based tabs and child-script automatic
height measurement are out of scope under the no-JavaScript requirement. A trusted
control outside the frame could choose a bounded height without executing code
inside it. Never add `allow-scripts` or `allow-same-origin` as a layout workaround.

### Discourse features and author experience

Add a composer insert button, templates, sanitizer feedback, a plain reading
view and source copy/edit tools. Test rich-editor round trips before enabling
that editor for these blocks. Add semantic text fallbacks for search, excerpts,
quotes, email, RSS, notifications, screen readers and printing. The prototype's
fallback is escaped source, so these are not yet polished. Run multi-post and
rapid-preview load tests and bound active offscreen frames.

### Migration

Keep existing BBCode until the replacement passes representative layout tests.
Inventory the actual tags and CSS, convert with a structured parser, and retain
the original raw posts plus a versioned conversion report. Preserve Discourse
quotes, mentions, uploads and oneboxes outside the design block. Convert a small
fixture set, review differences, then perform resumable batches on the servers.
Some Sock Pile source posts exceed 180 KiB: do not choose migration budgets based
only on tiny examples. Run migration batches in a dedicated migration environment.

### Release gates

- Independent security review of the sanitizer, transport, lifecycle and sandbox.
- Malformed HTML/mutation-XSS corpus, CSS escape/network cases, frame escape,
  spoofed wrapper, privacy, CSRF, request limits and stale preview tests.
- Network capture proving blocked content cannot contact forum endpoints,
  third-party hosts or private network addresses.
- Chromium, Firefox and real Safari/WebKit desktop/mobile verification.
- Keyboard and screen-reader checks, clear fallback, performance limits and
  rollback plan, with sandbox flags kept fixed in code.
- A restricted beta with monitoring before public rollout and legacy retirement.

## References

- [MDN iframe sandbox](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/iframe#sandbox)
- [MDN srcdoc security considerations](https://developer.mozilla.org/en-US/docs/Web/API/HTMLIFrameElement/srcdoc#security_considerations)
- [MDN credentialless iframe support](https://developer.mozilla.org/en-US/docs/Web/API/HTMLIFrameElement/credentialless)
- [MDN CSP sandbox response header](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/sandbox)
- [MDN Shadow DOM and closed roots](https://developer.mozilla.org/en-US/docs/Web/API/Web_components/Using_shadow_DOM#element.shadowroot_and_the_mode_option)
- [OWASP XSS prevention and sanitization](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html)
- [OWASP HTML5 security](https://cheatsheetseries.owasp.org/cheatsheets/HTML5_Security_Cheat_Sheet.html)
- [Loofah](https://github.com/flavorjones/loofah)
- [Crass](https://github.com/rgrove/crass)

PHP HTML Purifier is not a direct fit for a Ruby Discourse plugin. DOMPurify is
a maintained browser-side option, but HTML sanitization alone does not establish
CSS containment or filter every CSS/network capability. The prototype uses the
existing Ruby stack and a separate, deliberately constrained CSS policy instead.
