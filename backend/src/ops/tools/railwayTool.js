function clean(value) {
  return String(value || "").trim();
}

function hasRailwayConfig(config) {
  return Boolean(config?.token && config?.projectId && config?.environmentId);
}

export function railwayConfigFromEnv(env) {
  return {
    token: clean(env.railwayApiToken),
    projectId: clean(env.railwayProjectId),
    environmentId: clean(env.railwayEnvironmentId),
  };
}

function fromEdges(connection) {
  if (!connection?.edges || !Array.isArray(connection.edges)) return [];
  return connection.edges.map((edge) => edge?.node).filter(Boolean);
}

async function railwayGraphql(config, query, variables = {}) {
  // Railway supports multiple token types:
  // - account/workspace tokens via Authorization: Bearer
  // - project tokens via Project-Access-Token
  // Sending both keeps compatibility with either token type.
  const response = await fetch("https://backboard.railway.com/graphql/v2", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${config.token}`,
      "Project-Access-Token": config.token,
    },
    body: JSON.stringify({ query, variables }),
  });
  if (!response.ok) {
    const raw = await response.text();
    throw new Error(`RAILWAY_HTTP_${response.status}:${raw}`);
  }
  const json = await response.json();
  if (json?.errors?.length) {
    throw new Error(`RAILWAY_GRAPHQL_ERROR:${JSON.stringify(json.errors)}`);
  }
  return json.data;
}

export async function fetchRailwayStatus(config) {
  if (!hasRailwayConfig(config)) {
    return {
      ok: false,
      reason: "railway_not_configured",
    };
  }

  try {
    const data = await railwayGraphql(
      config,
      `query($projectId: String!, $environmentId: String!) {
        project(id: $projectId) {
          id
          name
          environments {
            edges {
              node {
                id
                name
              }
            }
          }
        }
        environment(id: $environmentId) {
          id
          name
        }
      }`,
      {
        projectId: config.projectId,
        environmentId: config.environmentId,
      }
    );

    return {
      ok: true,
      status: {
        project: data?.project?.name || null,
        environment: data?.environment?.name || null,
      },
    };
  } catch (error) {
    return {
      ok: false,
      reason: error?.message || "railway_status_failed",
    };
  }
}

export async function findRailwayServiceByName({
  config,
  serviceName,
}) {
  const target = clean(serviceName).toLowerCase();
  if (!target) return null;

  const data = await railwayGraphql(
    config,
    `query($projectId: String!) {
      project(id: $projectId) {
        id
        name
        services {
          edges {
            node {
              id
              name
            }
          }
        }
      }
    }`,
    { projectId: config.projectId }
  );

  const services = fromEdges(data?.project?.services);
  for (const service of services) {
    if (clean(service?.name).toLowerCase() === target) {
      return {
        id: clean(service?.id),
        name: clean(service?.name),
      };
    }
  }
  return null;
}

export async function restartRailwayService({
  config,
  serviceId,
  serviceName = "",
}) {
  if (!hasRailwayConfig(config)) {
    return {
      ok: false,
      reason: "railway_not_configured",
    };
  }

  try {
    let resolvedServiceId = clean(serviceId);
    let resolvedServiceName = clean(serviceName);

    if (!resolvedServiceId && resolvedServiceName) {
      const matched = await findRailwayServiceByName({
        config,
        serviceName: resolvedServiceName,
      });
      if (matched?.id) {
        resolvedServiceId = matched.id;
        resolvedServiceName = matched.name || resolvedServiceName;
      }
    }

    if (!resolvedServiceId) {
      return {
        ok: false,
        reason: "missing_service_id",
      };
    }

    const instanceData = await railwayGraphql(
      config,
      `query($serviceId: String!, $environmentId: String!) {
        serviceInstance(serviceId: $serviceId, environmentId: $environmentId) {
          id
          serviceName
          latestDeployment {
            id
            status
          }
        }
      }`,
      {
        serviceId: resolvedServiceId,
        environmentId: clean(config.environmentId),
      }
    );

    const latestDeploymentId = clean(
      instanceData?.serviceInstance?.latestDeployment?.id
    );

    if (latestDeploymentId) {
      const restartData = await railwayGraphql(
        config,
        `mutation($id: String!) {
          deploymentRestart(id: $id)
        }`,
        { id: latestDeploymentId }
      );

      return {
        ok: true,
        mode: "deployment_restart",
        serviceId: resolvedServiceId,
        serviceName:
          clean(instanceData?.serviceInstance?.serviceName) || resolvedServiceName || null,
        deploymentId: latestDeploymentId,
        data: restartData,
      };
    }

    const fallbackData = await railwayGraphql(
      config,
      `mutation($serviceId: String!, $environmentId: String!) {
        serviceInstanceRedeploy(serviceId: $serviceId, environmentId: $environmentId)
      }`,
      {
        serviceId: resolvedServiceId,
        environmentId: clean(config.environmentId),
      }
    );

    return {
      ok: true,
      mode: "service_instance_redeploy",
      serviceId: resolvedServiceId,
      serviceName: resolvedServiceName || null,
      data: fallbackData,
    };
  } catch (error) {
    return {
      ok: false,
      reason: error?.message || "railway_restart_failed",
    };
  }
}
