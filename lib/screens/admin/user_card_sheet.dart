import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/cover_art.dart';
import '../../utils/errors.dart';
import '../../widgets/cupertino_liquid_switch.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/subject_cover.dart';
import '../../widgets/tappable.dart';
import 'admin_format.dart';

/// Карточка пользователя: профиль, расход ИИ с разбивкой, дневная квота,
/// предметы, учебная активность и управление аккаунтом — всё, что раньше
/// требовало нескольких экранов, одним листом.
///
/// [row] — строка из списка: заголовок и чипы рисуются мгновенно, пока грузится
/// детализация. [onAction] выполняет действие (роль/безлимит/блок/удаление) и
/// возвращает true, если оно применилось; список наверху обновляет себя сам.
Future<void> showUserCardSheet(
  BuildContext context, {
  required Map<String, dynamic> row,
  required bool isSelf,
  required Future<bool> Function(String action) onAction,
  VoidCallback? onDeleted,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet))),
    builder: (_) => _UserCardSheet(
      row: row,
      isSelf: isSelf,
      onAction: onAction,
      onDeleted: onDeleted,
    ),
  );
}

class _UserCardSheet extends StatefulWidget {
  const _UserCardSheet({
    required this.row,
    required this.isSelf,
    required this.onAction,
    this.onDeleted,
  });

  final Map<String, dynamic> row;
  final bool isSelf;
  final Future<bool> Function(String action) onAction;
  final VoidCallback? onDeleted;

  @override
  State<_UserCardSheet> createState() => _UserCardSheetState();
}

class _UserCardSheetState extends State<_UserCardSheet> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _busy = false;

  int get _userId => (widget.row['id'] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      _detail = await context.read<ApiService>().adminUserDetail(_userId);
    } catch (e) {
      logError('AdminUserCard.load', e);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Действие меняет и строку списка, и цифры карточки — перечитываем её, иначе
  /// чипы разойдутся с содержимым.
  Future<void> _run(String action, VoidCallback optimistic) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.onAction(action);
    if (!mounted) {
      return;
    }
    if (ok) optimistic();
    setState(() => _busy = false);
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final row = widget.row;
    final name = (row['full_name'] ?? '').toString().trim().isNotEmpty
        ? row['full_name'].toString()
        : (row['email'] ?? '').toString().split('@').first;
    final email = (row['email'] ?? '').toString();
    final role = (row['role'] ?? 'student').toString();
    final blocked = row['is_active'] == false;
    final unlimited = row['ai_unlimited'] == true;
    final unverified = row['is_verified'] == false;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, sc) => Column(children: [
        Container(
          width: 40,
          height: 5,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: adaptiveText4(context).withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(100)),
        ),
        // Шапка вне скролла: кто это — видно и после прокрутки вглубь карточки.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 12, 12),
          child: Row(children: [
            InitialsAvatar(id: _userId, name: name, size: 52, radius: 16),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: adaptiveTextSoft(context))),
                const SizedBox(height: 2),
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context))),
              ]),
            ),
            Tappable(
              onTap: () => Navigator.pop(context),
              label: l.t('close'),
              child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(CupertinoIcons.xmark, size: 19, color: adaptiveText4(context))),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            // «Активен» — состояние по умолчанию: чип появляется только когда с
            // аккаунтом что-то не так.
            _Chip(text: _roleLabel(l, role), color: adaptiveText3(context)),
            if (blocked) _Chip(text: l.t('blocked_short'), color: C.red, dot: true),
            if (unlimited) _Chip(text: l.t('ai_unlimited'), color: Theme.of(context).colorScheme.primary),
            if (unverified) _Chip(text: l.t('email_unverified_short'), color: C.amber),
          ]),
        ),
        Container(height: hairline(context), color: groupSeparator(context)),
        Expanded(
          child: _loading && _detail == null
              ? const Center(child: CupertinoActivityIndicator(radius: 13))
              : _detail == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(l.t('card_load_error'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: adaptiveText3(context))),
                      ),
                    )
                  : ListView(
                      controller: sc,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: _body(l, role, blocked, unlimited),
                    ),
        ),
      ]),
    );
  }

  String _roleLabel(L10n l, String role) => switch (role) {
    'admin' => l.t('role_admin_short'),
    'teacher' => l.t('role_teacher_short'),
    _ => l.t('role_student_short'),
  };

  List<Widget> _body(L10n l, String role, bool blocked, bool unlimited) {
    final d = _detail!;
    final ai = (d['ai'] as Map?)?.cast<String, dynamic>() ?? const {};
    final activity = (d['activity'] as Map?)?.cast<String, dynamic>() ?? const {};
    final classes = (d['classes'] as List?) ?? const [];
    final kinds = (ai['by_endpoint'] as List?) ?? const [];
    final maxKind = kinds.fold<int>(1, (m, k) {
      final v = ((k as Map)['total_tokens'] as num? ?? 0).toInt();
      return v > m ? v : m;
    });
    final messagesToday = (ai['messages_today'] as num? ?? 0).toInt();
    final messageLimit = (ai['message_limit'] as num? ?? 0).toInt();
    final quota = (unlimited || messageLimit <= 0)
        ? 0.0
        : (messagesToday / messageLimit).clamp(0.0, 1.0);
    final quotaColor = quota >= 0.9 ? C.red : quota >= 0.7 ? C.amber : Theme.of(context).colorScheme.primary;
    final generalTokens = (ai['general_tokens'] as num? ?? 0).toInt();

    return [
      _label(l.t('ai_usage_section')),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _Tile(value: fmtInt(ai['total_tokens']), label: l.t('tokens_total_label'))),
        const SizedBox(width: 8),
        Expanded(child: _Tile(value: fmtInt(ai['request_count']), label: l.t('requests_label'))),
        const SizedBox(width: 8),
        Expanded(child: _Tile(value: fmtInt(ai['avg_tokens']), label: l.t('avg_per_request'))),
      ]),
      const SizedBox(height: 14),

      // Дневная квота — то, по чему бэкенд реально отказывает в запросе.
      Row(children: [
        Expanded(
          child: Text(l.t('today_used'),
              style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context))),
        ),
        Text(
          messageLimit > 0 ? '$messagesToday ${l.t('of_word')} $messageLimit' : '$messagesToday',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: adaptiveTextSoft(context),
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ]),
      const SizedBox(height: 8),
      MiniBar(value: quota, color: quotaColor, height: 8),
      const SizedBox(height: 6),
      Text(
        unlimited
            ? l.t('quota_unlimited_note')
            : messageLimit > 0
                ? l.t('quota_reset_note')
                : l.t('quota_off_note'),
        style: TextStyle(fontSize: 13, color: adaptiveText4(context)),
      ),

      if (kinds.isNotEmpty) ...[
        const SizedBox(height: 16),
        InsetGroup(
          color: adaptiveSurface2(context),
          radius: AppRadii.tile,
          children: [
            for (var i = 0; i < kinds.length; i++)
              _kindRow(kinds[i] as Map, maxKind, innerPos(i, kinds.length)),
          ],
        ),
      ],

      const SizedBox(height: 22),
      _label(l.t('subjects_section')),
      const SizedBox(height: 8),
      if (classes.isEmpty)
        _emptyLine(l.t('no_subjects_user'))
      else
        InsetGroup(
          color: adaptiveSurface2(context),
          radius: AppRadii.tile,
          children: [
            for (var i = 0; i < classes.length; i++)
              _classRow(l, classes[i] as Map, innerPos(i, classes.length)),
          ],
        ),
      if (generalTokens > 0) ...[
        const SizedBox(height: 8),
        Text(
          '${l.t('outside_subjects')}: ${fmtInt(generalTokens)} ${l.t('tokens').toLowerCase()}',
          style: TextStyle(fontSize: 13, color: adaptiveText4(context)),
        ),
      ],

      const SizedBox(height: 22),
      _label(l.t('study_activity_section')),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _Tile(value: fmtInt(activity['submissions']), label: l.t('submitted_works'), small: true)),
        const SizedBox(width: 8),
        Expanded(child: _Tile(value: fmtInt(activity['graded']), label: l.t('graded_works'), small: true)),
        const SizedBox(width: 8),
        Expanded(
          child: _Tile(
            value: activity['avg_score'] == null ? '—' : '${activity['avg_score']}',
            label: l.t('avg_score_label'),
            small: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Tile(
            value: fmtInt(role == 'student' ? activity['posts'] : activity['assignments_created']),
            label: role == 'student' ? l.t('posts_label') : l.t('assignments_label'),
            small: true,
          ),
        ),
      ]),
      const SizedBox(height: 12),
      InsetGroup(
        color: adaptiveSurface2(context),
        radius: AppRadii.tile,
        children: [
          _metaRow(l.t('last_activity'), fmtRelativeDate(d['last_active'] as String?, l), GroupPos.middle),
          _metaRow(l.t('registered_at'), fmtLongDate(d['created_at'] as String?, l), GroupPos.middle),
          _metaRow(l.t('account_id'), '#${d['id']}', GroupPos.last),
        ],
      ),

      const SizedBox(height: 22),
      _label(l.t('manage_section')),
      const SizedBox(height: 8),
      _roleSegment(l, role),
      const SizedBox(height: 12),
      InsetGroup(children: [
        _actionRow(
          pos: widget.isSelf ? GroupPos.last : GroupPos.middle,
          icon: unlimited ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt,
          color: C.amber,
          title: l.t('ai_unlimited'),
          subtitle: unlimited ? l.t('ai_unlimited_on_sub') : l.t('ai_unlimited_off_sub'),
          trailing: IgnorePointer(
              child: CupertinoLiquidSwitch(value: unlimited, onChanged: (_) {}, accent: C.amber)),
          onTap: () => _run('toggle_ai_unlimited', () => widget.row['ai_unlimited'] = !unlimited),
        ),
        if (!widget.isSelf)
          _actionRow(
            pos: GroupPos.middle,
            icon: blocked ? CupertinoIcons.lock_open : CupertinoIcons.nosign,
            color: blocked ? C.green : C.red,
            title: blocked ? l.t('unblock') : l.t('block'),
            subtitle: blocked ? l.t('unblock_sub') : l.t('block_sub'),
            onTap: () => _run(blocked ? 'unblock' : 'block', () => widget.row['is_active'] = blocked),
          ),
        if (!widget.isSelf)
          _actionRow(
            pos: GroupPos.last,
            icon: CupertinoIcons.trash,
            color: C.red,
            title: l.t('delete'),
            subtitle: l.t('delete_user_sub'),
            onTap: () async {
              if (_busy) return;
              setState(() => _busy = true);
              final ok = await widget.onAction('delete');
              if (!mounted) return;
              setState(() => _busy = false);
              if (ok) {
                widget.onDeleted?.call();
                Navigator.pop(context);
              }
            },
          ),
      ]),
      if (widget.isSelf) ...[
        const SizedBox(height: 10),
        Text(l.t('self_account_note'),
            style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
      ],
    ];
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: adaptiveText3(context))),
      );

  Widget _emptyLine(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: TextStyle(fontSize: 15, color: adaptiveText4(context))),
      );

  Widget _kindRow(Map k, int maxTokens, GroupPos pos) {
    final tokens = (k['total_tokens'] as num? ?? 0).toInt();
    final color = kindColor(context, (k['group'] ?? 'other').toString());
    return GroupRow(
      pos: pos,
      color: Colors.transparent,
      separatorInset: 12,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((k['label'] ?? k['endpoint'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText2(context))),
            const SizedBox(height: 5),
            MiniBar(value: maxTokens > 0 ? tokens / maxTokens : 0, color: color, height: 5),
          ]),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fmtInt(tokens),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: adaptiveTextSoft(context),
                  fontFeatures: const [FontFeature.tabularFigures()])),
          Text('${fmtInt(k['request_count'])} ${context.read<L10n>().t('requests_short')}',
              style: TextStyle(fontSize: 12, color: adaptiveText4(context))),
        ]),
      ]),
    );
  }

  Widget _classRow(L10n l, Map c, GroupPos pos) {
    return GroupRow(
      pos: pos,
      color: Colors.transparent,
      separatorInset: 12,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 34,
            height: 34,
            // Тон подложки — из палитры обложек (глиф в SubjectIconOverlay
            // белый, на сером фоне он был бы не виден).
            child: Stack(fit: StackFit.expand, children: [
              Container(color: kFallbackCoverOptions.colorFor(c['cover_color'] as String?).base),
              SubjectIconOverlay(
                  icon: c['cover_icon'] as String?, color: c['cover_color'] as String?, size: 17),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text((c['name'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.3, color: adaptiveTextSoft(context))),
        ),
        if ((c['role'] ?? '') == 'creator') ...[
          const SizedBox(width: 8),
          _Chip(text: l.t('creator_short'), color: adaptiveText4(context), small: true),
        ],
        const SizedBox(width: 10),
        Text(fmtInt(c['total_tokens']),
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: adaptiveText2(context),
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _metaRow(String label, String value, GroupPos pos) => GroupRow(
        pos: pos,
        color: Colors.transparent,
        separatorInset: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Text(label, style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: adaptiveTextSoft(context))),
          ),
        ]),
      );

  Widget _roleSegment(L10n l, String role) {
    final primary = Theme.of(context).colorScheme.primary;
    Widget seg(String value, String label, Color color) {
      final selected = role == value;
      return Expanded(
        child: Tappable(
          onTap: (selected || widget.isSelf || _busy) ? null : () => _run(value, () => widget.row['role'] = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? Theme.of(context).colorScheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(100),
              boxShadow: selected
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3, offset: const Offset(0, 1))]
                  : null,
            ),
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: -0.2,
                      color: selected ? color : adaptiveText3(context))),
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: widget.isSelf ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(100)),
        child: Row(children: [
          seg('student', l.t('role_student_short'), const Color(0xFF059669)),
          seg('teacher', l.t('role_teacher_short'), C.indigo),
          seg('admin', l.t('role_admin_short'), primary),
        ]),
      ),
    );
  }

  Widget _actionRow({
    required GroupPos pos,
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GroupRow(
      pos: pos,
      color: Colors.transparent,
      onTap: _busy ? null : onTap,
      separatorInset: 62,
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.4,
                    color: color == C.red ? C.red : adaptiveTextSoft(context))),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(subtitle, style: TextStyle(fontSize: 13, height: 1.3, color: adaptiveText4(context))),
              ),
          ]),
        ),
        if (trailing != null)
          trailing
        else
          Icon(CupertinoIcons.chevron_right, size: 14, color: adaptiveText4(context).withValues(alpha: 0.8)),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, this.small = false});

  final String value;
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                  fontSize: small ? 17 : 19,
                  fontWeight: small ? FontWeight.w600 : FontWeight.w700,
                  letterSpacing: -0.4,
                  color: adaptiveTextSoft(context),
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, height: 1.2, color: adaptiveText4(context))),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color, this.dot = false, this.small = false});

  final String text;
  final Color color;
  final bool dot;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        Text(text,
            style: TextStyle(
                fontSize: small ? 11 : 13, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: color)),
      ]),
    );
  }
}
