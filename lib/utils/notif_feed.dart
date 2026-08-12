import '../services/api_service.dart';
import 'dates.dart';

/// ЕДИНСТВЕННОЕ место, где вычисляется, какие уведомления есть у пользователя.
///
/// Раньше их считали ДВА независимых куска кода: `ClassesProvider.loadNotifBadge`
/// (число на колокольчике) и `NotificationsScreen._load` (сам список). Правила
/// в них разошлись, и бейдж показывал «1» при пустом списке — навсегда, потому
/// что «прочитанным» уведомление отмечается только при показе в списке:
///
///  * бейдж считал ЛЮБУЮ проверенную работу, а список показывал её только если
///    класс задания нашёлся среди `getPosts()` — а это первая страница (100
///    записей) вместе с лекциями, так что у активного класса пост-«класс»
///    просто уезжал за пределы страницы;
///  * членство в классах бейдж брал из `joinedClassIds` провайдера, а список —
///    из SharedPreferences (`joined_classes_$uid`); после входа в другой
///    аккаунт кэша не было, и «новые задания» в список не попадали вообще;
///  * `loadJoined()` и `loadNotifBadge()` на главном экране запускались
///    параллельно, поэтому бейдж часто считался по ещё пустому `joinedClassIds`.
///
/// Теперь оба потребителя вызывают [loadNotifFeed], а счётчик — это
/// [NotifFeed.unreadCount] того же самого списка: разойтись они не могут
/// по построению.
enum NotifKind { grade, newAssignment, deadline }

class NotifItem {
  /// Канонический ключ состояния на сервере: '{kind}:{ref_id}'.
  final String key;
  final NotifKind kind;
  final DateTime date;
  final bool isRead;

  /// Класс задания — только если пользователь всё ещё его участник: по нему
  /// строится переход из уведомления, и вести в класс без доступа нельзя.
  final int? classId;
  final String? className;

  /// Название задания; null — задание не найдено (например, уехало за пределы
  /// страницы выдачи), тогда экран подставит родовое «Задание».
  final String? assignmentTitle;

  /// Балл — для [NotifKind.grade].
  final num? score;

  /// Сколько осталось до дедлайна — для [NotifKind.deadline].
  final Duration? remaining;

  const NotifItem({
    required this.key,
    required this.kind,
    required this.date,
    required this.isRead,
    this.classId,
    this.className,
    this.assignmentTitle,
    this.score,
    this.remaining,
  });

  NotifItem copyWith({bool? isRead}) => NotifItem(
        key: key,
        kind: kind,
        date: date,
        isRead: isRead ?? this.isRead,
        classId: classId,
        className: className,
        assignmentTitle: assignmentTitle,
        score: score,
        remaining: remaining,
      );
}

class NotifFeed {
  final List<NotifItem> items;

  const NotifFeed({required this.items});

  /// Одно правило для счётчика, для точек в списке и для «отметить все»:
  /// непрочитанное — это `!isRead`, без исключений по типу. Дедлайны приходят
  /// из фида уже «прочитанными» (см. ниже), поэтому отдельная оговорка
  /// «кроме дедлайнов» больше не нужна — а именно из таких оговорок,
  /// продублированных в трёх местах с разными формулировками, и вырастало
  /// расхождение бейджа со списком.
  int get unreadCount => items.where((i) => !i.isRead).length;
}

/// Страница выдачи для фида. Дефолтные 50 заданий/100 постов — размеры под
/// экранные списки; здесь нужен полный охват, иначе уведомление о проверенной
/// работе теряет своё задание (а раньше — и вовсе исчезало из списка, оставаясь
/// в счётчике).
const int _feedPageSize = 200;

/// Окно «новое задание» и окно «скоро дедлайн» — те же значения, что были в
/// обеих старых реализациях.
const Duration _newAssignmentWindow = Duration(days: 7);
const Duration _deadlineWindow = Duration(hours: 48);

Future<NotifFeed> loadNotifFeed(ApiService api, {DateTime? now}) async {
  final at = now ?? DateTime.now();

  List<dynamic> mySubs = [];
  List<dynamic> assignments = [];
  List<dynamic> myClasses = [];
  List<dynamic> states = [];

  // Каждый запрос со своим catch: одна упавшая ручка не должна обнулять фид
  // целиком (в офлайне это выглядело бы как «уведомления пропали»).
  await Future.wait([
    () async { try { mySubs = await api.getMySubmissions(); } catch (_) {} }(),
    () async { try { assignments = await api.getAssignments(pageSize: _feedPageSize); } catch (_) {} }(),
    () async { try { myClasses = await api.getClasses(); } catch (_) {} }(),
    () async { try { states = await api.getNotifStates(); } catch (_) {} }(),
  ]);

  final readBy = <String, bool>{};
  final dismissed = <String>{};
  for (final s in states) {
    final key = (s['notif_key'] ?? '').toString();
    if (key.isEmpty) continue;
    if (s['dismissed'] == true) dismissed.add(key);
    readBy[key] = s['read'] == true;
  }

  // Членство — серверная истина (GET /classes/), а не локальный кэш: иначе на
  // новом устройстве или после входа в другой аккаунт список пуст, а счётчик
  // считает по данным сервера.
  final classNames = <int, String>{};
  for (final c in myClasses) {
    final id = (c['id'] as num?)?.toInt();
    if (id == null) continue;
    classNames[id] = (c['name'] ?? c['title'] ?? '').toString();
  }

  final assignmentById = <int, dynamic>{};
  for (final a in assignments) {
    final id = (a['id'] as num?)?.toInt();
    if (id != null) assignmentById[id] = a;
  }

  final subByAssignment = <int, dynamic>{};
  for (final s in mySubs) {
    final aId = (s['assignment_id'] as num?)?.toInt();
    if (aId != null) subByAssignment[aId] = s;
  }

  final items = <NotifItem>[];

  // ── Проверенные работы ──────────────────────────────────────────────
  for (final sub in mySubs) {
    if (sub['status'] != 'graded' || sub['grade'] == null) continue;
    final subId = (sub['id'] as num?)?.toInt();
    if (subId == null) continue;
    final key = 'grade:$subId';
    if (dismissed.contains(key)) continue;

    final a = assignmentById[(sub['assignment_id'] as num?)?.toInt()];
    final cid = (a?['class_id'] as num?)?.toInt();
    final isMember = cid != null && classNames.containsKey(cid);

    items.add(NotifItem(
      key: key,
      kind: NotifKind.grade,
      // Момент ПРОВЕРКИ, а не сдачи: уведомление сообщает «работу проверили»,
      // поэтому и «2 дня назад», и группа «Сегодня/Вчера» должны считаться от
      // graded_at. submitted_at — фолбэк для старых записей без graded_at.
      date: parseServerDate(sub['grade']['graded_at']?.toString()) ??
          parseServerDate(sub['submitted_at']?.toString()) ??
          at,
      isRead: readBy[key] == true,
      classId: isMember ? cid : null,
      className: isMember ? classNames[cid] : null,
      assignmentTitle: a?['title']?.toString(),
      score: sub['grade']['score'] as num?,
    ));
  }

  // ── Новые задания и близкие дедлайны (только в своих классах) ───────
  for (final a in assignments) {
    final aId = (a['id'] as num?)?.toInt();
    final cid = (a['class_id'] as num?)?.toInt();
    if (aId == null || cid == null || !classNames.containsKey(cid)) continue;

    final title = a['title']?.toString();
    final createdAt = parseServerDate(a['created_at']?.toString());
    final newKey = 'assignment:$aId';
    // Допуск в час вперёд — расхождение часов клиента и сервера: только что
    // созданное задание не должно выпадать из «новых» из-за пары секунд.
    final age = createdAt == null ? null : at.difference(createdAt);
    if (age != null &&
        !dismissed.contains(newKey) &&
        age <= _newAssignmentWindow &&
        age >= const Duration(hours: -1)) {
      items.add(NotifItem(
        key: newKey,
        kind: NotifKind.newAssignment,
        date: createdAt!,
        isRead: readBy[newKey] == true,
        classId: cid,
        className: classNames[cid],
        assignmentTitle: title,
      ));
    }

    final deadline = parseServerDate(a['deadline']?.toString());
    final deadlineKey = 'deadline:$aId';
    if (deadline != null &&
        !dismissed.contains(deadlineKey) &&
        deadline.isAfter(at) &&
        deadline.difference(at) <= _deadlineWindow &&
        subByAssignment[aId] == null) {
      items.add(NotifItem(
        key: deadlineKey,
        kind: NotifKind.deadline,
        date: deadline,
        // Дедлайн — напоминание, а не новость: он не «прочитывается» (иначе
        // висел бы на колокольчике до самого срока сдачи), поэтому в фид он
        // приходит сразу прочитанным и в счётчик не попадает. Убрать его можно
        // свайпом, а сам он исчезнет после сдачи или когда срок пройдёт.
        isRead: true,
        classId: cid,
        className: classNames[cid],
        assignmentTitle: title,
        remaining: deadline.difference(at),
      ));
    }
  }

  // Непрочитанные — сверху, внутри группы — свежие первыми.
  items.sort((a, b) {
    if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
    return b.date.compareTo(a.date);
  });

  return NotifFeed(items: items);
}
