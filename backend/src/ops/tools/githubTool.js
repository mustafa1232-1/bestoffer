const REQUIRED_LABELS = [
  "incident",
  "sev1",
  "sev2",
  "sev3",
  "sev4",
  "ai-dev-support",
  "needs-human-review",
  "code-fix-needed",
  "production-risk",
  "payment-risk",
  "database-risk",
];

function clean(value) {
  return String(value || "").trim();
}

function makeHeaders(token) {
  return {
    "Content-Type": "application/json",
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": "2022-11-28",
  };
}

function normalizeLabels(labels = []) {
  const out = new Set();
  for (const label of labels) {
    const normalized = clean(label).toLowerCase();
    if (normalized) out.add(normalized);
  }
  return [...out];
}

function labelForSeverity(severity) {
  switch (String(severity || "").toUpperCase()) {
    case "SEV1":
      return "sev1";
    case "SEV2":
      return "sev2";
    case "SEV3":
      return "sev3";
    default:
      return "sev4";
  }
}

export function githubConfigFromEnv(env) {
  return {
    token: clean(env.githubToken),
    owner: clean(env.githubOwner),
    repo: clean(env.githubRepo),
  };
}

export function isGithubConfigured(config) {
  return Boolean(config?.token && config?.owner && config?.repo);
}

export async function ensureGithubLabels(config) {
  if (!isGithubConfigured(config)) {
    return {
      ok: false,
      reason: "github_not_configured",
    };
  }

  const baseUrl = `https://api.github.com/repos/${config.owner}/${config.repo}`;
  const headers = makeHeaders(config.token);

  for (const label of REQUIRED_LABELS) {
    try {
      const res = await fetch(`${baseUrl}/labels/${encodeURIComponent(label)}`, {
        method: "GET",
        headers,
      });
      if (res.status === 200) continue;
      await fetch(`${baseUrl}/labels`, {
        method: "POST",
        headers,
        body: JSON.stringify({
          name: label,
          color: "1f6feb",
          description: "AI DEV SUPPORT label",
        }),
      });
    } catch (_) {
      // Best effort.
    }
  }

  return {
    ok: true,
  };
}

export async function createGithubIssue({
  config,
  incident,
  title,
  body,
  labels = [],
}) {
  if (!isGithubConfigured(config)) {
    return {
      ok: false,
      reason: "github_not_configured",
    };
  }

  await ensureGithubLabels(config);

  const issueTitle = clean(title) || `[${incident?.severity || "SEV3"}] Incident`;
  const issueBody = clean(body) || "Auto-generated incident report from AI DEV SUPPORT.";
  const finalLabels = normalizeLabels([
    "incident",
    "ai-dev-support",
    "needs-human-review",
    labelForSeverity(incident?.severity),
    ...(Array.isArray(labels) ? labels : []),
  ]);

  const baseUrl = `https://api.github.com/repos/${config.owner}/${config.repo}`;
  const response = await fetch(`${baseUrl}/issues`, {
    method: "POST",
    headers: makeHeaders(config.token),
    body: JSON.stringify({
      title: issueTitle,
      body: issueBody,
      labels: finalLabels,
    }),
  });

  if (!response.ok) {
    const raw = await response.text();
    return {
      ok: false,
      reason: "github_issue_failed",
      status: response.status,
      error: raw,
    };
  }

  const json = await response.json();
  return {
    ok: true,
    issue: {
      id: json.id,
      number: json.number,
      url: json.html_url,
      apiUrl: json.url,
      title: json.title,
    },
  };
}

export function buildCodeFixPrompt({ incident, issueUrl }) {
  return [
    "You are fixing a Maslaki production incident with strict safety policy.",
    `Incident ID: ${incident?.id || "n/a"}`,
    `Severity: ${incident?.severity || "SEV3"}`,
    `Risk: ${incident?.risk_level || "medium"}`,
    `Affected module: ${incident?.affected_module || "general"}`,
    `Probable root cause: ${incident?.probable_root_cause || "n/a"}`,
    "Constraints:",
    "- Never merge PR",
    "- Never deploy production",
    "- Do not touch secrets or env",
    "- Do not run destructive SQL",
    "- Add tests for regression",
    issueUrl ? `Reference issue: ${issueUrl}` : "",
  ]
    .filter(Boolean)
    .join("\n");
}

export async function createCodeFixPullRequest({
  config,
  incident,
  issue,
  branchName,
  base = "main",
  head,
  title,
  body,
}) {
  if (!isGithubConfigured(config)) {
    return {
      ok: false,
      reason: "github_not_configured",
    };
  }

  const resolvedHead = clean(head) || clean(branchName);
  if (!resolvedHead) {
    return {
      ok: false,
      reason: "missing_head_branch",
    };
  }

  const prTitle =
    clean(title) ||
    `[AI DEV SUPPORT][${incident?.severity || "SEV3"}] Fix incident #${incident?.id || "unknown"}`;
  const prBody =
    clean(body) ||
    `Auto-generated PR request for incident ${incident?.id || "n/a"}.\n\nHuman review is required.`;

  const baseUrl = `https://api.github.com/repos/${config.owner}/${config.repo}`;
  const response = await fetch(`${baseUrl}/pulls`, {
    method: "POST",
    headers: makeHeaders(config.token),
    body: JSON.stringify({
      title: prTitle,
      body: prBody,
      head: resolvedHead,
      base,
      draft: true,
    }),
  });

  if (!response.ok) {
    const raw = await response.text();
    return {
      ok: false,
      reason: "github_pr_failed",
      status: response.status,
      error: raw,
    };
  }

  const json = await response.json();
  if (issue?.number) {
    try {
      await fetch(`${baseUrl}/issues/${issue.number}/comments`, {
        method: "POST",
        headers: makeHeaders(config.token),
        body: JSON.stringify({
          body: `Linked draft PR: ${json.html_url}`,
        }),
      });
    } catch (_) {
      // best effort
    }
  }

  return {
    ok: true,
    pullRequest: {
      id: json.id,
      number: json.number,
      url: json.html_url,
      state: json.state,
      draft: json.draft,
    },
  };
}
