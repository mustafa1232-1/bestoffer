import '../../../core/utils/store_printer_settings.dart';
import '../../orders/models/order_model.dart';
import 'adapters/generic_text_fallback_adapter.dart';
import 'adapters/internal_pos_printer_adapter.dart';
import 'adapters/preview_printer_adapter.dart';
import 'models/receipt_print_data.dart';
import 'printer_adapter.dart';
import 'receipt_builder.dart';

class ReceiptPrinterService {
  ReceiptPrinterService._();

  static final ReceiptPrinterService instance = ReceiptPrinterService._();

  final ReceiptBuilder _builder = const ReceiptBuilder();
  final List<ReceiptPrintJobResult> _history = <ReceiptPrintJobResult>[];

  List<ReceiptPrintJobResult> get history =>
      List<ReceiptPrintJobResult>.from(_history);

  Future<ReceiptTextDocument> buildOrderDocument({
    required OrderModel order,
    required String assignmentMode,
    required bool useArabicLabels,
    required String appTitle,
    String? branchName,
    String? cashierName,
  }) async {
    final data = ReceiptPrintData.fromOrder(
      order: order,
      assignmentMode: assignmentMode,
      appName: appTitle,
      branchName: branchName,
      cashierName: cashierName,
      currency: 'IQD',
    );

    final options = ReceiptBuildOptions(
      useArabicLabels: useArabicLabels,
      forceEnglishLabels: false,
      asciiSafe: false,
      lineWidth: 32,
    );

    return _builder.build(data: data, options: options);
  }

  Future<ReceiptTextDocument> buildSampleDocument({
    required bool useArabicLabels,
    required String appTitle,
  }) async {
    final now = DateTime.now();
    final sample = ReceiptPrintData(
      orderReference: 'MSK-000001',
      orderId: 1,
      orderCreatedAt: now.subtract(const Duration(minutes: 25)),
      printedAt: now,
      confirmedAt: now.subtract(const Duration(minutes: 20)),
      preparingAt: now.subtract(const Duration(minutes: 18)),
      outForDeliveryAt: now.subtract(const Duration(minutes: 7)),
      deliveredAt: null,
      orderStatus: 'ready_for_delivery',
      paymentMethod: 'Cash',
      deliveryType: 'App courier',
      orderSource: 'App',
      totalItemsCount: 2,
      totalQuantity: 3,
      couponCode: 'WELCOME5',
      savedAmount: 500,
      etaText: '20 min',
      internalMerchantNote: 'Call customer before arrival',
      customerGeneralNote: 'Please add extra sauce',
      store: ReceiptStore(
        appName: appTitle,
        title: 'Store Receipt',
        storeName: 'Maslaki Kitchen',
        storePhone: '07700000000',
        storeAddress: 'Basmaya - Block A7',
        branchName: 'Main Branch',
        cashierName: 'POS-1',
      ),
      customer: const ReceiptCustomer(
        name: 'Test Customer',
        phone: '07711111111',
        city: 'Basmaya',
        block: 'A7',
        building: '711',
        apartment: '507',
        note: 'Ring the bell',
      ),
      items: const [
        ReceiptItem(
          name: 'Classic Burger',
          quantity: 2,
          unitPrice: 5500,
          grossLineTotal: 11000,
          lineDiscount: 500,
          finalLineTotal: 10500,
          note: 'No onion',
        ),
        ReceiptItem(
          name: 'French Fries',
          quantity: 1,
          unitPrice: 2500,
          grossLineTotal: 2500,
          lineDiscount: 0,
          finalLineTotal: 2500,
          note: null,
        ),
      ],
      totals: const ReceiptTotals(
        grossSubtotal: 13500,
        productDiscounts: 500,
        couponDiscounts: 0,
        discounts: 500,
        afterDiscount: 13000,
        deliveryFee: 1500,
        serviceFee: 300,
        taxes: 0,
        total: 14800,
        currency: 'IQD',
      ),
      driverName: 'App Courier',
      driverPhone: '07722222222',
    );

    return _builder.build(
      data: sample,
      options: ReceiptBuildOptions(
        useArabicLabels: useArabicLabels,
        forceEnglishLabels: false,
        asciiSafe: false,
        lineWidth: 32,
      ),
    );
  }

  Future<ReceiptPrintJobResult> printOrder({
    required OrderModel order,
    required String assignmentMode,
    required bool useArabicLabels,
    required String appTitle,
    String? branchName,
    String? cashierName,
  }) async {
    final document = await buildOrderDocument(
      order: order,
      assignmentMode: assignmentMode,
      useArabicLabels: useArabicLabels,
      appTitle: appTitle,
      branchName: branchName,
      cashierName: cashierName,
    );

    return _dispatch(document: document, isTest: false);
  }

  Future<ReceiptPrintJobResult> printSampleInvoice({
    required bool useArabicLabels,
    required String appTitle,
  }) async {
    final document = await buildSampleDocument(
      useArabicLabels: useArabicLabels,
      appTitle: appTitle,
    );
    return _dispatch(document: document, isTest: false);
  }

  Future<ReceiptPrintJobResult> printTest({
    required bool useArabicLabels,
    required String appTitle,
  }) async {
    final now = DateTime.now();
    final lines = <String>[
      appTitle,
      useArabicLabels ? 'اختبار الطابعة الحرارية' : 'Thermal printer test',
      '${now.toLocal()}',
      '--------------------------------',
      useArabicLabels
          ? 'تم الاتصال بقناة الطباعة بنجاح.'
          : 'Print channel connected successfully.',
      '--------------------------------',
      'MASLAKI POS 58mm',
    ];

    final document = ReceiptTextDocument(lines: lines, lineWidth: 32);
    return _dispatch(document: document, isTest: true);
  }

  Future<ReceiptPrintJobResult> buildPreviewOnly({
    required ReceiptTextDocument document,
  }) async {
    final config = await StorePrinterSettings.readConfig();
    final preview = PreviewPrinterAdapter();
    final result = await preview.print(
      document: document,
      context: ReceiptAdapterContext(config: config),
      isTest: false,
    );
    return _remember(
      ReceiptPrintJobResult.fromAdapterResult(
        result: result,
        renderedText: document.text,
      ),
    );
  }

  Future<ReceiptPrintJobResult> _dispatch({
    required ReceiptTextDocument document,
    required bool isTest,
  }) async {
    final config = await StorePrinterSettings.readConfig();
    final context = ReceiptAdapterContext(config: config);

    final adapters = _buildAdapterPipeline(config);
    final allLogs = <ReceiptPrinterLog>[];

    for (final adapter in adapters) {
      final result = await adapter.print(
        document: document,
        context: context,
        isTest: isTest,
      );
      allLogs.addAll(result.logs);
      if (result.success) {
        return _remember(
          ReceiptPrintJobResult(
            success: true,
            adapterId: result.adapterId,
            errorCode: ReceiptPrinterErrorCode.none,
            message: result.message,
            renderedText: document.text,
            logs: allLogs,
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    return _remember(
      ReceiptPrintJobResult(
        success: false,
        adapterId: adapters.isEmpty ? 'none' : adapters.last.id,
        errorCode: ReceiptPrinterErrorCode.unknown,
        message: 'All print adapters failed.',
        renderedText: document.text,
        logs: allLogs,
        createdAt: DateTime.now(),
      ),
    );
  }

  List<ReceiptPrinterAdapter> _buildAdapterPipeline(StorePrinterConfig config) {
    final generic = GenericTextFallbackAdapter(
      networkHost: config.networkHost,
      networkPort: config.networkPort,
      systemPrinter: config.systemPrinter,
    );

    switch (config.mode) {
      case StorePrinterMode.iposBluetooth:
        return [InternalPosPrinterAdapter(), generic];
      case StorePrinterMode.networkEscPos:
        return [generic, InternalPosPrinterAdapter()];
      case StorePrinterMode.system:
        return [generic, InternalPosPrinterAdapter()];
    }
  }

  ReceiptPrintJobResult _remember(ReceiptPrintJobResult result) {
    _history.insert(0, result);
    if (_history.length > 60) {
      _history.removeRange(60, _history.length);
    }
    return result;
  }
}
