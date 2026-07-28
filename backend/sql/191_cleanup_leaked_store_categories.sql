-- Clean up store categories that leaked between stores of the same activity.
--
-- Previously, when a merchant created a private product category the app
-- defaulted to "publish globally", which turned the category into a shared
-- template and applied it to EVERY store of the same activity (merchant_category
-- rows with source='template'). That behaviour is removed from the merchant flow
-- in code; this migration removes the already-leaked rows.
--
-- Safety: we delete only leaked categories that (a) originated from a
-- merchant-published template (code custom_*) AND (b) hold no products, so no
-- store loses a category it actually uses. Then we drop the merchant-published
-- template definitions themselves; built-in / admin-managed templates are kept.

DELETE FROM merchant_category mc
 WHERE mc.source = 'template'
   AND NOT EXISTS (SELECT 1 FROM product p WHERE p.category_id = mc.id)
   AND EXISTS (
         SELECT 1
           FROM store_activity_internal_category_template t
          WHERE t.code LIKE 'custom\_%'
            AND t.name_ar = mc.name
       );

DELETE FROM store_activity_internal_category_template
 WHERE code LIKE 'custom\_%';
