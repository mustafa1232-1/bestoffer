class RoleRouteRegistry {
  const RoleRouteRegistry._();

  // Admin
  static const adminDashboard = 'admin_dashboard';
  static const adminRequestsInbox = 'admin_requests_inbox';
  static const adminApprovalRequests = 'admin_approval_requests';
  static const adminPaymentRequests = 'admin_payment_requests';
  static const adminMerchants = 'admin_merchants';
  static const adminCourier = 'admin_courier';
  static const adminTaxiCaptains = 'admin_taxi_captains';
  static const adminReceivables = 'admin_receivables';
  static const adminCompetitions = 'admin_competitions';
  static const adminNotifications = 'admin_notifications';
  static const adminReports = 'admin_reports';
  static const adminSupport = 'admin_support';
  static const adminSettings = 'admin_settings';

  // Merchant
  static const merchantDashboard = 'merchant_dashboard';
  static const merchantOrdersCurrent = 'merchant_orders_current';
  static const merchantOrdersCompleted = 'merchant_orders_completed';
  static const merchantOrdersCancelled = 'merchant_orders_cancelled';
  static const merchantOrderDetails = 'merchant_order_details';
  static const merchantReceivables = 'merchant_receivables';
  static const merchantPaymentRequests = 'merchant_payment_requests';
  static const merchantCouriers = 'merchant_couriers';
  static const merchantReports = 'merchant_reports';
  static const merchantNotifications = 'merchant_notifications';
  static const merchantSettings = 'merchant_settings';

  // Courier
  static const courierDashboard = 'courier_dashboard';
  static const courierOrdersNew = 'courier_orders_new';
  static const courierOrdersCurrent = 'courier_orders_current';
  static const courierOrdersCompleted = 'courier_orders_completed';
  static const courierOrdersCancelled = 'courier_orders_cancelled';
  static const courierOrderDetails = 'courier_order_details';
  static const courierEarnings = 'courier_earnings';
  static const courierReports = 'courier_reports';
  static const courierCompetitions = 'courier_competitions';
  static const courierNotifications = 'courier_notifications';
  static const courierSettings = 'courier_settings';

  // Taxi
  static const taxiDashboard = 'taxi_dashboard';
  static const taxiTripsNew = 'taxi_trips_new';
  static const taxiTripsCurrent = 'taxi_trips_current';
  static const taxiTripsCompleted = 'taxi_trips_completed';
  static const taxiTripsCancelled = 'taxi_trips_cancelled';
  static const taxiTripDetails = 'taxi_trip_details';
  static const taxiEarnings = 'taxi_earnings';
  static const taxiReports = 'taxi_reports';
  static const taxiNotifications = 'taxi_notifications';
  static const taxiSettings = 'taxi_settings';

  // Customer
  static const customerOrdersCurrent = 'customer_orders_current';
  static const customerOrdersCompleted = 'customer_orders_completed';
  static const customerOrdersCancelled = 'customer_orders_cancelled';
  static const customerOrderDetails = 'customer_order_details';
  static const customerNotifications = 'customer_notifications';
}
