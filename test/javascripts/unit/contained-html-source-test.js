import { module, test } from "qunit";
import {
  decodeHtmlSource,
  encodeHtmlSource,
} from "discourse/plugins/discourse-contained-html/discourse/lib/contained-html-source";

module("Unit | Lib | contained-html-source", function () {
  test("preserves HTML source and whitespace through a round trip", function (assert) {
    const sources = [
      "",
      " ",
      "\n",
      "\r",
      "\r\n",
      "\n\n<p>Character</p>\n\n",
      "\t<p>Character</p> \t",
      "<p>Character</p>\r",
      "<p>Character</p>\r\n",
      "<p>Character</p>\r\n<p>History</p>\r\n",
      '</textarea><style>body { display: none; }</style><img onerror="alert(1)">',
    ];

    for (const source of sources) {
      assert.strictEqual(
        decodeHtmlSource(encodeHtmlSource(source)),
        source,
        `preserves ${JSON.stringify(source)}`
      );
    }
  });

  test("uses a fence that source cannot close", function (assert) {
    const source =
      "<pre>\n```\n</textarea><style>body { display: none; }</style>\n``````\n</pre>";
    const raw = encodeHtmlSource(source);

    assert.true(
      raw.startsWith("```````rpn-html\n"),
      "the opening fence exceeds every source backtick run"
    );
    assert.true(raw.endsWith("\n```````"), "the closing fence matches");
    assert.strictEqual(
      decodeHtmlSource(raw),
      source,
      "embedded fences and HTML stay inside the source"
    );
  });

  test("recognizes single complete existing fences", function (assert) {
    const cases = [
      ["```rpn-html\n```", ""],
      ["```rpn-html\n<p>Character</p>\n```", "<p>Character</p>"],
      ["~~~ rpn-html\n<p>Character</p>\n~~~~\n", "<p>Character</p>"],
      ["```rpn-html\r\n<p>Character</p>\r\n```\r\n", "<p>Character</p>"],
      ["```rpn-html\r<p>Character</p>\r```\r", "<p>Character</p>"],
      ["```rpn-html \t\n<p>Character</p>\n   ```` \t", "<p>Character</p>"],
      ["````rpn-html\n```\n<p>Character</p>\n````", "```\n<p>Character</p>"],
      ["~~~rpn-html\n```\n<p>Character</p>\n~~~", "```\n<p>Character</p>"],
    ];

    for (const [raw, source] of cases) {
      assert.strictEqual(
        decodeHtmlSource(raw),
        source,
        `recognizes ${JSON.stringify(raw)}`
      );
    }
  });

  test("rejects mixed content and ambiguous or malformed fences", function (assert) {
    const layout = "```rpn-html\n<p>Character</p>\n```";
    const cases = [
      undefined,
      null,
      "",
      "<p>Character</p>",
      `Introduction\n${layout}`,
      `${layout}\nAfterword`,
      `${layout}\n\n${layout}`,
      "```rpn-html\n<p>First</p>\n```\n<p>Outside</p>\n```",
      "```rpn-html\n<p>First</p>\n   ```\n<p>Outside</p>\n```",
      "```rpn-html\n<p>Unclosed</p>",
      "```rpn-html\n<p>Character</p>\n~~~",
      "````rpn-html\n<p>Character</p>\n```",
      "```rpn-html\n<p>Character</p>\n    ```",
      "```rpn-html\n<p>Character</p>\n``` extra",
      "```rpn-html extra\n<p>Character</p>\n```",
      "```html\n<p>Character</p>\n```",
      "> ```rpn-html\n> <p>Quoted</p>\n> ```",
      "    ```rpn-html\n    <p>Indented</p>\n    ```",
    ];

    for (const raw of cases) {
      assert.strictEqual(
        decodeHtmlSource(raw),
        null,
        `leaves ${JSON.stringify(raw)} in Markdown mode`
      );
    }
  });
});
