import { action } from "@ember/object";
import { schedule } from "@ember/runloop";
import { USER_OPTION_COMPOSITION_MODES } from "discourse/lib/constants";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import ContainedHtmlEditor from "discourse/plugins/discourse-contained-html/discourse/components/contained-html-editor";
import { decodeHtmlSource } from "discourse/plugins/discourse-contained-html/discourse/lib/contained-html-source";

export default {
  name: "contained-html-composer",

  initialize(container) {
    if (!container.lookup("service:site-settings").contained_html_enabled) {
      return;
    }

    const mode = container.lookup("service:contained-html-composer");

    withPluginApi((api) => {
      api.modifyClass(
        "component:d-editor",
        (Superclass) =>
          class extends Superclass {
            get isRichEditorEnabled() {
              return this.editorComponent === ContainedHtmlEditor
                ? false
                : super.isRichEditorEnabled;
            }

            @action
            setupEditor() {
              // The outgoing input can update while the next editor's bundle
              // loads. It must not re-register itself as the active editor.
              if (!mode.isStaleEditorSetup(this)) {
                return super.setupEditor(...arguments);
              }
            }

            @action
            async toggleRichEditor() {
              const transition = mode.prepareNativeToggle(this);
              try {
                return await super.toggleRichEditor(...arguments);
              } finally {
                mode.finishNativeToggle(transition);
              }
            }
          }
      );

      api.registerValueTransformer(
        "composer-force-editor-mode",
        ({ value, context: { model } }) =>
          value === null &&
          decodeHtmlSource(model?.reply) !== null &&
          !mode.hasInitializedEditor(model)
            ? USER_OPTION_COMPOSITION_MODES.markdown
            : value
      );

      api.onToolbarCreate((toolbar) => {
        const editor = toolbar.context;
        if (
          !editor.composerEvents ||
          editor.outletArgs?.editorType !== "composer"
        ) {
          return;
        }

        for (const group of toolbar.groups) {
          for (const button of group.buttons) {
            const condition = button.condition;
            button.condition = (...args) =>
              !mode.isActive(editor) && (!condition || condition(...args));
          }
        }

        toolbar.addButton({
          id: "contained-html-mode",
          get className() {
            return mode.isActive(editor)
              ? "contained-html-mode contained-html-mode--active"
              : "contained-html-mode";
          },
          group: "fontStyles",
          unshift: true,
          title: "contained_html.composer.switch_to_html",
          get translatedLabel() {
            return i18n(
              mode.isActive(editor)
                ? "contained_html.composer.markdown"
                : "contained_html.composer.html"
            );
          },
          get disabled() {
            return (
              editor.disabled ||
              (!mode.isActive(editor) && !mode.canEnter(editor))
            );
          },
          sendAction: () => mode.toggle(editor),
        });

        const modeButton = toolbar.groups[0].buttons[0];
        Object.defineProperty(modeButton, "title", {
          get: () =>
            i18n(
              mode.isActive(editor)
                ? "contained_html.composer.switch_to_markdown"
                : mode.uploadInProgress
                  ? "contained_html.composer.upload_in_progress"
                  : mode.canEnter(editor)
                    ? "contained_html.composer.switch_to_html"
                    : "contained_html.composer.unavailable"
            ),
        });

        schedule("afterRender", () => {
          if (
            !editor.isDestroying &&
            !editor.isDestroyed &&
            decodeHtmlSource(editor.outletArgs?.composer?.reply) !== null
          ) {
            mode.enter(editor);
          }
        });
      });
    });
  },
};
