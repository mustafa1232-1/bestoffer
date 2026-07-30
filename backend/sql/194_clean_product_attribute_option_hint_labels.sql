-- Product spec chips render as "<label>: <value>". A few clothing/furniture
-- fields historically stored the option hint *inside* the label itself, e.g.
-- gender = "الجنس: رجالي / نسائي / أطفال / عام". Combined with the value that
-- produced the ugly "الجنس: رجالي / نسائي / أطفال / عام: رجالي" on the product
-- card. Strip the hint suffix (everything from the first ':') from existing
-- rows so the card shows a clean "<field>: <value>" (e.g. "الجنس: رجالي").
--
-- The clean label is derived from the stored text via split_part, so no Arabic
-- literals are needed here (no encoding concerns). Idempotent: once cleaned the
-- label no longer contains ':' and the WHERE clause stops matching it.
UPDATE product_attribute
SET label_ar = btrim(split_part(label_ar, ':', 1)),
    updated_at = NOW()
WHERE attribute_code IN ('gender', 'fit', 'assembly_required')
  AND label_ar LIKE '%:%'
  AND label_ar LIKE '%/%';
