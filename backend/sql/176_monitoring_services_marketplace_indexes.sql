BEGIN;

CREATE INDEX IF NOT EXISTS idx_service_requests_monitoring_status_updated
  ON service_requests (status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_service_requests_monitoring_created
  ON service_requests (created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_service_requests_monitoring_customer
  ON service_requests (customer_user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_service_requests_monitoring_provider
  ON service_requests (provider_id, status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_service_reports_monitoring_request
  ON service_reports (target_type, target_id, status, created_at DESC)
  WHERE target_type = 'request';

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_monitoring_status_updated
  ON real_estate_listing (status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_monitoring_created
  ON real_estate_listing (created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_monitoring_owner
  ON real_estate_listing (owner_user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_real_estate_listing_monitoring_region
  ON real_estate_listing (city, block, status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_car_listing_monitoring_status_updated
  ON car_listing (status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_car_listing_monitoring_created
  ON car_listing (created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_car_listing_monitoring_owner
  ON car_listing (owner_user_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_car_listing_monitoring_city_status
  ON car_listing (city, status, updated_at DESC, id DESC);

COMMIT;
