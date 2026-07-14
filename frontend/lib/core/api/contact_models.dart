// SmartBiz AI — Contact API models.
//
// Maps backend /api/contacts responses and payloads.
// Handles nulls and missing fields safely.

/// Contact from backend API.
class ApiContact {
  final String id;
  final String type;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? taxNumber;
  final double balance;
  final ApiContactAssignee? assignedTo;
  final String? createdAt;
  final String? updatedAt;

  const ApiContact({
    required this.id,
    this.type = 'customer',
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.taxNumber,
    this.balance = 0,
    this.assignedTo,
    this.createdAt,
    this.updatedAt,
  });

  factory ApiContact.fromJson(Map<String, dynamic> json) => ApiContact(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'customer',
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        taxNumber: json['tax_number'] as String?,
        balance: _toDouble(json['balance']),
        assignedTo: json['assigned_to'] != null
            ? ApiContactAssignee.fromJson(json['assigned_to'] as Map<String, dynamic>)
            : null,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

/// Assignee info embedded in a contact response.
class ApiContactAssignee {
  final String membershipId;
  final String? fullName;
  const ApiContactAssignee({required this.membershipId, this.fullName});
  factory ApiContactAssignee.fromJson(Map<String, dynamic> j) => ApiContactAssignee(
        membershipId: j['membership_id'] as String? ?? '',
        fullName: j['full_name'] as String?,
      );
}

/// Paginated list result from GET /api/contacts.
class ContactListResult {
  final List<ApiContact> data;
  final int currentPage;
  final int lastPage;
  final int total;

  const ContactListResult({
    this.data = const [],
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
  });

  factory ContactListResult.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List<dynamic>? ?? [];
    final meta = json['meta'] as Map<String, dynamic>? ?? {};

    return ContactListResult(
      data: dataList
          .whereType<Map<String, dynamic>>()
          .map(ApiContact.fromJson)
          .toList(),
      currentPage: meta['current_page'] as int? ?? 1,
      lastPage: meta['last_page'] as int? ?? 1,
      total: meta['total'] as int? ?? dataList.length,
    );
  }

  bool get hasMore => currentPage < lastPage;
}

/// Payload for creating/updating a contact.
class ContactPayload {
  final String name;
  final String type;
  final String? phone;
  final String? email;
  final String? address;
  final String? taxNumber;
  final String? assignedMembershipId;

  const ContactPayload({
    required this.name,
    this.type = 'customer',
    this.phone,
    this.email,
    this.address,
    this.taxNumber,
    this.assignedMembershipId,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        if (email != null && email!.isNotEmpty) 'email': email,
        if (address != null && address!.isNotEmpty) 'address': address,
        if (taxNumber != null && taxNumber!.isNotEmpty) 'tax_number': taxNumber,
        if (assignedMembershipId != null) 'assigned_membership_id': assignedMembershipId,
      };
}
