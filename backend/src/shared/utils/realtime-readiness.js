export function buildTransientRealtimeProbeFailure({
  reason,
  status,
  error = null,
}) {
  const dualModeRequested =
    status?.enabled === true && status?.requestedMode === "dual";

  return {
    ok: false,
    status,
    // Provider timeouts and connection errors are degradation signals. They
    // must remain visible in diagnostics without making the core API unready.
    // Structured schema/configuration failures are returned by the provider
    // probe itself and retain their releaseBlocking=true value.
    releaseBlocking: false,
    transientFailure: true,
    reason,
    railwaySchemaReady: false,
    sharedTopicsReady: false,
    tokenReady: status?.configured === true,
    missingKeys: [...(status?.missingKeys || [])],
    missingObjects: [],
    checks: {
      dualModeRequested,
      hasSupabaseEnv: status?.configured === true,
      railwayOutboxTable: false,
      railwayOutboxDedupeColumn: false,
      railwayOutboxDedupeIndex: false,
      sharedTopicAuthorizationTables: false,
      realtimeTokenIssuance: status?.configured === true,
      outboxPumpEnabled: status?.enabled === true,
    },
    ...(error
      ? { probeError: String(error?.code || error?.name || "probe_failed") }
      : {}),
  };
}
