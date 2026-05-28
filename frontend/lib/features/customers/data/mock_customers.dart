// SmartBiz AI — Mock customer data.
import '../models/customer_models.dart';

final List<Customer> mockCustomers = [
  Customer(id: 'c1', name: 'Ahmed Al-Rashid', company: 'Rashid Trading Co.', email: 'ahmed@rashid.com', phone: '+966 55 123 4567', address: 'Riyadh, King Fahd Rd', tags: ['wholesale', 'vip'], status: CustomerStatus.vip, balance: 4250.0, totalInvoices: 18, totalSpent: 42500.0, lastActivity: DateTime.now().subtract(const Duration(hours: 2)), preferredLang: 'ar'),
  Customer(id: 'c2', name: 'Sara Mohamed', email: 'sara@email.com', phone: '+966 50 987 6543', tags: ['retail'], status: CustomerStatus.active, balance: 0, totalInvoices: 7, totalSpent: 3150.0, lastActivity: DateTime.now().subtract(const Duration(days: 1)), preferredLang: 'en'),
  Customer(id: 'c3', name: 'Khalid Enterprises', company: 'Khalid Group', email: 'info@khalidgroup.com', phone: '+966 55 456 7890', address: 'Jeddah, Tahlia St', tags: ['corporate', 'vip'], status: CustomerStatus.vip, balance: 12800.0, totalInvoices: 35, totalSpent: 128000.0, lastActivity: DateTime.now().subtract(const Duration(hours: 6)), preferredLang: 'ar', notes: 'Key account. Monthly bulk orders.'),
  Customer(id: 'c4', name: 'Fatima Hassan', phone: '+966 53 222 3333', status: CustomerStatus.active, balance: 750.0, totalInvoices: 3, totalSpent: 1500.0, lastActivity: DateTime.now().subtract(const Duration(days: 5)), preferredLang: 'ar'),
  Customer(id: 'c5', name: 'Tech Solutions LLC', company: 'Tech Solutions', email: 'sales@techsol.com', phone: '+966 55 777 8888', address: 'Dammam, Industrial Area', tags: ['corporate'], status: CustomerStatus.active, balance: 3200.0, totalInvoices: 12, totalSpent: 28000.0, lastActivity: DateTime.now().subtract(const Duration(days: 3)), preferredLang: 'en'),
  Customer(id: 'c6', name: 'Omar Bakery', company: 'Omar Bakery', phone: '+966 50 111 2222', status: CustomerStatus.inactive, balance: 0, totalInvoices: 2, totalSpent: 800.0, lastActivity: DateTime.now().subtract(const Duration(days: 45)), preferredLang: 'ar', notes: 'Inactive since last quarter.'),
];

final List<CustomerActivity> mockActivities = [
  CustomerActivity(id: 'a1', customerId: 'c1', titleKey: 'cust_act_invoice', descKey: 'cust_act_inv_created', iconName: 'receipt', timestamp: DateTime.now().subtract(const Duration(hours: 2))),
  CustomerActivity(id: 'a2', customerId: 'c1', titleKey: 'cust_act_payment', descKey: 'cust_act_pay_received', iconName: 'payment', timestamp: DateTime.now().subtract(const Duration(days: 1))),
  CustomerActivity(id: 'a3', customerId: 'c1', titleKey: 'cust_act_note', descKey: 'cust_act_note_added', iconName: 'task_alt', timestamp: DateTime.now().subtract(const Duration(days: 3))),
  CustomerActivity(id: 'a4', customerId: 'c3', titleKey: 'cust_act_invoice', descKey: 'cust_act_inv_created', iconName: 'receipt', timestamp: DateTime.now().subtract(const Duration(hours: 6))),
  CustomerActivity(id: 'a5', customerId: 'c3', titleKey: 'cust_act_vip', descKey: 'cust_act_vip_marked', iconName: 'auto_awesome', timestamp: DateTime.now().subtract(const Duration(days: 10))),
  CustomerActivity(id: 'a6', customerId: 'c5', titleKey: 'cust_act_invoice', descKey: 'cust_act_inv_created', iconName: 'receipt', timestamp: DateTime.now().subtract(const Duration(days: 3))),
];
