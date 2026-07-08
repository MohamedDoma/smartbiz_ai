// SmartBiz AI — Warehouse API models.
//
// Maps backend /api/warehouses responses and payloads.

/// Warehouse from backend API.
class ApiWarehouse {
  final String id;
  final String name;
  final String? location;

  const ApiWarehouse({
    required this.id,
    required this.name,
    this.location,
  });

  factory ApiWarehouse.fromJson(Map<String, dynamic> json) => ApiWarehouse(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        location: json['location'] as String?,
      );
}

/// Result from GET /api/warehouses.
/// Backend returns plain { data: [...] } without meta/links.
class WarehouseListResult {
  final List<ApiWarehouse> data;

  const WarehouseListResult({this.data = const []});

  factory WarehouseListResult.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List<dynamic>? ?? [];
    return WarehouseListResult(
      data: dataList
          .whereType<Map<String, dynamic>>()
          .map(ApiWarehouse.fromJson)
          .toList(),
    );
  }
}

/// Payload for creating/updating a warehouse.
class WarehousePayload {
  final String name;
  final String? location;

  const WarehousePayload({required this.name, this.location});

  Map<String, dynamic> toJson() => {
        'name': name,
        if (location != null && location!.isNotEmpty) 'location': location,
      };
}
