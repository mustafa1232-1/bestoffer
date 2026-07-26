-- 182_app_guides.sql
-- المرحلة 10: أدلة استخدام لكل تطبيق (versioned + scope-aware). قسم الإدارة
-- يمكن ربط كل خطوة بصلاحية فلا تظهر لمن لا يملكها. Forward-only.

BEGIN;

CREATE TABLE IF NOT EXISTS app_guide_section (
  id                  BIGSERIAL PRIMARY KEY,
  app_scope           VARCHAR(16) NOT NULL,
  section_key         VARCHAR(64) NOT NULL,
  title               VARCHAR(240) NOT NULL,
  body                TEXT NOT NULL,
  order_index         INTEGER NOT NULL DEFAULT 0,
  required_permission VARCHAR(80),
  deep_link           VARCHAR(160),
  version             INTEGER NOT NULL DEFAULT 1,
  is_published        BOOLEAN NOT NULL DEFAULT TRUE,
  updated_by_user_id  BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_app_guide_scope CHECK (app_scope IN (
    'user','store','captain','delivery','admin'
  )),
  UNIQUE (app_scope, section_key)
);

CREATE INDEX IF NOT EXISTS idx_app_guide_section_scope
  ON app_guide_section (app_scope, is_published, order_index);

-- بذور محتوى أساسي حقيقي لكل تطبيق (قابل للتحديث من الإدارة لاحقاً).
INSERT INTO app_guide_section (app_scope, section_key, title, body, order_index) VALUES
  ('user','account','الحساب والدخول','أنشئ حسابك برقم الهاتف، أو تابع كضيف. يمكنك إكمال ملفك لاحقاً من الإعدادات.',1),
  ('user','shopping','التسوق والطلب','تصفّح المتاجر، أضف المنتجات للسلة، ثم أكمل الطلب واختر طريقة الدفع.',2),
  ('user','delivery','التوصيل والتتبع','تابع حالة طلبك لحظياً على الخريطة حتى الاستلام.',3),
  ('user','taxi','التاكسي','اطلب رحلة، وتابع الكابتن. لا يمكن إلغاء الرحلة بعد توجه الكابتن إليك؛ استخدم زر المساعدة للطوارئ.',4),
  ('user','support','الشكاوى والدعم','ارفع شكوى من الطلب أو الرحلة مباشرة، وتابع تذكرتك حتى الحل والتقييم.',5),
  ('store','store_setup','إنشاء المتجر','أكمل بيانات متجرك ونشاطه، وفعّل ساعات العمل.',1),
  ('store','products','المنتجات والمخزون','أضف المنتجات وحدّث الأسعار والكميات؛ يمكنك إيقاف منتج مؤقتاً.',2),
  ('store','orders','الطلبات والتجهيز','استقبل الطلبات، جهّزها، ثم سلّمها للدلفري.',3),
  ('captain','availability','التوفّر','فعّل توفّرك لاستقبال طلبات الرحلات القريبة.',1),
  ('captain','trip','سير الرحلة','اقبل الرحلة، اضغط «التوجه إلى الزبون»، ثم الوصول والبدء والإنهاء. الإلغاء متاح فقط قبل التوجه.',2),
  ('delivery','pickup','الاستلام والتوصيل','استلم الطلب من المتجر، توجّه للزبون، وأثبت التسليم.',1),
  ('admin','command_center','لوحة المتابعة','تعرض البطاقات التشغيلية حسب صلاحياتك فقط، بعدّادات فورية.',1)
ON CONFLICT (app_scope, section_key) DO NOTHING;

INSERT INTO app_guide_section (app_scope, section_key, title, body, order_index, required_permission) VALUES
  ('admin','emergency','إلغاء الرحلة الطارئ','عند فتح تذكرة طوارئ لرحلة، يمكن للموظف المخوّل تنفيذ إلغاء طارئ بسبب إلزامي.',2,'taxi.rides.emergency_cancel'),
  ('admin','payroll','دورة الرواتب','جهّز الدورة، راجعها، ثم اعتمدها وأطلقها. لا يوافق مَن قدّمها.',3,'payroll.review')
ON CONFLICT (app_scope, section_key) DO NOTHING;

COMMIT;
