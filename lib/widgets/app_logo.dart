import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/org_provider.dart';
import '../theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  final double? width, height;
  final BoxFit? fit;
  final bool iconOnly;
  const AppLogo({super.key, this.width, this.height, this.fit, this.iconOnly = false});

  @override
  Widget build(BuildContext context) {
    final isSchool = context.select<OrgProvider, bool>((o) => o.isSchool);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      iconOnly ? 'assets/logo-icon.png' : 'assets/logo.png',
      width: width, height: height, fit: fit,
      color: isSchool ? C.amber : (isDark ? Colors.white : null),
    );
  }
}
