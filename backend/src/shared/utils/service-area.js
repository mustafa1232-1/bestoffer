import { env } from "../../config/env.js";

const DEFAULT_BISMAYAH_CENTER = {
  latitude: 33.19302,
  longitude: 44.62071,
};

const DEFAULT_BISMAYAH_POLYGON = [
  { latitude: 33.1975, longitude: 44.586 },
  { latitude: 33.2075, longitude: 44.595 },
  { latitude: 33.2135, longitude: 44.616 },
  { latitude: 33.214, longitude: 44.634 },
  { latitude: 33.207, longitude: 44.644 },
  { latitude: 33.197, longitude: 44.652 },
  { latitude: 33.187, longitude: 44.659 },
  { latitude: 33.178, longitude: 44.652 },
  { latitude: 33.174, longitude: 44.632 },
  { latitude: 33.1745, longitude: 44.613 },
  { latitude: 33.1795, longitude: 44.595 },
  { latitude: 33.188, longitude: 44.5865 },
];

function toFiniteNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function parsePoint(value) {
  if (!value || typeof value !== "object") return null;
  const latitude = toFiniteNumber(value.latitude ?? value.lat);
  const longitude = toFiniteNumber(value.longitude ?? value.lng ?? value.lon);
  if (latitude == null || longitude == null) return null;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return null;
  }
  return { latitude, longitude };
}

function parsePolygon(raw) {
  const text = String(raw || "").trim();
  if (!text) return [];

  try {
    const decoded = JSON.parse(text);
    if (!Array.isArray(decoded)) return [];
    return decoded
      .map((item) =>
        Array.isArray(item)
          ? parsePoint({ latitude: item[0], longitude: item[1] })
          : parsePoint(item)
      )
      .filter(Boolean);
  } catch {
    return text
      .split(";")
      .map((pair) => {
        const [lat, lng] = pair.split(",").map((part) => part.trim());
        return parsePoint({ latitude: lat, longitude: lng });
      })
      .filter(Boolean);
  }
}

function distanceMeters(a, b) {
  const radius = 6371000;
  const aLat = (a.latitude * Math.PI) / 180;
  const bLat = (b.latitude * Math.PI) / 180;
  const dLat = ((b.latitude - a.latitude) * Math.PI) / 180;
  const dLng = ((b.longitude - a.longitude) * Math.PI) / 180;
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const h =
    sinLat * sinLat + Math.cos(aLat) * Math.cos(bLat) * sinLng * sinLng;
  return 2 * radius * Math.asin(Math.min(1, Math.sqrt(h)));
}

function pointInPolygon(point, polygon) {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i, i += 1) {
    const xi = polygon[i].longitude;
    const yi = polygon[i].latitude;
    const xj = polygon[j].longitude;
    const yj = polygon[j].latitude;
    const intersects =
      yi > point.latitude !== yj > point.latitude &&
      point.longitude <
        ((xj - xi) * (point.latitude - yi)) / (yj - yi || Number.EPSILON) + xi;
    if (intersects) inside = !inside;
  }
  return inside;
}

export function getServiceAreaConfig() {
  const configuredPolygon = parsePolygon(env.serviceAreaPolygon);
  const polygon =
    configuredPolygon.length >= 3 ? configuredPolygon : DEFAULT_BISMAYAH_POLYGON;
  const center = {
    latitude: toFiniteNumber(env.serviceAreaCenterLatitude) ?? DEFAULT_BISMAYAH_CENTER.latitude,
    longitude: toFiniteNumber(env.serviceAreaCenterLongitude) ?? DEFAULT_BISMAYAH_CENTER.longitude,
  };
  return {
    enabled: env.serviceAreaEnabled !== false,
    registrationEnforced: env.serviceAreaRegistrationEnforced === true,
    name: env.serviceAreaName || "Bismayah",
    center,
    radiusM: Math.max(1000, Number(env.serviceAreaRadiusM || 18500)),
    polygon,
  };
}

export function isPointInsideServiceArea(input) {
  const point = parsePoint(input);
  const config = getServiceAreaConfig();
  if (!config.enabled) return { ok: true, code: "SERVICE_AREA_DISABLED", config };
  if (!point) return { ok: false, code: "LOCATION_REQUIRED", config };

  const inside =
    config.polygon.length >= 3
      ? pointInPolygon(point, config.polygon)
      : distanceMeters(point, config.center) <= config.radiusM;

  return {
    ok: inside,
    code: inside ? "INSIDE_SERVICE_AREA" : "OUTSIDE_SERVICE_AREA",
    point,
    config,
  };
}

export function assertPointInsideServiceArea(input) {
  const result = isPointInsideServiceArea(input);
  if (result.ok) return result;

  const err = new Error("SERVICE_AREA_COMING_SOON");
  err.status = 403;
  err.details = {
    code: result.code,
    serviceAreaName: result.config.name,
    message: "مسلكي سيكون في منطقتكم قريباً.",
  };
  throw err;
}
