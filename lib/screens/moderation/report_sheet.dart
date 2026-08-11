import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/errors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';
import '../settings/settings_shared.dart';

/// Тип объекта жалобы. Значения совпадают с контрактом бэкенда
/// (POST /reports, поле target_type).
enum ReportTarget { post, assignment, submission, user }

extension ReportTargetX on ReportTarget {
  String get wire => switch (this) {
        ReportTarget.post => 'post',
        ReportTarget.assignment => 'assignment',
        ReportTarget.submission => 'submission',
        ReportTarget.user => 'user',
      };

  String get labelKey => switch (this) {
        ReportTarget.post => 'report_target_post',
        ReportTarget.assignment => 'report_target_assignment',
        ReportTarget.submission => 'report_target_submission',
        ReportTarget.user => 'report_target_user',
      };
}

const _reasons = <(String, String)>[
  ('spam', 'report_reason_spam'),
  ('abuse', 'report_reason_abuse'),
  ('inappropriate', 'report_reason_inappropriate'),
  ('academic', 'report_reason_academic'),
  ('other', 'report_reason_other'),
];

/// Открыть шторку жалобы. Возвращает true, если жалоба отправлена.
Future<bool> openReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required int targetId,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(target: target, targetId: targetId),
  );
  return sent == true;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.target, required this.targetId});

  final ReportTarget target;
  final int targetId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _comment = TextEditingController();
  String _reason = _reasons.first.$1;
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = context.read<L10n>();
    final api = context.read<ApiService>();
    setState(() => _busy = true);
    try {
      await api.reportContent(
        targetType: widget.target.wire,
        targetId: widget.targetId,
        reason: _reason,
        comment: _comment.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      showToast(context, l.t('report_sent'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // 409 — повторная жалоба на тот же объект: это не ошибка, а нормальный
      // ответ сервера, и пугать пользователя «не удалось» не нужно.
      final status = (e is DioException) ? e.response?.statusCode : null;
      if (status == 409) {
        Navigator.pop(context, true);
        showToast(context, l.t('report_already'));
        return;
      }
      logError('ReportSheet.submit', e);
      showToast(context, l.t('report_error'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    return SheetScaffold(
      title: l.t('report_title'),
      icon: CupertinoIcons.flag,
      accent: C.red,
      children: [
        Text(l.t('report_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: adaptiveText3(context), height: 1.4)),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(l.t('report_reason'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: adaptiveText3(context))),
        ),
        for (final (value, key) in _reasons) ...[
          _ReasonRow(
            label: l.t(key),
            selected: _reason == value,
            onTap: () => setState(() => _reason = value),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _comment,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: l.t('report_comment_hint'),
            counterText: '',
          ),
        ),
        const SizedBox(height: 20),
        AppButton.destructive(
          label: l.t('report_send'),
          loading: _busy,
          onPressed: _submit,
          minHeight: 52,
        ),
      ],
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tappable(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.10) : adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(AppRadii.tile),
          border: Border.all(
            color: selected ? primary : adaptiveBorder(context).withValues(alpha: 0.5),
            width: selected ? 1.4 : 0.5,
          ),
        ),
        child: Row(children: [
          Icon(
            selected ? CupertinoIcons.largecircle_fill_circle : CupertinoIcons.circle,
            size: 19,
            color: selected ? primary : C.text4,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: adaptiveText1(context))),
          ),
        ]),
      ),
    );
  }
}
