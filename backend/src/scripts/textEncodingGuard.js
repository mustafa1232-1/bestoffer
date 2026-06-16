/* eslint-disable no-console */
import fs from "node:fs";
import path from "node:path";

const projectRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..", "..");
const scanRoots = [
  path.join(projectRoot, "src", "modules"),
  path.join(projectRoot, "src", "shared"),
];

const badMarkerPattern =
  /[\uFFFD\u00D8-\u00DB\u00C3\u00C6\u00C7\u00D0\u00D1\u00DE\u00E2]/;
const placeholderPattern = /\?{3,}/;

function normalizePath(filePath) {
  return filePath.replaceAll("\\", "/");
}

function collectFiles(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectFiles(fullPath, out);
      continue;
    }
    if (entry.isFile() && /\.(js|mjs|cjs)$/.test(entry.name)) {
      out.push(fullPath);
    }
  }
  return out;
}

function main() {
  const findings = [];
  for (const root of scanRoots) {
    const files = collectFiles(root);
    for (const filePath of files) {
      const source = fs.readFileSync(filePath, "utf8");
      const lines = source.split(/\r?\n/);
      for (let index = 0; index < lines.length; index += 1) {
        const line = lines[index];
        if (!badMarkerPattern.test(line) && !placeholderPattern.test(line)) {
          continue;
        }
        findings.push(
          `${normalizePath(path.relative(projectRoot, filePath))}:${index + 1}: ${line}`
        );
      }
    }
  }

  if (findings.length > 0) {
    console.error(
      [
        "[text-guard] Detected possible broken text markers in backend source:",
        ...findings,
      ].join("\n")
    );
    process.exit(1);
  }

  console.log("[text-guard] OK");
}

main();
