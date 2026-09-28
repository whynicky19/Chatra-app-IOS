import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_backdrop.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final theme = Theme.of(context);
    final title = l.t('terms_title');
    return CupertinoTheme(
      data: AppTheme.cupertinoFor(theme),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackdrop(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              CupertinoSliverNavigationBar(
                backgroundColor:
                    theme.scaffoldBackgroundColor.withValues(alpha: 0.84),
                border: null,
                middle: Text(title),
                largeTitle: Text(title),
                leading: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(CupertinoIcons.chevron_left, size: 21),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
                sliver: SliverToBoxAdapter(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(CupertinoIcons.checkmark_shield,
                            size: 22, color: theme.colorScheme.primary),
                        const SizedBox(height: 18),
                        Text(l.t('terms_body'),
                            style: TextStyle(
                                fontSize: 17,
                                height: 1.6,
                                letterSpacing: -0.2,
                                color: adaptiveText2(context))),
                      ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
