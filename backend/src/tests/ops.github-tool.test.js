import assert from "node:assert/strict";
import test from "node:test";

import {
  buildCodeFixPrompt,
  createGithubIssue,
} from "../ops/tools/githubTool.js";

test("buildCodeFixPrompt includes safety constraints", () => {
  const prompt = buildCodeFixPrompt({
    incident: {
      id: 4,
      severity: "SEV2",
      risk_level: "high",
      affected_module: "orders",
    },
    issueUrl: "https://github.com/acme/repo/issues/1",
  });
  assert.match(prompt, /Never merge PR/);
  assert.match(prompt, /Never deploy production/);
});

test("createGithubIssue handles successful response", async () => {
  const calls = [];
  const originalFetch = global.fetch;
  global.fetch = async (url, options) => {
    calls.push({ url: String(url), options });
    if (String(url).includes('/labels/')) {
      return new Response('', { status: 200 });
    }
    if (String(url).endsWith('/issues')) {
      return new Response(
        JSON.stringify({
          id: 123,
          number: 77,
          html_url: 'https://github.com/o/r/issues/77',
          url: 'https://api.github.com/repos/o/r/issues/77',
          title: 'Issue title',
        }),
        { status: 201, headers: { 'content-type': 'application/json' } }
      );
    }
    return new Response('', { status: 200 });
  };

  try {
    const result = await createGithubIssue({
      config: {
        token: 'x',
        owner: 'o',
        repo: 'r',
      },
      incident: { severity: 'SEV2' },
      title: 'Issue title',
      body: 'Issue body',
      labels: ['custom'],
    });

    assert.equal(result.ok, true);
    assert.equal(result.issue?.number, 77);
    assert.ok(calls.length >= 1);
  } finally {
    global.fetch = originalFetch;
  }
});
