# Validation

## Automated checks

From a Discourse checkout with this plugin installed:

```sh
bin/rspec plugins/discourse-contained-html/spec
bin/qunit --standalone --target discourse-contained-html
bin/lint --fix plugins/discourse-contained-html
```

From this plugin directory, frontend lint is also available with `pnpm install`
followed by `pnpm lint`. GitHub Actions uses Discourse's standard reusable plugin
workflow for lint, backend/frontend tests, and boot checks.

The 31 Ruby examples cover sanitizer behavior, malformed HTML/CSS, parser budgets,
registered raster/font validation, executable content rejection, fixed-height
bounds, endpoint input limits, CSRF, login-required sites, rate limits, and the
disabled setting. Raster examples build small synthetic files in temporary
directories; no external photos, network downloads, database dump, or local
forum fixture is required. Font examples use the licensed packaged fonts.

Four frontend examples use synthetic layouts to check the empty iframe sandbox,
source-only fallback, `srcdoc` insertion, bounded heights, removed nodes, and
late responses after a preview is replaced. These run in the standard plugin
QUnit job; they do not require the local comparison topic or its artwork.

## Browser checks performed locally

The local development evaluation on 2026-09-20 checked:

- Public-topic rendering in a fresh anonymous browser and a signed-in session.
- The real composer preview, including stale responses and mixed legacy BBCode
  inside the escaped HTML fence.
- Chromium and Firefox desktop, plus Chromium and WebKit mobile emulation.
- Empty iframe sandbox, opaque origin, blocked scripts/resources, no parent DOM
  or CSS changes, native disclosures, and ordinary replies.
- A Chromium test that supplied deliberately unsafe renderer output to confirm
  sandbox/CSP containment independently of the sanitizer.
- A separate reconstruction of two existing Sock Pile posts: all four blocks,
  local fonts and images, animated raster playback without scripts, complete
  card heights, and desktop/mobile scrolling.

The latest reconstruction checks used Chromium. Earlier desktop WebKit checks
passed, but a revised test navigating between posts stalled in desktop WebKit and
remains incomplete. Mobile emulation is not physical-device Safari/iOS testing.
These results do not replace independent security review or production testing.

The additional local browser scripts and forum comparison data belong to the
development workspace and are not part of this repository's CI. CI does not
claim to run that browser matrix. Before deployment, extend portable browser
coverage to quoting, rich-editor round trips, removal/reinsertion of posts, and
rapid composer updates through the full editor.

## Manual smoke check

1. Enable `contained_html_enabled` on a development site.
2. Paste the README example into a new topic using the Markdown editor.
3. Check the preview and saved post, then edit the source and switch between
   ordinary Markdown and an `rpn-html` fence.
4. Confirm native disclosures work and all design styles stay inside the frame.
5. Try author `<script>`, event handlers, remote CSS/image URLs and an oversized
   height hint; verify no script executes, no remote resources load, and frame
   dimensions stay bounded.
6. Repeat with an anonymous visitor where the topic is public, and on a site
   requiring login to verify normal access controls remain in effect.

See [architecture and release gates](architecture.md) for the remaining review,
accessibility, performance, private-asset, and migration requirements.
