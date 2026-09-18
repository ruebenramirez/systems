#!/usr/bin/env node
// Post-processes a mermaid xychart SVG so that point labels always stay inside
// the plot area. Mermaid emits every point label as a single, un-wrappable
// <text> anchored at the data point. This script measures each label, wraps the
// long ones into multiple vertical columns, and truncates as a last resort.
import { readFileSync, writeFileSync } from "node:fs";

const MARKER = "<!-- labels-fitted -->";
const CHAR_WIDTH_FACTOR = 0.7;
const COLUMN_SPACING_FACTOR = 1.2;

const svgPath = process.argv[2];
if (!svgPath) {
  console.error("usage: fit-chart-labels.mjs <svg>");
  process.exit(2);
}

let svg = readFileSync(svgPath, "utf8");
if (svg.includes(MARKER)) {
  console.error(`skipping ${svgPath}: already fitted`);
  process.exit(0);
}

const num = String.raw`[\d.]+`;
const viewBox = svg.match(new RegExp(`viewBox="0 0 (${num}) (${num})"`));
const leftAxis = svg.match(
  new RegExp(`<g class="axisl-line"><path d="M (${num}),(${num}) L (${num}),(${num})`),
);
const bottomAxis = svg.match(
  new RegExp(`<g class="axis-line"><path d="M (${num}),(${num}) L (${num}),(${num})`),
);
const fontSizeMatch = svg.match(/\.labels text\s*\{[\s\S]*?font-size:\s*(\d+(?:\.\d+)?)px/);
const labelsGroup = svg.match(/<g class="labels">([\s\S]*?)<\/g>/);

if (!viewBox || !leftAxis || !bottomAxis || !labelsGroup) {
  console.error(`could not locate chart geometry in ${svgPath}; leaving unchanged`);
  process.exit(1);
}

const plotLeft = Number(leftAxis[1]);
const plotTop = Number(leftAxis[2]);
const plotBottom = Number(leftAxis[4]);
const plotRight = Number(bottomAxis[3]);
const fontSize = fontSizeMatch ? Number(fontSizeMatch[1]) : 32;
const charWidth = fontSize * CHAR_WIDTH_FACTOR;

const escape = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const extent = (s) => [...s].length * charWidth;

// "fwai0, dev-vm-xps" -> ["fwai0,", "dev-vm-xps"]; "a / b" -> ["a /", "b"]
const tokenize = (s) => s.split(/(?<=[,/])\s+/).filter((t) => t.length > 0);

// A single token wider than the budget is truncated with an ellipsis.
function fitToken(token, maxLine) {
  if (extent(token) <= maxLine) return token;
  const keep = Math.max(1, Math.floor(maxLine / charWidth) - 1);
  return [...token].slice(0, keep).join("") + "…";
}

function wrapLabel(label, maxLine) {
  if (extent(label) <= maxLine) return [label];
  const lines = [];
  let current = "";
  for (const raw of tokenize(label)) {
    const token = fitToken(raw, maxLine);
    const candidate = current ? `${current} ${token}` : token;
    if (current && extent(candidate) > maxLine) {
      lines.push(current);
      current = token;
    } else {
      current = candidate;
    }
  }
  if (current) lines.push(current);
  return lines;
}

const replacement = labelsGroup[1].replace(
  /<text\b([^>]*)>([\s\S]*?)<\/text>/g,
  (whole, attrs, label) => {
    const translate = attrs.match(
      /translate\(\s*([\d.eE+-]+)\s*,\s*([\d.eE+-]+)\s*\)/,
    );
    if (!translate) return whole;
    const x = Number(translate[1]);
    const y = Number(translate[2]);

    const maxLine = 2 * Math.min(y - plotTop, plotBottom - y);
    const lines = wrapLabel(label, maxLine);
    const columns = lines.length;
    const columnSpacing = fontSize * COLUMN_SPACING_FACTOR;

    // Keep the whole block centered on the data point, then clamp to plot area.
    const halfWidth = (columns - 1) * columnSpacing / 2 + fontSize / 2;
    let shift = 0;
    if (x - halfWidth < plotLeft) {
      shift = plotLeft - (x - halfWidth);
    } else if (x + halfWidth > plotRight) {
      shift = plotRight - (x + halfWidth);
    }
    if (x + shift - halfWidth < plotLeft) shift = plotLeft - (x - halfWidth);

    const baseAttrs = attrs
      .replace(/\s*transform="[^"]*"/, "")
      .replace(/\s*text-anchor="[^"]*"/, "");
    const textAnchor = ' text-anchor="middle"';

    return lines
      .map((line, i) => {
        const cx = x + shift + (i - (columns - 1) / 2) * columnSpacing;
        return `<text${baseAttrs}${textAnchor} transform="translate(${cx}, ${y}) rotate(0)">${escape(line)}</text>`;
      })
      .join("");
  },
);

svg = svg.replace(
  /<g class="labels">[\s\S]*?<\/g>/,
  `<g class="labels">${replacement}</g>`,
);
svg = svg.replace(/(<svg\b[^>]*>)/, `$1${MARKER}`);
writeFileSync(svgPath, svg);
console.error(`fitted labels in ${svgPath}`);
