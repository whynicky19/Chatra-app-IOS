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

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override State<NotificationsScreen> createState() => _NotificationsScreenState();
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

  /// Название задания — главная строка карточки. Кавычек нет: заголовок и так
  /// выделен весом, а в списке из нескольких карточек ёлочки читались как шум.
  String _subject(NotifItem n, L10n l) =>
      n.assignmentTitle?.trim().isNotEmpty == true ? n.assignmentTitle! : l.t('assignment');

  /// Короткая акцентная метка справа в мета-строке: балл или остаток времени.
  /// Всегда коротка по построению (число + единица), поэтому пилюля под неё
  /// может быть без переносов — место под неё ограничено и предсказуемо.
  ///
  /// Название предмета сюда НЕ входит: оно переменной длины и в трёх языках
  /// доходит до нескольких слов, поэтому живёт отдельной строкой (см.
  /// [_NotifCard]). Раньше и предмет, и балл, и название задания жались в одну
  /// строку с `maxLines: 1` — предмет обрезался почти всегда.
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
      out.addAll(list);
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
    final surface = Theme.of(context).colorScheme.surface;
    final fresh = _fresh.length;
    final grouped = _grouped(l);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        // Панель навигации в духе iOS: «назад» и «обновить» — одиночные
        // акцентные глифы (рамок-квадратов, которые тут были раньше, в
        // системных барах не бывает).
        Padding(padding: const EdgeInsets.fromLTRB(8, 4, 16, 2), child: Row(children: [
          Tappable(onTap: () => Navigator.pop(context),
            label: 'Назад',
            child: SizedBox(width: 44, height: 44,
              child: Icon(CupertinoIcons.back, size: 26, color: Theme.of(context).colorScheme.primary))),
          const Spacer(),
          // Кнопки «отметить все» больше нет: открытие экрана и есть просмотр,
          // после него отмечать нечего — раньше она оставалась активной и
          // «отмечала» то, что уже отмечено.
          Tappable(onTap: _loading ? null : _load,
            label: 'Обновить',
            child: SizedBox(width: 44, height: 44,
              child: Icon(CupertinoIcons.refresh, size: 20,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: _loading ? 0.4 : 1)))),
        ])),

        // Крупный заголовок отдельной строкой под баром — та же вертикальная
        // структура, что у нативного largeTitle.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // FittedBox, а не ellipsis: заголовок экрана обрезать многоточием
            // нельзя, а «Хабарламалар» на узком экране (SE) в 34pt уже не
            // помещается. Уменьшение кегля — то же, что делает нативный
            // largeTitle iOS с длинным заголовком.
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(l.t('notifications'),
                    maxLines: 1,
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1, height: 1.1, color: adaptiveText1(context))),
              ),
            ),
            if (!_loading) ...[
              const SizedBox(height: 4),
              Row(children: [
                if (fresh > 0)
                  Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle))
                else ...[
                  Icon(CupertinoIcons.checkmark_circle_fill, size: 14, color: C.green.withValues(alpha: 0.85)),
                  const SizedBox(width: 5),
                ],
                // maxLines: 2 — «оқылмаған»/«unread» со счётчиком в одну
                // строку помещается, но при крупном системном шрифте
                // (Dynamic Type) строка переносится, а не обрезается.
                Flexible(child: Text(fresh > 0 ? '$fresh ${l.t('notif_unread')}' : l.t('all_read'),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, letterSpacing: -0.2, height: 1.25, color: adaptiveText3(context), fontWeight: FontWeight.w500))),
              ]),
            ],
          ]),
        ),

        Expanded(child: _loading
          ? ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: 5,
              itemBuilder: (ctx, i) => TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 260 + i * 70),
                curve: Curves.easeOut,
                builder: (_, t, child) => Opacity(opacity: t, child: child),
                child: const SkeletonNotifCard(),
              ),
            )
          : _items.isEmpty
            ? _emptyState()
            : CustomScrollView(
                slivers: [
                  CupertinoSliverRefreshControl(onRefresh: _load),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    sliver: SliverList(delegate: SliverChildBuilderDelegate(
                      childCount: grouped.length,
                      (ctx, i) {
                    final item = grouped[i];
                    if (item is String) {
                      return Padding(
                        padding: EdgeInsets.only(left: 6, right: 6, top: i == 0 ? 2 : 22, bottom: 10),
                        child: Text(item.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, height: 1.25,
                            color: adaptiveText3(context), letterSpacing: 0.6)),
                      );
                    }
                    final n = item as NotifItem;
                    final cfg = _config(n.kind);
                    final canNavigate = n.classId != null;
                    return Entrance(
                      key: ValueKey(n.key),
                      index: i,
                      rise: 14,
                      child: RepaintBoundary(child: Dismissible(
                        key: ValueKey('dismiss_${n.key}'),
                        direction: DismissDirection.endToStart,
                        dismissThresholds: const {DismissDirection.endToStart: 0.4},
                        onDismissed: (_) {
                          hapticMedium();
                          _dismiss(n.key);
                        },
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: C.red,
                            borderRadius: BorderRadius.circular(AppRadii.card),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 22),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(CupertinoIcons.trash_fill, color: Colors.white, size: 22),
                            const SizedBox(height: 3),
                            Text(l.t('delete'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        child: _NotifCard(
                          kindLabel: _title(n, l),
                          subject: _subject(n, l),
                          className: n.className,
                          accent: _accent(n, l),
                          isFresh: _fresh.contains(n.key),
                          icon: cfg.icon,
                          color: cfg.color,
                          surface: surface,
                          timeAgo: _timeAgo(n, l),
                          onTap: () {
                            // Прочитанным уведомление уже отмечено при загрузке
                            // экрана — тапом снимаем только акцент «новое».
                            setState(() => _fresh.remove(n.key));
                            if (canNavigate) {
                              guardedPush(context, MaterialPageRoute(
                                builder: (_) => ClassDetailScreen(classId: n.classId!, initialTab: 1)));
                            }
                          },
                        ),
                      )),
                    );
                      },
                    )),
                  ),
                ],
              )),
      ])),
    );
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

  Widget _emptyState() {
    final l = context.read<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    return Center(child: Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
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

/// Карточка одного уведомления в духе Центра уведомлений iOS: плоский цветной
/// значок, тип события мелкой акцентной строкой, время — справа в той же
/// строке, дальше содержимое. Непрочитанное отмечено точкой у типа и более
/// насыщенной подложкой значка.
///
/// Раньше непрочитанное дополнительно обводилось цветной рамкой в 1.2px по
/// всей карточке: в списке из нескольких непрочитанных экран превращался в
/// набор конкурирующих цветных прямоугольников. Теперь рамка всегда одна и та
/// же волосяная, а «непрочитанность» несут точка и значок — ровно как в Mail.
///
/// ТРИ строки вместо двух — это и есть починка обрезания. В прежней вёрстке
/// название предмета приклеивалось к названию задания в одну строку с
/// `maxLines: 1`, и в русском/казахском предмет пропадал под многоточием почти
/// всегда. Теперь у каждой сущности своя строка: тип (1 строка, ужимается),
/// название задания (до 2 строк), предмет (до 2 строк) плюс короткая пилюля
/// балла/остатка времени, ширина которой ограничена по построению.
class _NotifCard extends StatelessWidget {
  /// Тип события: «Задание проверено», «Скоро дедлайн», «Новое задание».
  final String kindLabel;

  /// Название задания — главная строка карточки.
  final String subject;

  /// Название предмета; null/пусто — строка не рисуется.
  final String? className;

  /// Короткая метка справа в мета-строке (балл, остаток времени).
  final String? accent;

  final bool isFresh;
  final IconData icon;
  final Color color;
  final Color surface;
  final String timeAgo;
  final VoidCallback onTap;

  const _NotifCard({
    required this.kindLabel,
    required this.subject,
    required this.className,
    required this.accent,
    required this.isFresh,
    required this.icon,
    required this.color,
    required this.surface,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasClass = className != null && className!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GroupRow.card(
        onTap: onTap,
        color: surface,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        // crossAxisAlignment.start: карточка теперь переменной высоты (задание
        // может занять две строки), и значок обязан держаться верха, а не
        // «плавать» по центру относительно соседних карточек.
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 44, height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isFresh ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(AppRadii.tile),
            ),
            child: Icon(icon, size: 20, color: color)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Строка 1: тип события + время ────────────────────────────
            Row(children: [
              if (isFresh)
                Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              // FittedBox внутри Expanded: тип события — короткая служебная
              // подпись, её лучше слегка ужать, чем оборвать многоточием
              // («Тапсырма бағаланды» длиннее английского вдвое).
              Expanded(child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(kindLabel, maxLines: 1,
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      letterSpacing: 0.1, color: color, height: 1.2)),
                ),
              )),
              if (timeAgo.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(timeAgo, maxLines: 1,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                      letterSpacing: -0.1, color: adaptiveText4(context))),
              ],
            ]),
            const SizedBox(height: 4),

            // ── Строка 2: название задания ───────────────────────────────
            Text(subject,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600,
                letterSpacing: -0.3, color: adaptiveText1(context), height: 1.25)),

            // ── Строка 3: предмет + балл/остаток ─────────────────────────
            if (hasClass || accent != null) ...[
              const SizedBox(height: 7),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (hasClass) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Icon(CupertinoIcons.book_fill, size: 12, color: adaptiveText4(context)),
                  ),
                  const SizedBox(width: 5),
                  Expanded(child: Text(className!,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                      letterSpacing: -0.1, height: 1.25, color: adaptiveText3(context)))),
                ] else
                  const Spacer(),
                if (accent != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                    ),
                    child: Text(accent!, maxLines: 1,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        letterSpacing: -0.1, color: color)),
                  ),
                ],
              ]),
            ],
          ])),
        ]),
      ),
    );
  }
}
