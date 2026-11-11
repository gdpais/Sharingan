#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const docsDir = path.join(repoRoot, "docs");
const args = process.argv.slice(2);
const mode = parseMode(args);
const productName = "Sharingan";
const source = "https://github.com/gdpais/Sharingan";
const docsBase = source + "/blob/main/docs/";
const releases = source + "/releases";
const outputPath = path.join(docsDir, "llms.txt");
const productDescription =
  "Sharingan is a tiny macOS menu bar app that keeps AI coding-provider usage limits, credits, costs, and resets " +
  "visible. It has no project website; it is distributed only through GitHub Releases.";

// Sharingan has no website, so the index points at the Markdown docs on GitHub. Each doc's frontmatter summary
// is its description; docs without a summary are skipped.
const pages = fs
  .readdirSync(docsDir)
  .filter((file) => file.endsWith(".md"))
  .sort((a, b) => a.localeCompare(b))
  .flatMap((file) => {
    const markdown = fs.readFileSync(path.join(docsDir, file), "utf8");
    const front = markdown.match(/^---\n([\s\S]*?)\n---/u)?.[1] ?? "";
    const summary = front
      .match(/^summary:\s*(.+)$/mu)?.[1]
      ?.trim()
      .replace(/^(["'])(.*)\1$/u, "$2");
    if (!summary) return [];
    const title = markdown.match(/^# (.+)$/mu)?.[1]?.trim() || titleize(path.basename(file, ".md"));
    return [{ file, title, description: summary }];
  });

const lines = [
  "# " + productName,
  "",
  productDescription,
  "",
  "Source: " + source,
  "Downloads: " + releases,
  "README: " + source + "/blob/main/README.md",
  "",
  "Documentation:",
  ...pages.map((page) => "- " + page.title + ": " + docsBase + page.file + " - " + page.description),
  "",
  "Guidance for agents:",
  "- Prefer the documentation URLs above over README excerpts or package metadata.",
  "- Fetch only the pages needed for the current task; this is an index, not a full documentation corpus.",
  "",
];
const output = lines.join("\n");

if (mode === "check") {
  const current = fs.existsSync(outputPath) ? fs.readFileSync(outputPath, "utf8") : null;
  if (current !== output) {
    console.error(`${path.relative(repoRoot, outputPath)} is out of date; run node Scripts/generate-llms.mjs`);
    process.exit(1);
  }
  console.log("llms index OK: " + path.relative(repoRoot, outputPath));
} else {
  fs.writeFileSync(outputPath, output, "utf8");
  console.log("wrote " + path.relative(repoRoot, outputPath));
}

function parseMode(values) {
  if (values.length === 0) return "write";
  if (values.length === 1 && (values[0] === "write" || values[0] === "--write")) return "write";
  if (values.length === 1 && (values[0] === "check" || values[0] === "--check")) return "check";
  console.error("Usage: node Scripts/generate-llms.mjs [write|--write|check|--check]");
  process.exit(2);
}

function titleize(input) {
  return input.replaceAll("-", " ").replace(/\b\w/g, (m) => m.toUpperCase());
}
