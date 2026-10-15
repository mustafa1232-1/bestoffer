import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { app } from '../app.js';
import { pool, q } from '../config/db.js';

// Opt-in full HTTP role matrix, isolated from production and other QA fixtures.
test('local permission matrix and fixture cleanup', {skip: process.env.LOCAL_PERMISSION_QA !== '1'}, async () => {
  const url = new URL(process.env.DATABASE_URL);
  assert.ok(['localhost','127.0.0.1'].includes(url.hostname));
  assert.ok(url.pathname.startsWith('/qa_f_'));
  assert.notEqual(process.env.NODE_ENV, 'production');
  const before = Number((await q('SELECT COUNT(*)::int AS n FROM app_user')).rows[0].n);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const child = spawn(process.execPath, ['src/scripts/rolePermissionCheckMatrix.js'], {
      env: {...process.env, API_BASE_URL: `http://127.0.0.1:${server.address().port}`,
        QA_ROLE_MATRIX_FILE: 'qa_artifacts/no-saved-accounts-for-local-check.json',
        PERMISSIONS_CHECK_USE_ENV_ACCOUNTS: 'false'},
      stdio: 'inherit', windowsHide: true,
    });
    const [code] = await once(child, 'exit');
    assert.equal(code, 0);
    assert.equal(Number((await q('SELECT COUNT(*)::int AS n FROM app_user')).rows[0].n), before);
  } finally {
    await new Promise(resolve => server.close(resolve));
    await pool.end();
  }
});
