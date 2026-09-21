import TextareaTextManipulation from "discourse/lib/textarea-text-manipulation";

export default class ContainedHtmlTextManipulation extends TextareaTextManipulation {
  #editor;
  #mode;

  constructor(owner, options) {
    super(owner, options);
    this.#editor = options.editor;
    this.#mode = options.mode;
  }

  applySurroundSelection(...args) {
    this.#mode.performNativeAction(
      this.#editor,
      "applySurroundSelection",
      args
    );
  }

  autocomplete() {
    return false;
  }

  insertBlock(...args) {
    this.#mode.performNativeAction(this.#editor, "insertBlock", args);
  }

  insertText(...args) {
    this.#mode.performNativeAction(this.#editor, "insertText", args);
  }

  // Keep native textarea paste; rich paste would rewrite HTML as Markdown.
  paste() {
    return false;
  }
}
