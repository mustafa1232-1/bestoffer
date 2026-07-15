// Deterministic multi-store delivery fixture (delivery closure §2).
//
// Builds, via SQL against the test DB, a real two-store checkout: one customer,
// two approved stores, one multi-store order_group, two accepted child
// customer_orders, and one approved+online app courier with fresh presence.
//
// Rows are tagged with a `fixt_ms_` marker so the fixture is idempotent
// (cleans its own prior rows first).

const MARK = "fixt_ms_";

async function insertUser(client, { role, name, suffix }) {
  const uname = `${MARK}${suffix}`;
  const row = (
    await client.query(
      `INSERT INTO app_user
         (full_name, phone, pin_hash, block, building_number, apartment, username, role)
       VALUES ($1,$2,'x',$3,$4,$5,$6,$7)
       RETURNING id`,
      [name, `0${suffix}`.slice(0, 15), "A", "A101", "1", uname, role]
    )
  ).rows[0];
  return Number(row.id);
}

export async function cleanupMultiStoreFixture(client) {
  // FK-safe teardown by marker.
  await client.query(
    `DELETE FROM delivery_pickup_stop WHERE child_order_id IN
       (SELECT id FROM customer_order WHERE customer_full_name LIKE '${MARK}%')`
  );
  await client.query(
    `DELETE FROM delivery_job WHERE order_group_id IN
       (SELECT id FROM order_group WHERE public_id LIKE '${MARK}%')`
  );
  await client.query(
    `DELETE FROM notification_outbox WHERE event_id LIKE 'deliveryjob-assign-%'
       AND target_entity_id NOT IN (SELECT id FROM delivery_job)`
  );
  await client.query(
    `DELETE FROM customer_order WHERE customer_full_name LIKE '${MARK}%'`
  );
  await client.query(`DELETE FROM order_group WHERE public_id LIKE '${MARK}%'`);
  await client.query(
    `DELETE FROM courier_presence WHERE courier_user_id IN
       (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  );
  await client.query(
    `DELETE FROM courier_profile WHERE user_id IN
       (SELECT id FROM app_user WHERE username LIKE '${MARK}%')`
  );
  await client.query(`DELETE FROM merchant WHERE name LIKE '${MARK}%'`);
  await client.query(`DELETE FROM app_user WHERE username LIKE '${MARK}%'`);
}

export async function createMultiStoreFixture(
  client,
  { childStatus = "accepted_by_store", courierOnline = true, presenceAgeSec = 5 } = {}
) {
  await cleanupMultiStoreFixture(client);

  const customerId = await insertUser(client, {
    role: "user",
    name: `${MARK}customer`,
    suffix: "cust01",
  });
  const owner1 = await insertUser(client, {
    role: "owner",
    name: `${MARK}owner1`,
    suffix: "own01",
  });
  const owner2 = await insertUser(client, {
    role: "owner",
    name: `${MARK}owner2`,
    suffix: "own02",
  });
  const courierId = await insertUser(client, {
    role: "delivery",
    name: `${MARK}courier`,
    suffix: "cour01",
  });

  const merchant1 = (
    await client.query(
      `INSERT INTO merchant (name, type, owner_user_id) VALUES ($1,'market',$2) RETURNING id`,
      [`${MARK}store1`, owner1]
    )
  ).rows[0].id;
  const merchant2 = (
    await client.query(
      `INSERT INTO merchant (name, type, owner_user_id) VALUES ($1,'market',$2) RETURNING id`,
      [`${MARK}store2`, owner2]
    )
  ).rows[0].id;

  // Approved, online app courier + fresh presence.
  await client.query(
    `INSERT INTO courier_profile (user_id, is_app_courier, active_status, availability_status)
     VALUES ($1, TRUE, TRUE, $2)
     ON CONFLICT (user_id) DO UPDATE
       SET is_app_courier=TRUE, active_status=TRUE, availability_status=$2`,
    [courierId, courierOnline ? "online" : "offline"]
  );
  await client.query(
    `INSERT INTO courier_presence (courier_user_id, is_online, recorded_at, updated_at)
     VALUES ($1, $2, NOW() - ($3 || ' seconds')::interval, NOW())`,
    [courierId, courierOnline, String(presenceAgeSec)]
  );

  const orderGroupId = (
    await client.query(
      `INSERT INTO order_group
         (public_id, customer_user_id, status, is_multi_store, stores_count, payment_method)
       VALUES ($1,$2,'active',TRUE,2,'cash') RETURNING id`,
      [`${MARK}${Math.floor(presenceAgeSec)}_grp`, customerId]
    )
  ).rows[0].id;

  const child = async (merchantId) =>
    Number(
      (
        await client.query(
          `INSERT INTO customer_order
             (merchant_id, customer_user_id, customer_full_name, customer_phone,
              customer_block, customer_building_number, customer_apartment,
              order_group_id, status, delivery_type, delivery_assignment_status,
              order_scope, courier_source)
           VALUES ($1,$2,$3,'0770',$4,'1','1',$5,$6,'delivery','NOT_REQUIRED','group_child','app')
           RETURNING id`,
          [
            merchantId,
            customerId,
            `${MARK}order`,
            "A101",
            orderGroupId,
            childStatus,
          ]
        )
      ).rows[0].id
    );

  const childOrder1 = await child(merchant1);
  const childOrder2 = await child(merchant2);

  return {
    customerId: Number(customerId),
    courierId: Number(courierId),
    merchantIds: [Number(merchant1), Number(merchant2)],
    orderGroupId: Number(orderGroupId),
    childOrderIds: [Number(childOrder1), Number(childOrder2)],
  };
}
