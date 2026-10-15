# Service Booking Rebuild Checklist

- [x] Keep every service attached to a main category and visible in its category.
- [x] Support fixed, hourly, daily/visit, unit/meter, inspection, and custom pricing labels.
- [x] Support multiple offering media files, including images and videos.
- [x] Show service details, media, included work, exclusions, duration, and pricing basis.
- [x] Use one short booking form for date, time, address, map coordinates, problem details, attachments, optional medical details, and contact preference.
- [x] Send new Maslaki service requests directly to the operations account without professional-routing fields.
- [x] Allow operations to accept the listed price or send a revised quote.
- [x] Produce a clear invoice after confirmation and allow an operations discount.
- [x] Allow a customer coupon before payment.
- [x] Allow the customer to mark the invoice as paid and operations to confirm receipt.
- [x] Support en-route, work-completed, payment-confirmed, completed, and archived stages.
- [x] Allow customer cancellation after 15 minutes and operations cancellation at any time.
- [x] Add an in-app conversation to every normal service request.
- [x] Run backend unit, contract, flow, and services checks (`628/628` backend tests, permissions `45/45`, flow check passed).
- [x] Run Flutter analyze and tests (no analyzer issues, `796/796` tests passed).
- [x] Run customer and services-operations UI smoke coverage, then launch the user web entry successfully (`HTTP 200`, Flutter started without runtime errors).

## Coupon Campaigns

- [x] Create the one-use `MASLAK3` welcome coupon for new customers only.
- [x] Add a one-time blurred welcome card after first registration.
- [x] Let administrators target a coupon popup to one customer or all customers.
- [x] Let administrators target shopping, taxi, services, or all surfaces.
- [x] Record popup delivery and acknowledgement so it is not repeatedly intrusive.
