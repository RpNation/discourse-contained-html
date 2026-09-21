import { tracked } from "@glimmer/tracking";
import { schedule } from "@ember/runloop";
import Service, { service } from "@ember/service";
import TextareaEditor from "discourse/components/composer/textarea-editor";
import ContainedHtmlEditor from "discourse/plugins/discourse-contained-html/discourse/components/contained-html-editor";
import {
  decodeHtmlSource,
  encodeHtmlSource,
} from "discourse/plugins/discourse-contained-html/discourse/lib/contained-html-source";

export default class ContainedHtmlComposer extends Service {
  @service composer;

  @tracked editor = null;
  @tracked initializedEditor = null;

  #nativeTransition = null;

  get uploadInProgress() {
    return this.composer.get("isUploading");
  }

  canEnter(editor) {
    const model = editor.outletArgs?.composer;
    return (
      Boolean(model) &&
      editor.composerEvents &&
      editor.outletArgs?.editorType === "composer" &&
      model === this.composer.model &&
      !editor.disabled &&
      !editor.loading &&
      !this.uploadInProgress &&
      (!model.get("reply") || decodeHtmlSource(model.get("reply")) !== null)
    );
  }

  enter(editor) {
    if (!this.canEnter(editor) || this.isActive(editor)) {
      return;
    }

    this.exit(this.editor);
    this.editor = editor;
    this.initializedEditor = editor;

    if (!editor.outletArgs.composer.reply) {
      editor.onChange({ target: { value: encodeHtmlSource("") } });
    }

    this.composer.notifyPropertyChange("model");
    this.composer.set("allowPreview", true);
    editor.editorComponent = ContainedHtmlEditor;
  }

  exit(editor) {
    if (!editor || this.editor !== editor) {
      return;
    }

    this.editor = null;
    if (!editor.isDestroying && !editor.isDestroyed) {
      editor.editorComponent = TextareaEditor;
      this.composer.notifyPropertyChange("model");
    }
  }

  isActive(editor) {
    return (
      Boolean(editor) &&
      this.editor === editor &&
      editor.editorComponent === ContainedHtmlEditor &&
      !editor.isDestroying &&
      !editor.isDestroyed &&
      editor.outletArgs?.composer === this.composer.model
    );
  }

  hasInitializedEditor(model) {
    const editor = this.initializedEditor;
    return (
      Boolean(editor) &&
      !editor.isDestroying &&
      !editor.isDestroyed &&
      editor.outletArgs?.composer === model
    );
  }

  prepareNativeToggle(editor) {
    if (editor !== this.initializedEditor || editor.forceEditorMode != null) {
      return null;
    }

    const transition = { editor, component: editor.editorComponent };
    this.#nativeTransition = transition;
    this.composer.set("allowPreview", null);
    return transition;
  }

  isStaleEditorSetup(editor) {
    return (
      this.#nativeTransition?.editor === editor &&
      this.#nativeTransition.component === editor.editorComponent
    );
  }

  finishNativeToggle(transition) {
    if (this.#nativeTransition === transition) {
      this.#nativeTransition = null;
    }
  }

  performNativeAction(editor, method, args) {
    const model = editor.outletArgs?.composer;
    this.exit(editor);
    schedule("afterRender", () => {
      if (
        !editor.isDestroying &&
        !editor.isDestroyed &&
        model === this.composer.model &&
        editor.outletArgs?.composer === model
      ) {
        const manipulation = editor.textManipulation;
        manipulation.selectText(manipulation.value.length, 0, {
          scroll: false,
        });
        if (decodeHtmlSource(manipulation.value) !== null) {
          manipulation.insertText("\n\n");
          manipulation.selectText(manipulation.value.length, 0, {
            scroll: false,
          });
        }
        manipulation[method](...args);
      }
    });
  }

  toggle(editor) {
    if (this.isActive(editor)) {
      this.exit(editor);
    } else {
      this.enter(editor);
    }
  }
}
