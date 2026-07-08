// SmartBiz AI — Inventory movement API service.
//
// Operations against /api/inventory-movements.
// Workspace header is attached automatically by ApiClient.

import 'api_client.dart';
import 'inventory_models.dart';

class InventoryService {
  final ApiClient _client;

  InventoryService(this._client);

  /// GET /api/inventory-movements
  Future<InventoryMovementListResult> listMovements({
    String? warehouseId,
    String? productId,
    String? movementType,
    int perPage = 50,
  }) async {
    final params = <String, dynamic>{'per_page': perPage};
    if (warehouseId != null && warehouseId.isNotEmpty) {
      params['warehouse_id'] = warehouseId;
    }
    if (productId != null && productId.isNotEmpty) {
      params['product_id'] = productId;
    }
    if (movementType != null && movementType.isNotEmpty) {
      params['movement_type'] = movementType;
    }

    final response =
        await _client.get('/inventory-movements', queryParameters: params);
    return InventoryMovementListResult.fromJson(
        response.data as Map<String, dynamic>);
  }

  /// GET /api/inventory-movements/{id}
  Future<ApiInventoryMovement> getMovement(String id) async {
    final response = await _client.get('/inventory-movements/$id');
    final data = response.data as Map<String, dynamic>;
    return ApiInventoryMovement.fromJson(
        data['data'] as Map<String, dynamic>);
  }

  /// POST /api/inventory-movements
  Future<ApiInventoryMovement> createMovement(
      InventoryMovementPayload payload) async {
    final response =
        await _client.post('/inventory-movements', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return ApiInventoryMovement.fromJson(
        data['data'] as Map<String, dynamic>);
  }

  /// GET /api/inventory-movements/levels
  Future<List<InventoryLevel>> getInventoryLevels({
    String? warehouseId,
    String? productId,
  }) async {
    final params = <String, dynamic>{};
    if (warehouseId != null && warehouseId.isNotEmpty) {
      params['warehouse_id'] = warehouseId;
    }
    if (productId != null && productId.isNotEmpty) {
      params['product_id'] = productId;
    }

    final response = await _client.get('/inventory-movements/levels',
        queryParameters: params);
    final data = response.data as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(InventoryLevel.fromJson)
        .toList();
  }
}
