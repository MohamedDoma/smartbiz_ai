// SmartBiz AI — Deferred route loading widget.
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A widget that shows a shimmer loading indicator while a deferred import loads.
class DeferredRouteLoader extends StatelessWidget {
  final Future<void> Function() loader;
  final Widget Function() builder;

  const DeferredRouteLoader({
    super.key,
    required this.loader,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: loader(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return builder();
        }
        return const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
        );
      },
    );
  }
}
