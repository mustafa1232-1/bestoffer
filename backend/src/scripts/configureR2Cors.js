import {
  GetBucketCorsCommand,
  PutBucketCorsCommand,
  S3Client,
} from "@aws-sdk/client-s3";

import { env } from "../config/env.js";

const allowedOrigins = [
  "https://maslaki-app.web.app",
  "https://maslaki-app.firebaseapp.com",
  "https://maslaki-store.web.app",
  "https://maslaki-store.firebaseapp.com",
  "https://maslaki-captain.web.app",
  "https://maslaki-captain.firebaseapp.com",
  "https://maslaki-delivery.web.app",
  "https://maslaki-delivery.firebaseapp.com",
  "https://maslaki-61a97.web.app",
  "https://maslaki-61a97.firebaseapp.com",
];

function assertR2Config() {
  const missing = [];
  if (!env.cfR2Bucket) missing.push("CF_R2_BUCKET");
  if (!env.cfR2Endpoint) missing.push("CF_R2_ENDPOINT");
  if (!env.cfR2AccessKeyId) missing.push("CF_R2_ACCESS_KEY_ID");
  if (!env.cfR2SecretAccessKey) missing.push("CF_R2_SECRET_ACCESS_KEY");
  if (missing.length > 0) {
    throw new Error(`R2_CONFIG_MISSING:${missing.join(",")}`);
  }
}

async function main() {
  assertR2Config();

  const client = new S3Client({
    region: "auto",
    endpoint: env.cfR2Endpoint,
    forcePathStyle: true,
    credentials: {
      accessKeyId: env.cfR2AccessKeyId,
      secretAccessKey: env.cfR2SecretAccessKey,
    },
  });

  const corsConfiguration = {
    CORSRules: [
      {
        AllowedOrigins: allowedOrigins,
        AllowedMethods: ["GET", "HEAD"],
        AllowedHeaders: ["*"],
        ExposeHeaders: ["Content-Length", "Content-Type", "ETag"],
        MaxAgeSeconds: 86400,
      },
    ],
  };

  await client.send(
    new PutBucketCorsCommand({
      Bucket: env.cfR2Bucket,
      CORSConfiguration: corsConfiguration,
    }),
  );

  const current = await client.send(
    new GetBucketCorsCommand({
      Bucket: env.cfR2Bucket,
    }),
  );

  const rules = current.CORSRules || [];
  const origins = new Set(
    rules.flatMap((rule) => rule.AllowedOrigins || []),
  );
  const missingOrigins = allowedOrigins.filter((origin) => !origins.has(origin));
  if (missingOrigins.length > 0) {
    throw new Error(`R2_CORS_VERIFY_FAILED:${missingOrigins.join(",")}`);
  }

  console.log(
    JSON.stringify({
      ok: true,
      bucket: env.cfR2Bucket,
      origins: allowedOrigins.length,
      methods: ["GET", "HEAD"],
    }),
  );
}

main().catch((error) => {
  console.error(
    JSON.stringify({
      ok: false,
      error: String(error?.message || error),
    }),
  );
  process.exitCode = 1;
});
