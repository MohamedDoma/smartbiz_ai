// SmartBiz AI — Dashboard Screen (Phase 16.3).
//
// Thin entry point that delegates to the DashboardCoordinator.
// The coordinator wires AppState/RolesState/OrgState into the
// dynamic dashboard engine and renders DynamicDashboardScreen.
import 'package:flutter/material.dart';
import 'dashboard_coordinator.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardCoordinator();
  }
}
