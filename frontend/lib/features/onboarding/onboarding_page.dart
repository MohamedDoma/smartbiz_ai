import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import 'onboarding_state.dart';
import 'screens/welcome_screen.dart';
import 'screens/discovery_screen.dart';
import 'screens/blueprint_screen.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: switch (state.phase) {
          OnboardingPhase.welcome => const WelcomeScreen(),
          OnboardingPhase.discovery => const DiscoveryScreen(),
          OnboardingPhase.blueprint ||
          OnboardingPhase.provisioning ||
          OnboardingPhase.complete => const BlueprintScreen(),
        },
      ),
    );
  }
}
