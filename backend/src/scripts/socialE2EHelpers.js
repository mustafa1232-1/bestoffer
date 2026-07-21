/* eslint-disable no-console */

import {
  assertStatus,
  cleanupAdminArtifacts,
  request,
  requestMultipart,
} from "./e2eTestUtils.js";
import { cleanupLoadArtifactsByRunTag } from "../shared/utils/testArtifactCleanup.js";

export const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

export function shouldSkipMigrations() {
  const raw = String(process.env.E2E_SKIP_SQL_MIGRATIONS || "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

export function shouldSkipEnsureSchema() {
  const raw = String(process.env.E2E_SKIP_ENSURE_SCHEMA || "").trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(raw);
}

const SOCIAL_FIXTURE_PNG_BYTES = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+3xQAAAAASUVORK5CYII=",
  "base64"
);

const REEL_FIXTURE_URL =
  "https://filesamples.com/samples/video/mp4/sample_640x360.mp4";

export function buildImageBlob(mimeType = "image/png") {
  return new Blob([SOCIAL_FIXTURE_PNG_BYTES], { type: mimeType });
}

export function buildMultipartForm({
  fields = {},
  fileFieldName = "mediaFile",
  fileName = "social-fixture.png",
  mimeType = "image/png",
} = {}) {
  const formData = new FormData();
  for (const [key, value] of Object.entries(fields || {})) {
    if (value === undefined || value === null) continue;
    formData.append(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  formData.append(fileFieldName, buildImageBlob(mimeType), fileName);
  return formData;
}

export async function buildVideoMultipartForm({
  fields = {},
  fileFieldName = "mediaFile",
  fileName = "social-fixture.mp4",
  mimeType = "video/mp4",
} = {}) {
  const response = await fetch(REEL_FIXTURE_URL, {
    headers: {
      "Cache-Control": "no-cache",
      Pragma: "no-cache",
    },
  });
  if (!response.ok) {
    throw new Error(
      `REEL_FIXTURE_FETCH_FAILED:${response.status}:${REEL_FIXTURE_URL}`
    );
  }
  const bytes = await response.arrayBuffer();
  const formData = new FormData();
  for (const [key, value] of Object.entries(fields || {})) {
    if (value === undefined || value === null) continue;
    formData.append(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  formData.append(fileFieldName, new Blob([bytes], { type: mimeType }), fileName);
  return formData;
}

function readToken(response, label) {
  const token = String(response?.data?.token || "").trim();
  assertStatus(response, response.status, label);
  if (!token) {
    throw new Error(`${label} -> missing token`);
  }
  return token;
}

function readUserId(response, label) {
  const id = Number(response?.data?.user?.id || 0);
  if (!Number.isFinite(id) || id <= 0) {
    throw new Error(`${label} -> missing user id`);
  }
  return id;
}

export async function loginActor(baseUrl, actor, phone, pin, label) {
  const response = await request(baseUrl, actor, "POST", "/api/auth/login", {
    phone,
    pin,
  });
  assertStatus(response, 200, label);
  actor.token = readToken(response, label);
  actor.userId = readUserId(response, label);
  actor.sessionId = Number(response.data?.sessionId || 0) || null;
  return response.data;
}

export async function registerActor(baseUrl, actor, payload, label) {
  const response = await request(baseUrl, actor, "POST", "/api/auth/register", {
    ...payload,
    analyticsConsentAccepted: true,
    analyticsConsentVersion: "social_e2e_v1",
  });
  assertStatus(response, 201, label);
  actor.token = String(response.data?.token || "").trim();
  actor.sessionId = Number(response.data?.sessionId || 0) || null;
  actor.userId = Number(response.data?.user?.id || 0) || null;
  return response.data;
}

export async function cleanupSocialArtifacts({
  runTag,
  adminSessionId = null,
  adminSessionIds = [],
}) {
  await cleanupAdminArtifacts({
    adminSessionId,
    adminSessionIds,
    runTag,
    approvalPaths: [],
  });
  await cleanupLoadArtifactsByRunTag(runTag);
}

export async function requestMultipartForm(baseUrl, actor, method, path, formData) {
  return requestMultipart(baseUrl, actor, method, path, formData);
}
