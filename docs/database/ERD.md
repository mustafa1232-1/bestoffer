# ERD

This is the initial high-level ERD sketch for the closure program.

```mermaid
erDiagram
  users ||--o{ merchants : owns
  merchants ||--o{ products : publishes
  merchants ||--o{ categories : manages
  users ||--o{ orders : places
  orders ||--o{ order_item : contains
  orders ||--o{ notifications : emits
  users ||--o{ taxi_ride : requests
  taxi_ride ||--o{ taxi_ride_bid : receives
  users ||--o{ realtime_outbox : receives
  users ||--o{ social_posts : creates
  users ||--o{ chat_threads : participates
```

## Notes

- This sketch is intentionally high level.
- The detailed relationship map will be expanded as Phase 1 inventory grows.

