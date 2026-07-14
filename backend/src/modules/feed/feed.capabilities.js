import { env } from "../../config/env.js";

/**
 * Authoritative social feature capabilities (Social V3 §3).
 *
 * The backend is the source of truth. Flutter may use this for UX (e.g. whether
 * to offer scoped-story options), but the backend independently enforces the
 * fail-closed gate regardless of what a client believes.
 */
export function buildSocialCapabilities(source = env) {
  const scopeEnabled = source.storyAudienceScopeEnabled === true;
  return {
    social: {
      storyAudienceScope: {
        supported: scopeEnabled,
        supportedTypes: scopeEnabled
          ? ["global", "block", "compound", "building"]
          : ["global"],
        officialStoriesSupported: false,
        version: 1,
      },
    },
  };
}
