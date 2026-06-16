function firstNonEmpty(...values) {
  for (const value of values) {
    if (value == null) continue;
    const normalized = String(value).trim();
    if (normalized) return normalized;
  }
  return null;
}

function assignI18n(
  payload,
  titleKey,
  bodyKey,
  { titleArgs = null, bodyArgs = null } = {}
) {
  if (!payload.i18nTitleKey) {
    payload.i18nTitleKey = titleKey;
  }
  if (!payload.i18nBodyKey) {
    payload.i18nBodyKey = bodyKey;
  }
  if (titleArgs && !payload.i18nTitleArgs) {
    payload.i18nTitleArgs = titleArgs;
  }
  if (bodyArgs && !payload.i18nBodyArgs) {
    payload.i18nBodyArgs = bodyArgs;
  }
  return payload;
}

export function attachNotificationI18n({ type, payload }) {
  const normalizedType = String(type || "").trim().toLowerCase();
  const out =
    payload && typeof payload === "object" && !Array.isArray(payload)
      ? { ...payload }
      : {};

  if (!normalizedType) {
    return assignI18n(
      out,
      "notifications.generic.title",
      "notifications.generic.body"
    );
  }

  const actorName = firstNonEmpty(
    out.remoteDisplayName,
    out.remote_display_name,
    out.senderName,
    out.sender_name,
    out.actorName,
    out.actor_name,
    out.callerName,
    out.caller_name
  );

  if (
    normalizedType.startsWith("social.call.") ||
    normalizedType.startsWith("social_call.")
  ) {
    return assignI18n(
      out,
      "notifications.social.call.title",
      "notifications.social.call.body",
      {
        bodyArgs: actorName ? { senderName: actorName } : null,
      }
    );
  }

  if (
    normalizedType.startsWith("social.chat.") ||
    normalizedType.startsWith("social_chat.") ||
    normalizedType === "social_chat_message" ||
    normalizedType === "order_chat_message" ||
    normalizedType === "taxi.chat.message"
  ) {
    return assignI18n(
      out,
      "notifications.chat.message.title",
      "notifications.chat.message.body",
      {
        bodyArgs: actorName ? { senderName: actorName } : null,
      }
    );
  }

  if (normalizedType.startsWith("social.post.like")) {
    return assignI18n(
      out,
      "notifications.social.post.like.title",
      "notifications.social.post.like.body"
    );
  }

  if (normalizedType.startsWith("social.reel.like")) {
    return assignI18n(
      out,
      "notifications.social.reel.like.title",
      "notifications.social.reel.like.body"
    );
  }

  if (
    normalizedType.startsWith("social.story.") ||
    normalizedType.startsWith("social_story.")
  ) {
    return assignI18n(
      out,
      "notifications.social.story.title",
      "notifications.social.story.body",
      {
        bodyArgs: actorName ? { senderName: actorName } : null,
      }
    );
  }

  if (normalizedType.includes(".comment")) {
    return assignI18n(
      out,
      "notifications.social.comment.title",
      "notifications.social.comment.body"
    );
  }

  if (
    normalizedType.startsWith("social.mention.") ||
    normalizedType.startsWith("social.tag.")
  ) {
    return assignI18n(
      out,
      "notifications.social.mention.title",
      "notifications.social.mention.body"
    );
  }

  if (normalizedType.startsWith("social.relation.")) {
    return assignI18n(
      out,
      "notifications.social.relation.title",
      "notifications.social.relation.body"
    );
  }

  if (normalizedType.startsWith("social.report.")) {
    return assignI18n(
      out,
      "notifications.social.report.title",
      "notifications.social.report.body"
    );
  }

  if (
    normalizedType.startsWith("social.community.") ||
    normalizedType.startsWith("social_community.") ||
    normalizedType === "same_block" ||
    normalizedType === "same_building" ||
    normalizedType === "same_compound"
  ) {
    return assignI18n(
      out,
      "notifications.social.community.title",
      "notifications.social.community.body"
    );
  }

  if (normalizedType.startsWith("social.")) {
    return assignI18n(
      out,
      "notifications.social.activity.title",
      "notifications.social.activity.body"
    );
  }

  if (
    normalizedType.startsWith("residence.change.") ||
    normalizedType.startsWith("profile.")
  ) {
    return assignI18n(
      out,
      "notifications.profile.title",
      "notifications.profile.body"
    );
  }

  if (
    normalizedType.startsWith("hr.") ||
    normalizedType.startsWith("employee.") ||
    normalizedType.startsWith("accountant.")
  ) {
    return assignI18n(
      out,
      "notifications.hr.title",
      "notifications.hr.body"
    );
  }

  if (
    normalizedType.startsWith("admin_") ||
    normalizedType.includes("approval") ||
    normalizedType.includes("settlement")
  ) {
    return assignI18n(
      out,
      "notifications.admin.title",
      "notifications.admin.body"
    );
  }

  if (normalizedType.startsWith("real_estate.")) {
    return assignI18n(
      out,
      "notifications.real_estate.title",
      "notifications.real_estate.body"
    );
  }

  if (normalizedType.startsWith("jobs.")) {
    return assignI18n(
      out,
      "notifications.jobs.title",
      "notifications.jobs.body"
    );
  }

  if (normalizedType.startsWith("paid_upgrade.")) {
    return assignI18n(
      out,
      "notifications.paid_upgrades.title",
      "notifications.paid_upgrades.body"
    );
  }

  if (normalizedType.startsWith("taxi.")) {
    return assignI18n(
      out,
      "notifications.taxi.title",
      "notifications.taxi.body"
    );
  }

  if (
    normalizedType.startsWith("delivery.") ||
    normalizedType.startsWith("delivery_") ||
    normalizedType.startsWith("courier_") ||
    normalizedType.startsWith("customer_delivery")
  ) {
    return assignI18n(
      out,
      "notifications.delivery.title",
      "notifications.delivery.body"
    );
  }

  if (
    normalizedType.startsWith("company.") ||
    normalizedType.startsWith("company_")
  ) {
    return assignI18n(
      out,
      "notifications.company.title",
      "notifications.company.body"
    );
  }

  if (
    normalizedType.startsWith("owner_") ||
    normalizedType.startsWith("customer_order") ||
    normalizedType.startsWith("order_") ||
    normalizedType.includes("order")
  ) {
    return assignI18n(
      out,
      "notifications.orders.title",
      "notifications.orders.body"
    );
  }

  return assignI18n(
    out,
    "notifications.generic.title",
    "notifications.generic.body"
  );
}
