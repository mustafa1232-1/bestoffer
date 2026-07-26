import dotenv from "dotenv";

dotenv.config({
  path: process.env.PERMISSIONS_CHECK_ENV_FILE || ".env.test",
  override: true,
});

await import("./rolePermissionCheckMatrix.js");
