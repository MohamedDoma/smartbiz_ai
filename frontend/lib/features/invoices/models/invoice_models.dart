// SmartBiz AI — Invoice data models.

/// Invoice status.
enum InvoiceStatus { draft, sent, paid, overdue }

/// A single line item in an invoice.
class InvoiceItem {
  String productName;
  int quantity;
  double unitPrice;

  InvoiceItem({required this.productName, this.quantity = 1, required this.unitPrice});

  double get total => quantity * unitPrice;
}

/// A customer.
class Customer {
  final String id;
  final String name;
  final String? email;
  final String? phone;

  const Customer({required this.id, required this.name, this.email, this.phone});
}

/// A single invoice.
class Invoice {
  final String id;
  final String number;
  final Customer customer;
  final List<InvoiceItem> items;
  final DateTime createdAt;
  final DateTime? dueDate;
  InvoiceStatus status;
  final double taxRate;

  Invoice({
    required this.id,
    required this.number,
    required this.customer,
    required this.items,
    required this.createdAt,
    this.dueDate,
    this.status = InvoiceStatus.draft,
    this.taxRate = 0.15,
  });

  double get subtotal => items.fold(0.0, (sum, i) => sum + i.total);
  double get tax => subtotal * taxRate;
  double get total => subtotal + tax;
}
