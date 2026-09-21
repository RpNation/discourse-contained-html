export function encodeHtmlSource(source) {
  let fenceLength = 3;
  for (const match of source.matchAll(/`+/g)) {
    fenceLength = Math.max(fenceLength, match[0].length + 1);
  }

  const fence = "`".repeat(fenceLength);
  return `${fence}rpn-html\n${source}\n${fence}`;
}

export function decodeHtmlSource(raw) {
  if (typeof raw !== "string") {
    return null;
  }

  const opening = raw.match(/^(`{3,}|~{3,})[ \t]*rpn-html[ \t]*(\r\n|\n|\r)/);
  if (!opening) {
    return null;
  }

  const fence = opening[1];
  const closings = /^ {0,3}(`+|~+)[ \t]*(?=\r|\n|$)/gm;
  closings.lastIndex = opening[0].length;

  for (const closing of raw.matchAll(closings)) {
    if (closing[1][0] !== fence[0] || closing[1].length < fence.length) {
      continue;
    }

    const remainder = raw.slice(closing.index + closing[0].length);
    if (!["", "\n", "\r", "\r\n"].includes(remainder)) {
      return null;
    }

    const source = raw.slice(opening[0].length, closing.index);
    // Use the opening separator so encoded source ending in a bare CR survives.
    if (source.endsWith(opening[2])) {
      return source.slice(0, -opening[2].length);
    }
    return source.replace(/[\r\n]$/, "");
  }

  return null;
}
