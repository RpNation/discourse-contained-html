import {
  clearRender,
  click,
  fillIn,
  find,
  render,
  settled,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import ComposerEditor from "discourse/components/composer-editor";
import { USER_OPTION_COMPOSITION_MODES } from "discourse/lib/constants";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import initializer from "discourse/plugins/discourse-contained-html/discourse/initializers/contained-html-composer";

const HTML_INPUT = "textarea.contained-html-composer__input";
const MODE_BUTTON = "button.contained-html-mode";
const SOURCE = '<p id="contained-composer-author-probe">Character details</p>';
const FENCED_SOURCE = `\`\`\`rpn-html\n${SOURCE}\n\`\`\``;

module("Contained HTML | Integration | composer mode", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.siteSettings.contained_html_enabled = true;
    this.currentUser.set(
      "user_option.composition_mode",
      USER_OPTION_COMPOSITION_MODES.markdown
    );

    this.composer = this.owner.lookup("service:composer");
    this.model = this.owner.lookup("service:store").createRecord("composer", {
      reply: "",
      action: "reply",
    });
    this.composer.set("model", this.model);
    this.composer.showPreview = true;

    pretender.get("/emojis/search-aliases.json", () => response([]));
    initializer.initialize(this.owner);
  });

  test("HTML mode edits source while previews and drafts retain an escaped fence", async function (assert) {
    await render(<template><ComposerEditor /></template>);

    assert.dom(MODE_BUTTON).hasText("HTML");
    assert.dom(".composer-toggle-switch").exists();

    await click(MODE_BUTTON);

    assert.dom(HTML_INPUT).exists();
    assert.dom(MODE_BUTTON).hasText("Markdown");
    assert.dom(".composer-toggle-switch").isVisible();
    assert.dom(".d-editor-preview-wrapper").isVisible();

    await fillIn(HTML_INPUT, SOURCE);

    assert.dom(HTML_INPUT).hasValue(SOURCE);
    assert.true(
      /^`{3,}rpn-html\n/.test(this.model.reply),
      "stores an escaped HTML fence"
    );
    assert.true(this.model.reply.includes(SOURCE));
    assert.strictEqual(
      this.model.serializeDraftData().reply,
      this.model.reply,
      "native draft persistence receives the fenced source"
    );
    assert
      .dom('.d-editor-preview pre[data-code-wrap="rpn-html"] code')
      .hasText(SOURCE);
    assert
      .dom("#contained-composer-author-probe")
      .doesNotExist("author HTML is never inserted into the composer document");
  });

  test("returning to Markdown keeps the layout and reopening restores source mode", async function (assert) {
    await render(<template><ComposerEditor /></template>);
    await click(MODE_BUTTON);
    await fillIn(HTML_INPUT, SOURCE);
    const savedReply = this.model.reply;

    await click(MODE_BUTTON);

    assert.dom(HTML_INPUT).doesNotExist();
    assert.dom("textarea.d-editor-input").hasValue(savedReply);
    assert.dom(".composer-toggle-switch").isVisible();
    assert.strictEqual(this.model.reply, savedReply);

    await clearRender();
    await render(<template><ComposerEditor /></template>);

    assert.dom(HTML_INPUT).hasValue(SOURCE);
    assert.strictEqual(this.model.reply, savedReply);
  });

  test("entering from the rich editor does not change the user's editor preference", async function (assert) {
    this.currentUser.set(
      "user_option.composition_mode",
      USER_OPTION_COMPOSITION_MODES.rich
    );
    await render(<template><ComposerEditor /></template>);

    assert.dom(".ProseMirror").exists();
    await click(MODE_BUTTON);
    await fillIn(HTML_INPUT, SOURCE);

    assert.dom(".ProseMirror").doesNotExist();
    assert.dom(HTML_INPUT).hasValue(SOURCE);
    assert.true(this.composer.allowPreview);
    assert.dom(".d-editor-preview-wrapper").isVisible();
    assert.strictEqual(
      this.currentUser.user_option.composition_mode,
      USER_OPTION_COMPOSITION_MODES.rich
    );

    await click(MODE_BUTTON);

    assert.dom("textarea.d-editor-input").exists();
    assert.strictEqual(
      this.currentUser.user_option.composition_mode,
      USER_OPTION_COMPOSITION_MODES.rich,
      "temporary HTML mode does not overwrite the saved rich-editor preference"
    );

    await click(".composer-toggle-switch");
    assert.dom(".ProseMirror").exists();
    assert.strictEqual(this.model.reply, FENCED_SOURCE);
  });

  test("opens an existing layout as HTML even when the user prefers rich text", async function (assert) {
    this.currentUser.set(
      "user_option.composition_mode",
      USER_OPTION_COMPOSITION_MODES.rich
    );
    this.model.set("reply", FENCED_SOURCE);

    await render(<template><ComposerEditor /></template>);

    assert.dom(HTML_INPUT).hasValue(SOURCE);
    assert.dom(".ProseMirror").doesNotExist();
    assert.strictEqual(this.model.reply, FENCED_SOURCE);
  });

  for (const preference of [
    USER_OPTION_COMPOSITION_MODES.markdown,
    USER_OPTION_COMPOSITION_MODES.rich,
  ]) {
    test(`native editor switch preserves HTML with preference ${preference}`, async function (assert) {
      const source = `${SOURCE}\n<pre>\n\`\`\`\nLiteral fence\n</pre>`;
      const reply = `\`\`\`\`rpn-html\n${source}\n\`\`\`\``;
      this.currentUser.set("user_option.composition_mode", preference);
      this.model.set("reply", reply);
      await render(<template><ComposerEditor /></template>);

      assert.dom(HTML_INPUT).hasValue(source);
      assert.dom(".composer-toggle-switch").isVisible();
      await click(".composer-toggle-switch");

      assert.dom(".ProseMirror").exists();
      assert.dom(HTML_INPUT).doesNotExist();
      assert.dom(".composer-toggle-switch").isVisible();
      assert.dom("#contained-composer-author-probe").doesNotExist();
      assert.strictEqual(
        this.model.reply,
        reply,
        "RTE entry keeps exact raw source"
      );

      await click(".composer-toggle-switch");

      assert.dom("textarea.d-editor-input").hasValue(reply);
      assert.dom(".composer-toggle-switch").isVisible();
      assert.dom(".d-editor-preview-wrapper").isVisible();

      await click(".composer-toggle-switch");
      assert.dom(".ProseMirror").exists();
      await click(".composer-toggle-switch");
      assert.dom("textarea.d-editor-input").hasValue(reply);

      await click(MODE_BUTTON);

      assert.dom(HTML_INPUT).hasValue(source);
      assert.dom(".composer-toggle-switch").isVisible();
      assert.strictEqual(
        this.model.reply,
        reply,
        "all mode changes retain exact source"
      );
    });
  }

  for (const [description, reply] of [
    ["ordinary prose", "Keep my **formatted** reply intact."],
    ["mixed content", `Introduction\n\n${FENCED_SOURCE}`],
    ["multiple layouts", `${FENCED_SOURCE}\n\n${FENCED_SOURCE}`],
  ]) {
    test(`does not reinterpret ${description} as an HTML document`, async function (assert) {
      this.model.set("reply", reply);
      await render(<template><ComposerEditor /></template>);

      assert.dom(MODE_BUTTON).isDisabled();
      assert.dom(HTML_INPUT).doesNotExist();
      assert.dom("textarea.d-editor-input").hasValue(reply);
      assert.strictEqual(this.model.reply, reply);
    });
  }

  test("native quote insertion returns to Markdown and keeps the quote outside the layout", async function (assert) {
    const quote = '[quote="Example"]A quoted reply[/quote]';
    this.model.set("reply", FENCED_SOURCE);
    await render(<template><ComposerEditor /></template>);

    assert.dom(HTML_INPUT).hasValue(SOURCE);

    this.owner
      .lookup("service:app-events")
      .trigger("composer:insert-text", quote);
    await settled();

    assert.dom(HTML_INPUT).doesNotExist();
    assert.true(
      this.model.reply.startsWith(FENCED_SOURCE),
      "the complete fenced layout remains intact"
    );
    assert.true(
      this.model.reply.indexOf(quote) >= FENCED_SOURCE.length,
      "quote is appended outside the HTML source"
    );
    assert.true(
      this.model.reply.startsWith(`${FENCED_SOURCE}\n\n`),
      "the quote cannot become part of the closing fence line"
    );
  });

  test("native formatting leaves a valid fence and starts outside the HTML layout", async function (assert) {
    this.model.set("reply", FENCED_SOURCE);
    await render(<template><ComposerEditor /></template>);

    assert.dom(HTML_INPUT).hasValue(SOURCE);

    this.owner
      .lookup("service:app-events")
      .trigger("composer:apply-surround", "**", "**", "bold_text");
    await settled();

    assert.dom(HTML_INPUT).doesNotExist();
    assert.strictEqual(
      this.model.reply,
      `${FENCED_SOURCE}\n\n**${i18n("composer.bold_text")}**`,
      "formatting starts after a blank line and cannot attach to the closing fence"
    );
    assert
      .dom('.d-editor-preview pre[data-code-wrap="rpn-html"] code')
      .hasText(
        SOURCE,
        "the original HTML source remains inside its code block"
      );
    assert
      .dom(".d-editor-preview p strong")
      .hasText(i18n("composer.bold_text"));
  });

  test("switching to another draft clears the previous HTML source and mode", async function (assert) {
    this.model.set("reply", FENCED_SOURCE);
    await render(<template><ComposerEditor /></template>);
    assert.dom(HTML_INPUT).hasValue(SOURCE);

    await clearRender();
    const ordinaryReply = "A separate **ordinary** draft.";
    const nextModel = this.owner
      .lookup("service:store")
      .createRecord("composer", { reply: ordinaryReply, action: "reply" });
    this.composer.set("model", nextModel);
    await render(<template><ComposerEditor /></template>);

    assert.dom(HTML_INPUT).doesNotExist();
    assert.dom("textarea.d-editor-input").hasValue(ordinaryReply);
    assert.dom(MODE_BUTTON).hasText("HTML").isDisabled();
    assert.dom(".composer-toggle-switch").exists();
    assert.strictEqual(nextModel.reply, ordinaryReply);
    assert.strictEqual(
      this.model.reply,
      FENCED_SOURCE,
      "switching drafts also leaves the earlier layout unchanged"
    );
  });

  for (const eventType of ["paste", "drop"]) {
    test(`blocks file ${eventType} in HTML mode without changing the draft`, async function (assert) {
      this.model.set("reply", FENCED_SOURCE);
      await render(<template><ComposerEditor /></template>);

      const transfer = new DataTransfer();
      transfer.items.add(
        new File(["synthetic image"], "layout.png", { type: "image/png" })
      );
      const event =
        eventType === "paste"
          ? new ClipboardEvent("paste", {
              bubbles: true,
              cancelable: true,
              clipboardData: transfer,
            })
          : new DragEvent("drop", {
              bubbles: true,
              cancelable: true,
              dataTransfer: transfer,
            });

      find(HTML_INPUT).dispatchEvent(event);
      await settled();

      assert.true(
        event.defaultPrevented,
        "file handling is stopped before upload"
      );
      assert
        .dom(".contained-html-composer__notice")
        .hasAttribute("role", "status")
        .hasText(i18n("contained_html.composer.upload_notice"));
      assert.dom(HTML_INPUT).hasValue(SOURCE);
      assert.strictEqual(this.model.reply, FENCED_SOURCE);
      assert.false(Boolean(this.composer.isUploading));
    });
  }

  test("cannot enter HTML mode while a native upload is in progress", async function (assert) {
    this.composer.set("isUploading", true);
    await render(<template><ComposerEditor /></template>);

    assert.dom(MODE_BUTTON).isDisabled();
    assert.dom(HTML_INPUT).doesNotExist();
    assert.strictEqual(this.model.reply, "");

    this.composer.set("isUploading", false);
    await settled();

    assert.dom(MODE_BUTTON).isNotDisabled();
    await click(MODE_BUTTON);
    assert.dom(HTML_INPUT).exists();
  });

  test("HTML containing fence and textarea delimiters remains one escaped preview block", async function (assert) {
    const hostileSource = [
      "</textarea>",
      "```",
      '<style id="contained-composer-style-probe">.d-header { display: none; }</style>',
      '<section id="contained-composer-live-probe">Remain isolated</section>',
    ].join("\n");

    await render(<template><ComposerEditor /></template>);
    await click(MODE_BUTTON);
    await fillIn(HTML_INPUT, hostileSource);

    assert.dom(HTML_INPUT).hasValue(hostileSource);
    assert.dom(".d-editor-preview pre").exists({ count: 1 });
    assert
      .dom('.d-editor-preview pre[data-code-wrap="rpn-html"] code')
      .hasText(hostileSource);
    assert.dom("#contained-composer-style-probe").doesNotExist();
    assert.dom("#contained-composer-live-probe").doesNotExist();
    assert.strictEqual(this.model.serializeDraftData().reply, this.model.reply);
  });
});
