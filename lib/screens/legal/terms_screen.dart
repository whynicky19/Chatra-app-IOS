import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 16, 4),
            child: Row(children: [
              IconButton(
                icon: Icon(CupertinoIcons.back, color: adaptiveText1(context)),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(child: Text(l.t('terms_title'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: adaptiveText1(context), letterSpacing: -0.3))),
            ]),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(CupertinoIcons.checkmark_shield, size: 28,
                  color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 18),
              Text(l.t('terms_body'),
                style: TextStyle(fontSize: 15, height: 1.6, color: adaptiveText1(context))),
            ],
          )),
        ]),
      ),
    );
  }
}
