Maslaki does not track users across apps or websites. Collected data is used only for account, taxi, shopping, delivery, community, messaging, safety, support, and app functionality.

## Background Processing

BGTaskSchedulerPermittedIdentifiers is declared in Info.plist as required by Apple when UIBackgroundModes includes 'processing'. The registered identifiers are:
- com.maslaki.user.refresh
- com.maslaki.user.processing
- com.maslaki.user.sync

TODO: These are reserved for future app sync, push notification handling, and order status updates. Register actual BGTaskScheduler tasks in AppDelegate when background sync is implemented.
