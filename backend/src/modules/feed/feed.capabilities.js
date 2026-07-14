import { env } from "../../config/env.js";

/**
 * CODE-LEVEL readiness for the scoped-story feature (Social V3 §1).
 *
 * This is intentionally a hardcoded constant, NOT an environment variable. It
 * stays `false` until the complete feature (creation authorization, transactional
 * persistence, read-side enforcement across every story query, and scope-aware
 * notifications) is implemented and its DB matrix passes.
 *
 * Because the effective state ANDs this with the env flag, an accidental or
 * premature `STORY_AUDIENCE_SCOPE_ENABLED=true` in Railway CANNOT enable scoped
 * publishing and cannot reopen the privacy leak.
 */
export const STORY_AUDIENCE_SCOPE_IMPLEMENTATION_READY = false;

/**
 * The single authoritative feature-state resolver (§2). Every consumer — the
 * service gate, the capability endpoint, startup diagnostics, and tests — must
 * use this so the state can never drift between surfaces.
 *
 * `source` lets tests inject a fake env; `implementationReadyOverride` lets tests
 * simulate the future implemented state without changing the shipped constant.
 */
export function getStoryAudienceScopeFeatureState(
  source = env,
  implementationReadyOverride = STORY_AUDIENCE_SCOPE_IMPLEMENTATION_READY
) {
  const requestedEnabled = source?.storyAudienceScopeEnabled === true;
  const implementationReady = implementationReadyOverride === true;
  const effectiveEnabled = implementationReady && requestedEnabled;
  return {
    implementationReady,
    requestedEnabled,
    effectiveEnabled,
    supportedTypes: effectiveEnabled
      ? ["global", "block", "compound", "building"]
      : ["global"],
    officialStoriesSupported: false,
    version: 1,
    reason: !implementationReady
      ? "IMPLEMENTATION_INCOMPLETE"
      : requestedEnabled
        ? "ENABLED"
        : "DISABLED_BY_CONFIG",
  };
}

/**
 * Authoritative social feature capabilities (§3/§7). Returns the EFFECTIVE
 * state — never the raw requested env value — so a stale/forced env flag cannot
 * advertise unsupported scope types.
 */
export function buildSocialCapabilities(source = env) {
  const s = getStoryAudienceScopeFeatureState(source);
  return {
    social: {
      storyAudienceScope: {
        supported: s.effectiveEnabled,
        supportedTypes: s.supportedTypes,
        officialStoriesSupported: s.officialStoriesSupported,
        version: s.version,
        reason: s.reason,
      },
    },
  };
}
