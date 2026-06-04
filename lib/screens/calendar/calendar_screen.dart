import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../classes/class_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  Map<DateTime, List<dynamic>> _deadlineMap = {};
  bool _loading = true;

  static const _monthNamesRU = [
    'Январь','Февраль','Март','Апрель','Май','Июнь',
    'Июль','Август','Сентябрь','Октябрь','Ноябрь','Декабрь',
  ];
  static const _weekDays = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    try {
      final api = context.read<ApiService>();
      final list = await api.getAssignments();
      if (!mounted) return;
      final map = <DateTime, List<dynamic>>{};
      for (final a in list) {
        final dueStr = a['due_date'] as String?;
        if (dueStr == null) continue;
        final dt = DateTime.tryParse(dueStr);
        if (dt == null) continue;
        final key = DateTime(dt.year, dt.month, dt.day);
        map.putIfAbsent(key, () => []).add(a);
      }
      setState(() {
        _deadlineMap = map;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<dynamic> _getForDay(DateTime day) =>
      _deadlineMap[DateTime(day.year, day.month, day.day)] ?? [];

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: C.teal, strokeWidth: 2))
            : RefreshIndicator(
                color: C.teal,
                onRefresh: () async {
                  setState(() => _loading = true);
                  await _loadAssignments();
                },
                child: CustomScrollView(slivers: [
                  // ── Title ──
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                    child: Text(l.t('deadlines'), style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w900,
                      color: C.teal, letterSpacing: -0.8, height: 1.1,
                    )),
                  )),

                  // ── Mini calendar ──
                  SliverToBoxAdapter(child: _buildCalendar(isDark, today)),

                  // ── 7-day scroll ──
                  SliverToBoxAdapter(child: _build7DayScroll(today, isDark)),

                  // ── Day assignment list ──
                  SliverToBoxAdapter(child: _buildDayList(isDark, today)),

                  const SliverToBoxAdapter(child: SizedBox(height: 90)),
                ]),
              ),
      ),
    );
  }

  // ── Mini-calendar ────────────────────────────────────────────────────────────

  Widget _buildCalendar(bool isDark, DateTime today) {
    final surface = Theme.of(context).colorScheme.surface;
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    // Mon-first: Mon=1..Sun=7 → leading blanks = (weekday-1)%7
    final leadingBlanks = (firstDay.weekday - 1) % 7;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: cardShadow(isDark),
      ),
      child: Column(children: [
        // Month nav
        Row(children: [
          _navBtn(Icons.chevron_left, () => setState(() =>
            _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1))),
          Expanded(child: Text(
            '${_monthNamesRU[_focusedMonth.month - 1]} ${_focusedMonth.year}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.teal),
          )),
          _navBtn(Icons.chevron_right, () => setState(() =>
            _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1))),
        ]),
        const SizedBox(height: 12),
        // Weekday headers
        Row(children: _weekDays.map((d) => Expanded(
          child: Center(child: Text(d, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4))),
        )).toList()),
        const SizedBox(height: 8),
        // Grid
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
              return GestureDetector(
                onTap: () => setState(() => _selectedDay = day),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: isSelected ? C.teal : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isToday && !isSelected
                          ? Border.all(color: C.teal, width: 1.5)
                          : null,
                    ),
                    child: Center(child: Text('${i + 1}', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isToday ? C.teal : adaptiveText1(context)),
                    ))),
                  ),
                  if (deadlines.isNotEmpty)
                    Container(
                      width: 5, height: 5,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: deadlines.length > 1 ? C.red : C.teal,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(height: 7),
                ]),
              );
            }),
          ],
        ),
      ]),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: C.teal, size: 20),
    ),
  );

  // ── 7-day horizontal scroll ──────────────────────────────────────────────────

  Widget _build7DayScroll(DateTime today, bool isDark) {
    return SizedBox(
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: 7,
        itemBuilder: (_, i) {
          final day = today.add(Duration(days: i));
          final key = DateTime(day.year, day.month, day.day);
          final count = (_deadlineMap[key] ?? []).length;
          final isSelected = key == _selectedDay;
          final dayName = _weekDays[day.weekday - 1];

          return GestureDetector(
            onTap: () => setState(() {
              _selectedDay = key;
              _focusedMonth = DateTime(key.year, key.month);
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? C.teal : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isSelected ? tealGlow(opacity: 0.2) : softShadow(isDark),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(dayName, style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white70 : C.text4,
                )),
                const SizedBox(height: 2),
                Text('${day.day}', style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : C.teal,
                )),
                if (count > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withOpacity(0.25)
                          : C.teal.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$count', style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : C.teal,
                    )),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Assignment list for selected day ─────────────────────────────────────────

  Widget _buildDayList(bool isDark, DateTime today) {
    final l = context.watch<L10n>();
    final items = _getForDay(_selectedDay);
    final tomorrow = today.add(const Duration(days: 1));

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.event_available_rounded, size: 52, color: C.text4.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(l.t('no_deadlines'), style: const TextStyle(fontSize: 15, color: C.text4)),
        ])),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        children: items.map((a) {
          final dueStr = a['due_date'] as String?;
          final due = dueStr != null ? DateTime.tryParse(dueStr) : null;
          final dueDay = due != null ? DateTime(due.year, due.month, due.day) : null;

          Color bg;
          if (dueDay != null && dueDay.isBefore(today)) {
            bg = isDark ? C.red.withOpacity(0.18) : C.redLt;
          } else if (_selectedDay == today) {
            bg = isDark ? C.yellow.withOpacity(0.1) : C.yellowLt;
          } else if (_selectedDay == tomorrow) {
            bg = adaptiveTealLt(context);
          } else {
            bg = Theme.of(context).colorScheme.surface;
          }

          return GestureDetector(
            onTap: () {
              final classId = (a['class_id'] as num?)?.toInt();
              if (classId != null) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ClassDetailScreen(classId: classId, initialTab: 2),
                ));
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: cardShadow(isDark),
              ),
              child: Row(children: [
                Container(
                  width: 4, height: 48,
                  decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['title'] ?? '', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: adaptiveText1(context),
                  )),
                  if (due != null)
                    Text(
                      '${due.day.toString().padLeft(2,'0')}.${due.month.toString().padLeft(2,'0')}.${due.year}',
                      style: const TextStyle(fontSize: 12, color: C.text3),
                    ),
                ])),
                const Icon(Icons.chevron_right_rounded, size: 18, color: C.text4),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}
