import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/dates.dart';
import '../../widgets/cupertino_date_sheet.dart';
import '../../widgets/toast.dart';

/// «Задания и дедлайны» в настройках предмета: учитель выбирает поток,
/// видит все задания потока (с дедлайном и без), может править дату,
/// переключать «без срока», публиковать по одному или все черновики разом.
///
/// Стиль — переиспользует общую палитру приложения (adaptiveSurface2, AppRadii,
/// C.text1..4), аналогично `rollover_screen.dart` и `class_detail_screen.dart`,
/// чтобы экран выглядел естественной частью настроек, а не отдельной админ-панелью.
class CohortDeadlinesScreen extends StatefulWidget {
  final int classId;
  final List<dynamic> cohorts;
  final int? initialCohortId;
  const CohortDeadlinesScreen({
    super.key,
    required this.classId,
    required this.cohorts,
    this.initialCohortId,
  });

  @override
  State<CohortDeadlinesScreen> createState() => _CohortDeadlinesScreenState();
}

class _CohortDeadlinesScreenState extends State<CohortDeadlinesScreen> {
  late int? _selectedCohortId;
  List<dynamic> _deadlines = [];
  bool _loading = false;
  bool _busy = false;
  // В кеше — id дедлайнов, на которых прямо сейчас крутится операция
  // (правка даты / переключение / публикация) — чтобы не давать двойные клики.
  final Set<int> _pending = {};

  @override
  void initState() {
    super.initState();
    _selectedCohortId = widget.initialCohortId ??
        _firstActiveId() ??
        (widget.cohorts.isNotEmpty ? (widget.cohorts.first['id'] as num).toInt() : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  int? _firstActiveId() {
    for (final c in widget.cohorts) {
      if (c['status'] == 'active') return (c['id'] as num).toInt();
    }
    return null;
  }

  Map<String, dynamic>? _selectedCohort() {
    if (_selectedCohortId == null) return null;
    for (final c in widget.cohorts) {
      if ((c['id'] as num).toInt() == _selectedCohortId) {
        return c as Map<String, dynamic>;
      }
    }
    return null;
  }

  bool get _isArchivedSelected => _selectedCohort()?['status'] == 'archived';

  int get _draftsCount => _deadlines.where((d) => d['is_published'] != true).length;

  Future<void> _load() async {
    if (_selectedCohortId == null) return;
    setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      final list = await api.getCohortDeadlines(_selectedCohortId!);
      if (!mounted) return;
      setState(() {
        _deadlines = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toastError(e);
    }
  }

  void _toastError(Object e) {
    final l = context.read<L10n>();
    String msg = l.t('cd_error');
    if (e is Exception) {
      final stripped = e.toString().replaceFirst('Exception: ', '');
      if (stripped.isNotEmpty) msg = stripped;
    }
    showToast(context, msg, error: true);
  }

  Future<void> _onCohortChanged(int? id) async {
    setState(() => _selectedCohortId = id);
    await _load();
  }

  Future<void> _editDate(dynamic d) async {
    final due = parseServerDate((d['due_date'] ?? '').toString()) ?? DateTime.now();
    final newDt = await showCupertinoDateTimeSheet(
      context,
      initialDateTime: due,
      minimumDate: DateTime(2020),
      maximumDate: DateTime(2100),
      title: d['assignment_title']?.toString() ?? '#${d['assignment_id']}',
    );
    if (newDt == null || !mounted) return;
    final id = (d['id'] as num).toInt();
    if (_pending.contains(id)) return;
    setState(() => _pending.add(id));
    try {
      final updated = await context
          .read<ApiService>()
          .updateDeadline(id, dueDate: toServerDateString(newDt));
      if (!mounted) return;
      setState(() {
        final i = _deadlines.indexWhere((x) => (x['id'] as num).toInt() == id);
        if (i >= 0) _deadlines[i] = updated;
      });
      showToast(context, context.read<L10n>().t('deadline_updated'));
    } catch (e) {
      _toastError(e);
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  Future<void> _toggleNoDeadline(dynamic d) async {
    final id = (d['id'] as num).toInt();
    if (_pending.contains(id)) return;
    final next = !(d['no_deadline'] == true);
    setState(() => _pending.add(id));
    try {
      final updated = await context
          .read<ApiService>()
          .updateDeadline(id, noDeadline: next);
      if (!mounted) return;
      setState(() {
        final i = _deadlines.indexWhere((x) => (x['id'] as num).toInt() == id);
        if (i >= 0) _deadlines[i] = updated;
      });
    } catch (e) {
      _toastError(e);
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  Future<void> _publishOne(dynamic d) async {
    final id = (d['id'] as num).toInt();
    if (_pending.contains(id)) return;
    setState(() => _pending.add(id));
    try {
      final updated = await context
          .read<ApiService>()
          .updateDeadline(id, isPublished: true);
      if (!mounted) return;
      setState(() {
        final i = _deadlines.indexWhere((x) => (x['id'] as num).toInt() == id);
        if (i >= 0) _deadlines[i] = updated;
      });
      showToast(context, context.read<L10n>().t('cd_published'));
    } catch (e) {
      _toastError(e);
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  Future<void> _publishAll() async {
    if (_selectedCohortId == null) return;
    setState(() => _busy = true);
    try {
      final res = await context
          .read<ApiService>()
          .publishAllDeadlines(_selectedCohortId!);
      final n = (res['published'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      // Локально отражаем: все is_published → true.
      setState(() {
        _deadlines = _deadlines
            .map((x) => Map<String, dynamic>.from(x as Map)..['is_published'] = true)
            .toList();
      });
      final l = context.read<L10n>();
      showToast(context, l.t('cd_published_n').replaceAll('{n}', '$n'));
    } catch (e) {
      _toastError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _labelForCohort(Map<String, dynamic> c) {
    final year = (c['academic_year'] ?? '').toString();
    final isActive = c['status'] == 'active';
    final l = context.read<L10n>();
    return isActive ? '$year · ${l.t('active_cohort')}' : year;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l.t('cd_title')),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: adaptiveText1(context),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _subtitle(l),
            ),
            if (widget.cohorts.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _cohortSelector(l, primary),
              ),
            if (_isArchivedSelected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _archiveNotice(l),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? Center(
                      child: CupertinoActivityIndicator(
                          radius: 13, color: primary),
                    )
                  : _body(l, primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subtitle(L10n l) => Padding(
        padding: const EdgeInsets.only(left: 2, right: 2, top: 2),
        child: Text(l.t('cd_subtitle'),
            style: TextStyle(
                fontSize: 13,
                color: adaptiveText3(context),
                height: 1.45)),
      );

  Widget _archiveNotice(L10n l) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(AppRadii.tile),
          border: Border.all(color: adaptiveBorder(context)),
        ),
        child: Row(children: [
          Icon(CupertinoIcons.eye, size: 14, color: adaptiveText3(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l.t('cd_viewing_archive'),
                style: TextStyle(
                    fontSize: 12.5,
                    color: adaptiveText3(context),
                    fontWeight: FontWeight.w500)),
          ),
        ]),
      );

  Widget _cohortSelector(L10n l, Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _isArchivedSelected
            ? primary.withValues(alpha: 0.10)
            : adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: _isArchivedSelected
            ? Border.all(color: primary.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(children: [
        Icon(CupertinoIcons.calendar,
            size: 15, color: _isArchivedSelected ? primary : C.text4),
        const SizedBox(width: 8),
        Text('${l.t('cd_select_cohort')}:',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    _isArchivedSelected ? primary : adaptiveText3(context))),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              isExpanded: true,
              isDense: true,
              value: _selectedCohortId,
              icon: Icon(CupertinoIcons.chevron_down,
                  size: 14, color: adaptiveText3(context)),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: adaptiveText1(context)),
              items: [
                for (final c in widget.cohorts)
                  DropdownMenuItem<int?>(
                    value: (c['id'] as num).toInt(),
                    child: Text(
                        _labelForCohort(c as Map<String, dynamic>),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => _onCohortChanged(v),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _body(L10n l, Color primary) {
    if (_deadlines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.tray,
                  size: 36,
                  color: adaptiveText1(context).withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(l.t('cd_no_assignments'),
                  style: TextStyle(
                      fontSize: 14, color: adaptiveText3(context))),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _publishAllBar(l, primary),
        const SizedBox(height: 4),
        for (final d in _deadlines) _row(l, primary, d),
      ],
    );
  }

  Widget _publishAllBar(L10n l, Color primary) {
    if (_draftsCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(CupertinoIcons.checkmark_seal_fill,
              size: 14, color: const Color(0xFF2EBD6F)),
          const SizedBox(width: 6),
          Text(l.t('cd_no_drafts'),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: adaptiveText3(context))),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(AppRadii.tile),
          border: Border.all(color: adaptiveBorder(context)),
        ),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24),
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
            child: Text('$_draftsCount',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF342900))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l.t('draft'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: adaptiveText1(context))),
          ),
          AppButton(
            label: l.t('publish_all'),
            loading: _busy,
            onPressed: _busy ? null : _publishAll,
            primary: primary,
            dense: true,
          ),
        ]),
      ),
    );
  }

  Widget _row(L10n l, Color primary, dynamic d) {
    final id = (d['id'] as num).toInt();
    final isPending = _pending.contains(id);
    final title = (d['assignment_title'] ?? '#${d['assignment_id']}').toString();
    final published = d['is_published'] == true;
    final shifted = d['was_shifted'] == true;
    final noDl = d['no_deadline'] == true;
    final due = parseServerDate((d['due_date'] ?? '').toString());

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: isPending ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.tile),
            border: Border.all(color: adaptiveBorder(context)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: adaptiveText1(context),
                          height: 1.3)),
                  if (shifted) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(AppRadii.chip),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(CupertinoIcons.exclamationmark_triangle,
                            size: 11, color: Color(0xFFB45309)),
                        const SizedBox(width: 4),
                        Text(l.t('cd_was_shifted'),
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFB45309))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(children: [
                    if (noDl) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: adaptiveSurface2(context),
                          borderRadius: BorderRadius.circular(AppRadii.chip),
                          border: Border.all(color: adaptiveBorder(context)),
                        ),
                        child: Text(l.t('cd_no_deadline'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: adaptiveText3(context))),
                      ),
                    ] else ...[
                      GestureDetector(
                        onTap: isPending ? null : () => _editDate(d),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: adaptiveSurface2(context),
                            borderRadius:
                                BorderRadius.circular(AppRadii.button),
                            border: Border.all(color: adaptiveBorder(context)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(CupertinoIcons.calendar,
                                size: 12, color: C.text4),
                            const SizedBox(width: 5),
                            Text(due != null ? fmtDateTimeLocal(due.toIso8601String()) : '—',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: adaptiveText1(context),
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    if (published)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2EBD6F).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppRadii.chip),
                        ),
                        child: Text(l.t('cd_published'),
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2EBD6F))),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadii.chip),
                        ),
                        child: Text(l.t('draft'),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: primary)),
                      ),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (noDl)
                  AppButton(
                    label: l.t('cd_add_due'),
                    onPressed: isPending ? null : () => _toggleNoDeadline(d),
                    primary: primary,
                    outline: true,
                    dense: true,
                  )
                else
                  _iconAction(
                    icon: CupertinoIcons.calendar_badge_minus,
                    tooltip: l.t('cd_drop_due'),
                    onTap: isPending ? null : () => _toggleNoDeadline(d),
                  ),
                const SizedBox(height: 6),
                if (published)
                  _iconAction(
                    icon: CupertinoIcons.checkmark_seal,
                    color: const Color(0xFF2EBD6F),
                    tooltip: l.t('cd_published'),
                    onTap: null,
                  )
                else
                  AppButton(
                    label: l.t('cd_publish'),
                    onPressed: isPending ? null : () => _publishOne(d),
                    primary: primary,
                    dense: true,
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final c = color ?? adaptiveText3(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap == null
                ? adaptiveSurface2(context)
                : c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadii.tile),
            border: Border.all(
                color: onTap == null
                    ? adaptiveBorder(context)
                    : c.withValues(alpha: 0.20)),
          ),
          child: Icon(icon, size: 15, color: c),
        ),
      ),
    );
  }
}

/// Минималистичная кнопка в стиле приложения (тонкая обводка для outline,
/// заливка primary для обычной). Используется в строке дедлайна и в шапке
/// «Опубликовать все» — чтобы не тянуть большой `AppButton` из общих виджетов.
class AppButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final Color primary;
  final bool outline;
  final bool dense;
  const AppButton({
    super.key,
    required this.label,
    required this.primary,
    this.loading = false,
    this.onPressed,
    this.outline = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final paddingV = dense ? 6.0 : 9.0;
    final paddingH = dense ? 11.0 : 14.0;
    final fontSize = dense ? 12.5 : 13.5;
    final bg = outline
        ? Colors.transparent
        : (enabled ? primary : primary.withValues(alpha: 0.4));
    final fg = outline
        ? (enabled ? primary : primary.withValues(alpha: 0.5))
        : Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.7,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: paddingH, vertical: paddingV),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadii.button),
            border: outline
                ? Border.all(
                    color: enabled
                        ? primary.withValues(alpha: 0.45)
                        : primary.withValues(alpha: 0.20),
                    width: 1.2)
                : null,
          ),
          child: loading
              ? SizedBox(
                  width: fontSize,
                  height: fontSize,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(fg)),
                )
              : Text(label,
                  style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                      letterSpacing: 0)),
        ),
      ),
    );
  }
}
