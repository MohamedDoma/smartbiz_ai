// SmartBiz AI — Splash screen.
// First entry point. Attempts to restore session from stored token,
// then routes user based on auth state.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/l10n/app_localizations.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    // Fade + scale in
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutBack));

    // Subtle pulse on logo
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);

    _fadeCtrl.forward();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final app = context.read<AppState>();

    // Run session restore and minimum visual duration in parallel.
    final results = await Future.wait([
      _safeLoadSession(app),
      Future.delayed(const Duration(milliseconds: 2200)),
    ]);

    if (!mounted) return;

    final sessionRestored = results[0] as bool;
    final String target;

    if (!sessionRestored) {
      target = '/login';
    } else if (app.isSuperAdmin) {
      target = '/super-admin';
    } else if (!app.isOnboardingCompleted) {
      target = '/onboarding';
    } else {
      target = '/dashboard';
    }

    context.go(target);
  }

  /// Safely attempt to restore session. Never crashes.
  Future<bool> _safeLoadSession(AppState app) async {
    try {
      return await app.loadCurrentSession();
    } catch (_) {
      // Network error, server down, etc. — go to login.
      return false;
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A), // slate-900
              Color(0xFF1E293B), // slate-800
              Color(0xFF0F172A), // slate-900
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Animated logo ──
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (context, child) {
                        final glow = 0.2 + (_pulseCtrl.value * 0.25);
                        return Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.accent],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(color: AppColors.primary.withValues(alpha: glow), blurRadius: 32, spreadRadius: 2),
                              BoxShadow(color: AppColors.accent.withValues(alpha: glow * 0.6), blurRadius: 48, spreadRadius: 4),
                            ],
                          ),
                          child: const Icon(Icons.auto_awesome, size: 38, color: Colors.white),
                        );
                      },
                    ),
                    const SizedBox(height: 28),

                    // ── App name ──
                    const Text('SmartBiz AI',
                      style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w700,
                        color: Colors.white, letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Tagline ──
                    Text(tr(context, 'splash_tagline'),
                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.6), letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 48),

                    // ── Progress indicator ──
                    SizedBox(width: 28, height: 28, child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primaryLight,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                    )),
                    const SizedBox(height: 14),

                    // ── Loading text ──
                    Text(tr(context, 'splash_loading'),
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
