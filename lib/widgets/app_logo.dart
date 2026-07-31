import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/org_provider.dart';
import '../theme/app_theme.dart';
import 'brand_gradient.dart';

class AppLogo extends StatelessWidget {
  final double? width, height;
  final BoxFit? fit;
  final bool iconOnly;
  const AppLogo({super.key, this.width, this.height, this.fit, this.iconOnly = false});

  @override
  Widget build(BuildContext context) {
    final isSchool = context.select<OrgProvider, bool>((o) => o.isSchool);
    final asset = iconOnly ? 'assets/logo-icon.png' : 'assets/logo.png';
    if (isSchool) {
      return Image.asset(asset, width: width, height: height, fit: fit, color: C.amber);
    }
    return BrandGradient.mask(
      child: Image.asset(asset, width: width, height: height, fit: fit),
    );
  }
}
