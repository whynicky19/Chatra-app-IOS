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
import '../../widgets/inset_group.dart';
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
                  // Подзаголовок под largeTitle. maxLines: 2 — «Алдағы
                  // тапсырмалар: 12» и «No upcoming deadlines» длиннее
                  // русского варианта, а обрезать сводку нельзя: это
                  // единственное место, где видно общее число.
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Text(
                      _deadlineMap.isEmpty
                          ? l.t('no_upcoming_deadlines')
                          : '${l.t('upcoming_tasks')}: ${_deadlineMap.values.fold<int>(0, (n, list) => n + list.length)}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2,
                        height: 1.25, color: adaptiveText3(context)),
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
          // FittedBox: «Қыркүйек 2026» / «September 2026» заметно длиннее
          // «Май 2026», а между двумя кнопками-стрелками остаётся всего ~230pt.
          // Заголовок месяца ужимается, но не обрывается многоточием.
          Expanded(child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${l.t('months_full').split(',')[_focusedMonth.month - 1]} ${_focusedMonth.year}',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4,
                color: adaptiveText1(context)),
            ),
          )),
          _navBtn(CupertinoIcons.chevron_right, () => setState(() =>
            _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1)), 'Следующий месяц'),
        ]),
        const SizedBox(height: 14),
        // Подписи дней недели ужимаются каждая в своей колонке: «Mon/Tue» на 3
        // буквы шире, чем «Пн/Вт», и на узком экране упирались друг в друга.
        Row(children: l.t('weekdays_short').split(',').map((d) => Expanded(
          child: Center(child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(d, maxLines: 1, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2,
              color: adaptiveText4(context))),
          )),
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
                // Ячейка дня не «пружинит»: 42 клетки подряд, сжатие каждой по
                // тапу читалось бы как дребезг сетки, а не как отклик.
                scale: 1,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
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
                      fontSize: 15, letterSpacing: -0.3,
                      // Раньше здесь стоял тернарник `w600 : w600` — обе ветки
                      // одинаковые, то есть вся сетка была полужирной и
                      // «сегодня» в ней ничем не выделялось.
                      fontWeight: isSelected || isToday ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white
                          : (isToday ? Theme.of(context).colorScheme.primary : adaptiveText1(context)),
                    ))),
                  ),
                  if (dotColor != null)
                    Container(
                      width: 5, height: 5,
                      margin: const EdgeInsets.only(top: 2),
                      // На залитом кружке выбранного дня цветная точка тонет —
                      // там она белая, как в календаре iOS.
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : dotColor,
                        shape: BoxShape.circle),
                    )
                  else
                    const SizedBox(height: 7),
                ]),
              );
            }),
          ],
        ),
        const SizedBox(height: 8),
        Divider(height: 1, color: groupSeparator(context)),
        const SizedBox(height: 12),
        // Wrap, а не Row: три подписи легенды в одну строку помещаются только
        // по-русски. «бірнеше тапсырма» и «several due» на узком экране уже не
        // влезали и обрезались многоточием — теперь лишний пункт целиком
        // переносится на вторую строку. Wrap отдаёт детям maxWidth всей строки,
        // поэтому и одна длинная подпись переносится по словам, а не уходит за
        // край карточки.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16, runSpacing: 8,
          children: [
            _legendDot(Theme.of(context).colorScheme.primary, l.t('cal_legend_due')),
            _legendDot(C.red, l.t('cal_legend_multiple')),
            _legendDot(C.green, l.t('cal_legend_done')),
          ],
        ),
      ]),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      // Без maxLines/ellipsis: подпись легенды должна читаться целиком на любом
      // языке — не влезла в строку, значит переносится.
      Flexible(child: Text(label, style: TextStyle(
        fontSize: 12, height: 1.2, letterSpacing: -0.1,
        color: adaptiveText3(context), fontWeight: FontWeight.w500))),
    ]);

  Widget _navBtn(IconData icon, VoidCallback onTap, String label) => Tappable(
    onTap: onTap,
    label: label,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: adaptiveSurface2(context).withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 18),
    ),
  );

  Widget _build7DayScroll(DateTime today, bool isDark) {
    final l = context.read<L10n>();
    return SizedBox(
      height: 92,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        itemCount: 7,
        itemBuilder: (_, i) {
          final day = today.add(Duration(days: i));
          final key = DateTime(day.year, day.month, day.day);
          final items = _deadlineMap[key] ?? [];
          final count = items.length;
          final isSelected = key == _selectedDay;
          final isToday = i == 0;
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
            label: '${day.day}',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              // Фиксированная ширина вместо padding по содержимому: с ней лента
              // идёт ровным ритмом. Раньше ячейка «Mon» была шире «Пн», а день
              // со счётчиком — шире дня без него, и колонки гуляли.
              width: 58,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.tile),
                border: isSelected ? null : Border.all(color: groupSeparator(context), width: hairline(context)),
                boxShadow: isSelected ? primaryGlow(Theme.of(context).colorScheme.primary, opacity: 0.2) : softShadow(isDark),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                // FittedBox: «Mon/Tue/Wed» на треть длиннее «Пн/Вт», а ячейка
                // теперь фиксированной ширины.
                FittedBox(fit: BoxFit.scaleDown, child: Text(dayName.toUpperCase(), maxLines: 1, style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3,
                  color: isSelected ? Colors.white.withValues(alpha: 0.75) : adaptiveText4(context),
                ))),
                const SizedBox(height: 3),
                Text('${day.day}', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.1,
                  color: isSelected
                      ? Colors.white
                      : (isToday ? Theme.of(context).colorScheme.primary : adaptiveText1(context)),
                )),
                const SizedBox(height: 4),
                // Место под счётчик занято всегда: без этого ячейки с
                // заданиями были выше пустых и лента шла «ступеньками».
                SizedBox(
                  height: 16,
                  child: count == 0
                      ? null
                      : Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.25)
                                : (allDone ? C.green.withValues(alpha: 0.15) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)),
                            borderRadius: BorderRadius.circular(AppRadii.chip),
                          ),
                          child: Text('$count', style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, height: 1.1,
                            color: isSelected ? Colors.white : (allDone ? C.green : Theme.of(context).colorScheme.primary),
                          )),
                        ),
                ),
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
        padding: const EdgeInsets.fromLTRB(40, 34, 40, 40),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 66, height: 66,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.03),
              ]),
              shape: BoxShape.circle),
            child: Icon(CupertinoIcons.calendar, size: 28, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 14),
          Text('$dayLabel · ${l.t('no_deadlines')}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2,
              height: 1.35, color: adaptiveText3(context))),
        ])),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10, top: 4),
          // Flexible вокруг подписи дня: «15 қыркүйек»/«15 September» длиннее
          // «Сегодня», и без него длинная дата выдавливала пилюлю со счётчиком
          // за край строки.
          child: Row(children: [
            Flexible(child: Text(dayLabel.toUpperCase(),
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, height: 1.25,
                color: adaptiveText3(context), letterSpacing: 0.6))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadii.chip)),
              child: Text('${items.length}', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
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
          final className = classId == null ? '' : (classNames[classId] ?? '');

          // Карточка всегда на обычной поверхности, а состояние несут значок и
          // время. Раньше вся карточка заливалась жёлтым/зелёным/фирменным
          // цветом: список из пяти заданий на разные дни превращался в
          // светофор, а текст на пастельной заливке терял контраст в тёмной
          // теме. Акцент цветом — точечный, как в Напоминаниях: красный только
          // на «сегодня», янтарный на «завтра», дальше — фирменный.
          final Color accentColor;
          if (isSubmitted) {
            accentColor = C.green;
          } else if (_selectedDay == today) {
            accentColor = C.red;
          } else if (_selectedDay == tomorrow) {
            accentColor = C.amberDk;
          } else {
            accentColor = Theme.of(context).colorScheme.primary;
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GroupRow.card(
              onTap: classId != null ? () => guardedPush(context, MaterialPageRoute(
                builder: (_) => ClassDetailScreen(classId: classId, initialTab: 1),
              )) : null,
              label: (a['title'] ?? '').toString(),
              radius: AppRadii.tile,
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              // start: название занимает до двух строк, и значок обязан
              // держаться верха карточки, а не «плавать» по её центру.
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 42, height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                  ),
                  child: Icon(isSubmitted ? CupertinoIcons.checkmark_alt : CupertinoIcons.clock,
                      size: 20, color: accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((a['title'] ?? '').toString(), style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600,
                    letterSpacing: -0.3, height: 1.25,
                    color: adaptiveText1(context),
                  ), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  // Время фиксированной ширины (5 знаков), а всё оставшееся
                  // место в строке отдано названию предмета — и до двух строк.
                  // Раньше они делили строку поровну через Flexible с
                  // `maxLines: 1`, и предмет почти всегда обрывался.
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (due != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(CupertinoIcons.clock, size: 12, color: accentColor),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${due.hour.toString().padLeft(2,'0')}:${due.minute.toString().padLeft(2,'0')}',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          letterSpacing: -0.1, height: 1.25, color: accentColor),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (className.isNotEmpty)
                      Expanded(child: Text(className,
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500,
                          letterSpacing: -0.1, height: 1.25, color: adaptiveText3(context)),
                        maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ])),
                if (classId != null) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Icon(CupertinoIcons.chevron_right, size: 15,
                        color: adaptiveText4(context).withValues(alpha: 0.7)),
                  ),
                ],
              ]),
            ),
          );
        }),
      ]),
    );
  }
}
