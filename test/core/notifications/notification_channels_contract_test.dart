import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/notifications/notification_channels.dart';

void main() {
  test('taxi urgent notification channel ids match backend contract', () {
    expect(
      MaslakiNotificationChannels.taxiRequestsUrgent,
      'maslaki_taxi_requests_urgent_v2',
    );
    expect(
      MaslakiNotificationChannels.taxiCounteroffersUrgent,
      'maslaki_taxi_counteroffers_urgent_v2',
    );
    expect(
      MaslakiNotificationChannels.taxiRequestsUrgent,
      isNot(MaslakiNotificationChannels.liveUpdates),
    );
    expect(
      MaslakiNotificationChannels.taxiCounteroffersUrgent,
      isNot(MaslakiNotificationChannels.liveUpdates),
    );
  });
}
