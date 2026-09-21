import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { schedule } from "@ember/runloop";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import { i18n } from "discourse-i18n";
import {
  decodeHtmlSource,
  encodeHtmlSource,
} from "discourse/plugins/discourse-contained-html/discourse/lib/contained-html-source";
import ContainedHtmlTextManipulation from "discourse/plugins/discourse-contained-html/discourse/lib/contained-html-text-manipulation";

export default class ContainedHtmlEditor extends Component {
  @service containedHtmlComposer;

  @tracked uploadNotice = false;

  preserveExternalChanges = modifier(() => {
    if (decodeHtmlSource(this.args.value) === null) {
      const editor = this.containedHtmlComposer.editor;
      schedule("afterRender", () => this.containedHtmlComposer.exit(editor));
    }
  });

  #textManipulation;

  #cleanup;

  @action
  setup(textarea) {
    const editor = this.containedHtmlComposer.editor;
    const manipulation = new ContainedHtmlTextManipulation(getOwner(this), {
      editor,
      markdownOptions: this.args.markdownOptions,
      mode: this.containedHtmlComposer,
      textarea,
    });
    this.#textManipulation = manipulation;

    const uploadRoot =
      textarea.closest("#reply-control") ?? textarea.closest(".wmd-controls");
    const events = ["paste", "drop", "dragover", "change"];
    for (const event of events) {
      uploadRoot?.addEventListener(event, this.blockFiles, { capture: true });
    }
    const cleanup = this.args.onSetup(manipulation);

    this.#cleanup = () => {
      cleanup?.();
      for (const event of events) {
        uploadRoot?.removeEventListener(event, this.blockFiles, {
          capture: true,
        });
      }
    };
  }

  @action
  teardown() {
    this.#cleanup?.();
  }

  get source() {
    return decodeHtmlSource(this.args.value) ?? "";
  }

  @action
  blockFiles(event) {
    const transfer = event.clipboardData ?? event.dataTransfer;
    const hasFiles =
      transfer?.files?.length ||
      Array.from(transfer?.types ?? []).includes("Files");
    const pickedFiles =
      event.type === "change" &&
      event.target.type === "file" &&
      event.target.files?.length;
    if (hasFiles || pickedFiles) {
      event.preventDefault();
      event.stopImmediatePropagation();
      this.uploadNotice = true;
    }
  }

  @action
  changeSource(event) {
    if (decodeHtmlSource(this.args.value) === null) {
      this.containedHtmlComposer.exit(this.containedHtmlComposer.editor);
      return;
    }

    this.args.change({
      target: { value: encodeHtmlSource(event.target.value) },
    });
  }

  @action
  indent(event) {
    if (event.key === "Tab" && !event.ctrlKey && !event.metaKey) {
      if (
        this.#textManipulation.indentSelection(
          event.shiftKey ? "left" : "right"
        )
      ) {
        event.preventDefault();
      }
    }
  }

  @action
  focusIn() {
    schedule("afterRender", () => {
      if (!this.isDestroying && !this.isDestroyed) {
        this.args.focusIn?.();
      }
    });
  }

  @action
  focusOut() {
    schedule("afterRender", () => {
      if (!this.isDestroying && !this.isDestroyed) {
        this.args.focusOut?.();
      }
    });
  }

  <template>
    <div class="contained-html-composer" {{this.preserveExternalChanges}}>
      <div class="contained-html-composer__label">
        {{i18n "contained_html.composer.source_label"}}
      </div>
      {{#if this.uploadNotice}}
        <p class="contained-html-composer__notice" role="status">
          {{i18n "contained_html.composer.upload_notice"}}
        </p>
      {{/if}}
      <textarea
        aria-label={{i18n "contained_html.composer.source_label"}}
        autocapitalize="off"
        autocomplete="off"
        class="{{@class}} contained-html-composer__input"
        disabled={{@disabled}}
        id={{@id}}
        placeholder={{i18n "contained_html.composer.placeholder"}}
        spellcheck="false"
        value={{this.source}}
        {{on "input" this.changeSource}}
        {{on "keydown" this.indent}}
        {{on "focusin" this.focusIn}}
        {{on "focusout" this.focusOut}}
        {{didInsert this.setup}}
        {{willDestroy this.teardown}}
      ></textarea>
    </div>
  </template>
}
