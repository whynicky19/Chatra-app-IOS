import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';
import '../../utils/dates.dart';

class RolloverScreen extends StatefulWidget {
  const RolloverScreen({super.key});
  @override
  State<RolloverScreen> createState() => _RolloverScreenState();
}

class _RolloverScreenState extends State<RolloverScreen> {
  int _step = 0;
  bool _loading = true;
  bool _busy = false;

  List<dynamic> _preview = [];
  final Set<int> _checked = {};
  final _yearCtrl = TextEditingController();
  String? _yearError;
  DateTime? _startDate;

  final List<_RolledCohort> _rolled = [];

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() => _loading = true);
    try {
      final items = await context.read<ApiService>().getRolloverPreview();
      if (!mounted) return;
      _preview = items;
      _checked
        ..clear()
        ..addAll(items.map((e) => (e['class_id'] as num).toInt()));
      _prefillYearAndDate(items);
    } catch (_) {
      if (mounted) _preview = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _prefillYearAndDate(List<dynamic> items) {
    if (items.isEmpty) return;
    final current = (items.first['academic_year'] ?? '').toString();
    final m = RegExp(r'^(\d{4})/(\d{4})$').firstMatch(current);
    if (m != null) {
      final y1 = int.parse(m.group(1)!) + 1;
      final y2 = int.parse(m.group(2)!) + 1;
      _yearCtrl.text = '$y1/$y2';
      _startDate = DateTime(y1, 9, 1);
    }
  }

  bool get _yearValid => RegExp(r'^\d{4}/\d{4}$').hasMatch(_yearCtrl.text.trim());

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _confirmRollover(L10n l) async {
    setState(() => _yearError = _yearValid ? null : l.t('academic_year_invalid'));
    if (!_yearValid || _startDate == null || _checked.isEmpty) return;

    setState(() => _busy = true);
    try {
      final api = context.read<ApiService>();
      final d = _startDate!;
      final startStr =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final results = await api.rollover(
        _checked.toList(),
        newAcademicYear: _yearCtrl.text.trim(),
        newStartDate: startStr,
      );
      if (!mounted) return;

      _rolled.clear();
      for (final r in results) {
        final status = (r['status'] ?? '').toString();
        final newCohortId = (r['new_cohort_id'] as num?)?.toInt();
        if (status == 'rolled' && newCohortId != null) {
          final className = _preview.firstWhere(
            (p) => (p['class_id'] as num).toInt() == (r['class_id'] as num).toInt(),
            orElse: () => {'class_name': ''},
          )['class_name'];
          _rolled.add(_RolledCohort(
            cohortId: newCohortId,
            className: (className ?? '').toString(),
          ));
        }
      }

      final rolledCount = results.where((r) => r['status'] == 'rolled').length;
      showToast(context, '${l.t('rollover_done')} · $rolledCount');

      if (_rolled.isEmpty) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _busy = false;
        _step = 1;
      });
      _loadDeadlines();
    } catch (_) {
      if (mounted) {
        showToast(context, l.t('rollover_conflict'), error: true);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loadDeadlines() async {
    final api = context.read<ApiService>();
    setState(() => _loading = true);
    for (final rc in _rolled) {
      try {
        rc.deadlines = await api.getCohortDeadlines(rc.cohortId);
      } catch (_) {
        rc.deadlines = [];
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _editDeadline(_RolledCohort rc, dynamic deadline) async {
    final current = parseServerDate((deadline['due_date'] ?? '').toString()) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted) return;
    final newDt = DateTime(date.year, date.month, date.day,
        time?.hour ?? current.hour, time?.minute ?? current.minute);
    try {
      final updated = await context.read<ApiService>()
          .updateDeadline((deadline['id'] as num).toInt(), dueDate: toServerDateString(newDt));
      if (!mounted) return;
      setState(() {
        final idx = rc.deadlines.indexWhere((d) => d['id'] == deadline['id']);
        if (idx >= 0) rc.deadlines[idx] = updated;
      });
    } catch (_) {
      if (mounted) showToast(context, context.read<L10n>().t('rollover_conflict'), error: true);
    }
  }

  Future<void> _publishAll(L10n l) async {
    setState(() => _busy = true);
    final api = context.read<ApiService>();
    int total = 0;
    for (final rc in _rolled) {
      try {
        final res = await api.publishAllDeadlines(rc.cohortId);
        total += (res['published'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    if (!mounted) return;
    showToast(context, '${l.t('deadlines_published')} · $total');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(children: [
          _header(l),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary, strokeWidth: 2.5))
                : _step == 0
                    ? _previewStep(l)
                    : _deadlinesStep(l),
          ),
        ]),
      ),
    );
  }

  Widget _header(L10n l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(children: [
        GestureDetector(
          onTap: () => _step == 1 && !_loading
              ? setState(() => _step = 0)
              : Navigator.pop(context),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
                color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
            child: Icon(CupertinoIcons.chevron_left, size: 20, color: adaptiveText1(context)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_step == 0 ? l.t('new_academic_year') : l.t('review_deadlines'),
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700,
                    color: adaptiveText1(context), letterSpacing: -0.3)),
            Text(_step == 0 ? l.t('rollover_preview_sub') : l.t('review_deadlines_sub'),
                style: const TextStyle(fontSize: 12, color: C.text4)),
          ]),
        ),
      ]),
    );
  }

  Widget _previewStep(L10n l) {
    final primary = Theme.of(context).colorScheme.primary;
    if (_preview.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(CupertinoIcons.calendar_badge_plus, size: 44, color: C.text4),
            const SizedBox(height: 14),
            Text(l.t('rollover_no_classes'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.text4)),
          ]),
        ),
      );
    }
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          children: [
            for (final p in _preview) _previewCard(l, p),
            const SizedBox(height: 16),
            _label(l.t('academic_year')),
            TextField(
              controller: _yearCtrl,
              onChanged: (_) { if (_yearError != null) setState(() => _yearError = null); },
              decoration: InputDecoration(
                hintText: l.t('academic_year_hint'),
                errorText: _yearError,
              ),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: 16),
            _label(l.t('semester_start_date')),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _startDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _startDate = d);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                decoration: BoxDecoration(
                    color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Icon(CupertinoIcons.calendar, size: 18, color: primary),
                  const SizedBox(width: 10),
                  Text(_startDate != null ? _fmtDate(_startDate!) : '—',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                          color: adaptiveText1(context))),
                ]),
              ),
            ),
          ],
        ),
      ),
      _bottomBar(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
          onPressed: (_busy || _checked.isEmpty) ? null : () => _confirmRollover(l),
          child: _busy
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('${l.t('rollover_confirm')} (${_checked.length})'),
        ),
      ),
    ]);
  }

  Widget _previewCard(L10n l, dynamic p) {
    final id = (p['class_id'] as num).toInt();
    final checked = _checked.contains(id);
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => checked ? _checked.remove(id) : _checked.add(id));
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: checked ? primary.withValues(alpha: 0.5) : adaptiveBorder(context)),
          ),
          child: Row(children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: checked ? primary : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: checked ? primary : C.text4, width: 1.6),
              ),
              child: checked
                  ? const Icon(CupertinoIcons.check_mark, size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((p['class_name'] ?? '').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: adaptiveText1(context))),
                const SizedBox(height: 3),
                Text('${p['academic_year']}  ·  '
                    '${p['student_count']} ${l.t('students_count')}  ·  '
                    '${p['assignment_count']} ${l.t('assignments_count')}',
                    style: const TextStyle(fontSize: 12, color: C.text4)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _deadlinesStep(L10n l) {
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          children: [
            for (final rc in _rolled) ...[
              if (rc.className.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Text(rc.className,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                          color: adaptiveText1(context))),
                ),
              if (rc.deadlines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text(l.t('no_assignments'),
                      style: const TextStyle(fontSize: 13, color: C.text4)),
                )
              else
                for (final d in rc.deadlines) _deadlineRow(l, rc, d),
            ],
          ],
        ),
      ),
      _bottomBar(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
          onPressed: _busy ? null : () => _publishAll(l),
          child: _busy
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(l.t('publish_all')),
        ),
      ),
    ]);
  }

  Widget _deadlineRow(L10n l, _RolledCohort rc, dynamic d) {
    final due = parseServerDate((d['due_date'] ?? '').toString());
    final published = d['is_published'] == true;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _editDeadline(rc, d),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.tile),
            border: Border.all(color: adaptiveBorder(context)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((d['assignment_title'] ?? '#${d['assignment_id']}').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: adaptiveText1(context))),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(CupertinoIcons.calendar, size: 12, color: C.text4),
                  const SizedBox(width: 5),
                  Text(due != null ? _fmtDateTime(due) : '—',
                      style: const TextStyle(fontSize: 12, color: C.text4)),
                  if (!published) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(l.t('draft'),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                              color: primary)),
                    ),
                  ],
                ]),
              ]),
            ),
            Icon(CupertinoIcons.pencil, size: 16, color: primary),
          ]),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: C.text4, letterSpacing: 0.5)),
      );

  Widget _bottomBar({required Widget child}) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: SizedBox(width: double.infinity, child: child),
      );
}

class _RolledCohort {
  final int cohortId;
  final String className;
  List<dynamic> deadlines = [];
  _RolledCohort({required this.cohortId, required this.className});
}
