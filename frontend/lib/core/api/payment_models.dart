// SmartBiz AI — Payment API models.
//
// Maps backend /api/payments responses and payloads.

/// Payment from backend API.
class ApiPayment {
  final String id;
  final String? invoiceId;
  final String? accountId;
  final double amount;
  final String paymentMethod;
  final String? referenceNumber;
  final String? paymentDate;
  final String? paymentNumber;
  final String status;
  final bool isReversal;
  final String? reversalReason;
  final String? createdAt;
  final String? updatedAt;

  const ApiPayment({
    required this.id,
    this.invoiceId,
    this.accountId,
    this.amount = 0,
    this.paymentMethod = 'cash',
    this.referenceNumber,
    this.paymentDate,
    this.paymentNumber,
    this.status = 'completed',
    this.isReversal = false,
    this.reversalReason,
    this.createdAt,
    this.updatedAt,
  });

  factory ApiPayment.fromJson(Map<String, dynamic> json) => ApiPayment(
        id: json['id'] as String? ?? '',
        invoiceId: json['invoice_id'] as String?,
        accountId: json['account_id'] as String?,
        amount: _toDouble(json['amount']),
        paymentMethod: json['payment_method'] as String? ?? 'cash',
        referenceNumber: json['reference_number'] as String?,
        paymentDate: json['payment_date'] as String?,
        paymentNumber: json['payment_number'] as String?,
        status: json['status'] as String? ?? 'completed',
        isReversal: json['is_reversal'] as bool? ?? false,
        reversalReason: json['reversal_reason'] as String?,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

/// Paginated list result from GET /api/payments.
class PaymentListResult {
  final List<ApiPayment> data;
  final int currentPage;
  final int lastPage;
  final int total;

  const PaymentListResult({
    this.data = const [],
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
  });

  factory PaymentListResult.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List<dynamic>? ?? [];
    final meta = json['meta'] as Map<String, dynamic>? ?? {};

    return PaymentListResult(
      data: dataList
          .whereType<Map<String, dynamic>>()
          .map(ApiPayment.fromJson)
          .toList(),
      currentPage: meta['current_page'] as int? ?? 1,
      lastPage: meta['last_page'] as int? ?? 1,
      total: meta['total'] as int? ?? dataList.length,
    );
  }

  bool get hasMore => currentPage < lastPage;
}

/// Payload for creating a payment.
class PaymentPayload {
  final String? invoiceId;
  final double amount;
  final String paymentMethod;
  final String? referenceNumber;
  final String? paymentDate;
  final String? paymentNumber;

  const PaymentPayload({
    this.invoiceId,
    required this.amount,
    this.paymentMethod = 'cash',
    this.referenceNumber,
    this.paymentDate,
    this.paymentNumber,
  });

  Map<String, dynamic> toJson() => {
        if (invoiceId != null) 'invoice_id': invoiceId,
        'amount': amount,
        'payment_method': paymentMethod,
        if (referenceNumber != null && referenceNumber!.isNotEmpty)
          'reference_number': referenceNumber,
        if (paymentDate != null) 'payment_date': paymentDate,
        if (paymentNumber != null && paymentNumber!.isNotEmpty)
          'payment_number': paymentNumber,
      };
}
