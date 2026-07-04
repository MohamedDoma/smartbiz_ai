// SmartBiz AI — Mock payment data.
import '../models/payment_models.dart';

class MockPayments {
  MockPayments._();

  static List<Payment> payments() => [
    Payment(
      id: 'pay_1', referenceNumber: 'PAY-001',
      invoiceNumber: 'INV-001', customerName: 'Ahmed Al-Rashid',
      amount: 2450.00, method: PaymentMethod.transfer,
      status: PaymentStatus.completed,
      date: DateTime.now().subtract(const Duration(days: 1)),
    ),
    Payment(
      id: 'pay_2', referenceNumber: 'PAY-002',
      invoiceNumber: 'INV-002', customerName: 'Sara Khalil',
      amount: 1200.00, method: PaymentMethod.card,
      status: PaymentStatus.completed,
      date: DateTime.now().subtract(const Duration(days: 2)),
    ),
    Payment(
      id: 'pay_3', referenceNumber: 'PAY-003',
      invoiceNumber: 'INV-003', customerName: 'Mohammed Doma',
      amount: 850.00, method: PaymentMethod.cash,
      status: PaymentStatus.pending,
      date: DateTime.now().subtract(const Duration(days: 3)),
    ),
    Payment(
      id: 'pay_4', referenceNumber: 'PAY-004',
      invoiceNumber: 'INV-004', customerName: 'Fatima Nasser',
      amount: 3200.00, method: PaymentMethod.online,
      status: PaymentStatus.completed,
      date: DateTime.now().subtract(const Duration(days: 5)),
    ),
    Payment(
      id: 'pay_5', referenceNumber: 'PAY-005',
      invoiceNumber: 'INV-005', customerName: 'Khalid Ibrahim',
      amount: 760.00, method: PaymentMethod.transfer,
      status: PaymentStatus.failed,
      date: DateTime.now().subtract(const Duration(days: 7)),
    ),
    Payment(
      id: 'pay_6', referenceNumber: 'PAY-006',
      customerName: 'Nour Hasan',
      amount: 500.00, method: PaymentMethod.cash,
      status: PaymentStatus.refunded,
      date: DateTime.now().subtract(const Duration(days: 10)),
    ),
    Payment(
      id: 'pay_7', referenceNumber: 'PAY-007',
      invoiceNumber: 'INV-003', customerName: 'Omar Youssef',
      amount: 1800.00, method: PaymentMethod.card,
      status: PaymentStatus.pending,
      date: DateTime.now().subtract(const Duration(hours: 6)),
    ),
  ];
}
