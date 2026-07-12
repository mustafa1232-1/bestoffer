/* eslint-disable no-console */
import { runSocialDiscoveryProfileMessagingFlow } from "./socialPhase3AFlow.js";

async function main() {
  await runSocialDiscoveryProfileMessagingFlow();
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error("[social-phase3a] FAILED");
    console.error(error?.stack || error?.message || error);
    process.exit(1);
  });
