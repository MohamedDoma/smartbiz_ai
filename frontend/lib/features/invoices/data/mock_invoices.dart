// SmartBiz AI — Mock invoice data.
import '../models/invoice_models.dart';

class MockInvoices {
  MockInvoices._();

  static final List<Customer> customers = [
    const Customer(id: 'c1', name: 'Ahmed Trading Co.', email: 'ahmed@trading.com', phone: '+966 55 111 2222'),
    const Customer(id: 'c2', name: 'Sara Group', email: 'sara@group.sa', phone: '+966 55 333 4444'),
    const Customer(id: 'c3', name: 'Khalid Enterprises', email: 'khalid@ent.com', phone: '+966 55 555 6666'),
    const Customer(id: 'c4', name: 'Layla Boutique', email: 'layla@boutique.sa', phone: '+966 55 777 8888'),
    const Customer(id: 'c5', name: 'Omar Supplies', email: 'omar@supplies.com', phone: '+966 55 999 0000'),
  ];

  static List<Invoice> invoices() => [
    Invoice(
      id: 'inv_1', number: 'INV-001', customer: customers[0],
      items: [
        InvoiceItem(productName: 'Premium Coffee Beans', quantity: 10, unitPrice: 24.99),
        InvoiceItem(productName: 'Paper Cups (100pc)', quantity: 5, unitPrice: 15.00),
        InvoiceItem(productName: 'Sugar 1kg', quantity: 3, unitPrice: 8.50),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 2)), status: InvoiceStatus.paid,
    ),
    Invoice(
      id: 'inv_2', number: 'INV-002', customer: customers[1],
      items: [
        InvoiceItem(productName: 'Premium Tea Box', quantity: 20, unitPrice: 18.00),
        InvoiceItem(productName: 'Honey Jar 500g', quantity: 8, unitPrice: 22.50),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      dueDate: DateTime.now().subtract(const Duration(days: 2)), status: InvoiceStatus.overdue,
    ),
    Invoice(
      id: 'inv_3', number: 'INV-003', customer: customers[2],
      items: [
        InvoiceItem(productName: 'Office Supplies Kit', quantity: 2, unitPrice: 89.99),
        InvoiceItem(productName: 'Printer Paper A4', quantity: 10, unitPrice: 12.00),
        InvoiceItem(productName: 'Ink Cartridge', quantity: 4, unitPrice: 35.00),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 1)), status: InvoiceStatus.sent,
    ),
    Invoice(
      id: 'inv_4', number: 'INV-004', customer: customers[3],
      items: [
        InvoiceItem(productName: 'Fabric Roll (50m)', quantity: 3, unitPrice: 120.00),
        InvoiceItem(productName: 'Thread Set', quantity: 6, unitPrice: 8.00),
      ],
      createdAt: DateTime.now(), status: InvoiceStatus.draft,
    ),
    Invoice(
      id: 'inv_5', number: 'INV-005', customer: customers[4],
      items: [
        InvoiceItem(productName: 'Cleaning Solution 5L', quantity: 12, unitPrice: 18.00),
        InvoiceItem(productName: 'Mop Pro', quantity: 4, unitPrice: 25.00),
        InvoiceItem(productName: 'Gloves Box (100)', quantity: 10, unitPrice: 14.50),
      ],
      createdAt: DateTime.now().subtract(const Duration(hours: 6)), status: InvoiceStatus.sent,
    ),
  ];
}
