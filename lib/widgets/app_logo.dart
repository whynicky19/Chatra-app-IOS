import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/org_provider.dart';
import '../theme/app_theme.dart';

/// Логотип Chatra. Ассет монохромный (тил), поэтому для школьной
/// организации он перекрашивается в оранжевый через color/srcIn —
/// отдельный ассет не нужен, сглаживание сохраняется.
class AppLogo extends StatelessWidget {
  final double? width, height;
  final BoxFit? fit;
  /// true — знак без надписи (logo-icon.png), false — полный логотип.
  final bool iconOnly;
  const AppLogo({super.key, this.width, this.height, this.fit, this.iconOnly = false});

  @override
  Widget build(BuildContext context) {
    final isSchool = context.select<OrgProvider, bool>((o) => o.isSchool);
    return Image.asset(
      iconOnly ? 'assets/logo-icon.png' : 'assets/logo.png',
      width: width, height: height, fit: fit,
      color: isSchool ? C.amber : null,
    );
  }
}
