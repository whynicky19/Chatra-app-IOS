import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/classes_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../classes/class_detail_screen.dart';
import '../../utils/haptics.dart';
import '../../utils/nav_guard.dart';
import '../../utils/notif_feed.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tappable.dart';

/// Экран уведомлений в идиоме нативного iOS: полупрозрачный крупный заголовок,
/// под который уезжает содержимое, и inset-grouped список вместо стопки
/// плавающих карточек.
///
/// Раньше это была лента отдельных карточек с тенями и зазорами — та самая
/// «карточная» подача iOS 12, от которой системные приложения ушли. Уведомления
/// внутри одной группы («Сегодня», «Вчера») — не независимые объекты, а строки
/// одного списка, поэтому теперь у группы одна сплошная подложка, волосяные
/// разделители между строками и скругление только по краям — как в Почте,
/// Настройках и Напоминаниях.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override State<NotificationsScreen> createState() => _NotificationsScreenState();
}

/// Строка списка вместе со своим местом в группе: скругление и разделитель
/// зависят от того, первая она в секции, последняя или в середине.
class _Row {
  const _Row(this.item, this.pos);
  final NotifItem item;
  final GroupPos pos;
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<NotifItem> _items = [];

  /// Ключи, которые были непрочитанными на момент ОТКРЫТИЯ экрана. Нужны
  /// только для вида: точка и жирный заголовок показывают «вот это новое с
  /// прошлого визита», хотя прочитанными они уже отмечены.
  ///
  /// Раньше «новизна» хранилась в самом флаге прочитанности, и получалась
  /// вилка: список рисовал точки (флаг ещё старый), а счётчик уже считал ноль.
  Set<String> _fresh = {};

  late final ClassesProvider _classesProvider;

  @override
  void initState() {
    super.initState();
    // Провайдер берём СРАЗУ, а не лениво при первом обращении: бейдж
    // синхронизируется после сетевого ожидания, и если пользователь успел
    // закрыть экран, ленивый `context.read` выполнился бы на уже отсоединённом
    // элементе («Looking up a deactivated widget's ancestor is unsafe»).
    _classesProvider = context.read<ClassesProvider>();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final api = context.read<ApiService>();
    // Тот же самый расчёт, что и у бейджа: см. loadNotifFeed.
    final feed = await loadNotifFeed(api);

    final toMark = feed.items.where((i) => !i.isRead).map((i) => i.key).toList();
    // Открытый экран = уведомления просмотрены. Помечаем локально сразу, не
    // дожидаясь ответа сервера, иначе бейдж «дожил» бы до следующего запуска.
    final items = feed.items.map((i) => i.copyWith(isRead: true)).toList();

    if (mounted) {
      setState(() {
        _items = items;
        _fresh = toMark.toSet();
        _loading = false;
      });
    }
    // Не выходим по !mounted: пользователь мог уже нажать «назад», но отметка
    // прочитанным и синхронизация бейджа обязаны отработать, иначе счётчик на
    // главном экране зависает на старом значении.
    _syncBadge(items);

    if (toMark.isNotEmpty) {
      try { await api.markAllNotifsRead(toMark); } catch (_) {}
    }
  }

  /// Бейдж считается по тому же правилу, что [NotifFeed.unreadCount] — по
  /// списку, который экран показывает. Разойтись им теперь нечем.
  void _syncBadge(List<NotifItem> items) {
    _classesProvider.notifBadge.value = items.where((i) => !i.isRead).length;
  }

  Future<void> _dismiss(String key) async {
    setState(() {
      _items.removeWhere((i) => i.key == key);
      _fresh.remove(key);
    });
    _syncBadge(_items);
    try { await context.read<ApiService>().setNotifState(key, dismissed: true); } catch (_) {}
  }

  /// Заголовок и тело строит экран, а не фид: фид отдаёт данные (тип, название
  /// задания, балл), локализация — забота UI.
  String _title(NotifItem n, L10n l) {
    switch (n.kind) {
      case NotifKind.grade:
        return l.t('notif_graded');
      case NotifKind.deadline:
        return l.t('notif_deadline');
      case NotifKind.newAssignment:
        return l.t('new_assignment');
    }
  }

  /// Название задания — главная строка. Кавычек нет: заголовок и так выделен
  /// весом, а в списке из нескольких строк ёлочки читались как шум.
  String _subject(NotifItem n, L10n l) =>
      n.assignmentTitle?.trim().isNotEmpty == true ? n.assignmentTitle! : l.t('assignment');

  /// Короткая акцентная метка в мета-строке: балл или остаток времени. Коротка
  /// по построению (число + единица), поэтому место под неё предсказуемо.
  ///
  /// Название предмета сюда НЕ входит: оно переменной длины и в трёх языках
  /// доходит до нескольких слов, поэтому живёт отдельной строкой. Раньше и
  /// предмет, и название задания, и балл жались в одну строку с `maxLines: 1`,
  /// и предмет обрезался почти всегда.
  String? _accent(NotifItem n, L10n l) {
    switch (n.kind) {
      case NotifKind.grade:
        return '${n.score ?? 0} ${l.t('pts')}';
      case NotifKind.deadline:
        final d = n.remaining ?? Duration.zero;
        return d.inHours >= 1
            ? '${d.inHours} ${l.t('hours_short')}'
            : '${d.inMinutes} ${l.t('minutes_short')}';
      case NotifKind.newAssignment:
        return null;
    }
  }

  /// Плоский список для sliver-а: [String] — заголовок секции, [_Row] — строка
  /// вместе со своей позицией внутри секции.
  List<Object> _grouped(L10n l) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart = todayStart.subtract(const Duration(days: 7));
    int bucketOf(DateTime d) {
      if (!d.isBefore(todayStart)) return 0;
      if (!d.isBefore(yesterdayStart)) return 1;
      if (!d.isBefore(weekStart)) return 2;
      return 3;
    }
    final buckets = <int, List<NotifItem>>{};
    for (final n in _items) {
      // У дедлайна дата — это САМ срок сдачи, то есть будущее: группировать по
      // ней нельзя (получилась бы группа «раньше»/будущее), напоминание
      // актуально сейчас, поэтому оно всегда в «сегодня».
      final at = n.kind == NotifKind.deadline ? now : n.date;
      buckets.putIfAbsent(bucketOf(at), () => []).add(n);
    }
    const keys = ['notif_today', 'notif_yesterday', 'notif_this_week', 'notif_earlier'];
    final out = <Object>[];
    for (var b = 0; b < 4; b++) {
      final list = buckets[b];
      if (list == null || list.isEmpty) continue;
      out.add(l.t(keys[b]));
      for (var i = 0; i < list.length; i++) {
        out.add(_Row(list[i], groupPos(i, list.length)));
      }
    }
    return out;
  }

  /// Для дедлайна возвращает пустую строку: его дата в будущем, и «сколько
  /// назад» для неё смысла не имеет — остаток времени и так стоит в тексте
  /// уведомления. Раньше такая карточка показывала «только что».
  String _timeAgo(NotifItem n, L10n l) {
    if (n.kind == NotifKind.deadline) return '';
    final diff = DateTime.now().difference(n.date);
    // Отрицательная разница (часы сервера впереди) попадает сюда же.
    if (diff.inMinutes < 1) return l.t('just_now');
    if (diff.inHours < 1) return '${diff.inMinutes} ${l.t('min_ago')}';
    if (diff.inDays < 1) return '${diff.inHours} ${l.t('hr_ago')}';
    if (diff.inDays < 7) return '${diff.inDays} ${l.t('day_ago')}';
    final d = n.date;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final grouped = _grouped(l);

    return Scaffold(
      backgroundColor: bg,
      // SafeArea тут не нужен: верхний инсет забирает сам навбар, нижний
      // добавлен отступом последнего sliver-а.
      body: CustomScrollView(slivers: [
        // Крупный заголовок теперь ЧАСТЬ прокрутки: он сжимается в обычный бар
        // при скролле, а полупрозрачный фон включает под баром блюр — контент
        // уезжает под него, а не упирается в непрозрачную полосу. Раньше
        // заголовок стоял неподвижной строкой над списком.
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
          // Кнопки «отметить все» больше нет: открытие экрана и есть просмотр,
          // после него отмечать нечего — раньше она оставалась активной и
          // «отмечала» то, что уже отмечено.
          trailing: Tappable(
            onTap: _loading ? null : () { hapticLight(); _load(); },
            label: 'Обновить',
            child: SizedBox(width: 40, height: 40,
              child: Icon(CupertinoIcons.arrow_clockwise, size: 20,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: _loading ? 0.35 : 1))),
          ),
          largeTitle: Text(l.t('notifications'),
            maxLines: 1,
            style: TextStyle(
              fontSize: 34, fontWeight: FontWeight.w700,
              letterSpacing: -1, height: 1.1, color: adaptiveText1(context))),
        ),

        CupertinoSliverRefreshControl(onRefresh: _load),

        if (!_loading) SliverToBoxAdapter(child: _statusLine(l)),

        if (_loading)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            sliver: SliverList(delegate: SliverChildBuilderDelegate(
              childCount: 5,
              (ctx, i) => SkeletonNotifCard(pos: groupPos(i, 5)),
            )),
          )
        else if (_items.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _emptyState(l))
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 32 + MediaQuery.paddingOf(context).bottom),
            sliver: SliverList(delegate: SliverChildBuilderDelegate(
              childCount: grouped.length,
              (ctx, i) {
                final entry = grouped[i];
                if (entry is String) return _sectionHeader(entry, first: i == 0);
                return _row(entry as _Row, l);
              },
            )),
          ),
      ]),
    );
  }

  /// Строка состояния под заголовком: сколько нового с прошлого визита.
  Widget _statusLine(L10n l) {
    final fresh = _fresh.length;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
      child: Row(children: [
        if (fresh > 0)
          Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 7),
            decoration: BoxDecoration(color: primary, shape: BoxShape.circle))
        else ...[
          Icon(CupertinoIcons.checkmark_circle_fill, size: 15, color: C.green.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
        ],
        // maxLines: 2 — со счётчиком и на казахском строка длиннее русской, при
        // крупном системном шрифте она переносится, а не обрезается.
        Flexible(child: Text(fresh > 0 ? '$fresh ${l.t('notif_unread')}' : l.t('all_read'),
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2,
            height: 1.25, color: adaptiveText3(context)))),
      ]),
    );
  }

  Widget _sectionHeader(String title, {required bool first}) => Padding(
    padding: EdgeInsets.only(left: 6, right: 6, top: first ? 0 : 26, bottom: 8),
    child: Text(title.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, height: 1.25,
        letterSpacing: 0.6, color: adaptiveText3(context))),
  );

  Widget _row(_Row row, L10n l) {
    final n = row.item;
    final cfg = _config(n.kind);
    final canNavigate = n.classId != null;
    final radius = groupRadius(row.pos, radius: AppRadii.card);

    return RepaintBoundary(child: Dismissible(
      key: ValueKey('dismiss_${n.key}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.4},
      onDismissed: (_) {
        hapticMedium();
        _dismiss(n.key);
      },
      // Подложка повторяет скругление строки по её месту в группе: иначе у
      // первой/последней строки из-под красного выглядывали прямые углы.
      background: Container(
        decoration: BoxDecoration(color: C.red, borderRadius: radius),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(CupertinoIcons.trash_fill, color: Colors.white, size: 21),
          const SizedBox(height: 3),
          Text(l.t('delete'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
      child: GroupRow(
        pos: row.pos,
        // Разделитель начинается там, где начинается текст, — правило iOS.
        // 14 (отступ строки) + 12 (гуттер под точку) + 26 (значок) + 12 = 64.
        separatorInset: 64,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: () {
          hapticSelection();
          // Прочитанным уведомление уже отмечено при загрузке экрана — тапом
          // снимаем только акцент «новое».
          setState(() => _fresh.remove(n.key));
          if (canNavigate) {
            guardedPush(context, MaterialPageRoute(
              builder: (_) => ClassDetailScreen(classId: n.classId!, initialTab: 1)));
          }
        },
        child: _NotifRowContent(
          kindLabel: _title(n, l),
          subject: _subject(n, l),
          className: n.className,
          accent: _accent(n, l),
          isFresh: _fresh.contains(n.key),
          icon: cfg.icon,
          color: cfg.color,
          timeAgo: _timeAgo(n, l),
        ),
      ),
    ));
  }

  ({IconData icon, Color color}) _config(NotifKind kind) {
    switch (kind) {
      case NotifKind.grade:
        return (icon: CupertinoIcons.rosette, color: Theme.of(context).colorScheme.primary);
      case NotifKind.deadline:
        return (icon: CupertinoIcons.clock_fill, color: C.red);
      case NotifKind.newAssignment:
        return (icon: CupertinoIcons.doc_text_fill, color: C.indigo);
    }
  }

  Widget _emptyState(L10n l) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(child: Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 80),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 76, height: 76,
          decoration: BoxDecoration(
            gradient: RadialGradient(colors: [primary.withValues(alpha: 0.16), primary.withValues(alpha: 0.03)]),
            shape: BoxShape.circle),
          child: Icon(CupertinoIcons.bell_fill, size: 32, color: primary)),
        const SizedBox(height: 18),
        Text(l.t('no_notif'), textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: adaptiveText1(context))),
        const SizedBox(height: 6),
        Text(l.t('no_notif_sub'), textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText3(context), height: 1.4)),
      ]),
    ));
  }
}

/// Содержимое строки уведомления — три уровня, как в Центре уведомлений iOS:
/// тип события мелкой акцентной подписью со временем справа, само событие
/// главной строкой, предмет и балл — мета-строкой.
///
/// Непрочитанное отмечено точкой в ЛЕВОМ ГУТТЕРЕ, вне значка (так это сделано
/// в Почте), а не рядом с заголовком: точка у текста конкурировала с самим
/// заголовком за начало строки и сдвигала его, из-за чего заголовки соседних
/// строк не выравнивались по левому краю.
///
/// Три строки вместо двух — это и есть починка обрезания: раньше предмет
/// приклеивался к названию задания в одну строку с `maxLines: 1` и в
/// русском/казахском пропадал под многоточием почти всегда.
class _NotifRowContent extends StatelessWidget {
  const _NotifRowContent({
    required this.kindLabel,
    required this.subject,
    required this.className,
    required this.accent,
    required this.isFresh,
    required this.icon,
    required this.color,
    required this.timeAgo,
  });

  /// Тип события: «Задание проверено», «Скоро дедлайн», «Новое задание».
  final String kindLabel;

  /// Название задания — главная строка.
  final String subject;

  /// Название предмета; null/пусто — строка не рисуется.
  final String? className;

  /// Короткая метка справа в мета-строке (балл, остаток времени).
  final String? accent;

  final bool isFresh;
  final IconData icon;
  final Color color;
  final String timeAgo;

  @override
  Widget build(BuildContext context) {
    final hasClass = className != null && className!.trim().isNotEmpty;

    // center: значок и точка стоят по СЕРЕДИНЕ строки — так их ставят строки
    // Настроек и Почты. Прижимать их к верху имело смысл, пока значок был
    // плиткой 38×38 высотой в две текстовые строки; голый глиф 22pt на той же
    // верхней линии выглядит просто съехавшим вверх, потому что текстовый блок
    // втрое выше него.
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      // Гуттер занят всегда, даже когда точки нет: иначе прочитанные и
      // непрочитанные строки начинались бы с разного отступа и левый край
      // списка «дышал» бы.
      SizedBox(width: 12, child: isFresh
          ? Center(child: Container(width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)))
          : null),
      // Значок без подложки: цвет несёт сам глиф. Плитка с тонированным фоном
      // добавляла в каждую строку второй цветной прямоугольник, и список из
      // нескольких типов уведомлений читался как набор разноцветных плашек, а
      // не как текст. Ширина колонки фиксирована, чтобы текст всех строк
      // начинался по одной линии независимо от глифа.
      SizedBox(width: 26, child: Icon(icon, size: 22, color: color)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Строка 1: тип события + время ──────────────────────────────────
        Row(children: [
          // FittedBox внутри Expanded: тип события — короткая служебная
          // подпись, её лучше слегка ужать, чем оборвать многоточием
          // («Тапсырма бағаланды» заметно длиннее английского).
          Expanded(child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(kindLabel, maxLines: 1,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  letterSpacing: 0.2, color: color, height: 1.2)),
            ),
          )),
          if (timeAgo.isNotEmpty) ...[
            const SizedBox(width: 8),
            // Табличные цифры: иначе время в соседних строках «дышит» по
            // ширине и правый край списка выглядит рваным.
            Text(timeAgo, maxLines: 1,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: -0.1,
                  color: adaptiveText4(context),
                  fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ]),
        const SizedBox(height: 3),

        // ── Строка 2: название задания ─────────────────────────────────────
        Text(subject,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600,
            letterSpacing: -0.3, color: adaptiveText1(context), height: 1.25)),

        // ── Строка 3: предмет + балл/остаток ───────────────────────────────
        if (hasClass || accent != null) ...[
          const SizedBox(height: 5),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Предмет занимает всю строку и выдавливает пилюлю вправо. Если
            // предмета нет (класс, из которого выбыли), пилюля встаёт по
            // левому краю: одиноко висящая справа плашка читалась как
            // потерянный элемент в пустой строке.
            if (hasClass) ...[
              Expanded(child: Text(className!,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500,
                  letterSpacing: -0.1, height: 1.25, color: adaptiveText3(context)))),
              const SizedBox(width: 8),
            ],
            if (accent != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                child: Text(accent!, maxLines: 1,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: -0.1,
                    color: color, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ],
          ]),
        ],
      ])),
    ]);
  }
}
