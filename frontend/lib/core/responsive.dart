// Responsive breakpoints.
import 'package:flutter/widgets.dart';

class Responsive {
  Responsive._();

  static const double mobileBreakpoint  = 600;
  static const double tabletBreakpoint  = 900;
  static const double desktopBreakpoint = 1200;

  static bool isMobile(BuildContext context)  => MediaQuery.sizeOf(context).width < mobileBreakpoint;
  static bool isTablet(BuildContext context)  => MediaQuery.sizeOf(context).width >= mobileBreakpoint && MediaQuery.sizeOf(context).width < desktopBreakpoint;
  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  /// Sidebar width (expanded).
  static const double sidebarWidth = 260;
  /// Sidebar width (collapsed / rail).
  static const double sidebarCollapsed = 72;
}
