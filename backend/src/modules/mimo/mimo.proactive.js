/**
 * "ميمو يبادر": at most one friendly nudge per day, chosen by plain rules from
 * the user's real data (no AI call, so it's free):
 *   - habit: they usually order around now / on this weekday → "same as usual?"
 *   - expiring coupon → "your coupon ends soon"
 *   - meal time + a favorite store → "lunch time, X is open"
 * The app shows it as Mimo's speech bubble; tapping it opens his chat with a
 * ready message.
 */

import { buildTasteProfile } from "./mimo.memory.js";
import { ACTIVE_ORDER } from "./mimo.support.js";

const DAY = 86400000;
const AR_DAYS = ["الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];

function baghdad(now) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Baghdad",
    weekday: "short",
    hour: "2-digit",
    hour12: false,
  }).formatToParts(now);
  const wd = parts.find((p) => p.type === "weekday")?.value;
  const hour = Number(parts.find((p) => p.type === "hour")?.value);
  const weekday = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].indexOf(wd);
  return { weekday, hour };
}

function slotOf(hour) {
  return hour < 11 ? "morning" : hour < 16 ? "midday" : hour < 19 ? "afternoon" : "evening";
}

export function createDefaultProactiveDeps() {
  return {
    async orders(userId) {
      const m = await import("../orders/orders.repo.js");
      return m.listCustomerOrders(userId, { paginate: true, limit: 30 });
    },
    async coupons(userId) {
      const m = await import("../coupons/coupons.repo.js");
      return m.listCustomerCoupons({ customerId: userId, limit: 20 });
    },
    async name(userId) {
      const m = await import("../auth/auth.repo.js");
      const u = await m.findUserByIdWithAuthFields(userId);
      return String(u?.full_name || "").trim().split(/\s+/)[0] || null;
    },
  };
}

/** Picks today's nudge (or null). `lang` "ar" | "en". */
export async function pickNudge(deps, userId, { now = new Date(), lang = "ar" } = {}) {
  const ar = lang !== "en";
  const [orders, coupons, name] = await Promise.all([
    deps.orders(userId).catch(() => []),
    deps.coupons(userId).catch(() => []),
    deps.name(userId).catch(() => null),
  ]);
  const { weekday, hour } = baghdad(now);
  const today = now.toISOString().slice(0, 10);
  const hi = name ? (ar ? `${name}، ` : `${name}, `) : "";
  const profile = buildTasteProfile(orders, now.getTime());
  const active = orders.some((o) => ACTIVE_ORDER.has(String(o.status)));
  if (active) return null; // they're already ordering — don't interrupt

  // 1) Habit: same weekday they usually order + similar time + a while since.
  if (profile && profile.orders >= 3 && (profile.daysSinceLastOrder ?? 0) >= 4) {
    const days = new Map();
    for (const o of orders) {
      if (!o.created_at) continue;
      const d = baghdad(new Date(o.created_at)).weekday;
      days.set(d, (days.get(d) || 0) + 1);
    }
    const [topDay, topCount] = [...days.entries()].sort((a, b) => b[1] - a[1])[0] || [];
    const fav = profile.favoriteStores[0];
    const dish = profile.favoriteDishes[0];
    if (fav && (topDay === weekday && topCount >= 2) && profile.usualTime === slotOf(hour)) {
      return {
        id: `habit:${today}`,
        kind: "habit",
        mood: "dancing",
        text: ar
          ? `${hi}${AR_DAYS[weekday]} سعيد! 😋 تريد نفس طلبك من ${fav.name}؟`
          : `${hi}happy ${["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][weekday]}! Same order from ${fav.name}?`,
        action: {
          type: "chat",
          message: ar ? `اريد نفس طلبي من ${fav.name}` : `Same order from ${fav.name} please`,
        },
        detail: { storeId: fav.id, dish: dish?.name || null },
      };
    }
  }

  // 2) A usable coupon that ends within 3 days.
  const soon = coupons
    .filter((c) => c.code && c.valid_until)
    .map((c) => ({ c, left: (new Date(c.valid_until).getTime() - now.getTime()) / DAY }))
    .filter((x) => x.left > 0 && x.left <= 3)
    .sort((a, b) => a.left - b.left)[0];
  if (soon) {
    const value = soon.c.discount_type === "fixed" ? `${Number(soon.c.discount_value)} د.ع` : `${Number(soon.c.discount_value)}%`;
    const when = soon.left < 1 ? (ar ? "اليوم" : "today") : ar ? "قريباً" : "soon";
    return {
      id: `coupon:${soon.c.code}:${today}`,
      kind: "coupon",
      mood: "wink",
      text: ar
        ? `${hi}عندك كوبون ${soon.c.code} خصم ${value} يخلص ${when}! 🎁`
        : `${hi}your coupon ${soon.c.code} (${value}) expires ${when}! 🎁`,
      action: { type: "section", section: "offers" },
    };
  }

  // 3) Meal time + a favorite store they haven't ordered from today.
  const mealTime = (hour >= 12 && hour < 15) || (hour >= 19 && hour < 22);
  if (mealTime && profile?.favoriteStores?.length && (profile.daysSinceLastOrder ?? 0) >= 1) {
    const fav = profile.favoriteStores[0];
    const lunch = hour < 15;
    return {
      id: `meal:${lunch ? "lunch" : "dinner"}:${today}`,
      kind: "meal",
      mood: "yummy",
      text: ar
        ? `${hi}صار وقت ${lunch ? "الغدا" : "العشا"} 😋 تحب أشوفلك شي من ${fav.name}؟`
        : `${hi}it's ${lunch ? "lunch" : "dinner"} time 😋 want something from ${fav.name}?`,
      action: {
        type: "chat",
        message: ar ? `اريد ${lunch ? "غدا" : "عشا"} من ${fav.name}` : `I want ${lunch ? "lunch" : "dinner"} from ${fav.name}`,
      },
    };
  }
  return null;
}
