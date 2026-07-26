import { q } from "./monitoring.shared.js";

export async function getTaxiRideMonitoringDetail(
  rideId,
  { includeLive = false, includeMessages = false } = {}
) {
  const id = Number(rideId);
  if (!Number.isFinite(id) || id <= 0) return null;

  const rideRes = await q(
    `SELECT
       r.id,
       r.status,
       r.customer_user_id,
       cu.full_name AS customer_name,
       r.assigned_captain_user_id,
       ca.full_name AS captain_name,
       ca.phone AS captain_phone,
       r.pickup_latitude,
       r.pickup_longitude,
       r.dropoff_latitude,
       r.dropoff_longitude,
       r.pickup_label,
       r.dropoff_label,
       r.proposed_fare_iqd,
       r.agreed_fare_iqd,
       r.accepted_bid_id,
       r.cancelled_by_role,
       r.cancel_reason_code,
       r.cancel_reason_text,
       r.cancel_previous_status,
       r.cancel_is_emergency,
       r.created_at,
       r.accepted_at,
       r.captain_arriving_at,
       r.started_at,
       r.completed_at,
       r.cancelled_at,
       r.updated_at,
       cp.profile_image_url AS captain_profile_image_url,
       cp.car_image_url AS captain_car_image_url,
       cp.car_make,
       cp.car_model,
       cp.car_year,
       cp.car_color,
       cp.plate_number,
       cp.plate_governorate,
       cp.plate_category,
       cp.plate_letter,
       cp.plate_digits,
       cp.rating_avg,
       cp.rides_count
     FROM taxi_ride_request r
     JOIN app_user cu ON cu.id = r.customer_user_id
     LEFT JOIN app_user ca ON ca.id = r.assigned_captain_user_id
     LEFT JOIN taxi_captain_profile cp ON cp.user_id = r.assigned_captain_user_id
     WHERE r.id = $1
     LIMIT 1`,
    [id]
  );
  const ride = rideRes.rows[0] || null;
  if (!ride) return null;

  const bidsRes = await q(
    `SELECT
       b.id,
       b.captain_user_id,
       u.full_name AS captain_name,
       b.offered_fare_iqd,
       b.eta_minutes,
       b.status,
       b.created_at,
       b.updated_at
     FROM taxi_ride_bid b
     JOIN app_user u ON u.id = b.captain_user_id
     WHERE b.ride_request_id = $1
     ORDER BY b.created_at ASC, b.id ASC`,
    [id]
  );

  const eventsRes = await q(
    `SELECT id, actor_user_id, event_type, message, payload, created_at
     FROM taxi_ride_event
     WHERE ride_request_id = $1
     ORDER BY created_at ASC, id ASC
     LIMIT 200`,
    [id]
  );

  let liveLocation = null;
  if (includeLive) {
    const locationRes = await q(
      `SELECT
         id,
         captain_user_id,
         latitude,
         longitude,
         heading_deg,
         speed_kmh,
         accuracy_m,
         source,
         created_at,
         created_at >= NOW() - INTERVAL '90 seconds' AS is_fresh
       FROM taxi_ride_location_log
       WHERE ride_request_id = $1
       ORDER BY created_at DESC, id DESC
       LIMIT 1`,
      [id]
    );
    liveLocation = locationRes.rows[0] || null;
  }

  let messages = null;
  if (includeMessages) {
    const messagesRes = await q(
      `SELECT
         m.id,
         m.sender_user_id,
         u.full_name AS sender_name,
         m.sender_role,
         m.message_type,
         m.message_text,
         m.offered_fare_iqd,
         m.created_at
       FROM taxi_ride_chat_message m
       JOIN app_user u ON u.id = m.sender_user_id
       WHERE m.ride_request_id = $1
       ORDER BY m.id ASC
       LIMIT 300`,
      [id]
    );
    messages = messagesRes.rows;
  }

  return {
    ride,
    bids: bidsRes.rows,
    events: eventsRes.rows,
    liveLocation,
    messages,
  };
}
