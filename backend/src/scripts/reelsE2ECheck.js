/* eslint-disable no-console */
import { runReelsPhase3AFlow } from "./socialPhase3AFlow.js";

async function main() {
  await runReelsPhase3AFlow();
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error("[reels-phase3a] FAILED");
    console.error(error?.stack || error?.message || error);
    process.exit(1);
  });
