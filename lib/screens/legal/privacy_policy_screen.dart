import 'package:flutter/cupertino.dart';
import 'legal_doc_screen.dart';

const String _kPrivacyUpdated = '20.07.2026';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = <(IconData, String, String)>[
    (CupertinoIcons.doc_text, 'pp_collect_title', 'pp_collect_body'),
    (CupertinoIcons.gear_alt, 'pp_use_title', 'pp_use_body'),
    (CupertinoIcons.arrow_2_squarepath, 'pp_share_title', 'pp_share_body'),
    (CupertinoIcons.lock_shield, 'pp_store_title', 'pp_store_body'),
    (CupertinoIcons.checkmark_seal, 'pp_rights_title', 'pp_rights_body'),
    (CupertinoIcons.person_crop_circle, 'pp_children_title', 'pp_children_body'),
    (CupertinoIcons.mail, 'pp_contact_title', 'pp_contact_body'),
  ];

  @override
  Widget build(BuildContext context) {
    return const LegalDocScreen(
      titleKey: 'pp_title',
      headerIcon: CupertinoIcons.lock_shield_fill,
      updated: _kPrivacyUpdated,
      introKey: 'pp_intro',
      sections: _sections,
    );
  }
}
