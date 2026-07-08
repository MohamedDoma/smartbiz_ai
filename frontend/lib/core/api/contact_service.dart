// SmartBiz AI — Contact API service.
//
// CRUD operations against the backend /api/contacts endpoints.
// Workspace header is attached automatically by ApiClient.

import 'api_client.dart';
import 'contact_models.dart';

class ContactService {
  final ApiClient _client;

  ContactService(this._client);

  /// GET /api/contacts
  Future<ContactListResult> listContacts({
    String? search,
    String? type,
    int page = 1,
    int perPage = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (type != null && type.isNotEmpty) params['type'] = type;

    final response = await _client.get('/contacts', queryParameters: params);
    return ContactListResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// POST /api/contacts
  Future<ApiContact> createContact(ContactPayload payload) async {
    final response = await _client.post('/contacts', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return ApiContact.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// PUT /api/contacts/{id}
  Future<ApiContact> updateContact(String id, ContactPayload payload) async {
    final response = await _client.put('/contacts/$id', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return ApiContact.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// DELETE /api/contacts/{id}
  Future<void> deleteContact(String id) async {
    await _client.delete('/contacts/$id');
  }
}
