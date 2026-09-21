import { ajax } from "discourse/lib/ajax";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

const MAX_BLOCKS = 3;
const MAX_SOURCE_BYTES = 256 * 1024;

function prepareLayout(pre, index) {
  if (pre.closest(".contained-html")) {
    return;
  }

  const source = pre.querySelector("code").textContent;
  const wrapper = document.createElement("section");
  wrapper.className = "contained-html";

  const label = document.createElement("div");
  label.className = "contained-html__label";
  label.textContent = i18n("contained_html.label");

  const status = document.createElement("p");
  status.className = "contained-html__status";
  status.textContent = i18n("contained_html.loading");
  status.setAttribute("role", "status");

  const details = document.createElement("details");
  details.className = "contained-html__source";
  const summary = document.createElement("summary");
  summary.textContent = i18n("contained_html.source");
  details.append(summary);

  pre.replaceWith(wrapper);
  details.append(pre);
  wrapper.append(label, status, details);

  if (
    index >= MAX_BLOCKS ||
    new TextEncoder().encode(source).length > MAX_SOURCE_BYTES
  ) {
    status.textContent = i18n(
      index >= MAX_BLOCKS
        ? "contained_html.limit"
        : "contained_html.unavailable"
    );
    return;
  }

  // Preview nodes are replaced while typing; never render into a stale node.
  const timer = setTimeout(async () => {
    if (!wrapper.isConnected) {
      return;
    }

    try {
      const response = await ajax("/contained-html/render.json", {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify({ source }),
      });
      if (!wrapper.isConnected) {
        return;
      }

      if (typeof response.document !== "string") {
        throw new TypeError("Invalid contained HTML response");
      }

      const frame = document.createElement("iframe");
      frame.className = "contained-html__frame";
      frame.title = i18n("contained_html.title");
      frame.setAttribute("sandbox", "");
      frame.setAttribute("referrerpolicy", "no-referrer");
      frame.setAttribute(
        "allow",
        "camera 'none'; microphone 'none'; geolocation 'none'; payment 'none'; fullscreen 'none'"
      );
      frame.loading = "lazy";
      if (
        Number.isInteger(response.height) &&
        response.height >= 200 &&
        response.height <= 1600
      ) {
        frame.style.height = `${response.height}px`;
      }
      // This document must only enter the opaque-origin frame, never the forum DOM.
      frame.srcdoc = response.document;
      status.replaceWith(frame);
    } catch {
      if (wrapper.isConnected) {
        status.textContent = i18n("contained_html.unavailable");
      }
    }
  }, 350);

  return () => clearTimeout(timer);
}

export default {
  name: "contained-html",

  initialize(container) {
    if (!container.lookup("service:site-settings").contained_html_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.decorateCookedElement(
        (element) => {
          const cleanups = Array.from(
            element.querySelectorAll('pre[data-code-wrap="rpn-html"]')
          )
            .filter((pre) => pre.querySelector("code.lang-rpn-html"))
            .map(prepareLayout)
            .filter(Boolean);
          return () => cleanups.forEach((cleanup) => cleanup());
        },
        { id: "contained-html" }
      );
    });
  },
};
