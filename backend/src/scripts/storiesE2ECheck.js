/* eslint-disable no-console */
import { runStoriesPhase3AFlow } from "./socialPhase3AFlow.js";

async function main() {
  await runStoriesPhase3AFlow();
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error("[stories-phase3a] FAILED");
    console.error(error?.stack || error?.message || error);
    process.exit(1);
  });
