// SmartBiz AI — Payment data models.

/// Payment status.
enum PaymentStatus { completed, pending, failed, refunded }

/// Payment method.
enum PaymentMethod { cash, card, transfer, online }

/// A single payment record.
class Payment {
  final String id;
  final String referenceNumber;
  final String? invoiceNumber;
  final String customerName;
  final double amount;
  final PaymentMethod method;
  PaymentStatus status;
  final DateTime date;
  final String? notes;

  Payment({
    required this.id,
    required this.referenceNumber,
    this.invoiceNumber,
    required this.customerName,
    required this.amount,
    required this.method,
    this.status = PaymentStatus.completed,
    required this.date,
    this.notes,
  });
}
