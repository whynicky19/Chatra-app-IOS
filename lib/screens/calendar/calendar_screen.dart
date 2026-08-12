import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/classes_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../classes/class_detail_screen.dart';
import '../../utils/dates.dart';
import '../../utils/nav_guard.dart';
import '../../widgets/tappable.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  Map<DateTime, List<dynamic>> _deadlineMap = {};
  Map<int, dynamic> _submissionMap = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiService>();
      final isStudent = !context.read<AuthProvider>().isTeacher;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final activeClassIds = context.read<ClassesProvider>()
          .classes
          .map((c) => (c['id'] as num).toInt())
          .toSet();

      final results = await Future.wait([
        api.getAssignments(),
        if (isStudent) api.getMySubmissions(),
      ]);

      if (!mounted) return;

      final allAssignments = results[0];
      final submissions = (isStudent && results.length > 1) ? results[1] : <dynamic>[];

      final assignments = allAssignments.where((a) {
        final classId = (a['class_id'] as num?)?.toInt();
        return classId != null && activeClassIds.contains(classId);
      }).toList();

      final subMap = <int, dynamic>{};
      for (final s in submissions) {
        final aid = (s['assignment_id'] as num?)?.toInt();
        if (aid != null) subMap[aid] = s;
      }

      final map = <DateTime, List<dynamic>>{};
      for (final a in assignments) {
        final dueStr = a['deadline'] as String?;
        if (dueStr == null) continue;
        final dt = parseServerDate(dueStr);
        if (dt == null) continue;
        final dueDay = DateTime(dt.year, dt.month, dt.day);
        if (dueDay.isBefore(today)) continue;
        map.putIfAbsent(dueDay, () => []).add(a);
      }

      setState(() {
        _deadlineMap = map;
        _submissionMap = subMap;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<dynamic> _getForDay(DateTime day) =>
      _deadlineMap[DateTime(day.year, day.month, day.day)] ?? [];

  String? _submissionStatus(dynamic assignment) {
    final id = (assignment['id'] as num?)?.toInt();
    if (id == null) return null;
    final sub = _submissionMap[id];
    return sub?['status'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? Center(child: CupertinoActivityIndicator(radius: 13, color: Theme.of(context).colorScheme.primary))
            : CustomScrollView(slivers: [
                  CupertinoSliverNavigationBar(
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    border: null,
                    stretch: true,
                    leading: Tappable(
                      onTap: () => Navigator.pop(context),
                      label: 'Назад',
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: softShadow(isDark),
                        ),
                        child: Icon(CupertinoIcons.chevron_left, size: 17, color: adaptiveText1(context)),
                      ),
                    ),
                    largeTitle: Text(l.t('deadlines'), style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w700,
                      color: adaptiveText1(context), letterSpacing: -0.4, height: 1.1,
                    )),
                  ),
                  CupertinoSliverRefreshControl(
                    onRefresh: () async {
                      setState(() => _loading = true);
                      await _load();
                    },
                  ),
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      _deadlineMap.isEmpty
                          ? l.t('no_upcoming_deadlines')
                          : '${l.t('upcoming_tasks')}: ${_deadlineMap.values.fold<int>(0, (n, list) => n + list.length)}',
                      style: TextStyle(fontSize: 13, color: adaptiveText3(context)),
                    ),
                  )),

                  SliverToBoxAdapter(child: _buildCalendar(isDark, today)),
                  SliverToBoxAdapter(child: _build7DayScroll(today, isDark)),
                  SliverToBoxAdapter(child: _buildDayList(isDark, today)),
                  SliverToBoxAdapter(child: SizedBox(height: bottomBarClearance(context))),
                ]),
      ),
    );
  }

  Widget _buildCalendar(bool isDark, DateTime today) {
    final l = context.read<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final leadingBlanks = (firstDay.weekday - 1) % 7;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: cardShadow(isDark),
      ),
      child: Column(children: [
        Row(children: [
          _navBtn(CupertinoIcons.chevron_left, () => setState(() =>
            _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1)), 'Предыдущий месяц'),
          Expanded(child: Text(
            '${l.t('months_full').split(',')[_focusedMonth.month - 1]} ${_focusedMonth.year}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
          )),
          _navBtn(CupertinoIcons.chevron_right, () => setState(() =>
            _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1)), 'Следующий месяц'),
        ]),
        const SizedBox(height: 12),
        Row(children: l.t('weekdays_short').split(',').map((d) => Expanded(
          child: Center(child: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: adaptiveText3(context)))),
        )).toList()),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1,
          children: [
            ...List.generate(leadingBlanks, (_) => const SizedBox()),
            ...List.generate(daysInMonth, (i) {
              final day = DateTime(_focusedMonth.year, _focusedMonth.month, i + 1);
              final deadlines = _getForDay(day);
              final isSelected = day == _selectedDay;
              final isToday = day == today;

              Color? dotColor;
              if (deadlines.isNotEmpty) {
                final allDone = deadlines.every((a) {
                  final s = _submissionStatus(a);
                  return s == 'submitted' || s == 'graded';
                });
                if (allDone) {
                  dotColor = C.green;
                } else if (deadlines.length > 1) {
                  dotColor = C.red;
                } else {
                  dotColor = Theme.of(context).colorScheme.primary;
                }
              }

              return Tappable(
                onTap: () => setState(() => _selectedDay = day),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : isToday
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                      shape: BoxShape.circle,
                      boxShadow: isSelected ? primaryGlow(Theme.of(context).colorScheme.primary, opacity: 0.28) : null,
                    ),
                    child: Center(child: Text('${i + 1}', style: TextStyle(
                      fontSize: 13, fontWeight: isSelected || isToday ? FontWeight.w600 : FontWeight.w600,
                      color: isSelected ? Colors.white
                          : (isToday ? Theme.of(context).colorScheme.primary : adaptiveText1(context)),
                    ))),
                  ),
                  if (dotColor != null)
                    Container(
                      width: 5, height: 5,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                    )
                  else
                    const SizedBox(height: 7),
                ]),
              );
            }),
          ],
        ),
        const SizedBox(height: 6),
        Divider(height: 1, color: adaptiveBorder(context).withValues(alpha: 0.5)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: _legendDot(Theme.of(context).colorScheme.primary, context.read<L10n>().t('cal_legend_due'))),
          const SizedBox(width: 12),
          Flexible(child: _legendDot(C.red, context.read<L10n>().t('cal_legend_multiple'))),
          const SizedBox(width: 12),
          Flexible(child: _legendDot(C.green, context.read<L10n>().t('cal_legend_done'))),
        ]),
      ]),
    );
  }

  Widget _legendDot(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Flexible(child: Text(label, style: TextStyle(fontSize: 11, color: adaptiveText3(context), fontWeight: FontWeight.w500),
      maxLines: 1, overflow: TextOverflow.ellipsis)),
  ]);

  Widget _navBtn(IconData icon, VoidCallback onTap, String label) => Tappable(
    onTap: onTap,
    label: label,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
    ),
  );

  Widget _build7DayScroll(DateTime today, bool isDark) {
    final l = context.read<L10n>();
    return SizedBox(
      height: 88,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: 7,
        itemBuilder: (_, i) {
          final day = today.add(Duration(days: i));
          final key = DateTime(day.year, day.month, day.day);
          final items = _deadlineMap[key] ?? [];
          final count = items.length;
          final isSelected = key == _selectedDay;
          final dayName = l.t('weekdays_short').split(',')[day.weekday - 1];
          final allDone = count > 0 && items.every((a) {
            final s = _submissionStatus(a);
            return s == 'submitted' || s == 'graded';
          });

          return Tappable(
            onTap: () => setState(() {
              _selectedDay = key;
              _focusedMonth = DateTime(key.year, key.month);
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.tile),
                boxShadow: isSelected ? primaryGlow(Theme.of(context).colorScheme.primary, opacity: 0.2) : softShadow(isDark),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(dayName, style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white70 : adaptiveText3(context),
                )),
                const SizedBox(height: 2),
                Text('${day.day}', style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
                )),
                if (count > 0) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : (allDone ? C.green.withValues(alpha: 0.15) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                    ),
                    child: Text('$count', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : (allDone ? C.green : Theme.of(context).colorScheme.primary),
                    )),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDayList(bool isDark, DateTime today) {
    final l = context.watch<L10n>();
    final items = _getForDay(_selectedDay);
    final tomorrow = today.add(const Duration(days: 1));
    final classNames = <int, String>{
      for (final c in context.read<ClassesProvider>().classes)
        if (c['id'] != null) (c['id'] as num).toInt(): (c['title'] ?? '').toString(),
    };
    final monthGen = l.t('months_genitive').split(',');
    final dayLabel = _selectedDay == today
        ? l.t('notif_today')
        : _selectedDay == tomorrow
            ? l.t('tomorrow')
            : '${_selectedDay.day} ${monthGen[_selectedDay.month - 1]}';

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.calendar_badge_plus, size: 52, color: C.text4.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(l.t('no_deadlines'), style: TextStyle(fontSize: 15, color: adaptiveText3(context))),
        ])),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
          child: Row(children: [
            Text(dayLabel.toUpperCase(), style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: adaptiveText3(context), letterSpacing: 1.0)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadii.chip)),
              child: Text('${items.length}', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary)),
            ),
          ]),
        ),
        ...items.map((a) {
          final dueStr = a['deadline'] as String?;
          final due = dueStr != null ? parseServerDate(dueStr) : null;
          final status = _submissionStatus(a);
          final isSubmitted = status == 'submitted' || status == 'graded';
          final classId = (a['class_id'] as num?)?.toInt();

          Color bg;
          if (isSubmitted) {
            bg = isDark ? C.green.withValues(alpha: 0.15) : C.greenLt;
          } else if (_selectedDay == today) {
            bg = isDark ? C.yellow.withValues(alpha: 0.1) : C.yellowLt;
          } else if (_selectedDay == tomorrow) {
            bg = adaptivePrimaryLt(context);
          } else {
            bg = Theme.of(context).colorScheme.surface;
          }

          final accentColor = isSubmitted ? C.green : Theme.of(context).colorScheme.primary;

          return Tappable(
            onTap: classId != null ? () => guardedPush(context, MaterialPageRoute(
              builder: (_) => ClassDetailScreen(classId: classId, initialTab: 1),
            )) : null,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppRadii.tile),
                boxShadow: cardShadow(isDark),
              ),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                  ),
                  child: Icon(isSubmitted ? CupertinoIcons.checkmark_alt : CupertinoIcons.clock,
                      size: 20, color: accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['title'] ?? '', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: adaptiveText1(context),
                  ), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (due != null) ...[
                      Icon(CupertinoIcons.clock, size: 12, color: isSubmitted ? C.green : C.text4),
                      const SizedBox(width: 3),
                      Text(
                        '${due.hour.toString().padLeft(2,'0')}:${due.minute.toString().padLeft(2,'0')}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSubmitted ? C.green : C.text3),
                      ),
                    ],
                    if (classId != null && (classNames[classId] ?? '').isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(child: Text(classNames[classId]!,
                        style: TextStyle(fontSize: 13, color: adaptiveText3(context)),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ]),
                ])),
                if (classId != null)
                  const Icon(CupertinoIcons.chevron_right, size: 18, color: C.text4),
              ]),
            ),
          );
        }),
      ]),
    );
  }
}
