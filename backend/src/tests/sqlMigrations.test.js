import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { isNumberedSqlMigrationFileName } from "../config/sqlMigrations.js";

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
);

function listGitWorktreePaths() {
  const output = execFileSync("git", ["worktree", "list", "--porcelain"], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  const worktreePaths = [];
  for (const line of output.split(/\r?\n/)) {
    if (!line.startsWith("worktree ")) continue;
    const candidate = line.slice("worktree ".length).trim();
    if (candidate) worktreePaths.push(candidate);
  }
  return worktreePaths;
}

function collectMigrationNumbersFromWorktree(worktreePath) {
  const sqlDir = path.join(worktreePath, "backend", "sql");
  if (!fs.existsSync(sqlDir)) return [];
  return fs
    .readdirSync(sqlDir, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => isNumberedSqlMigrationFileName(name))
    .map((name) => {
      const match = name.match(/^(\d+)[a-z]?(?:_.*)?\.sql$/i);
      return match ? Number(match[1]) : null;
    })
    .filter((value) => Number.isFinite(value));
}

function listChangedMigrationNumbers() {
  const statusOutput = execFileSync(
    "git",
    ["status", "--porcelain", "--", "sql"],
    {
      cwd: repoRoot,
      encoding: "utf8",
    }
  );
  const changedPaths = [];
  for (const line of statusOutput.split(/\r?\n/)) {
    if (!line.trim()) continue;
    const pathPart = line.slice(3).trim();
    if (!pathPart) continue;
    const candidate = pathPart.includes(" -> ")
      ? pathPart.split(" -> ").pop().trim()
      : pathPart;
    if (candidate.toLowerCase().endsWith(".sql")) {
      changedPaths.push(path.resolve(repoRoot, candidate));
    }
  }
  const changedNumbers = new Map();
  for (const changedPath of changedPaths) {
    const name = path.basename(changedPath);
    if (!isNumberedSqlMigrationFileName(name)) continue;
    const match = name.match(/^(\d+)[a-z]?(?:_.*)?\.sql$/i);
    if (!match) continue;
    const number = Number(match[1]);
    if (!Number.isFinite(number)) continue;
    changedNumbers.set(number, changedPath);
  }
  return changedNumbers;
}

test("sql migrations only accept numbered migration file names", () => {
  assert.equal(isNumberedSqlMigrationFileName("001_init.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("090a_social_scope_core.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("131_order_item_display_snapshot.sql"), true);
  assert.equal(isNumberedSqlMigrationFileName("diag_order_181_delivery_assignment.sql"), false);
  assert.equal(isNumberedSqlMigrationFileName("notes.sql"), false);
});

test("changed migration numbers stay unique across all git worktrees", () => {
  const allEntries = new Map();
  for (const worktreePath of listGitWorktreePaths()) {
    const relative = path.relative(repoRoot, worktreePath) || ".";
    for (const number of collectMigrationNumbersFromWorktree(worktreePath)) {
      const list = allEntries.get(number) || [];
      list.push(relative);
      allEntries.set(number, list);
    }
  }

  const changedNumbers = listChangedMigrationNumbers();
  assert.ok(
    changedNumbers.size > 0,
    "expected at least one changed numbered migration in the current worktree",
  );

  for (const [number, changedPath] of changedNumbers.entries()) {
    const relativeChanged = path.relative(repoRoot, changedPath) || ".";
    const matches = allEntries.get(number) || [];
    if (matches.length > 1) {
      assert.fail(
        `duplicate migration number ${number} found for ${relativeChanged} and ${matches.join(
          ", ",
        )}`,
      );
    }
  }
});
