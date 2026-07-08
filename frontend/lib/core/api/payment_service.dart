// SmartBiz AI — Payment API service.
//
// CRUD operations against /api/payments.
// Workspace header is attached automatically by ApiClient.

import 'api_client.dart';
import 'payment_models.dart';

class PaymentService {
  final ApiClient _client;

  PaymentService(this._client);

  /// GET /api/payments
  Future<PaymentListResult> listPayments({
    String? invoiceId,
    String? status,
    int page = 1,
    int perPage = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };
    if (invoiceId != null && invoiceId.isNotEmpty) {
      params['invoice_id'] = invoiceId;
    }
    if (status != null && status.isNotEmpty) {
      params['status'] = status;
    }

    final response = await _client.get('/payments', queryParameters: params);
    return PaymentListResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// POST /api/payments
  Future<ApiPayment> createPayment(PaymentPayload payload) async {
    final response = await _client.post('/payments', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return ApiPayment.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// POST /api/payments/{id}/reverse
  Future<ApiPayment> reversePayment(String id, String reason) async {
    final response = await _client.post(
      '/payments/$id/reverse',
      data: {'reason': reason},
    );
    final data = response.data as Map<String, dynamic>;
    return ApiPayment.fromJson(data['data'] as Map<String, dynamic>);
  }
}
