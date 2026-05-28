// SmartBiz AI — Customer data models.

/// Customer status.
enum CustomerStatus { active, inactive, vip }

/// A single customer.
class Customer {
  final String id;
  String name;
  String? company;
  String? email;
  String phone;
  String? address;
  List<String> tags;
  String? notes;
  CustomerStatus status;
  double balance; // unpaid amount
  int totalInvoices;
  double totalSpent;
  DateTime? lastActivity;
  String preferredLang; // 'en' or 'ar'
  String? assignedEmployeeId;

  Customer({
    required this.id,
    required this.name,
    this.company,
    this.email,
    required this.phone,
    this.address,
    this.tags = const [],
    this.notes,
    this.status = CustomerStatus.active,
    this.balance = 0,
    this.totalInvoices = 0,
    this.totalSpent = 0,
    this.lastActivity,
    this.preferredLang = 'en',
    this.assignedEmployeeId,
  });
}

/// Customer activity entry.
class CustomerActivity {
  final String id;
  final String customerId;
  final String titleKey;
  final String descKey;
  final String iconName;
  final DateTime timestamp;

  const CustomerActivity({
    required this.id,
    required this.customerId,
    required this.titleKey,
    required this.descKey,
    required this.iconName,
    required this.timestamp,
  });
}
