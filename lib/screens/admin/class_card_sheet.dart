import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/cover_art.dart';
import '../../utils/errors.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/subject_cover.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';
import 'admin_format.dart';

/// Карточка предмета: состав с расходом каждого участника, потоки, содержимое
/// (лекции, задания, сдачи, средний балл), расход ИИ по видам и возврат
/// студентов из прошлых потоков.
Future<void> showClassCardSheet(
  BuildContext context, {
  required int classId,
  required String name,
  String? coverIcon,
  String? coverColor,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet))),
    builder: (_) => _ClassCardSheet(
      classId: classId,
      name: name,
      coverIcon: coverIcon,
      coverColor: coverColor,
    ),
  );
}

class _ClassCardSheet extends StatefulWidget {
  const _ClassCardSheet({
    required this.classId,
    required this.name,
    this.coverIcon,
    this.coverColor,
  });

  final int classId;
  final String name;
  final String? coverIcon;
  final String? coverColor;

  @override
  State<_ClassCardSheet> createState() => _ClassCardSheetState();
}

class _ClassCardSheetState extends State<_ClassCardSheet> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  String _memberQuery = '';

  List<dynamic> _rejoinable = const [];
  bool _rejoinLoading = true;
  final _adding = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
    _loadRejoinable();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      _detail = await context.read<ApiService>().adminClassDetail(widget.classId);
    } catch (e) {
      logError('AdminClassCard.load', e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRejoinable() async {
    try {
      final list = await context.read<ApiService>().getRejoinableStudents(widget.classId);
      if (mounted) setState(() => _rejoinable = list);
    } catch (e) {
      logError('AdminClassCard.rejoinable', e);
    }
    if (mounted) setState(() => _rejoinLoading = false);
  }

  Future<void> _returnStudent(Map<String, dynamic> u) async {
    final l = context.read<L10n>();
    final id = (u['id'] as num?)?.toInt();
    if (id == null || _adding.contains(id)) return;
    setState(() => _adding.add(id));
    try {
      await context.read<ApiService>().addClassMember(widget.classId, id);
      if (!mounted) return;
      setState(() => _rejoinable = _rejoinable.where((c) => (c['id'] as num?)?.toInt() != id).toList());
      showToast(context, l.t('student_returned'));
      await _load();
    } catch (e) {
      logError('AdminClassCard.returnStudent', e);
      if (mounted) showToast(context, l.t('error'), error: true);
    }
    if (mounted) setState(() => _adding.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final d = _detail;
    final base = kFallbackCoverOptions.colorFor(widget.coverColor ?? d?['cover_color'] as String?).base;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 12, 12),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.tile),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Stack(fit: StackFit.expand, children: [
                  Container(color: base),
                  SubjectIconOverlay(
                      icon: widget.coverIcon ?? d?['cover_icon'] as String?,
                      color: widget.coverColor ?? d?['cover_color'] as String?,
                      size: 26),
                ]),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d?['name']?.toString() ?? widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        height: 1.15,
                        color: adaptiveTextSoft(context))),
                if (d?['creator'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    ((d!['creator'] as Map)['full_name'] ?? (d['creator'] as Map)['email'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context)),
                  ),
                ],
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
        Container(height: hairline(context), color: groupSeparator(context)),
        Expanded(
          child: _loading && d == null
              ? const Center(child: CupertinoActivityIndicator(radius: 13))
              : d == null
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
                      children: _body(l, d),
                    ),
        ),
      ]),
    );
  }

  List<Widget> _body(L10n l, Map<String, dynamic> d) {
    final ai = (d['ai'] as Map?)?.cast<String, dynamic>() ?? const {};
    final content = (d['content'] as Map?)?.cast<String, dynamic>() ?? const {};
    final kinds = (ai['by_endpoint'] as List?) ?? const [];
    final cohorts = (d['cohorts'] as List?) ?? const [];
    final members = (d['members'] as List?) ?? const [];
    final totalTokens = (ai['total_tokens'] as num? ?? 0).toInt();
    final inviteCode = (d['invite_code'] ?? '').toString();
    final description = (d['description'] ?? '').toString();

    final needle = _memberQuery.trim().toLowerCase();
    final shownMembers = needle.isEmpty
        ? members
        : members.where((m) {
            final map = m as Map;
            return (map['email'] ?? '').toString().toLowerCase().contains(needle) ||
                (map['full_name'] ?? '').toString().toLowerCase().contains(needle);
          }).toList();

    return [
      if (description.isNotEmpty) ...[
        Text(description,
            style: TextStyle(fontSize: 15, height: 1.4, letterSpacing: -0.2, color: adaptiveText3(context))),
        const SizedBox(height: 16),
      ],

      // Ключевые числа предмета одной строкой.
      Row(children: [
        Expanded(child: _Tile(value: fmtInt(d['member_count']), label: l.t('members_label'))),
        const SizedBox(width: 8),
        Expanded(child: _Tile(value: fmtCompact(totalTokens, l), label: l.t('tokens').toLowerCase())),
        const SizedBox(width: 8),
        Expanded(child: _Tile(value: fmtInt(content['assignments']), label: l.t('assignments_label'))),
      ]),
      if (inviteCode.isNotEmpty) ...[
        const SizedBox(height: 10),
        GroupRow.card(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: inviteCode));
            if (mounted) showToast(context, l.t('code_copied'));
          },
          child: Row(children: [
            Icon(CupertinoIcons.person_badge_plus, size: 18, color: adaptiveText4(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l.t('invite_code_label'),
                  style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText3(context))),
            ),
            Text(inviteCode,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: Theme.of(context).colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.doc_on_doc, size: 15, color: adaptiveText4(context)),
          ]),
        ),
      ],

      const SizedBox(height: 22),
      _label(l.t('content_section')),
      const SizedBox(height: 8),
      InsetGroup(
        color: adaptiveSurface2(context),
        radius: AppRadii.tile,
        children: [
          _metaRow(l.t('lectures_label'), fmtInt(content['lectures']), GroupPos.middle),
          _metaRow(l.t('assignments_active_label'),
              '${fmtInt(content['assignments_active'])} / ${fmtInt(content['assignments'])}', GroupPos.middle),
          _metaRow(l.t('submissions_label'), fmtInt(content['submissions']), GroupPos.middle),
          _metaRow(
            l.t('avg_score_label'),
            content['avg_score'] == null
                ? '—'
                : '${content['avg_score']} · ${fmtInt(content['graded'])} ${l.t('graded_short')}',
            GroupPos.last,
          ),
        ],
      ),

      const SizedBox(height: 22),
      _label(l.t('ai_usage_section')),
      const SizedBox(height: 8),
      if (kinds.isEmpty)
        _emptyLine(l.t('no_ai_in_subject'))
      else ...[
        _SplitBar(
          segments: [
            for (final k in kinds)
              (
                ((k as Map)['total_tokens'] as num? ?? 0).toInt(),
                kindColor(context, (k['group'] ?? 'other').toString()),
              ),
          ],
        ),
        const SizedBox(height: 12),
        InsetGroup(
          color: adaptiveSurface2(context),
          radius: AppRadii.tile,
          children: [
            for (var i = 0; i < kinds.length; i++)
              _kindRow(l, kinds[i] as Map, innerPos(i, kinds.length)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${l.t('prompt_short')} ${fmtInt(ai['prompt_tokens'])} · ${l.t('completion_short')} ${fmtInt(ai['completion_tokens'])}'
          '${ai['last_used'] != null ? ' · ${fmtRelativeDate(ai['last_used'] as String?, l)}' : ''}',
          style: TextStyle(fontSize: 13, color: adaptiveText4(context)),
        ),
      ],

      if (cohorts.isNotEmpty) ...[
        const SizedBox(height: 22),
        _label(l.t('cohorts_section')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in cohorts) _cohortChip(l, c as Map),
        ]),
      ],

      const SizedBox(height: 22),
      _label('${l.t('members_label')} · ${members.length}'),
      const SizedBox(height: 8),
      if (members.length > 6) ...[
        CupertinoSearchTextField(
          placeholder: l.t('find_member'),
          backgroundColor: adaptiveSurface2(context),
          style: TextStyle(fontSize: 16, letterSpacing: -0.3, color: adaptiveTextSoft(context)),
          placeholderStyle: TextStyle(fontSize: 16, letterSpacing: -0.3, color: adaptiveText4(context)),
          itemColor: adaptiveText4(context),
          onChanged: (v) => setState(() => _memberQuery = v),
        ),
        const SizedBox(height: 10),
      ],
      if (shownMembers.isEmpty)
        _emptyLine(members.isEmpty ? l.t('no_students_class') : l.t('nobody_found'))
      else
        InsetGroup(
          color: adaptiveSurface2(context),
          radius: AppRadii.tile,
          children: [
            for (var i = 0; i < shownMembers.length; i++)
              _memberRow(l, shownMembers[i] as Map, innerPos(i, shownMembers.length)),
          ],
        ),

      const SizedBox(height: 22),
      _label(l.t('return_student')),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(l.t('return_student_hint'),
            style: TextStyle(fontSize: 13, height: 1.35, color: adaptiveText4(context))),
      ),
      if (_rejoinLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CupertinoActivityIndicator(radius: 10)),
        )
      else if (_rejoinable.isEmpty)
        _emptyLine(l.t('no_archived_students'))
      else
        InsetGroup(
          color: adaptiveSurface2(context),
          radius: AppRadii.tile,
          children: [
            for (var i = 0; i < _rejoinable.length; i++)
              _rejoinRow(l, _rejoinable[i] as Map<String, dynamic>, innerPos(i, _rejoinable.length)),
          ],
        ),
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

  Widget _metaRow(String label, String value, GroupPos pos) => GroupRow(
        pos: pos,
        color: Colors.transparent,
        separatorInset: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context))),
          ),
          const SizedBox(width: 12),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: adaptiveTextSoft(context),
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );

  Widget _kindRow(L10n l, Map k, GroupPos pos) {
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
          child: Text((k['label'] ?? k['endpoint'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText2(context))),
        ),
        const SizedBox(width: 10),
        Text('${fmtInt(k['request_count'])} ${l.t('requests_short')}',
            style: TextStyle(fontSize: 12, color: adaptiveText4(context))),
        const SizedBox(width: 10),
        Text(fmtInt(k['total_tokens']),
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: adaptiveTextSoft(context),
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _cohortChip(L10n l, Map c) {
    final active = (c['status'] ?? '') == 'active';
    final primary = Theme.of(context).colorScheme.primary;
    final count = (c['student_count'] as num? ?? 0).toInt();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: active ? primary.withValues(alpha: 0.10) : adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: active
            ? Border.all(color: primary.withValues(alpha: 0.28), width: hairline(context))
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((c['academic_year'] ?? '').toString(),
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: adaptiveTextSoft(context))),
        const SizedBox(height: 1),
        Text(
          '${active ? l.t('cohort_active') : l.t('cohort_archived')} · $count',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: active ? primary : adaptiveText4(context)),
        ),
      ]),
    );
  }

  Widget _memberRow(L10n l, Map m, GroupPos pos) {
    final id = (m['id'] as num?)?.toInt() ?? 0;
    final name = (m['full_name'] ?? '').toString().trim();
    final email = (m['email'] ?? '').toString();
    final display = name.isNotEmpty ? name : email.split('@').first;
    final role = (m['role'] ?? '').toString();
    final roleLabel = role == 'teacher' || role == 'admin'
        ? l.t('role_teacher_short')
        : l.t('role_student_short');
    return GroupRow(
      pos: pos,
      color: Colors.transparent,
      separatorInset: 12,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Row(children: [
        InitialsAvatar(id: id, name: display, size: 32, radius: 10),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.3,
                        color: adaptiveTextSoft(context))),
              ),
              if (m['is_active'] == false) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration:
                      BoxDecoration(color: C.red.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
                  child: Text(l.t('blocked_short'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.red)),
                ),
              ],
            ]),
            const SizedBox(height: 1),
            Text('$roleLabel · ${fmtRelativeDate(m['last_active'] as String?, l)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: adaptiveText4(context))),
          ]),
        ),
        const SizedBox(width: 10),
        Text(fmtInt(m['total_tokens']),
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: adaptiveText2(context),
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _rejoinRow(L10n l, Map<String, dynamic> u, GroupPos pos) {
    final id = (u['id'] as num?)?.toInt() ?? 0;
    final display = (u['full_name'] ?? u['email'] ?? '').toString();
    final busy = _adding.contains(id);
    return GroupRow(
      pos: pos,
      color: Colors.transparent,
      separatorInset: 12,
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      onTap: busy ? null : () => _returnStudent(u),
      child: Row(children: [
        InitialsAvatar(id: id, name: display, size: 32, radius: 10),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.3, color: adaptiveTextSoft(context))),
            Text((u['email'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: adaptiveText4(context))),
          ]),
        ),
        const SizedBox(width: 10),
        busy
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: CupertinoActivityIndicator(radius: 9),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(l.t('return_add'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.3,
                        color: Theme.of(context).colorScheme.primary)),
              ),
      ]),
    );
  }
}

/// Полоса «часть от целого»: доли видов расхода одной строкой, с зазором
/// поверхностью между сегментами (а не обводкой — она добавила бы «чернил»).
class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.segments});

  final List<(int value, Color color)> segments;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (s, e) => s + e.$1);
    if (total <= 0) return const SizedBox.shrink();
    return SizedBox(
      height: 12,
      child: Row(children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            flex: (segments[i].$1 * 1000 ~/ total).clamp(1, 1000),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: segments[i].$2,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(i == 0 ? 6 : 3),
                  right: Radius.circular(i == segments.length - 1 ? 6 : 3),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label});

  final String value;
  final String label;

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
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
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
