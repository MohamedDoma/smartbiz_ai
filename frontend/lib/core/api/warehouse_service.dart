// SmartBiz AI — Warehouse API service.
//
// CRUD operations against /api/warehouses.
// Workspace header is attached automatically by ApiClient.

import 'api_client.dart';
import 'warehouse_models.dart';

class WarehouseService {
  final ApiClient _client;

  WarehouseService(this._client);

  /// GET /api/warehouses
  Future<WarehouseListResult> listWarehouses() async {
    final response = await _client.get('/warehouses');
    return WarehouseListResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// POST /api/warehouses
  Future<ApiWarehouse> createWarehouse(WarehousePayload payload) async {
    final response = await _client.post('/warehouses', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return ApiWarehouse.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// PUT /api/warehouses/{id}
  Future<ApiWarehouse> updateWarehouse(
      String id, WarehousePayload payload) async {
    final response =
        await _client.put('/warehouses/$id', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return ApiWarehouse.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// DELETE /api/warehouses/{id}
  Future<void> deleteWarehouse(String id) async {
    await _client.delete('/warehouses/$id');
  }
}
