# Grouped delivery — Flutter surface map (delivery closure §2)

The mobile client is a **single Flutter package `maslaki`** with per-flavor entry
bootstraps (not separate apps). Grouped-delivery client work must extend these
active surfaces — not create parallel implementations.

## Flavor entry points (ACTIVE)
| Surface | Bootstrap | Home |
|---|---|---|
| User | `lib/app_user_bootstrap.dart` | user shell |
| Store | `lib/app_store_bootstrap.dart` | owner/store workspace |
| Delivery | `lib/app_delivery_bootstrap.dart` | `DeliveryDashboardScreen` |
| Taxi captain | `lib/app_taxi_captain_bootstrap.dart` | — |
| Company | `lib/app_company_bootstrap.dart` | — |

Delivery entry: `app_delivery_bootstrap.dart` → `DeliveryDashboardScreen`
(`lib/features/delivery/ui/delivery_dashboard_screen.dart`).

## Delivery feature classification
| Path | Role | Status |
|---|---|---|
| `features/delivery/data/delivery_api.dart` | Dio API client (`/api/delivery/*`, `/api/courier/*`) | ACTIVE |
| `features/delivery/state/delivery_controller.dart` | Riverpod `StateNotifier` (current orders, presence, analytics) | ACTIVE |
| `features/delivery/ui/delivery_dashboard_screen.dart` | Delivery home | ACTIVE |
| `features/delivery/ui/delivery_order_detail_screen.dart` | Single-order detail | ACTIVE (legacy single-order) |
| `features/delivery/ui/courier_pages.dart` | Courier list/pages | ACTIVE |
| `features/delivery/ui/delivery_offer_overlay_screen.dart` | Incoming-offer overlay | ACTIVE |
| `features/delivery/ui/delivery_restricted_screen.dart` | Not-approved gate | ACTIVE |
| **`features/delivery/models/grouped_delivery_job.dart`** | Grouped job + pickup-stop models (**new**) | ACTIVE |
| **`features/delivery/state/grouped_delivery_controller.dart`** | Grouped-job controller (**new**) | ACTIVE |

## Grouped-job API surface consumed (backend `deliveryRouter`, prefix `/api/delivery`)
`GET delivery-jobs/current` · `GET delivery-jobs` · `GET delivery-jobs/history` ·
`GET delivery-jobs/:id` · `POST …/acknowledge` · `POST …/heading-to-pickups` ·
`POST …/stops/:stopId/arrived` · `POST …/stops/:stopId/collected` ·
`POST …/heading-to-customer` · `POST …/delivered`.

## Store / User assignment consumption
- Store order screens: `features/owner/**` + `features/orders/ui/widgets/order_delivery_assignment_card.dart` (COMPATIBILITY today — decides assignment from child-order fields; must move to the normalized grouped assignment contract).
- User tracking: `features/tracking/**`, `features/orders/**`.

## Done in this pass
- Grouped-delivery **data + logic layer** for the Delivery surface (models,
  parser, API client methods, controller with optimistic updates, stale-version
  refresh, duplicate-tap guard) + unit tests (10, passing).

## Pending (client UI + other surfaces)
- Delivery grouped-job **screens/widgets** wired into `DeliveryDashboardScreen`.
- Store normalized-assignment screen migration (remove child-flag `ASSIGNED` UI).
- User grouped-tracking screen.
- Android urgent notification channels (Store/Delivery) + background handler.
- Presence heartbeat lifecycle review; session-persistence audit.
