// SmartBiz AI — Shell state (navigation, drawer, sidebar).
import 'package:flutter/material.dart';

class ShellState extends ChangeNotifier {
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;
  bool _isSuperAdmin = false;

  int get selectedIndex => _selectedIndex;
  bool get sidebarExpanded => _sidebarExpanded;
  bool get isSuperAdmin => _isSuperAdmin;

  void selectIndex(int index) {
    _selectedIndex = index;
    notifyListeners();
  }

  void toggleSidebar() {
    _sidebarExpanded = !_sidebarExpanded;
    notifyListeners();
  }

  void setSuperAdmin(bool value) {
    _isSuperAdmin = value;
    notifyListeners();
  }
}
