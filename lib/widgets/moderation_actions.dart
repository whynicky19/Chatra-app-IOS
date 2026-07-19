import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/l10n_provider.dart';
import '../services/moderation_service.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'toast.dart';

/// UGC-модерация (App Store Guideline 1.2): жалоба на пользователя/сообщение
/// и блокировка. Жалоба записывается локально, уходит на почту модерации и
/// автоматически блокирует нарушителя (чтобы контент сразу пропал у жалобщика).

Future<void> showReportSheet(
  BuildContext context, {
  required int reportedUserId,
  String? content,
  int? messageId,
}) async {
  final l = context.read<L10n>();
  final reasons = <(String, IconData)>[
    ('report_spam', CupertinoIcons.money_dollar_circle),
    ('report_harassment', CupertinoIcons.exclamationmark_bubble),
    ('report_inappropriate', CupertinoIcons.eye_slash),
    ('report_other', CupertinoIcons.ellipsis_circle),
  ];

  await showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4,
          decoration: BoxDecoration(color: adaptiveBorder(ctx), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),
        Text(l.t('report_reason_title'),
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: adaptiveText1(ctx))),
        const SizedBox(height: 4),
        Text(l.t('report_auto_block_note'),
          style: const TextStyle(fontSize: 12.5, color: C.text4)),
        const SizedBox(height: 14),
        for (final r in reasons)
          GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              await _submitReport(context,
                reportedUserId: reportedUserId,
                reasonKey: r.$1,
                content: content,
                messageId: messageId);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: adaptiveSurface2(ctx),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(r.$2, size: 19, color: C.red),
                const SizedBox(width: 12),
                Expanded(child: Text(l.t(r.$1),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(ctx)))),
                const Icon(CupertinoIcons.chevron_right, size: 14, color: C.text4),
              ]),
            ),
          ),
      ]),
    )),
  );
}

Future<void> _submitReport(
  BuildContext context, {
  required int reportedUserId,
  required String reasonKey,
  String? content,
  int? messageId,
}) async {
  final mod = context.read<ModerationService>();
  final l = context.read<L10n>();
  final reporterId = context.read<AuthProvider>().userId;

  await mod.recordReport(
    reportedUserId: reportedUserId,
    reason: reasonKey,
    content: content,
    messageId: messageId,
  );
  // Жалоба подразумевает, что жалующийся больше не хочет видеть нарушителя.
  await mod.block(reportedUserId);

  // Отправка модератору на почту (best-effort, не блокирует UX).
  final subject = 'UGC report: user #$reportedUserId ($reasonKey)';
  final body = [
    'Reason: $reasonKey',
    'Reported user id: $reportedUserId',
    if (reporterId != null) 'Reporter user id: $reporterId',
    if (messageId != null) 'Message id: $messageId',
    if (content != null && content.isNotEmpty) 'Content: $content',
    'At: ${DateTime.now().toIso8601String()}',
  ].join('\n');
  try {
    await launchUrl(
      Uri(scheme: 'mailto', path: kModerationEmail, query: _query({'subject': subject, 'body': body})),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {}

  if (context.mounted) showToast(context, l.t('report_sent'));
}

String _query(Map<String, String> params) => params.entries
    .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
    .join('&');

/// Спросить подтверждение и заблокировать пользователя. Возвращает true, если
/// заблокировали.
Future<bool> confirmAndBlock(BuildContext context, {required int userId}) async {
  final l = context.read<L10n>();
  final ok = await showConfirmDialog(context,
    title: l.t('block_user_q'),
    message: l.t('block_user_msg2'),
    icon: CupertinoIcons.nosign,
    danger: true,
    confirmText: l.t('block_user_action'),
    cancelText: l.t('cancel'));
  if (ok == true && context.mounted) {
    await context.read<ModerationService>().block(userId);
    if (context.mounted) showToast(context, l.t('user_blocked_toast'));
    return true;
  }
  return false;
}

Future<void> unblockUser(BuildContext context, {required int userId}) async {
  final l = context.read<L10n>();
  await context.read<ModerationService>().unblock(userId);
  if (context.mounted) showToast(context, l.t('user_unblocked_toast'));
}
