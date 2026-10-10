import { pool } from "../config/db.js";
import { seedTeamCodePuzzles } from "../modules/games/games.service.js";

seedTeamCodePuzzles()
  .then((result) => console.log(`[team-code-seed] verified=${result.count}`))
  .catch((error) => {
    console.error("[team-code-seed] failed", error);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
