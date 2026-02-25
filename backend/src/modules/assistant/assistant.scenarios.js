const INTENT_VARIANTS = [
  "BROWSE",
  "RECOMMEND",
  "MOOD_BASED",
  "ORDER_DIRECT",
  "OFFERS",
  "DISCOVER_NEW",
  "EVALUATE",
  "SUPPORT",
];

const STYLE_VARIANTS = ["neutral", "formal", "playful", "rush"];
const AUDIENCE_VARIANTS = ["unknown", "solo", "family", "group"];
const MEAL_VARIANTS = ["any", "breakfast", "lunch", "dinner", "snack"];
const PRIORITY_VARIANTS = ["balanced", "cheap", "fast", "quality"];

const OPENERS_AR = {
  BROWSE: [
    "على راسي، خليني أفهم ذوقك أكثر حتى أضبط الاختيارات.",
    "ممتاز، نرتبها خطوة بخطوة حتى يطلع الخيار مضبوط.",
  ],
  RECOMMEND: [
    "أكيد، أرتبلك ترشيح ذكي لكن أولاً أفهمك بدقة.",
    "تم، قبل الترشيح خليني آخذ منك كم معلومة سريعة.",
  ],
  MOOD_BASED: [
    "حلو، نختار على مزاجك اليوم.",
    "تمام، خل نحول المزاج لطلب مضبوط.",
  ],
  ORDER_DIRECT: [
    "وصلت فكرتك، بس خليني أحدد تفاصيل بسيطة حتى ما نخرب الطلب.",
    "ممتاز، قبل التثبيت آخذ منك نقطتين حتى يكون الطلب دقيق.",
  ],
  OFFERS: [
    "تمام، أشوفلك العروض المناسبة إلك.",
    "أكيد، نخلي العرض فعلاً مناسب لمزاجك.",
  ],
  DISCOVER_NEW: [
    "حلو، إذا تريد جديد فعلًا خلينا نحدد الاتجاه.",
    "ممتاز، أطلعلك الجديد بس حسب تفضيلك أنت.",
  ],
  EVALUATE: [
    "أكيد، أقيمه إلك بشكل واضح وبدون مجاملة.",
    "تمام، نعطيك تقييم متوازن يفيدك بالقرار.",
  ],
  SUPPORT: [
    "حقك علينا، خليني أتابعها وياك خطوة بخطوة.",
    "آسف على الإزعاج، راح أتعامل وياها مباشرة.",
  ],
};

const OPENERS_EN = {
  BROWSE: [
    "Sure, let me understand your taste first to tune the choices.",
    "Great, we can do this step by step for a precise pick.",
  ],
  RECOMMEND: [
    "Absolutely, I will recommend smartly after a quick understanding.",
    "Perfect, let me capture a few details before recommending.",
  ],
  MOOD_BASED: [
    "Nice, let us pick based on your current mood.",
    "Great, we will convert your mood into the right order.",
  ],
  ORDER_DIRECT: [
    "Got it. Let me lock a couple details so the order is accurate.",
    "Perfect. Before checkout, I need two quick details.",
  ],
  OFFERS: [
    "Great, I will surface offers that match you best.",
    "Sure, let us make the offer truly relevant to your needs.",
  ],
  DISCOVER_NEW: [
    "Nice, if you want new options we should set direction first.",
    "Great, I can show new places based on your preference.",
  ],
  EVALUATE: [
    "Sure, I can evaluate it clearly and objectively.",
    "Perfect, I will give you a balanced evaluation.",
  ],
  SUPPORT: [
    "I am sorry about this. Let me handle it with you step by step.",
    "Thanks for reporting this. I will follow it up right away.",
  ],
};

const TRACK_QUESTIONS = {
  cuisine: {
    ar: [
      "تميل اليوم لشرقي لو غربي؟",
      "تحب مشاوي، برغر، بيتزا، لو أكل خفيف؟",
    ],
    en: [
      "Do you prefer Eastern or Western today?",
      "Would you like grills, burgers, pizza, or lighter food?",
    ],
  },
  budget: {
    ar: [
      "شكد ميزانيتك تقريباً بالدينار؟",
      "تحبها اقتصادية لو عادي لو فخمة؟",
    ],
    en: [
      "What is your approximate budget in IQD?",
      "Do you prefer budget, medium, or premium options?",
    ],
  },
  speed: {
    ar: [
      "الأولوية عندك السرعة لو السعر؟",
      "تريد أسرع توصيل حتى لو أغلى شوي؟",
    ],
    en: [
      "Is your priority speed or price?",
      "Do you want fastest delivery even if slightly higher price?",
    ],
  },
  meal: {
    ar: [
      "الطلب فطور لو غداء لو عشاء؟",
      "مزاجك وجبة دسمة لو خفيفة؟",
    ],
    en: [
      "Is this for breakfast, lunch, or dinner?",
      "Do you want a heavy meal or a light one?",
    ],
  },
  audience: {
    ar: [
      "الطلب لشخص واحد لو للعائلة؟",
      "كم شخص تقريباً حتى أضبط الكمية؟",
    ],
    en: [
      "Is this for one person or family?",
      "How many people approximately?",
    ],
  },
  dietary: {
    ar: [
      "عندك حساسية أو نظام غذائي معين؟",
      "تحب بدون لحم أو خيارات صحية اليوم؟",
    ],
    en: [
      "Do you have any allergy or dietary requirement?",
      "Would you like no-meat or healthier choices today?",
    ],
  },
};

function simpleHash(value) {
  const text = String(value || "");
  let hash = 0;
  for (let i = 0; i < text.length; i += 1) {
    hash = (hash * 31 + text.charCodeAt(i)) % 2147483647;
  }
  return Math.abs(hash);
}

function buildScenarioLibrary() {
  const out = [];
  let id = 1;
  for (const intent of INTENT_VARIANTS) {
    for (const style of STYLE_VARIANTS) {
      for (const audience of AUDIENCE_VARIANTS) {
        for (const meal of MEAL_VARIANTS) {
          for (const priority of PRIORITY_VARIANTS) {
            const phase = intent === "SUPPORT" ? "support" : "discovery";
            const openerArSeed = OPENERS_AR[intent] || OPENERS_AR.BROWSE;
            const openerEnSeed = OPENERS_EN[intent] || OPENERS_EN.BROWSE;
            const openerIndex = (id + style.length + priority.length) % openerArSeed.length;
            out.push({
              id: `scn_${String(id).padStart(4, "0")}`,
              intent,
              style,
              audience,
              meal,
              priority,
              phase,
              openerAr: openerArSeed[openerIndex],
              openerEn: openerEnSeed[openerIndex],
              trackOrder:
                priority === "fast"
                  ? ["speed", "cuisine", "budget", "meal", "audience", "dietary"]
                  : priority === "cheap"
                  ? ["budget", "cuisine", "speed", "meal", "audience", "dietary"]
                  : ["cuisine", "budget", "speed", "meal", "audience", "dietary"],
            });
            id += 1;
          }
        }
      }
    }
  }
  return out;
}

const SCENARIO_LIBRARY = buildScenarioLibrary();

export function getScenarioLibrarySize() {
  return SCENARIO_LIBRARY.length;
}

export function pickScenarioBlueprint({
  intent = "BROWSE",
  style = "neutral",
  audience = "unknown",
  meal = "any",
  priority = "balanced",
  seed = "",
}) {
  const filtered = SCENARIO_LIBRARY.filter(
    (s) =>
      s.intent === intent &&
      s.style === style &&
      s.audience === audience &&
      s.meal === meal &&
      s.priority === priority
  );
  const source = filtered.length ? filtered : SCENARIO_LIBRARY.filter((s) => s.intent === intent);
  const pool = source.length ? source : SCENARIO_LIBRARY;
  const index = simpleHash(`${intent}|${style}|${audience}|${meal}|${priority}|${seed}`) % pool.length;
  return pool[index];
}

export function pickScenarioQuestion(slotKey, lang = "ar", seed = "") {
  const entry = TRACK_QUESTIONS[slotKey] || TRACK_QUESTIONS.cuisine;
  const items = lang === "en" ? entry.en : entry.ar;
  const index = simpleHash(`${slotKey}|${seed}|${lang}`) % items.length;
  return items[index];
}
