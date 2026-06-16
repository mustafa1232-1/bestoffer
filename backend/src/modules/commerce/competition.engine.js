import { AppError } from "../../shared/utils/errors.js";

function toNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function toInt(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function normalizeJsonObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value;
}

function normalizeTierRow(row) {
  const title = String(row?.title || "").trim();
  const requiredCompletedOrders = Math.max(
    1,
    toInt(row?.required_completed_orders, toInt(row?.requiredCompletedOrders, 1))
  );
  const sortOrder = Math.max(1, toInt(row?.sort_order, toInt(row?.sortOrder, 1)));
  return {
    id: row?.id ? Number(row.id) : null,
    competitionId: row?.competition_id ? Number(row.competition_id) : null,
    title: title || `Rank ${sortOrder}`,
    sortOrder,
    requiredCompletedOrders,
    rewardAmount: toNumber(row?.reward_amount ?? row?.rewardAmount, 0),
    rewardLabel: String(row?.reward_label ?? row?.rewardLabel ?? "").trim() || null,
  };
}

function compareTierPriority(a, b) {
  if (a.requiredCompletedOrders !== b.requiredCompletedOrders) {
    return b.requiredCompletedOrders - a.requiredCompletedOrders;
  }
  return a.sortOrder - b.sortOrder;
}

function defaultTierFromCompetition(competition) {
  return {
    id: null,
    competitionId: Number(competition.id),
    title: "Rank 1",
    sortOrder: 1,
    requiredCompletedOrders: Math.max(1, toInt(competition.target_value, 1)),
    rewardAmount: toNumber(competition.reward_amount, 0),
    rewardLabel: null,
  };
}

export function resolveHighestRank(tiers, completedCount) {
  const count = Math.max(0, toInt(completedCount, 0));
  const normalized = Array.isArray(tiers)
    ? tiers.map(normalizeTierRow).sort(compareTierPriority)
    : [];
  for (const tier of normalized) {
    if (count >= tier.requiredCompletedOrders) {
      return tier;
    }
  }
  return null;
}

function resolveNextRank(tiers, completedCount) {
  const count = Math.max(0, toInt(completedCount, 0));
  const normalized = Array.isArray(tiers)
    ? tiers.map(normalizeTierRow).sort(compareTierPriority)
    : [];
  const pending = normalized.filter((tier) => count < tier.requiredCompletedOrders);
  if (!pending.length) return null;
  return pending[pending.length - 1] || null;
}

function mapTiersByCompetition(rows) {
  const map = new Map();
  for (const raw of rows || []) {
    const tier = normalizeTierRow(raw);
    if (!tier.competitionId) continue;
    const list = map.get(tier.competitionId) || [];
    list.push(tier);
    map.set(tier.competitionId, list);
  }
  for (const [key, list] of map.entries()) {
    list.sort(compareTierPriority);
    map.set(key, list);
  }
  return map;
}

async function loadCompetitionTiersTx(client, competitionIds) {
  const ids = (competitionIds || [])
    .map((id) => Number(id))
    .filter((id) => Number.isFinite(id) && id > 0);
  if (!ids.length) return new Map();

  const r = await client.query(
    `SELECT *
     FROM courier_competition_tier
     WHERE competition_id = ANY($1::bigint[])
     ORDER BY competition_id ASC, required_completed_orders DESC, sort_order ASC`,
    [ids]
  );
  return mapTiersByCompetition(r.rows);
}

function valueAsText(value) {
  if (value == null) return "";
  return String(value).trim();
}

function isCompetitionEligibleForOrder(competition, orderRow) {
  const filters = normalizeJsonObject(competition?.filters_json);

  const merchantFilter = toInt(filters.merchantId, 0);
  if (merchantFilter > 0 && merchantFilter !== Number(orderRow?.merchant_id || 0)) {
    return false;
  }

  const blockFilter = valueAsText(filters.customerBlock || filters.block).toUpperCase();
  if (blockFilter) {
    const customerBlock = valueAsText(orderRow?.customer_block).toUpperCase();
    if (!customerBlock || customerBlock !== blockFilter) return false;
  }

  const courierSourceFilter = valueAsText(filters.courierSource).toLowerCase();
  if (courierSourceFilter) {
    const source = valueAsText(orderRow?.courier_source).toLowerCase();
    if (!source || source !== courierSourceFilter) return false;
  }

  const deliveryTypeFilter = valueAsText(filters.deliveryType).toLowerCase();
  if (deliveryTypeFilter) {
    const type = valueAsText(orderRow?.delivery_type).toLowerCase();
    if (!type || type !== deliveryTypeFilter) return false;
  }

  return true;
}

export async function finalizeExpiredCompetitionsTx(client, { now = new Date() } = {}) {
  const finalizedAt = now instanceof Date ? now : new Date(now);
  const expired = await client.query(
    `SELECT *
     FROM courier_competition
     WHERE end_at < $1::timestamptz
       AND (
         is_active = TRUE
         OR status IN ('active', 'draft')
         OR finalized_at IS NULL
       )
     ORDER BY end_at ASC, id ASC
     FOR UPDATE`,
    [finalizedAt]
  );

  if ((expired.rowCount || 0) === 0) {
    return {
      finalizedCompetitionIds: [],
      winnerEvents: [],
      summaryEvents: [],
      courierFinishedEvents: [],
    };
  }

  const competitionIds = expired.rows.map((row) => Number(row.id));
  const tiersByCompetition = await loadCompetitionTiersTx(client, competitionIds);
  const winnerEvents = [];
  const summaryEvents = [];
  const courierFinishedEvents = [];

  for (const competition of expired.rows) {
    const competitionId = Number(competition.id);
    const tiers = tiersByCompetition.get(competitionId) || [defaultTierFromCompetition(competition)];

    const progressRows = await client.query(
      `SELECT *
       FROM courier_competition_progress
       WHERE competition_id = $1`,
      [competitionId]
    );

    let winnersCount = 0;
    for (const progress of progressRows.rows) {
      const completedCount = Math.max(0, toInt(progress.current_value, 0));
      const rank = resolveHighestRank(tiers, completedCount);
      const won = !!rank;
      if (won) winnersCount += 1;

      await client.query(
        `INSERT INTO courier_competition_result
          (
            competition_id,
            courier_user_id,
            final_completed_orders,
            final_rank_sort_order,
            final_rank_title,
            reward_amount,
            won,
            result_json,
            created_at
          )
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,NOW())
         ON CONFLICT (competition_id, courier_user_id)
         DO UPDATE
           SET final_completed_orders = EXCLUDED.final_completed_orders,
               final_rank_sort_order = EXCLUDED.final_rank_sort_order,
               final_rank_title = EXCLUDED.final_rank_title,
               reward_amount = EXCLUDED.reward_amount,
               won = EXCLUDED.won,
               result_json = EXCLUDED.result_json`,
        [
          competitionId,
          Number(progress.courier_user_id),
          completedCount,
          rank ? rank.sortOrder : null,
          rank ? rank.title : null,
          rank ? rank.rewardAmount : 0,
          won,
          JSON.stringify({
            competitionId,
            courierUserId: Number(progress.courier_user_id),
            finalCompletedOrders: completedCount,
            finalRankSortOrder: rank ? rank.sortOrder : null,
            finalRankTitle: rank ? rank.title : null,
            rewardAmount: rank ? rank.rewardAmount : 0,
            won,
          }),
        ]
      );

      await client.query(
        `UPDATE courier_competition_progress
         SET reward_status = CASE WHEN $3::boolean THEN 'qualified' ELSE 'not_qualified' END,
             reward_paid_at = CASE
               WHEN $3::boolean = FALSE THEN reward_paid_at
               ELSE reward_paid_at
             END,
             current_rank_sort_order = $4,
             current_rank_title = $5,
             highest_rank_sort_order = COALESCE(highest_rank_sort_order, $4),
             highest_rank_title = COALESCE(highest_rank_title, $5),
             updated_at = NOW()
         WHERE id = $1`,
        [
          Number(progress.id),
          competitionId,
          won,
          rank ? rank.sortOrder : null,
          rank ? rank.title : null,
        ]
      );

      if (won) {
        winnerEvents.push({
          type: "admin_competition_new_winner",
          competitionId,
          competitionTitle: competition.title,
          courierUserId: Number(progress.courier_user_id),
          finalCompletedOrders: completedCount,
          rankSortOrder: rank.sortOrder,
          rankTitle: rank.title,
          rewardAmount: rank.rewardAmount,
        });
      }

      courierFinishedEvents.push({
        type: "courier_competition_finished",
        competitionId,
        competitionTitle: competition.title,
        courierUserId: Number(progress.courier_user_id),
        finalCompletedOrders: completedCount,
        won,
        rankSortOrder: rank ? rank.sortOrder : null,
        rankTitle: rank ? rank.title : null,
        rewardAmount: rank ? rank.rewardAmount : 0,
      });
    }

    await client.query(
      `UPDATE courier_competition
       SET is_active = FALSE,
           status = 'ended',
           ended_at = COALESCE(ended_at, $2::timestamptz),
           archived_at = COALESCE(archived_at, $2::timestamptz),
           finalized_at = COALESCE(finalized_at, $2::timestamptz),
           updated_at = NOW()
       WHERE id = $1`,
      [competitionId, finalizedAt]
    );

    summaryEvents.push({
      type: "admin_competition_finished_summary",
      competitionId,
      competitionTitle: competition.title,
      winnersCount,
      participantsCount: Number(progressRows.rowCount || 0),
    });
  }

  return {
    finalizedCompetitionIds: competitionIds,
    winnerEvents,
    summaryEvents,
    courierFinishedEvents,
  };
}

export async function onOrderFinallyCompletedTx(client, { orderRow }) {
  if (!orderRow) return { applied: [], courierEvents: [], adminEvents: [], finalized: null };

  const finalized = await finalizeExpiredCompetitionsTx(client);
  const orderId = Number(orderRow.id || 0);
  const courierUserId = Number(orderRow.delivery_user_id || 0);
  if (!orderId || !courierUserId) {
    return { applied: [], courierEvents: [], adminEvents: finalized.winnerEvents, finalized };
  }

  const completedAt = orderRow.completed_at ? new Date(orderRow.completed_at) : new Date();

  const activeCompetitions = await client.query(
    `SELECT *
     FROM courier_competition
     WHERE is_active = TRUE
       AND status IN ('active', 'draft')
       AND start_at <= $1::timestamptz
       AND end_at >= $1::timestamptz
     ORDER BY start_at DESC, id DESC`,
    [completedAt]
  );

  if ((activeCompetitions.rowCount || 0) === 0) {
    return { applied: [], courierEvents: [], adminEvents: finalized.winnerEvents, finalized };
  }

  const competitionIds = activeCompetitions.rows.map((row) => Number(row.id));
  const tiersByCompetition = await loadCompetitionTiersTx(client, competitionIds);

  const applied = [];
  const courierEvents = [];
  const adminEvents = [...(finalized.winnerEvents || [])];

  for (const competition of activeCompetitions.rows) {
    const competitionId = Number(competition.id);

    if (!isCompetitionEligibleForOrder(competition, orderRow)) continue;

    const counted = await client.query(
      `INSERT INTO courier_competition_counted_order
        (competition_id, courier_user_id, order_id, counted_at)
       VALUES ($1,$2,$3,NOW())
       ON CONFLICT (competition_id, courier_user_id, order_id)
       DO NOTHING
       RETURNING id`,
      [competitionId, courierUserId, orderId]
    );

    if ((counted.rowCount || 0) === 0) continue;

    const tiers = tiersByCompetition.get(competitionId) || [defaultTierFromCompetition(competition)];

    const existing = await client.query(
      `SELECT *
       FROM courier_competition_progress
       WHERE competition_id = $1
         AND courier_user_id = $2
       FOR UPDATE`,
      [competitionId, courierUserId]
    );

    const previous = existing.rows[0] || null;
    const previousCount = Math.max(0, toInt(previous?.current_value, 0));
    const previousRankSort = previous?.current_rank_sort_order
      ? Number(previous.current_rank_sort_order)
      : null;
    const previousHighestSort = previous?.highest_rank_sort_order
      ? Number(previous.highest_rank_sort_order)
      : null;

    const currentCount = previousCount + 1;
    const currentRank = resolveHighestRank(tiers, currentCount);
    const nextRank = resolveNextRank(tiers, currentCount);

    const shouldUpdateHighest =
      !!currentRank &&
      (previousHighestSort == null || currentRank.sortOrder < previousHighestSort);

    if (!previous) {
      await client.query(
        `INSERT INTO courier_competition_progress
          (
            competition_id,
            courier_user_id,
            current_value,
            is_completed,
            completed_at,
            reward_status,
            current_rank_sort_order,
            current_rank_title,
            highest_rank_sort_order,
            highest_rank_title,
            last_counted_order_id,
            created_at,
            updated_at
          )
         VALUES ($1,$2,$3,$4,$5,'pending',$6,$7,$8,$9,$10,NOW(),NOW())`,
        [
          competitionId,
          courierUserId,
          currentCount,
          !!currentRank,
          currentRank ? completedAt : null,
          currentRank ? currentRank.sortOrder : null,
          currentRank ? currentRank.title : null,
          currentRank ? currentRank.sortOrder : null,
          currentRank ? currentRank.title : null,
          orderId,
        ]
      );
    } else {
      await client.query(
        `UPDATE courier_competition_progress
         SET current_value = $3,
             is_completed = $4,
             completed_at = CASE
               WHEN completed_at IS NULL AND $4::boolean = TRUE THEN $5::timestamptz
               ELSE completed_at
             END,
             current_rank_sort_order = $6,
             current_rank_title = $7,
             highest_rank_sort_order = CASE
               WHEN $8::boolean THEN $6
               ELSE highest_rank_sort_order
             END,
             highest_rank_title = CASE
               WHEN $8::boolean THEN $7
               ELSE highest_rank_title
             END,
             last_counted_order_id = $9,
             updated_at = NOW()
         WHERE id = $1`,
        [
          Number(previous.id),
          competitionId,
          currentCount,
          !!currentRank,
          completedAt,
          currentRank ? currentRank.sortOrder : null,
          currentRank ? currentRank.title : null,
          shouldUpdateHighest,
          orderId,
        ]
      );
    }

    applied.push({
      competitionId,
      competitionTitle: String(competition.title || "").trim(),
      orderId,
      courierUserId,
      currentCount,
      currentRank,
      nextRank,
    });

    if (currentRank && previousRankSort == null) {
      courierEvents.push({
        type: "courier_competition_rank_unlocked",
        competitionId,
        competitionTitle: String(competition.title || "").trim(),
        courierUserId,
        orderId,
        currentCount,
        rankSortOrder: currentRank.sortOrder,
        rankTitle: currentRank.title,
        rewardAmount: currentRank.rewardAmount,
      });
      adminEvents.push({
        type: "admin_competition_new_winner",
        competitionId,
        competitionTitle: String(competition.title || "").trim(),
        courierUserId,
        orderId,
        currentCount,
        rankSortOrder: currentRank.sortOrder,
        rankTitle: currentRank.title,
        rewardAmount: currentRank.rewardAmount,
      });
    }

    if (
      currentRank &&
      previousRankSort != null &&
      Number(currentRank.sortOrder) < Number(previousRankSort)
    ) {
      courierEvents.push({
        type: "courier_competition_upgraded_rank",
        competitionId,
        competitionTitle: String(competition.title || "").trim(),
        courierUserId,
        orderId,
        currentCount,
        rankSortOrder: currentRank.sortOrder,
        rankTitle: currentRank.title,
        rewardAmount: currentRank.rewardAmount,
        previousRankSortOrder: previousRankSort,
      });
      adminEvents.push({
        type: "admin_competition_new_winner",
        competitionId,
        competitionTitle: String(competition.title || "").trim(),
        courierUserId,
        orderId,
        currentCount,
        rankSortOrder: currentRank.sortOrder,
        rankTitle: currentRank.title,
        rewardAmount: currentRank.rewardAmount,
        previousRankSortOrder: previousRankSort,
      });
    }
  }

  return {
    applied,
    courierEvents,
    adminEvents,
    finalized,
  };
}

export function assertCompetitionTiers(tiers) {
  if (!Array.isArray(tiers) || tiers.length === 0) {
    throw new AppError("COMPETITION_TIERS_REQUIRED", { status: 400 });
  }

  const normalized = tiers.map(normalizeTierRow).sort(compareTierPriority);
  for (let i = 0; i < normalized.length; i += 1) {
    const tier = normalized[i];
    if (!Number.isFinite(tier.requiredCompletedOrders) || tier.requiredCompletedOrders <= 0) {
      throw new AppError("COMPETITION_TIER_REQUIRED_ORDERS_INVALID", { status: 400 });
    }
    if (i > 0) {
      const prev = normalized[i - 1];
      if (tier.requiredCompletedOrders >= prev.requiredCompletedOrders) {
        throw new AppError("COMPETITION_TIERS_MUST_BE_DESCENDING", { status: 400 });
      }
    }
  }

  return normalized.map((tier, index) => ({
    ...tier,
    sortOrder: index + 1,
    title: tier.title || `Rank ${index + 1}`,
  }));
}

