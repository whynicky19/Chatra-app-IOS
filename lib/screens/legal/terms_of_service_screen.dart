import 'package:flutter/cupertino.dart';
import 'legal_doc_screen.dart';

const String _kTermsUpdated = '20.07.2026';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const _sections = <(IconData, String, String)>[
    (CupertinoIcons.square_grid_2x2, 'tos_use_title', 'tos_use_body'),
    (CupertinoIcons.person_crop_circle, 'tos_account_title', 'tos_account_body'),
    (CupertinoIcons.hand_raised, 'tos_conduct_title', 'tos_conduct_body'),
    (CupertinoIcons.sparkles, 'tos_ai_title', 'tos_ai_body'),
    (CupertinoIcons.doc_text, 'tos_content_title', 'tos_content_body'),
    (CupertinoIcons.doc_on_doc, 'tos_ip_title', 'tos_ip_body'),
    (CupertinoIcons.exclamationmark_shield, 'tos_liability_title', 'tos_liability_body'),
    (CupertinoIcons.nosign, 'tos_suspend_title', 'tos_suspend_body'),
    (CupertinoIcons.arrow_2_squarepath, 'tos_changes_title', 'tos_changes_body'),
    (CupertinoIcons.checkmark_seal, 'tos_final_title', 'tos_final_body'),
  ];

  @override
  Widget build(BuildContext context) {
    return const LegalDocScreen(
      titleKey: 'tos_title',
      headerIcon: CupertinoIcons.doc_plaintext,
      updated: _kTermsUpdated,
      introKey: 'tos_intro',
      sections: _sections,
    );
  }
}
