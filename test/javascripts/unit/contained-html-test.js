import { settled, waitUntil } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { withPluginApi } from "discourse/lib/plugin-api";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import initializer from "discourse/plugins/discourse-contained-html/discourse/initializers/contained-html";

const CHILD_DOCUMENT = `<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'"></head><body><p id="contained-child-probe">Synthetic layout</p></body></html>`;

function appendCodeBlock(element, source) {
  const pre = document.createElement("pre");
  pre.dataset.codeWrap = "rpn-html";
  const code = document.createElement("code");
  code.className = "lang-rpn-html";
  code.textContent = source;
  pre.append(code);
  element.append(pre);
}

module("Contained HTML | Integration | frame boundary", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.siteSettings.contained_html_enabled = true;
    this.sandbox = sinon.createSandbox();
    this.cleanups = [];
    this.requests = [];
    this.replies = new Map();
    this.root = document.createElement("div");
    document.getElementById("qunit-fixture").append(this.root);

    withPluginApi((api) => {
      const registration = this.sandbox.stub(
        Object.getPrototypeOf(api),
        "decorateCookedElement"
      );
      initializer.initialize(this.owner);
      this.decorate = registration.firstCall.args[0];
    });

    pretender.post("/contained-html/render.json", (request) => {
      const { source } = JSON.parse(request.requestBody);
      this.requests.push(source);
      return (
        this.replies.get(source) ??
        response({ document: CHILD_DOCUMENT, height: 600 })
      );
    });

    this.addLayout = (source) => {
      const cooked = document.createElement("div");
      appendCodeBlock(cooked, source);
      this.root.append(cooked);
      this.cleanups.push(this.decorate(cooked));
      return cooked;
    };
  });

  hooks.afterEach(function () {
    this.cleanups.forEach((cleanup) => cleanup());
    this.root.remove();
    this.sandbox.restore();
  });

  test("places renderer output only in an opaque sandboxed frame", async function (assert) {
    const source = '<p id="author-source-probe" onclick="alert(1)">Source</p>';
    const cooked = this.addLayout(source);
    await waitUntil(() => cooked.querySelector("iframe"));

    const frame = cooked.querySelector("iframe");
    assert.strictEqual(frame.getAttribute("sandbox"), "");
    assert.strictEqual(
      frame.sandbox.length,
      0,
      "grants no sandbox permissions"
    );
    assert.strictEqual(frame.srcdoc, CHILD_DOCUMENT);
    assert.false(frame.hasAttribute("src"));
    assert.strictEqual(frame.getAttribute("referrerpolicy"), "no-referrer");
    assert.strictEqual(frame.style.height, "600px");
    assert.dom("#contained-child-probe", this.root).doesNotExist();
    assert.dom("#author-source-probe", this.root).doesNotExist();
    assert
      .dom("code", cooked)
      .hasText(source, "retains escaped source fallback");
    assert.deepEqual(this.requests, [source]);
  });

  test("accepts only integer frame heights within the allowed range", async function (assert) {
    const cases = [200, 1600, 199, 1601, "600", null];
    const layouts = cases.map((height) => {
      const source = `Height ${JSON.stringify(height)}`;
      this.replies.set(source, response({ document: CHILD_DOCUMENT, height }));
      return this.addLayout(source);
    });
    await waitUntil(() =>
      layouts.every((layout) => layout.querySelector("iframe"))
    );

    assert.deepEqual(
      layouts.map((layout) => layout.querySelector("iframe").style.height),
      ["200px", "1600px", "", "", "", ""],
      "invalid heights leave the stylesheet default intact"
    );
  });

  test("does not send requests for content removed before decoration", async function (assert) {
    const removed = this.addLayout("Removed before request");
    removed.remove();
    const current = this.addLayout("Current preview");
    await waitUntil(() => current.querySelector("iframe"));

    assert.deepEqual(this.requests, ["Current preview"]);
    assert.dom("iframe", removed).doesNotExist();
  });

  test("ignores a late response after its preview has been replaced", async function (assert) {
    let releaseOldResponse;
    this.replies.set(
      "Old preview",
      new Promise((resolve) => {
        releaseOldResponse = resolve;
      })
    );
    const old = this.addLayout("Old preview");
    await waitUntil(() => this.requests.includes("Old preview"));
    old.remove();

    const current = this.addLayout("New preview");
    await waitUntil(() => current.querySelector("iframe"));
    const currentFrame = current.querySelector("iframe");
    releaseOldResponse(response({ document: "Old response", height: 1600 }));
    await settled();

    assert.dom("iframe", old).doesNotExist();
    assert.strictEqual(current.querySelector("iframe"), currentFrame);
    assert.strictEqual(currentFrame.srcdoc, CHILD_DOCUMENT);
    assert.dom("iframe", this.root).exists({ count: 1 });
  });
});
