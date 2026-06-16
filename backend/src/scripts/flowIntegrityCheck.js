/* eslint-disable no-console */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(here, "..", "..");

const requiredFiles = [
  "src/app.js",
  "src/server.js",
  "src/config/db.js",
  "src/config/redis.js",
  "src/config/aiDb.js",
  "src/modules/auth/auth.service.js",
  "src/modules/taxi/taxi.controller.js",
  "src/modules/taxi/taxi.routes.js",
  "src/modules/assistant/assistant.routes.js",
];

const requiredModuleExports = [
  {
    module: "src/modules/auth/auth.service.js",
    exports: ["runWithGeneratedAppUserUsername"],
  },
  {
    module: "src/modules/taxi/taxi.controller.js",
    exports: [
      "listNearbyCaptains",
      "createShareToken",
      "getRideCallState",
      "startRideCall",
      "sendRideCallSignal",
      "endRideCall",
      "publicTrack",
    ],
  },
  {
    module: "src/modules/taxi/taxi.routes.js",
    exports: ["taxiRouter"],
  },
  {
    module: "src/modules/assistant/assistant.routes.js",
    exports: ["assistantRouter"],
  },
];

function checkRequiredFiles() {
  const missing = [];
  for (const rel of requiredFiles) {
    const fullPath = path.join(projectRoot, rel);
    if (!fs.existsSync(fullPath)) {
      missing.push(rel);
    }
  }
  if (missing.length > 0) {
    throw new Error(`Missing required files:\n- ${missing.join("\n- ")}`);
  }
}

function checkScriptTargets() {
  const packageJsonPath = path.join(projectRoot, "package.json");
  if (!fs.existsSync(packageJsonPath)) {
    throw new Error("backend/package.json not found");
  }

  const pkg = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
  const scripts = pkg?.scripts || {};
  const missingScriptTargets = [];

  for (const [name, cmd] of Object.entries(scripts)) {
    const match = String(cmd).match(/\bnode\s+src\/scripts\/([a-zA-Z0-9._-]+\.js)\b/);
    if (!match) continue;
    const target = path.join(projectRoot, "src", "scripts", match[1]);
    if (!fs.existsSync(target)) {
      missingScriptTargets.push(`${name} -> src/scripts/${match[1]}`);
    }
  }

  if (missingScriptTargets.length > 0) {
    throw new Error(
      `package.json scripts reference missing files:\n- ${missingScriptTargets.join("\n- ")}`
    );
  }
}

async function checkModuleExports() {
  const failures = [];

  for (const item of requiredModuleExports) {
    const fullPath = path.join(projectRoot, item.module);
    try {
      const mod = await import(pathToFileURL(fullPath).href);
      for (const exportName of item.exports) {
        if (!(exportName in mod)) {
          failures.push(`${item.module} missing export "${exportName}"`);
          continue;
        }
        const value = mod[exportName];
        const isRouter = exportName.toLowerCase().endsWith("router");
        if (isRouter && (!value || typeof value !== "function")) {
          // Express Router is callable function object.
          failures.push(`${item.module} export "${exportName}" is not an Express router`);
        }
        if (!isRouter && typeof value !== "function") {
          failures.push(`${item.module} export "${exportName}" is not a function`);
        }
      }
    } catch (error) {
      failures.push(`${item.module} import failed: ${error?.message || error}`);
    }
  }

  if (failures.length > 0) {
    throw new Error(`Flow integrity export checks failed:\n- ${failures.join("\n- ")}`);
  }
}

async function main() {
  checkRequiredFiles();
  checkScriptTargets();
  await checkModuleExports();
  console.log("[flow-check] OK");
}

main().catch((error) => {
  console.error("[flow-check] failed:", error?.message || error);
  process.exit(1);
});
