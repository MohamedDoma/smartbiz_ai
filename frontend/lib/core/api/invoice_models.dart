// SmartBiz AI — Invoice API models.
//
// Maps backend /api/invoices responses and payloads.
// Handles nulls, numeric strings, and missing fields safely.

/// Invoice from backend API.
class ApiInvoice {
  final String id;
  final String? contactId;
  final String? contactName;
  final String? contactEmail;
  final String invoiceType;
  final String? invoiceNumber;
  final String currency;
  final double totalAmount;
  final double discountAmount;
  final double taxAmount;
  final double netAmount;
  final String paymentStatus;
  final String? dueDate;
  final List<ApiInvoiceItem> items;
  final String? createdAt;
  final String? updatedAt;

  const ApiInvoice({
    required this.id,
    this.contactId,
    this.contactName,
    this.contactEmail,
    this.invoiceType = 'sale',
    this.invoiceNumber,
    this.currency = 'USD',
    this.totalAmount = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.netAmount = 0,
    this.paymentStatus = 'unpaid',
    this.dueDate,
    this.items = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory ApiInvoice.fromJson(Map<String, dynamic> json) {
    // Contact may be nested object or null
    final contact = json['contact'] as Map<String, dynamic>?;

    // Items may be list or null
    final itemsRaw = json['items'] as List<dynamic>? ?? [];

    return ApiInvoice(
      id: json['id'] as String? ?? '',
      contactId: json['contact_id'] as String?,
      contactName: contact?['name'] as String?,
      contactEmail: contact?['email'] as String?,
      invoiceType: json['invoice_type'] as String? ?? 'sale',
      invoiceNumber: json['invoice_number'] as String?,
      currency: json['currency'] as String? ?? 'USD',
      totalAmount: _toDouble(json['total_amount']),
      discountAmount: _toDouble(json['discount_amount']),
      taxAmount: _toDouble(json['tax_amount']),
      netAmount: _toDouble(json['net_amount']),
      paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      dueDate: json['due_date'] as String?,
      items: itemsRaw
          .whereType<Map<String, dynamic>>()
          .map(ApiInvoiceItem.fromJson)
          .toList(),
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

/// Invoice line item from backend API.
class ApiInvoiceItem {
  final String id;
  final String? productId;
  final double quantity;
  final double unitPrice;
  final double discountAmount;
  final double taxAmount;
  final double subtotal;
  final String? productNameSnapshot;
  final String? skuSnapshot;

  const ApiInvoiceItem({
    required this.id,
    this.productId,
    this.quantity = 1,
    this.unitPrice = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.subtotal = 0,
    this.productNameSnapshot,
    this.skuSnapshot,
  });

  factory ApiInvoiceItem.fromJson(Map<String, dynamic> json) => ApiInvoiceItem(
        id: json['id'] as String? ?? '',
        productId: json['product_id'] as String?,
        quantity: ApiInvoice._toDouble(json['quantity']),
        unitPrice: ApiInvoice._toDouble(json['unit_price']),
        discountAmount: ApiInvoice._toDouble(json['discount_amount']),
        taxAmount: ApiInvoice._toDouble(json['tax_amount']),
        subtotal: ApiInvoice._toDouble(json['subtotal']),
        productNameSnapshot: json['product_name_snapshot'] as String?,
        skuSnapshot: json['sku_snapshot'] as String?,
      );
}

/// Paginated list result from GET /api/invoices.
class InvoiceListResult {
  final List<ApiInvoice> data;
  final int currentPage;
  final int lastPage;
  final int total;

  const InvoiceListResult({
    this.data = const [],
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
  });

  factory InvoiceListResult.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List<dynamic>? ?? [];
    final meta = json['meta'] as Map<String, dynamic>? ?? {};

    return InvoiceListResult(
      data: dataList
          .whereType<Map<String, dynamic>>()
          .map(ApiInvoice.fromJson)
          .toList(),
      currentPage: meta['current_page'] as int? ?? 1,
      lastPage: meta['last_page'] as int? ?? 1,
      total: meta['total'] as int? ?? dataList.length,
    );
  }

  bool get hasMore => currentPage < lastPage;
}

/// Payload for creating an invoice.
class InvoicePayload {
  final String? contactId;
  final String invoiceType;
  final String? currency;
  final String? dueDate;
  final String? invoiceNumber;
  final List<InvoiceItemPayload> items;

  const InvoicePayload({
    this.contactId,
    this.invoiceType = 'sale',
    this.currency,
    this.dueDate,
    this.invoiceNumber,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        if (contactId != null) 'contact_id': contactId,
        'invoice_type': invoiceType,
        if (currency != null) 'currency': currency,
        if (dueDate != null) 'due_date': dueDate,
        if (invoiceNumber != null) 'invoice_number': invoiceNumber,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

/// Payload for a single invoice line item.
class InvoiceItemPayload {
  final String? productId;
  final double quantity;
  final double unitPrice;
  final double discountAmount;
  final double taxAmount;
  final String? productNameSnapshot;
  final String? skuSnapshot;

  const InvoiceItemPayload({
    this.productId,
    required this.quantity,
    required this.unitPrice,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.productNameSnapshot,
    this.skuSnapshot,
  });

  Map<String, dynamic> toJson() => {
        if (productId != null) 'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        if (discountAmount > 0) 'discount_amount': discountAmount,
        if (taxAmount > 0) 'tax_amount': taxAmount,
        if (productNameSnapshot != null)
          'product_name_snapshot': productNameSnapshot,
        if (skuSnapshot != null) 'sku_snapshot': skuSnapshot,
      };
}
