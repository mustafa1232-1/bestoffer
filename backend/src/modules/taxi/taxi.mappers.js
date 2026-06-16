function toNumberOrNull(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function toIntOrNull(value) {
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

function normalizeRide(row) {
  if (!row) return null;
  const finalAcceptanceDeadlineAt = row.final_acceptance_deadline_at || null;
  const rejectedCaptainsCount = toIntOrNull(row.rejected_captains_count) || 0;
  const deadlineExpired = finalAcceptanceDeadlineAt
    ? new Date(finalAcceptanceDeadlineAt).getTime() <= Date.now()
    : false;

  return {
    id: Number(row.id),
    customerUserId: Number(row.customer_user_id),
    assignedCaptainUserId: toIntOrNull(row.assigned_captain_user_id),
    currentBidId: toIntOrNull(row.current_bid_id),
    pickup: {
      latitude: Number(row.pickup_latitude),
      longitude: Number(row.pickup_longitude),
      label: row.pickup_label,
    },
    dropoff: {
      latitude: Number(row.dropoff_latitude),
      longitude: Number(row.dropoff_longitude),
      label: row.dropoff_label,
    },
    proposedFareIqd: Number(row.proposed_fare_iqd),
    agreedFareIqd: toIntOrNull(row.agreed_fare_iqd),
    scheduleMode: row.schedule_mode || "now",
    scheduledRideId: toIntOrNull(row.scheduled_ride_id),
    scheduledFor: row.scheduled_for || null,
    couponId: toIntOrNull(row.coupon_id),
    couponCodeSnapshot: row.coupon_code_snapshot || null,
    couponUseIndex: toIntOrNull(row.coupon_use_index),
    fareBeforeDiscountIqd: toIntOrNull(row.fare_before_discount_iqd),
    couponDiscountIqd: toIntOrNull(row.coupon_discount_iqd) || 0,
    fareAfterDiscountIqd: toIntOrNull(row.fare_after_discount_iqd),
    couponSettlementState: row.coupon_settlement_state || "none",
    searchRadiusM: Number(row.search_radius_m),
    note: row.note || null,
    status: row.status,
    shareToken: row.share_token || null,
    acceptedBidId: toIntOrNull(row.accepted_bid_id),
    expiresAt: row.expires_at,
    searchPhase: toIntOrNull(row.search_phase) || 1,
    nextEscalationAt: row.next_escalation_at || null,
    noCaptainNotifiedAt: row.no_captain_notified_at || null,
    rejectedCaptainsCount,
    priceRaisePromptedAt: row.price_raise_prompted_at || null,
    finalAcceptanceDeadlineAt,
    priceRaiseRecommended: rejectedCaptainsCount >= 3 || deadlineExpired,
    acceptedAt: row.accepted_at,
    captainArrivingAt: row.captain_arriving_at,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    cancelledAt: row.cancelled_at,
    captainRating: toIntOrNull(row.captain_rating),
    captainReview: row.captain_review || null,
    captainRatedAt: row.captain_rated_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    distanceM: toNumberOrNull(row.distance_m),
    myBid: row.my_bid_id
      ? {
          id: Number(row.my_bid_id),
          offeredFareIqd: Number(row.my_offered_fare_iqd),
          etaMinutes: toIntOrNull(row.my_eta_minutes),
          status: row.my_bid_status,
          counterOfferCount: toIntOrNull(row.my_counter_offer_count) || 0,
          lastOfferIqd: toIntOrNull(row.my_last_offer_iqd),
          lastOfferBy: row.my_last_offer_by || null,
          createdAt: row.my_bid_created_at || null,
          updatedAt: row.my_bid_updated_at || null,
        }
      : null,
    customer: row.customer_full_name
      ? {
          id: Number(row.customer_user_id),
          fullName: row.customer_full_name,
          phone: row.customer_phone || null,
        }
      : null,
    captain: row.captain_full_name
      ? {
          id: toIntOrNull(row.assigned_captain_user_id),
          fullName: row.captain_full_name,
          phone: row.captain_phone || null,
          profileImageUrl: row.captain_profile_image_url || null,
          carImageUrl: row.captain_car_image_url || null,
          vehicleType: row.captain_vehicle_type || null,
          carMake: row.captain_car_make || null,
          carModel: row.captain_car_model || null,
          carYear: toIntOrNull(row.captain_car_year),
          carColor: row.captain_car_color || null,
          plateNumber: row.captain_plate_number || null,
          ratingAvg: toNumberOrNull(row.captain_rating_avg),
          ridesCount: toIntOrNull(row.captain_rides_count) || 0,
        }
      : null,
  };
}

function normalizeBid(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    captainUserId: Number(row.captain_user_id),
    offeredFareIqd: Number(row.offered_fare_iqd),
    etaMinutes: toIntOrNull(row.eta_minutes),
    note: row.note || null,
    status: row.status,
    counterOfferCount: toIntOrNull(row.counter_offer_count) || 0,
    lastOfferIqd: toIntOrNull(row.last_offer_iqd),
    lastOfferBy: row.last_offer_by || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    captain: row.captain_full_name
      ? {
          id: Number(row.captain_user_id),
          fullName: row.captain_full_name,
          phone: row.captain_phone || null,
          profileImageUrl: row.captain_profile_image_url || null,
          carImageUrl: row.captain_car_image_url || null,
          vehicleType: row.captain_vehicle_type || null,
          carMake: row.captain_car_make || null,
          carModel: row.captain_car_model || null,
          carYear: toIntOrNull(row.captain_car_year),
          carColor: row.captain_car_color || null,
          plateNumber: row.captain_plate_number || null,
          ratingAvg: toNumberOrNull(row.captain_rating_avg),
          ridesCount: toIntOrNull(row.captain_rides_count) || 0,
        }
      : null,
  };
}

function normalizeChatMessage(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    senderUserId: Number(row.sender_user_id),
    senderRole: row.sender_role,
    messageType: row.message_type,
    messageText: row.message_text || null,
    offeredFareIqd: toIntOrNull(row.offered_fare_iqd),
    createdAt: row.created_at,
    sender: row.sender_full_name
      ? {
          id: Number(row.sender_user_id),
          fullName: row.sender_full_name,
          phone: row.sender_phone || null,
          imageUrl: row.sender_image_url || null,
        }
      : null,
  };
}

function normalizeCallSession(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    initiatorUserId: Number(row.initiator_user_id),
    receiverUserId: Number(row.receiver_user_id),
    status: row.status,
    startedAt: row.started_at,
    answeredAt: row.answered_at || null,
    endedAt: row.ended_at || null,
    endedByUserId: toIntOrNull(row.ended_by_user_id),
    endReason: row.end_reason || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function normalizeCallSignal(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    callSessionId: Number(row.call_session_id),
    rideRequestId: Number(row.ride_request_id),
    senderUserId: Number(row.sender_user_id),
    signalType: row.signal_type,
    signalPayload: row.signal_payload || null,
    createdAt: row.created_at,
  };
}

function normalizePresence(row) {
  if (!row) return null;
  return {
    captainUserId: Number(row.captain_user_id),
    isOnline: row.is_online === true,
    latitude: toNumberOrNull(row.latitude),
    longitude: toNumberOrNull(row.longitude),
    headingDeg: toNumberOrNull(row.heading_deg),
    speedKmh: toNumberOrNull(row.speed_kmh),
    accuracyM: toNumberOrNull(row.accuracy_m),
    lastSeenAt: row.last_seen_at,
    updatedAt: row.updated_at,
  };
}

function normalizeLocation(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    captainUserId: Number(row.captain_user_id),
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    headingDeg: toNumberOrNull(row.heading_deg),
    speedKmh: toNumberOrNull(row.speed_kmh),
    accuracyM: toNumberOrNull(row.accuracy_m),
    source: row.source,
    createdAt: row.created_at,
  };
}

function normalizeEvent(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    actorUserId: toIntOrNull(row.actor_user_id),
    eventType: row.event_type,
    message: row.message || null,
    payload: row.payload || null,
    createdAt: row.created_at,
  };
}

function normalizeRideFriendShare(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    customerUserId: Number(row.customer_user_id),
    friendUserId: Number(row.friend_user_id),
    status: row.status,
    sharedAt: row.shared_at || null,
    revokedAt: row.revoked_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
    friend: row.friend_full_name
      ? {
          id: Number(row.friend_user_id),
          fullName: row.friend_full_name,
          phone: row.friend_phone || null,
        }
      : null,
  };
}

export {
  normalizeBid,
  normalizeCallSession,
  normalizeCallSignal,
  normalizeChatMessage,
  normalizeEvent,
  normalizeLocation,
  normalizePresence,
  normalizeRide,
  normalizeRideFriendShare,
  toIntOrNull,
  toNumberOrNull,
};
