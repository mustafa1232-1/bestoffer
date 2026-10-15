import assert from 'node:assert/strict';
import test, { after } from 'node:test';
import { q, pool } from '../config/db.js';
import { listPostCommentPreviews } from '../modules/feed/feed.repo.js';
import { listPosts } from '../modules/feed/feed.service.js';

after(() => pool.end());

test('comment previews are batched, bounded and respect moderation and blocking', async () => {
  assert.match(new URL(process.env.DATABASE_URL).pathname, /\/qa_f_/);
  const users = await q(`INSERT INTO app_user(full_name,phone,username,pin_hash,role,block,building_number,apartment,social_posts_public)
    SELECT 'Preview author ' || i, '077preview' || i, 'preview_test_' || i, 'test', 'user', 'A', 'A203', '1', TRUE
    FROM generate_series(1,3) i RETURNING id`);
  const [viewer, author, blocked] = users.rows.map((r) => Number(r.id));
  const postRows = await q(`INSERT INTO social_post(user_id,post_kind,caption)
    SELECT $1,'text','Preview post ' || i FROM generate_series(1,2) i RETURNING id`, [author]);
  const ids = postRows.rows.map((r) => Number(r.id));
  for (const postId of ids) {
    await q(`INSERT INTO social_post_comment(post_id,user_id,body)
      SELECT $1,$2,'Approved ' || i FROM generate_series(1,4) i`, [postId, author]);
    await q(`INSERT INTO social_post_comment(post_id,user_id,body,is_deleted)
      VALUES ($1,$2,'Deleted',TRUE),($1,$3,'Blocked',FALSE)`, [postId,author,blocked]);
    await q(`INSERT INTO social_post_comment(post_id,user_id,body,moderation_status)
      VALUES ($1,$2,'Pending','pending')`, [postId,author]);
  }
  await q(`INSERT INTO social_user_relation(user_a_id,user_b_id,initiator_user_id,status)
    VALUES (LEAST($1::bigint,$2::bigint),GREATEST($1::bigint,$2::bigint),$1,'blocked')`, [viewer,blocked]);
  let queries = 0;
  const original = pool.query.bind(pool);
  pool.query = (...args) => { queries++; return original(...args); };
  let comments;
  try { comments = await listPostCommentPreviews({postIds:ids,viewerUserId:viewer}); }
  finally { pool.query = original; }
  assert.equal(queries,1);
  assert.equal(comments.length,4);
  for (const postId of ids) {
    assert.deepEqual(comments.filter((c) => Number(c.post_id) === postId).map((c) => c.body), ['Approved 3','Approved 4']);
  }
  assert.equal(comments[0].user_full_name, 'Preview author 2');
  const feed = await listPosts(viewer, {limit:20,feed:'for_you'});
  const post = feed.posts.find((p) => p.id === ids[0]);
  assert.ok(post);
  assert.equal(post.commentPreview.length,2);
  assert.equal(post.commentPreview[0].author.fullName,'Preview author 2');
  await q(`UPDATE social_post SET story_style='{"postSettings":{"commentsEnabled":false}}'::jsonb WHERE id=$1`,[ids[0]]);
  const disabled = await listPosts(viewer, {limit:20,feed:'for_you'});
  assert.deepEqual(disabled.posts.find((p) => p.id === ids[0]).commentPreview,[]);
});
