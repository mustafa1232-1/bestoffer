import { pool, q } from "../config/db.js";

try {
  const tables = await q(
    `SELECT table_name
     FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_name LIKE 'ai_%'
     ORDER BY table_name`,
  );

  for (const { table_name: tableName } of tables.rows) {
    const columns = await q(
      `SELECT column_name, data_type, udt_name, is_nullable
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = $1
       ORDER BY ordinal_position`,
      [tableName],
    );
    const summary = columns.rows
      .map(
        (column) =>
          `${column.column_name}:${column.udt_name || column.data_type}:${column.is_nullable}`,
      )
      .join(",");
    console.log(`${tableName}|${summary}`);
  }
} finally {
  await pool.end();
}
