export const CENTRAL_SERVICE_CATALOG = Object.freeze([
  {
    key: "legal",
    title: "خدمات قانونية",
    subtitle: "استشارة ومتابعة معاملات وعقود",
    icon: "balance",
    color: "#6E5845",
    executionModes: ["remote", "provider_location"],
    quickIssues: ["استشارة قانونية", "مراجعة عقد", "متابعة معاملة", "محامٍ لقضية"],
    questions: [
      { key: "caseType", label: "نوع الموضوع القانوني", type: "text", required: true },
      { key: "hasDeadline", label: "هل توجد جلسة أو مهلة قريبة؟", type: "boolean" },
    ],
  },
  {
    key: "medical",
    title: "خدمات طبية",
    subtitle: "مساعدة صحية منزلية وحجز مختص",
    icon: "medical_services",
    color: "#2F6F68",
    executionModes: ["home", "remote", "provider_location"],
    quickIssues: ["طبيب منزلي", "ممرض أو ممرضة", "تحاليل منزلية", "استشارة طبية"],
    questions: [
      { key: "patientAge", label: "عمر المريض", type: "number" },
      { key: "symptoms", label: "الأعراض أو الخدمة المطلوبة", type: "text", required: true },
    ],
  },
  {
    key: "home_maintenance",
    title: "صيانة منزلية",
    subtitle: "كهرباء وسباكة وتبريد وتصليحات",
    icon: "home_repair_service",
    color: "#3F6550",
    executionModes: ["home"],
    quickIssues: ["كهرباء", "سباكة", "تبريد وتكييف", "نجارة", "صيانة عامة"],
    questions: [
      { key: "faultType", label: "ما نوع العطل؟", type: "text", required: true },
      { key: "materialsNeeded", label: "هل تعتقد أن قطع غيار مطلوبة؟", type: "boolean" },
    ],
  },
  {
    key: "roadside",
    title: "صيانة سيارات متنقلة",
    subtitle: "فني يصل إلى موقع السيارة",
    icon: "car_repair",
    color: "#384F67",
    executionModes: ["home"],
    quickIssues: ["بطارية", "إطار مثقوب", "عطل مفاجئ", "تشغيل سيارة", "فحص متنقل"],
    questions: [
      { key: "carModel", label: "نوع وموديل السيارة", type: "text", required: true },
      { key: "canMove", label: "هل السيارة قابلة للحركة؟", type: "boolean" },
    ],
  },
  {
    key: "cleaning",
    title: "تنظيف الشقق",
    subtitle: "تنظيف دوري أو عميق حسب الموعد",
    icon: "cleaning_services",
    color: "#5B7180",
    executionModes: ["home"],
    quickIssues: ["تنظيف شامل", "تنظيف بعد الانتقال", "تنظيف مطبخ", "تنظيف مجالس"],
    questions: [
      { key: "rooms", label: "عدد الغرف التقريبي", type: "number" },
      { key: "deepCleaning", label: "هل المطلوب تنظيف عميق؟", type: "boolean" },
    ],
  },
  {
    key: "wellbeing",
    title: "خدمات الرفاهية",
    subtitle: "عناية شخصية ومناسبات وخدمات منزلية",
    icon: "spa",
    color: "#76566C",
    executionModes: ["home", "provider_location"],
    quickIssues: ["عناية شخصية", "تنظيم مناسبة", "ضيافة", "خدمة منزلية خاصة"],
    questions: [
      { key: "guestCount", label: "عدد الأشخاص إن وجد", type: "number" },
      { key: "preferences", label: "التفضيلات المهمة", type: "text" },
    ],
  },
  {
    key: "sos",
    title: "SOS مساعدة عاجلة",
    subtitle: "أرسل موقعك وتفاصيل الحالة فوراً",
    icon: "sos",
    color: "#A33A32",
    executionModes: ["home"],
    quickIssues: ["إسعاف", "إطفاء", "شرطة", "عطل سيارة خطر", "مساعدة عاجلة أخرى"],
    questions: [
      { key: "emergencyTarget", label: "الجهة المطلوبة", type: "choice", required: true },
      { key: "peopleAtRisk", label: "هل يوجد أشخاص في خطر مباشر؟", type: "boolean" },
    ],
    emergency: true,
  },
]);

export function getCentralServiceCatalogItem(key) {
  const normalized = String(key || "").trim().toLowerCase();
  return CENTRAL_SERVICE_CATALOG.find((item) => item.key === normalized) || null;
}

export function listCentralServiceCatalog() {
  return CENTRAL_SERVICE_CATALOG.map((item, index) => ({
    ...item,
    sortOrder: index + 1,
  }));
}
