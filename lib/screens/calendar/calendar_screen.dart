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
import '../../utils/haptics.dart';
import '../../utils/nav_guard.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/tappable.dart';

/// Календарь дедлайнов в идиоме нативного Календаря iOS.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

/// Сколько месяцев доступно свайпом в каждую сторону от текущего. Индекс
/// страницы [PageView] — это смещение в месяцах от «сегодня» плюс эта база.
const int _kMonthPageBase = 600;

/// Высота одной строки сетки: кружок дня 36 + зазор 3 + точка 5 + воздух.
const double _kDayCellHeight = 50;

/// Сетка всегда в шесть строк — столько нужно самому длинному месяцу. При
/// подгонке под конкретный месяц (4-6 строк) содержимое ниже прыгало вверх-вниз
/// при листании.
const int _kGridRows = 6;

class _CalendarScreenState extends State<CalendarScreen> {
  final DateTime _today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  late DateTime _focusedMonth = DateTime(_today.year, _today.month);
  late DateTime _selectedDay = _today;
  late final PageController _monthPages = PageController(initialPage: _kMonthPageBase);

  Map<DateTime, List<dynamic>> _deadlineMap = {};
  Map<int, dynamic> _submissionMap = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _monthPages.dispose();
    super.dispose();
  }

  DateTime _monthAt(int page) => DateTime(_today.year, _today.month + (page - _kMonthPageBase));

  Future<void> _load() async {
    try {
      final api = context.read<ApiService>();
      final isStudent = !context.read<AuthProvider>().isTeacher;

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
        // Прошедшие сроки не показываем: экран про то, что ВПЕРЕДИ.
        if (dueDay.isBefore(_today)) continue;
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

  bool _isDone(dynamic a) {
    final s = _submissionStatus(a);
    return s == 'submitted' || s == 'graded';
  }

  void _selectDay(DateTime day) {
    if (day == _selectedDay) return;
    hapticSelection();
    setState(() => _selectedDay = day);
  }

  void _stepMonth(int delta) {
    hapticLight();
    _monthPages.animateToPage(
      (_monthPages.page ?? _kMonthPageBase.toDouble()).round() + delta,
      // Отклик на кнопку, а не «проезд»: без перелёта, коротко.
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(slivers: [
        CupertinoSliverNavigationBar(
          backgroundColor: bg.withValues(alpha: 0.78),
          border: null,
          stretch: true,
          padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
          leading: Tappable(
            onTap: () => Navigator.pop(context),
            label: 'Назад',
            child: SizedBox(width: 40, height: 40,
              child: Icon(CupertinoIcons.back, size: 26, color: Theme.of(context).colorScheme.primary)),
          ),
          largeTitle: Text(l.t('deadlines'),
            maxLines: 1,
            style: TextStyle(
              fontSize: 34, fontWeight: FontWeight.w700,
              letterSpacing: -1, height: 1.1, color: adaptiveText1(context))),
        ),

        if (_loading)
          const SliverFillRemaining(hasScrollBody: false, child: _CalendarLoading())
        else ...[
          CupertinoSliverRefreshControl(onRefresh: () async {
            setState(() => _loading = true);
            await _load();
          }),

          if (_deadlineMap.isNotEmpty) SliverToBoxAdapter(child: _summary(l)),
          SliverToBoxAdapter(child: _monthHeader(l)),
          SliverToBoxAdapter(child: _weekdayRow(l)),
          SliverToBoxAdapter(child: _monthPager()),
          SliverToBoxAdapter(child: _legend(l)),
          ..._daySlivers(l, isDark),
          SliverToBoxAdapter(child: SizedBox(height: bottomBarClearance(context))),
        ],
      ]),
    );
  }

  // ── Шапка ──────────────────────────────────────────────────────────────────

  /// Сводка под заголовком: сколько дедлайнов впереди. Когда впереди пусто,
  /// строки нет совсем — под сеткой и так стоит «Дедлайнов нет».
  Widget _summary(L10n l) {
    final total = _deadlineMap.values.fold<int>(0, (n, list) => n + list.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 22),
      child: Text(
        '${l.t('upcoming_tasks')}: $total',
        maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2,
          height: 1.25, color: adaptiveText3(context)),
      ),
    );
  }

  Widget _monthHeader(L10n l) {
    final months = l.t('months_full').split(',');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
      child: Row(children: [
        // FittedBox: «Қыркүйек 2026» / «September 2026» заметно длиннее
        // «Май 2026». Заголовок ужимается, но не обрывается многоточием.
        Expanded(child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${months[_focusedMonth.month - 1]} ${_focusedMonth.year}',
              maxLines: 1,
              style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700,
                letterSpacing: -0.5, height: 1.15, color: adaptiveText1(context))),
          ),
        )),
        _navBtn(CupertinoIcons.chevron_left, () => _stepMonth(-1), 'Предыдущий месяц'),
        _navBtn(CupertinoIcons.chevron_right, () => _stepMonth(1), 'Следующий месяц'),
      ]),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap, String label) => Tappable(
    onTap: onTap,
    label: label,
    child: SizedBox(width: 40, height: 40,
      child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 19)),
  );

  Widget _weekdayRow(L10n l) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    // Подписи ужимаются каждая в своей колонке: «Mon/Tue» на треть шире
    // «Пн/Вт» и на узком экране упирались друг в друга.
    child: Row(children: l.t('weekdays_short').split(',').map((d) => Expanded(
      child: Center(child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(d.toUpperCase(), maxLines: 1, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4,
          color: adaptiveText4(context))),
      )),
    )).toList()),
  );

  // ── Сетка месяца ───────────────────────────────────────────────────────────

  Widget _monthPager() => SizedBox(
    height: _kDayCellHeight * _kGridRows,
    child: PageView.builder(
      controller: _monthPages,
      onPageChanged: (page) {
        hapticSelection();
        setState(() => _focusedMonth = _monthAt(page));
      },
      itemBuilder: (_, page) => _monthGrid(_monthAt(page)),
    ),
  );

  Widget _monthGrid(DateTime month) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final leadingBlanks = (DateTime(month.year, month.month, 1).weekday - 1) % 7;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: List.generate(_kGridRows, (row) => SizedBox(
        height: _kDayCellHeight,
        child: Row(children: List.generate(7, (col) {
          final dayNum = row * 7 + col - leadingBlanks + 1;
          if (dayNum < 1 || dayNum > daysInMonth) return const Expanded(child: SizedBox());
          return Expanded(child: _dayCell(DateTime(month.year, month.month, dayNum)));
        })),
      ))),
    );
  }

  Widget _dayCell(DateTime day) {
    final deadlines = _getForDay(day);
    final isSelected = day == _selectedDay;
    final isToday = day == _today;
    final primary = Theme.of(context).colorScheme.primary;

    Color? dotColor;
    if (deadlines.isNotEmpty) {
      if (deadlines.every(_isDone)) {
        dotColor = C.green;
      } else if (deadlines.length > 1) {
        dotColor = C.red;
      } else {
        dotColor = primary;
      }
    }

    return Tappable(
      onTap: () => _selectDay(day),
      scale: 1,
      minSize: 0,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: isSelected ? primary : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Center(child: Text('${day.day}', style: TextStyle(
            fontSize: 16, letterSpacing: -0.4, height: 1,
            fontWeight: isSelected || isToday ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : (isToday ? primary : adaptiveText1(context)),
            // Табличные цифры: иначе «11» и «18» разной ширины и колонки сетки
            // оптически гуляют.
            fontFeatures: const [FontFeature.tabularFigures()],
          ))),
        ),
        const SizedBox(height: 3),
        // Место под точку занято всегда — иначе дни с заданиями и без них
        // стоят на разной высоте.
        SizedBox(height: 5, child: dotColor == null ? null : Center(
          child: Container(width: 5, height: 5, decoration: BoxDecoration(
            color: isSelected ? Colors.white : dotColor, shape: BoxShape.circle)),
        )),
      ]),
    );
  }

  Widget _legend(L10n l) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 16, runSpacing: 8,
      children: [
        _legendDot(Theme.of(context).colorScheme.primary, l.t('cal_legend_due')),
        _legendDot(C.red, l.t('cal_legend_multiple')),
        _legendDot(C.green, l.t('cal_legend_done')),
      ],
    ),
  );

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(width: 5, height: 5, margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      // Без maxLines/ellipsis: подпись легенды должна читаться целиком на любом
      // языке — не влезла в строку, значит переносится.
      Flexible(child: Text(label, style: TextStyle(
        fontSize: 12, height: 1.2, letterSpacing: -0.1,
        color: adaptiveText3(context), fontWeight: FontWeight.w500))),
    ]);

  // ── Задания выбранного дня ─────────────────────────────────────────────────

  List<Widget> _daySlivers(L10n l, bool isDark) {
    final items = _getForDay(_selectedDay);
    final tomorrow = _today.add(const Duration(days: 1));
    final monthGen = l.t('months_genitive').split(',');
    final dayLabel = _selectedDay == _today
        ? l.t('notif_today')
        : _selectedDay == tomorrow
            ? l.t('tomorrow')
            : '${_selectedDay.day} ${monthGen[_selectedDay.month - 1]}';

    if (items.isEmpty) {
      final primary = Theme.of(context).colorScheme.primary;
      return [SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 26, 40, 20),
        child: Column(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                primary.withValues(alpha: 0.14),
                primary.withValues(alpha: 0.03),
              ]),
              shape: BoxShape.circle),
            child: Icon(CupertinoIcons.calendar, size: 24, color: primary),
          ),
          const SizedBox(height: 14),
          Text('$dayLabel · ${l.t('no_deadlines')}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2,
              height: 1.35, color: adaptiveText3(context))),
        ]),
      ))];
    }

    final classNames = <int, String>{
      for (final c in context.read<ClassesProvider>().classes)
        if (c['id'] != null) (c['id'] as num).toInt(): (c['title'] ?? '').toString(),
    };

    return [
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
        // Flexible вокруг подписи дня: «15 қыркүйек»/«15 September» длиннее
        // «Сегодня», и без него длинная дата выдавливала счётчик за край.
        child: Row(children: [
          Flexible(child: Text(dayLabel.toUpperCase(),
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, height: 1.25,
              letterSpacing: 0.6, color: adaptiveText3(context)))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadii.chip)),
            child: Text('${items.length}', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ]),
      )),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(delegate: SliverChildBuilderDelegate(
          childCount: items.length,
          (ctx, i) => _assignmentRow(items[i], groupPos(i, items.length), classNames, tomorrow, isDark),
        )),
      ),
    ];
  }

  Widget _assignmentRow(
    dynamic a,
    GroupPos pos,
    Map<int, String> classNames,
    DateTime tomorrow,
    bool isDark,
  ) {
    final dueStr = a['deadline'] as String?;
    final due = dueStr != null ? parseServerDate(dueStr) : null;
    final isSubmitted = _isDone(a);
    final classId = (a['class_id'] as num?)?.toInt();
    final className = classId == null ? '' : (classNames[classId] ?? '');
    final title = (a['title'] ?? '').toString();

    final Color accent;
    if (isSubmitted) {
      accent = C.green;
    } else if (_selectedDay == _today) {
      accent = C.red;
    } else if (_selectedDay == tomorrow) {
      accent = C.amberDk;
    } else {
      accent = Theme.of(context).colorScheme.primary;
    }

    return GroupRow(
      pos: pos,
      // Разделитель начинается там, где начинается текст: 14 + 26 + 12.
      separatorInset: 52,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      label: title,
      onTap: classId == null ? null : () {
        hapticSelection();
        guardedPush(context, MaterialPageRoute(
          builder: (_) => ClassDetailScreen(classId: classId, initialTab: 1)));
      },
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 26,
          child: Icon(isSubmitted ? CupertinoIcons.checkmark_alt : CupertinoIcons.clock,
              size: 22, color: accent)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600,
              letterSpacing: -0.3, height: 1.25, color: adaptiveText1(context))),
          const SizedBox(height: 5),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (due != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(CupertinoIcons.clock, size: 12, color: accent),
              ),
              const SizedBox(width: 4),
              Text(
                '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.1,
                  height: 1.25, color: accent,
                  fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(width: 8),
            ],
            if (className.isNotEmpty)
              Expanded(child: Text(className,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: -0.1,
                  height: 1.25, color: adaptiveText3(context)))),
          ]),
        ])),
        if (classId != null)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(CupertinoIcons.chevron_right, size: 15,
                color: adaptiveText4(context).withValues(alpha: 0.7)),
          ),
      ]),
    );
  }
}

class _CalendarLoading extends StatelessWidget {
  const _CalendarLoading();

  @override
  Widget build(BuildContext context) => Center(
    child: CupertinoActivityIndicator(radius: 13, color: Theme.of(context).colorScheme.primary));
}
