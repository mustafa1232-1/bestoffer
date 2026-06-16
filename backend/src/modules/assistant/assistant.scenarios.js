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
      "شنو مزاجك اليوم: عراقي، إيطالي، سريع، لو خفيف؟",
      "تحب نروح على مطاعم مجربة لو نجرب شي جديد؟",
      "تفضّل أكل بيتي وطعم تقليدي لو شي غربي سريع؟",
      "تحب يكون الأكل حار لو عادي؟",
    ],
    en: [
      "Do you prefer Eastern or Western today?",
      "Would you like grills, burgers, pizza, or lighter food?",
      "What is your mood today: Iraqi, Italian, fast food, or light meals?",
      "Would you prefer trusted places or a new experience?",
      "Do you prefer spicy food or regular?",
    ],
  },
  budget: {
    ar: [
      "شكد ميزانيتك تقريباً بالدينار؟",
      "تحبها اقتصادية لو عادي لو فخمة؟",
      "تحب أخلي السلة ضمن مبلغ معين؟",
      "تقريباً كم تريد تدفع للطلب كامل؟",
      "نركّز على الأرخص حتى لو الخيارات أقل؟",
    ],
    en: [
      "What is your approximate budget in IQD?",
      "Do you prefer budget, medium, or premium options?",
      "Do you want me to keep the basket under a target amount?",
      "How much do you want to spend for the full order?",
      "Should I prioritize the cheapest options even with fewer choices?",
    ],
  },
  speed: {
    ar: [
      "الأولوية عندك السرعة لو السعر؟",
      "تريد أسرع توصيل حتى لو أغلى شوي؟",
      "مستعجل لو عادي إذا التوصيل أخذ وقت أكثر؟",
      "تحب توصيل قريب وسريع لو سعر أقل حتى لو أبعد؟",
      "نرتبها على أسرع وصول لو أفضل قيمة؟",
    ],
    en: [
      "Is your priority speed or price?",
      "Do you want fastest delivery even if slightly higher price?",
      "Are you in a hurry, or is extra delivery time okay?",
      "Do you want nearby fast delivery or lower price with longer time?",
      "Should I optimize for fastest arrival or best value?",
    ],
  },
  meal: {
    ar: [
      "الطلب فطور لو غداء لو عشاء؟",
      "مزاجك وجبة دسمة لو خفيفة؟",
      "الطلب إلك وحدك لو للجمعه؟",
      "تحب وجبة رئيسية لو سناك سريع؟",
      "تحب نضيف مشروب أو حلو ويا الوجبة؟",
    ],
    en: [
      "Is this for breakfast, lunch, or dinner?",
      "Do you want a heavy meal or a light one?",
      "Is this for you only or for a group?",
      "Do you want a full meal or a quick snack?",
      "Would you like a drink or dessert with it?",
    ],
  },
  audience: {
    ar: [
      "الطلب لشخص واحد لو للعائلة؟",
      "كم شخص تقريباً حتى أضبط الكمية؟",
      "عدكم ضيوف اليوم؟ حتى أرتب كميات مناسبة.",
      "تحب وجبات فردية لو صواني مشاركة؟",
      "تريد كمية تشبع الكل لو خيارات منوعة أكثر؟",
    ],
    en: [
      "Is this for one person or family?",
      "How many people approximately?",
      "Do you have guests today so I can size portions correctly?",
      "Do you prefer individual meals or sharing platters?",
      "Should we prioritize larger portions or more variety?",
    ],
  },
  dietary: {
    ar: [
      "عندك حساسية أو نظام غذائي معين؟",
      "تحب بدون لحم أو خيارات صحية اليوم؟",
      "في مكونات ما تريدها نهائياً؟",
      "تحب نركز على أكل صحي وسعرات أقل؟",
      "تريد خيارات نباتية أو بدون غلوتين؟",
    ],
    en: [
      "Do you have any allergy or dietary requirement?",
      "Would you like no-meat or healthier choices today?",
      "Any ingredients you want me to avoid completely?",
      "Should I focus on healthier, lower-calorie options?",
      "Do you need vegetarian or gluten-free options?",
    ],
  },
};

const TRACK_FOLLOWUPS = {
  cuisine: {
    ar: [
      "تفضّل نركز على مطاعم مضمونة ومجربة لو تحب نجرب مكان جديد؟",
      "تريد الطعم التقليدي العراقي لو نروح لشي مختلف اليوم؟",
      "تحب الأكل يكون ثقيل ومشبع لو خفيف وسريع؟",
      "نختار حسب الطعم أولًا لو حسب التقييم أولًا؟",
    ],
    en: [
      "Do you want trusted places or to try somewhere new?",
      "Should we optimize for familiar taste or a new experience?",
      "Do you want a heavy satisfying meal or a lighter one?",
      "Should we rank by taste first or ratings first?",
    ],
  },
  budget: {
    ar: [
      "تريدني أضبط لك خيار اقتصادي قوي حتى لو الخيارات أقل؟",
      "أفضّل أراعي السعر الكلي مع التوصيل حتى ما يصير فرق بعد الدفع.",
      "تحب نثبت سقف واضح للسلة حتى ما نتجاوزه؟",
      "نوازن بين السعر والجودة لو نركز على الأرخص فقط؟",
    ],
    en: [
      "Should I optimize for strict budget even with fewer options?",
      "I can include delivery cost in the total to avoid surprises, okay?",
      "Do you want a hard basket limit so we do not exceed it?",
      "Do we balance cost and quality or focus on lowest price only?",
    ],
  },
  speed: {
    ar: [
      "الآن الوقت يهمك أكثر لو الجودة حتى لو تتأخر شوي؟",
      "أرتب لك الخيارات الأقرب أولًا حتى يوصل الطلب أسرع.",
      "تحب أوصل لك أسرع نتيجة الآن وبعدها نفلتر بهدوء؟",
      "إذا التأخير زاد، أبدله مباشرة بخيار أسرع؟",
    ],
    en: [
      "Is speed more important now than quality?",
      "I can rank nearby options first for faster delivery.",
      "Do you want the fastest shortlist now then refine?",
      "If ETA increases, should I auto-switch to a faster option?",
    ],
  },
  meal: {
    ar: [
      "تريد وجبة كاملة مع إضافات لو شيء بسيط وسريع؟",
      "تحب أضيف مشروب/حلو بشكل ذكي حسب الاختيار؟",
      "هل الأهم التشبّع لو الطعم الخفيف اليوم؟",
      "نمشي بوجبة فردية لو عرض عائلي إذا أوفر؟",
    ],
    en: [
      "Do you want a full meal with extras or something quick?",
      "Should I smart-add drink/dessert suggestions?",
      "Is fullness or light taste more important today?",
      "Single meal or family combo if value is better?",
    ],
  },
  audience: {
    ar: [
      "بناءً على عدد الأشخاص أقدر أضبط الكمية بدون هدر.",
      "تحب صواني مشاركة لو كل شخص له وجبته؟",
      "عدكم أطفال؟ حتى أراعي الخيارات المناسبة إلهم.",
      "ننوع أكثر لو نختار طبقين مضمونين للكل؟",
    ],
    en: [
      "Based on headcount, I can size portions with less waste.",
      "Do you prefer sharing platters or individual meals?",
      "Any kids in the group so I tailor kid-friendly choices?",
      "More variety or fewer but safer crowd-pleasers?",
    ],
  },
  dietary: {
    ar: [
      "أأكد عليك: أكو مكونات لازم نمنعها نهائيًا؟",
      "تريد خيارات صحية أكثر حتى لو أغلى شوي؟",
      "أضيف فلتر خالٍ من مسببات الحساسية بشكل صارم؟",
      "نختار خيارات قليلة سعرات أو نركز على الطعم؟",
    ],
    en: [
      "Let me confirm: any ingredients to avoid strictly?",
      "Do you want healthier options even if slightly pricier?",
      "Should I apply strict allergy-safe filtering?",
      "Do we optimize for lower calories or taste?",
    ],
  },
};

const RESPONSE_STYLE_HINTS = {
  ar: [
    "أجاوبك بشكل واضح ومباشر بدون تعقيد.",
    "أعطيك ترشيح مبني على التقييم والطلبات والمراجعات.",
    "إذا ما كانت الصورة كاملة، أسألك سؤال توضيحي قبل القرار.",
    "أذكر لك السبب وراء كل ترشيح حتى تكون واثق بالاختيار.",
  ],
  en: [
    "I answer clearly and directly.",
    "I recommend based on ratings, order trends, and reviews.",
    "If data is incomplete, I ask a clarifying question first.",
    "I explain why each recommendation was selected.",
  ],
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

export function pickScenarioFollowUp(slotKey, lang = "ar", seed = "") {
  const entry = TRACK_FOLLOWUPS[slotKey] || TRACK_FOLLOWUPS.cuisine;
  const items = lang === "en" ? entry.en : entry.ar;
  const index = simpleHash(`followup|${slotKey}|${seed}|${lang}`) % items.length;
  return items[index];
}

export function pickScenarioResponseHint(lang = "ar", seed = "") {
  const items = lang === "en" ? RESPONSE_STYLE_HINTS.en : RESPONSE_STYLE_HINTS.ar;
  const index = simpleHash(`response_hint|${seed}|${lang}`) % items.length;
  return items[index];
}
