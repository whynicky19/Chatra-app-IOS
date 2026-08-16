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

/// Экран уведомлений: полупрозрачный крупный заголовок, под который уезжает
/// содержимое, и inset-grouped список.
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
  Set<String> _fresh = {};

  late final ClassesProvider _classesProvider;

  @override
  void initState() {
    super.initState();
    // Провайдер берём СРАЗУ, а не лениво: бейдж синхронизируется после сетевого
    // ожидания, и на закрытом экране `context.read` упал бы на deactivated widget.
    _classesProvider = context.read<ClassesProvider>();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final api = context.read<ApiService>();
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
    // Не выходим по !mounted: отметка прочитанным и синхронизация бейджа
    // обязаны отработать, даже если экран уже закрыли.
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

  /// Название задания — главная строка.
  String _subject(NotifItem n, L10n l) =>
      n.assignmentTitle?.trim().isNotEmpty == true ? n.assignmentTitle! : l.t('assignment');

  /// Короткая акцентная метка в мета-строке: балл или остаток времени.
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
  /// назад» для неё смысла не имеет.
  String _timeAgo(NotifItem n, L10n l) {
    if (n.kind == NotifKind.deadline) return '';
    final diff = DateTime.now().difference(n.date);
    // Отрицательная разница (часы сервера впереди) попадает сюда же.
    if (diff.inMinutes < 1) return l.t('just_now');
    if (diff.inHours < 1) return '${diff.inMinutes} ${l.t('minutes_short')}';
    if (diff.inDays < 1) return '${diff.inHours} ${l.t('hours_short')}';
    if (diff.inDays < 7) return '${diff.inDays} ${l.t('days_short')}';
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

/// Содержимое строки уведомления: название задания со временем справа и серая
/// мета-строка «тип события · предмет · балл» под ним.
class _NotifRowContent extends StatelessWidget {
  const _NotifRowContent({
    required this.subject,
    required this.className,
    required this.accent,
    required this.isFresh,
    required this.icon,
    required this.color,
    required this.timeAgo,
  });

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

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(width: 12, child: isFresh
          ? Center(child: Container(width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)))
          : null),
      SizedBox(width: 26, child: Icon(icon, size: 22, color: color)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(subject,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600,
              letterSpacing: -0.3, color: adaptiveText1(context), height: 1.25))),
          if (timeAgo.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(timeAgo, maxLines: 1,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: -0.1,
                  color: adaptiveText4(context),
                  fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ]),

        if (hasClass || accent != null) ...[
          const SizedBox(height: 3),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (hasClass) ...[
              Expanded(child: Text(className!,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500,
                  letterSpacing: -0.1, height: 1.25, color: adaptiveText3(context)))),
              const SizedBox(width: 8),
            ],
            if (accent != null)
              Text(accent!, maxLines: 1,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.1,
                  height: 1.25, color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ],
      ])),
    ]);
  }
}
