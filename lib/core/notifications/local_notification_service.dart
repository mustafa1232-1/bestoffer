import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/app_platform_capabilities.dart';
import '../i18n/notification_localizer.dart';
import '../../features/notifications/models/app_notification_model.dart';
import 'notification_channels.dart';

final localNotificationsProvider = Provider<LocalNotificationService>((ref) {
  final service = LocalNotificationService();
  ref.onDispose(service.dispose);
  return service;
});

class NotificationTapPayload {
  final int? requestId;
  final int? orderId;
  final int? rideId;
  final int? offerId;
  final int? bidId;
  final int? jobId;
  final int? applicationId;
  final int? postId;
  final int? reelId;
  final int? storyId;
  final int? threadId;
  final int? sessionId;
  final int? senderUserId;
  final int? captainId;
  final int? customerUserId;
  final int? notificationId;
  final String? type;
  final String? target;
  final String? targetModule;
  final String? roleScope;
  final String? appSurface;
  final String? action;
  final String? quickActionId;
  final String? targetEntity;
  final int? entityId;
  final String? scopeType;
  final String? scopeCode;
  final String? remoteDisplayName;
  final int? restrictionId;
  final String? capabilityKey;
  final String? restrictionReason;
  final String? restrictionStartsAt;
  final String? restrictionEndsAt;
  final bool requiresAction;

  const NotificationTapPayload({
    this.requestId,
    this.orderId,
    this.rideId,
    this.offerId,
    this.bidId,
    this.jobId,
    this.applicationId,
    this.postId,
    this.reelId,
    this.storyId,
    this.threadId,
    this.sessionId,
    this.senderUserId,
    this.captainId,
    this.customerUserId,
    this.notificationId,
    this.type,
    this.target,
    this.targetModule,
    this.roleScope,
    this.appSurface,
    this.action,
    this.quickActionId,
    this.targetEntity,
    this.entityId,
    this.scopeType,
    this.scopeCode,
    this.remoteDisplayName,
    this.restrictionId,
    this.capabilityKey,
    this.restrictionReason,
    this.restrictionStartsAt,
    this.restrictionEndsAt,
    this.requiresAction = false,
  });
}

enum _ActionReminderGroup {
  ownerApproval,
  deliveryPickup,
  customerConfirmation,
}

class LocalNotificationService {
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    MaslakiNotificationChannels.liveUpdates,
    'Maslaki Live Updates',
    description: 'Maslaki live order, taxi, and alert updates',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  static const AndroidNotificationChannel _actionChannel =
      AndroidNotificationChannel(
        MaslakiNotificationChannels.actionRequired,
        'Maslaki Action Required',
        description: 'Critical order actions that need immediate attention',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
  static const AndroidNotificationChannel _taxiRequestsUrgentChannel =
      AndroidNotificationChannel(
        MaslakiNotificationChannels.taxiRequestsUrgent,
        'Maslaki Taxi Requests',
        description: 'Urgent taxi ride requests and nearby trip alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
  static const AndroidNotificationChannel _taxiCounteroffersUrgentChannel =
      AndroidNotificationChannel(
        MaslakiNotificationChannels.taxiCounteroffersUrgent,
        'Maslaki Taxi Offers',
        description:
            'Urgent taxi counteroffers, assignment, and arrival alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
  static const AndroidNotificationChannel _deliveryUrgentChannel =
      AndroidNotificationChannel(
        'maslaki_delivery_urgent_v1',
        'Maslaki Delivery Urgent',
        description:
            'Urgent courier assignments, pickup, cancellation, and chat alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
  static const AndroidNotificationChannel _callChannel =
      AndroidNotificationChannel(
        'maslaki_calls_v1',
        'Maslaki Calls',
        description: 'Incoming call alerts and ringing notifications',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
  static const AndroidNotificationChannel _deliveryOrdersChannel =
      AndroidNotificationChannel(
        'maslaki_delivery_orders_v1',
        'Maslaki Delivery Orders',
        description: 'Courier order assignments, pickup readiness, and status',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );
  static const AndroidNotificationChannel _deliveryChatChannel =
      AndroidNotificationChannel(
        'maslaki_delivery_chat_v1',
        'Maslaki Delivery Chat',
        description: 'Customer and merchant messages for courier orders',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );
  static const AndroidNotificationChannel _deliveryCompetitionsChannel =
      AndroidNotificationChannel(
        'maslaki_delivery_competitions_v1',
        'Maslaki Delivery Competitions',
        description: 'Courier competition updates, progress, and rewards',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<NotificationTapPayload> _tapController =
      StreamController<NotificationTapPayload>.broadcast();

  bool _initialized = false;
  int _fallbackId = 100000;

  Stream<NotificationTapPayload> get tapStream => _tapController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    if (!appSupportsLocalNotifications) {
      _initialized = true;
      return;
    }

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: LinuxInitializationSettings(
        defaultActionName: 'Open notification',
      ),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.createNotificationChannel(_actionChannel);
    await androidPlugin?.createNotificationChannel(_taxiRequestsUrgentChannel);
    await androidPlugin?.createNotificationChannel(
      _taxiCounteroffersUrgentChannel,
    );
    await androidPlugin?.createNotificationChannel(_deliveryUrgentChannel);
    await androidPlugin?.createNotificationChannel(_callChannel);
    await androidPlugin?.createNotificationChannel(_deliveryOrdersChannel);
    await androidPlugin?.createNotificationChannel(_deliveryChatChannel);
    await androidPlugin?.createNotificationChannel(
      _deliveryCompetitionsChannel,
    );

    _initialized = true;

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchPayload != null && launchPayload.isNotEmpty) {
      final parsed = _parsePayload(launchPayload);
      if (parsed != null) {
        _tapController.add(parsed);
      }
    }
  }

  Future<void> showFromModel(AppNotificationModel notification) async {
    await initialize();
    final localized = resolveNotificationText(
      l10n: appLocalizationsForCurrentLocale(),
      notification: notification,
    );

    final orderId =
        notification.orderId ??
        int.tryParse('${notification.payload?['orderId'] ?? ''}');
    final rideId =
        notification.rideId ??
        int.tryParse('${notification.payload?['rideId'] ?? ''}');
    final offerId =
        int.tryParse('${notification.payload?['offerId'] ?? ''}') ??
        int.tryParse('${notification.payload?['offer_id'] ?? ''}');
    final bidId =
        int.tryParse('${notification.payload?['bidId'] ?? ''}') ??
        int.tryParse('${notification.payload?['bid_id'] ?? ''}');
    final target =
        notification.target ?? notification.payload?['target']?.toString();
    final id = notification.id > 0 ? notification.id : ++_fallbackId;
    final requiresAction = _parseBool(notification.payload?['requiresAction']);

    await showRaw(
      title: localized.title,
      body:
          localized.body ??
          appLocalizationsForCurrentLocale().notificationsGenericBody,
      requestId:
          int.tryParse('${notification.payload?['requestId'] ?? ''}') ??
          int.tryParse('${notification.payload?['request_id'] ?? ''}'),
      orderId: orderId,
      rideId: rideId,
      offerId: offerId,
      bidId: bidId,
      jobId: int.tryParse('${notification.payload?['jobId'] ?? ''}'),
      applicationId: int.tryParse(
        '${notification.payload?['applicationId'] ?? ''}',
      ),
      postId: int.tryParse('${notification.payload?['postId'] ?? ''}'),
      reelId:
          notification.reelId ??
          int.tryParse('${notification.payload?['reelId'] ?? ''}') ??
          int.tryParse('${notification.payload?['reel_id'] ?? ''}'),
      storyId:
          notification.storyId ??
          int.tryParse('${notification.payload?['storyId'] ?? ''}'),
      threadId:
          int.tryParse('${notification.payload?['threadId'] ?? ''}') ??
          int.tryParse('${notification.payload?['thread_id'] ?? ''}'),
      senderUserId: int.tryParse(
        '${notification.payload?['senderUserId'] ?? notification.payload?['sender_user_id'] ?? notification.payload?['actorUserId'] ?? notification.payload?['actor_user_id'] ?? ''}',
      ),
      captainId: int.tryParse(
        '${notification.payload?['captainId'] ?? notification.payload?['captain_id'] ?? ''}',
      ),
      customerUserId: int.tryParse(
        '${notification.payload?['customerUserId'] ?? notification.payload?['customer_user_id'] ?? ''}',
      ),
      sessionId:
          int.tryParse('${notification.payload?['sessionId'] ?? ''}') ??
          int.tryParse('${notification.payload?['session_id'] ?? ''}'),
      type: notification.type,
      target: target,
      targetModule:
          notification.payload?['targetModule']?.toString() ??
          notification.payload?['target_module']?.toString(),
      roleScope:
          notification.payload?['roleScope']?.toString() ??
          notification.payload?['role_scope']?.toString(),
      appSurface:
          notification.payload?['appSurface']?.toString() ??
          notification.payload?['app_surface']?.toString(),
      action:
          notification.payload?['action']?.toString() ??
          notification.payload?['target_action']?.toString(),
      targetEntity:
          notification.payload?['targetEntity']?.toString() ??
          notification.payload?['target_entity']?.toString(),
      entityId:
          int.tryParse('${notification.payload?['entityId'] ?? ''}') ??
          int.tryParse('${notification.payload?['entity_id'] ?? ''}') ??
          int.tryParse('${notification.payload?['listingId'] ?? ''}') ??
          int.tryParse('${notification.payload?['listing_id'] ?? ''}'),
      scopeType:
          notification.payload?['scopeType']?.toString() ??
          notification.payload?['scope_type']?.toString(),
      scopeCode:
          notification.payload?['scopeCode']?.toString() ??
          notification.payload?['scope_code']?.toString(),
      remoteDisplayName:
          notification.payload?['remoteDisplayName']?.toString() ??
          notification.payload?['remote_display_name']?.toString(),
      restrictionId: int.tryParse(
        '${notification.payload?['restrictionId'] ?? notification.payload?['restriction_id'] ?? ''}',
      ),
      capabilityKey:
          notification.payload?['capabilityKey']?.toString() ??
          notification.payload?['capability_key']?.toString(),
      restrictionReason: notification.payload?['reason']?.toString(),
      restrictionStartsAt:
          notification.payload?['startsAt']?.toString() ??
          notification.payload?['starts_at']?.toString(),
      restrictionEndsAt:
          notification.payload?['endsAt']?.toString() ??
          notification.payload?['ends_at']?.toString(),
      notificationId: id,
      requiresAction: requiresAction,
    );
  }

  Future<void> showRaw({
    required String title,
    required String body,
    int? requestId,
    int? orderId,
    int? rideId,
    int? offerId,
    int? bidId,
    int? jobId,
    int? applicationId,
    int? postId,
    int? reelId,
    int? storyId,
    int? threadId,
    int? sessionId,
    int? senderUserId,
    int? captainId,
    int? customerUserId,
    int? notificationId,
    String? type,
    String? target,
    String? targetModule,
    String? roleScope,
    String? appSurface,
    String? action,
    String? targetEntity,
    int? entityId,
    String? scopeType,
    String? scopeCode,
    String? remoteDisplayName,
    int? restrictionId,
    String? capabilityKey,
    String? restrictionReason,
    String? restrictionStartsAt,
    String? restrictionEndsAt,
    bool requiresAction = false,
  }) async {
    await initialize();
    if (!appSupportsLocalNotifications) return;

    final actionId = requiresAction
        ? _resolveActionReminderNotificationId(type: type, orderId: orderId)
        : null;
    final isCall = _isCallNotification(type: type, target: target);
    final isDeliveryUrgent = _isDeliveryUrgentNotification(
      type: type,
      target: target,
      roleScope: roleScope,
      action: action,
      orderId: orderId,
    );
    final isUrgentRealtime = _isUrgentRealtimeNotification(
      type: type,
      target: target,
      requiresAction: requiresAction,
    );
    final taxiUrgentChannel = _resolveTaxiUrgentChannel(
      type: type,
      target: target,
    );
    final id =
        actionId ??
        ((notificationId != null && notificationId > 0)
            ? notificationId
            : ++_fallbackId);

    final payload = jsonEncode({
      'requestId': requestId,
      'orderId': orderId,
      'rideId': rideId,
      'offerId': offerId,
      'bidId': bidId,
      'jobId': jobId,
      'applicationId': applicationId,
      'postId': postId,
      'reelId': reelId,
      'storyId': storyId,
      'threadId': threadId,
      'sessionId': sessionId,
      'senderUserId': senderUserId,
      'captainId': captainId,
      'customerUserId': customerUserId,
      'notificationId': id,
      'type': type,
      'target': target,
      'targetModule': targetModule,
      'roleScope': roleScope,
      'appSurface': appSurface,
      'action': action,
      'targetEntity': targetEntity,
      'entityId': entityId,
      'scopeType': scopeType,
      'scopeCode': scopeCode,
      'remoteDisplayName': remoteDisplayName,
      'restrictionId': restrictionId,
      'capabilityKey': capabilityKey,
      'reason': restrictionReason,
      'startsAt': restrictionStartsAt,
      'endsAt': restrictionEndsAt,
      'requiresAction': requiresAction,
    });

    final androidChannel = isCall
        ? _callChannel
        : (taxiUrgentChannel ??
              (isDeliveryUrgent
                  ? _deliveryUrgentChannel
                  : (requiresAction ? _actionChannel : _channel)));
    final useAttentionSound =
        requiresAction ||
        isCall ||
        isUrgentRealtime ||
        isDeliveryUrgent ||
        taxiUrgentChannel != null;
    final androidActions = _buildAndroidActions(
      requiresAction: requiresAction,
      isUrgentRealtime: isUrgentRealtime,
    );
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        androidChannel.id,
        androidChannel.name,
        channelDescription: androidChannel.description,
        importance: Importance.max,
        priority:
            (requiresAction ||
                isCall ||
                isUrgentRealtime ||
                isDeliveryUrgent ||
                taxiUrgentChannel != null)
            ? Priority.max
            : Priority.high,
        playSound: true,
        sound: useAttentionSound
            ? const RawResourceAndroidNotificationSound('maslaki_attention')
            : null,
        audioAttributesUsage: isCall
            ? AudioAttributesUsage.notificationRingtone
            : (requiresAction || isDeliveryUrgent || taxiUrgentChannel != null
                  ? AudioAttributesUsage.alarm
                  : AudioAttributesUsage.notification),
        enableVibration: true,
        vibrationPattern: useAttentionSound
            ? Int64List.fromList(const [0, 700, 250, 700, 250, 900])
            : null,
        ticker: isCall
            ? 'maslaki_incoming_call'
            : (taxiUrgentChannel != null
                  ? 'maslaki_taxi_urgent'
                  : (isDeliveryUrgent
                        ? 'maslaki_delivery_urgent'
                        : (requiresAction
                              ? 'maslaki_action_required'
                              : 'maslaki_update'))),
        category: isCall
            ? AndroidNotificationCategory.call
            : (requiresAction || isDeliveryUrgent || taxiUrgentChannel != null
                  ? AndroidNotificationCategory.alarm
                  : AndroidNotificationCategory.status),
        fullScreenIntent: isCall,
        autoCancel: !(requiresAction || isCall || isUrgentRealtime),
        ongoing: isCall,
        visibility: NotificationVisibility.public,
        timeoutAfter: (isCall || isUrgentRealtime) ? 30000 : null,
        actions: androidActions,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: requiresAction
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: requiresAction
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
      linux: const LinuxNotificationDetails(),
    );

    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> cancelOwnerApprovalReminder(int orderId) async {
    await _cancelActionReminder(_ActionReminderGroup.ownerApproval, orderId);
  }

  Future<void> cancelDeliveryPickupReminder(int orderId) async {
    await _cancelActionReminder(_ActionReminderGroup.deliveryPickup, orderId);
  }

  Future<void> cancelCustomerConfirmationReminder(int orderId) async {
    await _cancelActionReminder(
      _ActionReminderGroup.customerConfirmation,
      orderId,
    );
  }

  Future<void> _cancelActionReminder(
    _ActionReminderGroup group,
    int orderId,
  ) async {
    await initialize();
    if (!appSupportsLocalNotifications || orderId <= 0) return;
    await _plugin.cancel(_actionReminderNotificationId(group, orderId));
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final parsed = _parsePayload(payload, responseActionId: response.actionId);
    if (parsed != null) {
      _tapController.add(parsed);
    }
  }

  Future<void> requestPermissionsIfNeeded() async {
    await initialize();
    if (!appSupportsLocalNotifications) return;

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    final macosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    await macosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  NotificationTapPayload? _parsePayload(
    String raw, {
    String? responseActionId,
  }) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final quickAction = (responseActionId ?? '').trim();
      return NotificationTapPayload(
        requestId:
            int.tryParse('${map['requestId'] ?? ''}') ??
            int.tryParse('${map['request_id'] ?? ''}'),
        orderId: int.tryParse('${map['orderId'] ?? ''}'),
        rideId: int.tryParse('${map['rideId'] ?? ''}'),
        offerId:
            int.tryParse('${map['offerId'] ?? ''}') ??
            int.tryParse('${map['offer_id'] ?? ''}'),
        bidId:
            int.tryParse('${map['bidId'] ?? ''}') ??
            int.tryParse('${map['bid_id'] ?? ''}'),
        jobId: int.tryParse('${map['jobId'] ?? ''}'),
        applicationId: int.tryParse('${map['applicationId'] ?? ''}'),
        postId: int.tryParse('${map['postId'] ?? ''}'),
        reelId:
            int.tryParse('${map['reelId'] ?? ''}') ??
            int.tryParse('${map['reel_id'] ?? ''}'),
        storyId: int.tryParse('${map['storyId'] ?? ''}'),
        threadId: int.tryParse('${map['threadId'] ?? ''}'),
        senderUserId:
            int.tryParse('${map['senderUserId'] ?? ''}') ??
            int.tryParse('${map['sender_user_id'] ?? ''}') ??
            int.tryParse('${map['actorUserId'] ?? ''}') ??
            int.tryParse('${map['actor_user_id'] ?? ''}'),
        captainId:
            int.tryParse('${map['captainId'] ?? ''}') ??
            int.tryParse('${map['captain_id'] ?? ''}'),
        customerUserId:
            int.tryParse('${map['customerUserId'] ?? ''}') ??
            int.tryParse('${map['customer_user_id'] ?? ''}'),
        sessionId:
            int.tryParse('${map['sessionId'] ?? ''}') ??
            int.tryParse('${map['session_id'] ?? ''}'),
        notificationId: int.tryParse('${map['notificationId'] ?? ''}'),
        type: map['type']?.toString(),
        target: map['target']?.toString(),
        targetModule:
            map['targetModule']?.toString() ?? map['target_module']?.toString(),
        roleScope:
            map['roleScope']?.toString() ?? map['role_scope']?.toString(),
        appSurface:
            map['appSurface']?.toString() ?? map['app_surface']?.toString(),
        action: map['action']?.toString() ?? map['target_action']?.toString(),
        quickActionId: quickAction.isEmpty ? null : quickAction,
        targetEntity:
            map['targetEntity']?.toString() ?? map['target_entity']?.toString(),
        entityId:
            int.tryParse('${map['entityId'] ?? ''}') ??
            int.tryParse('${map['entity_id'] ?? ''}') ??
            int.tryParse('${map['listingId'] ?? ''}') ??
            int.tryParse('${map['listing_id'] ?? ''}'),
        scopeType: map['scopeType']?.toString(),
        scopeCode: map['scopeCode']?.toString(),
        remoteDisplayName: map['remoteDisplayName']?.toString(),
        restrictionId:
            int.tryParse('${map['restrictionId'] ?? ''}') ??
            int.tryParse('${map['restriction_id'] ?? ''}'),
        capabilityKey:
            map['capabilityKey']?.toString() ??
            map['capability_key']?.toString(),
        restrictionReason: map['reason']?.toString(),
        restrictionStartsAt:
            map['startsAt']?.toString() ?? map['starts_at']?.toString(),
        restrictionEndsAt:
            map['endsAt']?.toString() ?? map['ends_at']?.toString(),
        requiresAction: _parseBool(map['requiresAction']),
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _tapController.close();
  }
}

int? _resolveActionReminderNotificationId({
  required String? type,
  required int? orderId,
}) {
  if (orderId == null || orderId <= 0) return null;
  final group = _resolveActionReminderGroup(type);
  if (group == null) return null;
  return _actionReminderNotificationId(group, orderId);
}

_ActionReminderGroup? _resolveActionReminderGroup(String? type) {
  final normalized = (type ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return null;
  if (normalized == 'owner_new_order' ||
      normalized == 'owner_order_pending_reminder') {
    return _ActionReminderGroup.ownerApproval;
  }
  if (normalized == 'delivery_order_ready' ||
      normalized == 'delivery_order_ready_reminder' ||
      normalized == 'delivery_assigned_by_owner') {
    return _ActionReminderGroup.deliveryPickup;
  }
  if (normalized == 'customer_order_delivered' ||
      normalized == 'customer_order_delivered_reminder') {
    return _ActionReminderGroup.customerConfirmation;
  }
  return null;
}

int _actionReminderNotificationId(_ActionReminderGroup group, int orderId) {
  final safeOrderId = orderId.clamp(1, 999999);
  switch (group) {
    case _ActionReminderGroup.ownerApproval:
      return 310000000 + safeOrderId;
    case _ActionReminderGroup.deliveryPickup:
      return 320000000 + safeOrderId;
    case _ActionReminderGroup.customerConfirmation:
      return 330000000 + safeOrderId;
  }
}

List<AndroidNotificationAction>? _buildAndroidActions({
  required bool requiresAction,
  required bool isUrgentRealtime,
}) {
  if (!requiresAction && !isUrgentRealtime) return null;
  final l10n = appLocalizationsForCurrentLocale();
  final actions = <AndroidNotificationAction>[
    AndroidNotificationAction(
      'open',
      l10n.commonOpen,
      showsUserInterface: true,
      cancelNotification: true,
    ),
  ];
  if (isUrgentRealtime) {
    actions.addAll([
      AndroidNotificationAction(
        'accept',
        l10n.commonAccept,
        showsUserInterface: true,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        'reject',
        l10n.commonReject,
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ]);
  }
  return actions;
}

bool _isDeliveryUrgentNotification({
  required String? type,
  required String? target,
  required String? roleScope,
  required String? action,
  required int? orderId,
}) {
  if (orderId == null || orderId <= 0) return false;
  final normalizedType = (type ?? '').trim().toLowerCase();
  final normalizedTarget = (target ?? '').trim().toLowerCase();
  final normalizedRoleScope = (roleScope ?? '').trim().toLowerCase();
  final normalizedAction = (action ?? '').trim().toLowerCase();
  final courierScoped =
      normalizedRoleScope == 'courier' ||
      normalizedRoleScope == 'delivery' ||
      normalizedTarget.startsWith('courier') ||
      normalizedTarget.startsWith('delivery') ||
      normalizedTarget == 'order_tracking';
  if (!courierScoped) return false;

  return normalizedType == 'delivery_order_available' ||
      normalizedType == 'delivery_order_offer' ||
      normalizedType == 'courier_order_offer' ||
      normalizedType == 'delivery_order_assigned' ||
      normalizedType == 'delivery_order_ready_for_pickup' ||
      normalizedType == 'delivery_order_ready' ||
      normalizedType == 'delivery_order_cancelled' ||
      normalizedType == 'courier_cancel_request_approved' ||
      normalizedType == 'courier_cancel_request_rejected' ||
      (normalizedType == 'order_chat_message' &&
          normalizedTarget != 'social_chat') ||
      normalizedAction.contains('ready_for_pickup') ||
      normalizedAction.contains('open_current_order') ||
      normalizedAction.contains('open_cancelled_order');
}

bool _parseBool(dynamic value) {
  if (value == true) return true;
  final normalized = '$value'.trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

bool _isCallNotification({required String? type, required String? target}) {
  final normalizedType = (type ?? '').trim().toLowerCase();
  final normalizedTarget = (target ?? '').trim().toLowerCase();
  if (normalizedTarget == 'social_call') {
    return true;
  }
  return normalizedType.startsWith('social.call.');
}

AndroidNotificationChannel? _resolveTaxiUrgentChannel({
  required String? type,
  required String? target,
}) {
  final normalizedType = (type ?? '').trim().toLowerCase();
  final normalizedTarget = (target ?? '').trim().toLowerCase();
  if (normalizedType == 'taxi.new_ride' ||
      normalizedType == 'taxi.request.new' ||
      normalizedType == 'taxi.ride.requested' ||
      normalizedTarget == 'taxi_new_request' ||
      normalizedTarget == 'taxi_ride_requested') {
    return LocalNotificationService._taxiRequestsUrgentChannel;
  }
  if (normalizedType == 'taxi.counteroffer.received' ||
      normalizedType == 'taxi.counter_offer.received' ||
      normalizedType == 'taxi.offer.received' ||
      normalizedType == 'taxi.offer.accepted' ||
      normalizedType == 'taxi.ride.assigned' ||
      normalizedType == 'taxi.captain.arrived' ||
      normalizedTarget == 'taxi_counter_offer_received' ||
      normalizedTarget == 'taxi_offer_received' ||
      normalizedTarget == 'taxi_offer_accepted' ||
      normalizedTarget == 'taxi_ride_assigned' ||
      normalizedTarget == 'taxi_captain_arrived') {
    return LocalNotificationService._taxiCounteroffersUrgentChannel;
  }
  return null;
}

bool _isUrgentRealtimeNotification({
  required String? type,
  required String? target,
  required bool requiresAction,
}) {
  if (!requiresAction) return false;
  final normalizedType = (type ?? '').trim().toLowerCase();
  final normalizedTarget = (target ?? '').trim().toLowerCase();
  if (normalizedTarget == 'courier_orders_new' ||
      normalizedTarget == 'delivery_order_offer' ||
      normalizedTarget == 'courier_order_offer' ||
      normalizedTarget == 'taxi_new_request' ||
      normalizedTarget == 'taxi_ride_requested' ||
      normalizedTarget == 'taxi_offer_received' ||
      normalizedTarget == 'taxi_counter_offer_received' ||
      normalizedTarget == 'taxi_offer_accepted' ||
      normalizedTarget == 'taxi_offer_rejected' ||
      normalizedTarget == 'taxi_ride_assigned' ||
      normalizedTarget == 'taxi_ride_unavailable' ||
      normalizedTarget == 'taxi_captain_arrived' ||
      normalizedTarget == 'taxi_ride_started' ||
      normalizedTarget == 'taxi_ride_completed' ||
      normalizedTarget == 'taxi_ride_canceled' ||
      normalizedTarget == 'taxi_chat_message') {
    return true;
  }
  return normalizedType == 'delivery_order_available' ||
      normalizedType == 'delivery_order_offer' ||
      normalizedType == 'courier_order_offer' ||
      normalizedType == 'taxi.request.new' ||
      normalizedType == 'taxi.ride.requested' ||
      normalizedType == 'taxi.offer.received' ||
      normalizedType == 'taxi.counter_offer.received' ||
      normalizedType == 'taxi.offer.accepted' ||
      normalizedType == 'taxi.offer.rejected' ||
      normalizedType == 'taxi.ride.assigned' ||
      normalizedType == 'taxi.ride.unavailable' ||
      normalizedType == 'taxi.captain.arrived' ||
      normalizedType == 'taxi.ride.started' ||
      normalizedType == 'taxi.ride.completed' ||
      normalizedType == 'taxi.ride.canceled' ||
      normalizedType == 'taxi.chat.message';
}
