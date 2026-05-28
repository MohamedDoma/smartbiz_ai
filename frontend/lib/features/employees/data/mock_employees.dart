// SmartBiz AI — Mock employees data.
import '../models/employee_models.dart';

class MockEmployees {
  MockEmployees._();

  static List<Employee> employees() => [
    Employee(
      id: 'emp_1', name: 'Mohamed Doma', email: 'mohamed@smartbiz.ai',
      role: AppRole.owner, status: EmpStatus.active, aiAccess: AiAccess.full,
      department: 'Management', langPref: 'en',
      lastActive: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    Employee(
      id: 'emp_2', name: 'Sara Ahmed', email: 'sara@smartbiz.ai',
      phone: '+966 55 222 3333', role: AppRole.accountant, status: EmpStatus.active,
      aiAccess: AiAccess.full, department: 'Finance', langPref: 'ar',
      lastActive: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    Employee(
      id: 'emp_3', name: 'Khalid Omar', email: 'khalid@smartbiz.ai',
      phone: '+966 55 444 5555', role: AppRole.cashier, status: EmpStatus.active,
      aiAccess: AiAccess.limited, department: 'Sales', langPref: 'ar',
      lastActive: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    Employee(
      id: 'emp_4', name: 'Layla Hassan', email: 'layla@smartbiz.ai',
      role: AppRole.warehouse, status: EmpStatus.active,
      aiAccess: AiAccess.limited, department: 'Operations', langPref: 'en',
      lastActive: DateTime.now().subtract(const Duration(days: 1)),
    ),
    Employee(
      id: 'emp_5', name: 'Ahmed Ali', email: 'ahmed.ali@smartbiz.ai',
      role: AppRole.employee, status: EmpStatus.invited,
      aiAccess: AiAccess.none, department: 'Operations', langPref: 'en',
    ),
    Employee(
      id: 'emp_6', name: 'Nour Khalil', email: 'nour@smartbiz.ai',
      phone: '+966 55 888 9999', role: AppRole.cashier, status: EmpStatus.suspended,
      aiAccess: AiAccess.none, department: 'Sales', langPref: 'ar',
      lastActive: DateTime.now().subtract(const Duration(days: 14)),
    ),
  ];
}
