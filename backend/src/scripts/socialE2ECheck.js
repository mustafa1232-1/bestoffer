/* eslint-disable no-console */
import {
  runSocialDiscoveryProfileMessagingFlow,
  runSocialMessagingPhase3BFlow,
} from "./socialPhase3AFlow.js";

async function main() {
  await runSocialDiscoveryProfileMessagingFlow({ closePool: false });
  await runSocialMessagingPhase3BFlow({ closePool: true });
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
