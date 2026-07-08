// SmartBiz AI — Invoice API service.
//
// CRUD operations against /api/invoices.
// Workspace header is attached automatically by ApiClient.

import 'api_client.dart';
import 'invoice_models.dart';

class InvoiceService {
  final ApiClient _client;

  InvoiceService(this._client);

  /// GET /api/invoices
  Future<InvoiceListResult> listInvoices({
    String? paymentStatus,
    String? invoiceType,
    String? contactId,
    int page = 1,
    int perPage = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };
    if (paymentStatus != null && paymentStatus.isNotEmpty) {
      params['payment_status'] = paymentStatus;
    }
    if (invoiceType != null && invoiceType.isNotEmpty) {
      params['invoice_type'] = invoiceType;
    }
    if (contactId != null && contactId.isNotEmpty) {
      params['contact_id'] = contactId;
    }

    final response = await _client.get('/invoices', queryParameters: params);
    return InvoiceListResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// GET /api/invoices/{id}
  Future<ApiInvoice> getInvoice(String id) async {
    final response = await _client.get('/invoices/$id');
    final data = response.data as Map<String, dynamic>;
    return ApiInvoice.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// POST /api/invoices
  Future<ApiInvoice> createInvoice(InvoicePayload payload) async {
    final response = await _client.post('/invoices', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return ApiInvoice.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// PUT /api/invoices/{id}
  Future<ApiInvoice> updateInvoice(
      String id, Map<String, dynamic> fields) async {
    final response = await _client.put('/invoices/$id', data: fields);
    final data = response.data as Map<String, dynamic>;
    return ApiInvoice.fromJson(data['data'] as Map<String, dynamic>);
  }
}
