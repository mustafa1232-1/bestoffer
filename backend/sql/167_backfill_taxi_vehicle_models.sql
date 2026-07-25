WITH seed(make_name, models) AS (
  VALUES
    ('Toyota', ARRAY['Corolla','Camry','Avalon','Yaris','Prius','RAV4','Highlander','Land Cruiser','Prado','Hilux','Fortuner','Coaster','Hiace','Crown']::text[]),
    ('Hyundai', ARRAY['Elantra','Sonata','Accent','Tucson','Santa Fe','Creta','i10','i20','Azera','Venue','Kona','Staria','H-1']::text[]),
    ('Kia', ARRAY['Rio','Cerato','Optima','K5','Sportage','Sorento','Picanto','Carnival','Seltos','Pegas','Cadenza']::text[]),
    ('Nissan', ARRAY['Sunny','Sentra','Altima','Maxima','Patrol','X-Trail','Pathfinder','Navara','Urvan','Kicks']::text[]),
    ('Chevrolet', ARRAY['Aveo','Cruze','Malibu','Impala','Captiva','Tahoe','Suburban','Trailblazer','Spark','Silverado']::text[]),
    ('GMC', ARRAY['Yukon','Sierra','Terrain','Acadia']::text[]),
    ('Ford', ARRAY['Focus','Fusion','Taurus','Escape','Explorer','Expedition','F-150','Ranger','Transit']::text[]),
    ('Honda', ARRAY['Civic','Accord','CR-V','HR-V','City','Pilot']::text[]),
    ('Mitsubishi', ARRAY['Lancer','Pajero','Outlander','ASX','L200','Attrage']::text[]),
    ('Mazda', ARRAY['2','3','6','CX-3','CX-5','CX-9','BT-50']::text[]),
    ('Suzuki', ARRAY['Swift','Dzire','Ciaz','Vitara','Ertiga','Baleno','Alto']::text[]),
    ('Renault', ARRAY['Logan','Duster','Symbol','Koleos','Megane']::text[]),
    ('Peugeot', ARRAY['301','308','508','2008','3008','Partner']::text[]),
    ('Volkswagen', ARRAY['Golf','Jetta','Passat','Tiguan','Touareg','Polo','Transporter']::text[]),
    ('Mercedes-Benz', ARRAY['C-Class','E-Class','S-Class','GLE','GLS','Vito','Sprinter']::text[]),
    ('BMW', ARRAY['3 Series','5 Series','7 Series','X3','X5','X6']::text[]),
    ('Audi', ARRAY['A3','A4','A6','Q3','Q5','Q7']::text[]),
    ('Lexus', ARRAY['ES','GS','LS','RX','LX','GX','IS','NX']::text[]),
    ('Land Rover', ARRAY['Range Rover','Range Rover Sport','Discovery','Defender']::text[]),
    ('Jeep', ARRAY['Cherokee','Grand Cherokee','Compass','Wrangler']::text[]),
    ('Dodge', ARRAY['Charger','Challenger','Durango','Journey']::text[]),
    ('Chrysler', ARRAY['300','Pacifica']::text[]),
    ('Haval', ARRAY['H6','Jolion','H9','Dargo']::text[]),
    ('Great Wall', ARRAY['Wingle','Poer']::text[]),
    ('MG', ARRAY['5','6','ZS','HS','RX5','GT']::text[]),
    ('Chery', ARRAY['Arrizo 5','Arrizo 6','Tiggo 2','Tiggo 4','Tiggo 7','Tiggo 8']::text[]),
    ('Geely', ARRAY['Emgrand','Coolray','Tugella','Azkarra','Geometry C']::text[]),
    ('Changan', ARRAY['Eado','Alsvin','CS35','CS55','CS75','UNI-T','UNI-K']::text[]),
    ('Jetour', ARRAY['X70','X90','Dashing','T2']::text[]),
    ('BYD', ARRAY['F3','Qin','Song','Tang','Han','Dolphin','Atto 3']::text[]),
    ('BAIC', ARRAY['D20','X35','X55','BJ40']::text[]),
    ('JAC', ARRAY['J7','S3','S4','S5','T6','T8']::text[]),
    ('Bestune', ARRAY['B30','B70','T77','T99']::text[]),
    ('Soueast', ARRAY['DX3','DX5','DX7','S09']::text[]),
    ('Isuzu', ARRAY['D-Max','MU-X','NPR']::text[]),
    ('Daihatsu', ARRAY['Sirion','Terios']::text[]),
    ('Subaru', ARRAY['Impreza','Legacy','Forester','XV']::text[]),
    ('Volvo', ARRAY['S60','S90','XC60','XC90']::text[]),
    ('Fiat', ARRAY['Tipo','Doblo','Ducato','500']::text[]),
    ('Skoda', ARRAY['Octavia','Superb','Kodiaq','Karoq','Fabia']::text[]),
    ('Opel', ARRAY['Astra','Insignia','Corsa','Mokka']::text[]),
    ('Tesla', ARRAY['Model 3','Model Y','Model S','Model X']::text[])
),
all_makes AS (
  SELECT id, normalized_name
  FROM taxi_vehicle_make
  WHERE normalized_name IN (
    SELECT LOWER(REGEXP_REPLACE(TRIM(make_name), '\s+', ' ', 'g'))
    FROM seed
  )
)
INSERT INTO taxi_vehicle_model (make_id, name, normalized_name, is_active)
SELECT
  all_makes.id,
  model_name,
  LOWER(REGEXP_REPLACE(TRIM(model_name), '\s+', ' ', 'g')),
  TRUE
FROM seed
JOIN all_makes
  ON all_makes.normalized_name = LOWER(REGEXP_REPLACE(TRIM(seed.make_name), '\s+', ' ', 'g'))
CROSS JOIN LATERAL UNNEST(seed.models) AS model_name
ON CONFLICT (make_id, normalized_name) DO UPDATE
  SET name = EXCLUDED.name,
      is_active = TRUE,
      updated_at = NOW();
