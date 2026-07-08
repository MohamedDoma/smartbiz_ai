// SmartBiz AI — Product API service.
//
// CRUD operations against the backend /api/products endpoints.
// Workspace header is attached automatically by ApiClient.

import 'api_client.dart';
import 'product_models.dart';

class ProductService {
  final ApiClient _client;

  ProductService(this._client);

  /// GET /api/products
  Future<ProductListResult> listProducts({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };
    if (search != null && search.isNotEmpty) params['search'] = search;

    final response = await _client.get('/products', queryParameters: params);
    return ProductListResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// POST /api/products
  Future<ApiProduct> createProduct(ProductPayload payload) async {
    final response = await _client.post('/products', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return ApiProduct.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// PUT /api/products/{id}
  Future<ApiProduct> updateProduct(String id, ProductPayload payload) async {
    final response = await _client.put('/products/$id', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return ApiProduct.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// DELETE /api/products/{id}
  Future<void> deleteProduct(String id) async {
    await _client.delete('/products/$id');
  }
}
