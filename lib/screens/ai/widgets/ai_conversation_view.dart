import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:dio/dio.dart' show CancelToken, DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../providers/ai_chats_provider.dart';
import '../../../services/api_service.dart';
import '../../../utils/ai_context.dart';
import '../../../utils/ai_quota.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ai_limit_notice.dart';
import '../../../widgets/inset_group.dart';
import '../../../widgets/tappable.dart';
import '../../../widgets/toast.dart';
import '../../../utils/dates.dart';
import 'ai_message_content.dart';
import '../../../utils/haptics.dart';

/// Тело одной переписки с главным ИИ-ассистентом: список сообщений + композер.
/// Встраивается как body в [AiScreen] (не пуш-экран) — история открывается
/// поверх неё в drawer. Если [threadId] ещё нет (новый чат), тред лениво
/// создаётся при первой отправке и сообщается наверх через [onThreadCreated].
class AiConversationView extends StatefulWidget {
  final int? threadId;
  final ValueChanged<int> onThreadCreated;

  const AiConversationView({
    super.key,
    required this.threadId,
    required this.onThreadCreated,
  });

  @override
  State<AiConversationView> createState() => _AiConversationViewState();
}

class _AiConversationViewState extends State<AiConversationView> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _msgs = [];
  bool _loading = false;
  CancelToken? _cancelToken;
  String? _pendingRequestId;
  AiQuota? _quota;
  int? _threadId;
  // Сообщения с индексом < этого порога — уже загруженная история: у них
  // нет entrance-анимации (см. _messageList). Иначе при открытии чата с
  // длинной перепиской десятки сообщений одновременно проигрывали бы
  // fade+slide, накладываясь на автоскролл — визуально «рвано». Анимация
  // появления остаётся только для реально нового сообщения (send/receive).
  int _bulkLoadedCount = 0;
  // Пока история существующего треда ещё грузится, список скрыт — как
  // только он готов (и уже доскроллен вниз), один плавный fade-in вместо
  // резкого появления. Новый пустой чат виден сразу, скрывать нечего.
  bool _listVisible = false;

  /// uid фиксируется один раз в initState. Раньше он читался через
  /// context.read внутри _loadLocal/_saveHistory — то есть УЖЕ ПОСЛЕ
  /// асинхронного разрыва (await SharedPreferences / .then). Если пользователь
  /// закрывал чат в этот момент (отправил сообщение и сразу свайпнул назад),
  /// context.read на деактивированном виджете бросал
  /// «Looking up a deactivated widget's ancestor is unsafe».
  late final String _uidPart;

  @override
  void initState() {
    super.initState();
    _uidPart = context.read<AuthProvider>().userId?.toString() ?? 'anon';
    _threadId = widget.threadId;
    _listVisible = _threadId == null;
    if (_threadId != null) _restoreHistory(_threadId!);
    _loadQuota();
  }

  String _historyKey(int threadId) => 'ai_chat_history_v2_${_uidPart}_$threadId';

  Future<void> _restoreHistory(int threadId) async {
    final local = await _loadLocal(threadId);
    if (mounted && local.isNotEmpty) {
      setState(() {
        _msgs
          ..clear()
          ..addAll(local);
        _bulkLoadedCount = _msgs.length;
      });
      _scrollDown(animate: false, reveal: true);
    }
    await _syncFromServer(threadId, local);
  }

  Future<void> _loadQuota() async {
    try {
      final q = AiQuota.fromJson(await context.read<ApiService>().getAiLimits());
      if (mounted && q != null) setState(() => _quota = q);
    } catch (_) {}
  }

  Future<List<Map<String, String>>> _loadLocal(int threadId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey(threadId));
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _syncFromServer(int threadId, List<Map<String, String>> local) async {
    try {
      final api = context.read<ApiService>();
      var rows = await api.getAiHistory(threadId: threadId);
      if (rows.isEmpty && local.isNotEmpty) {
        rows = await api.importAiHistory(
          local.map((m) => {'role': m['role'] ?? 'user', 'content': m['text'] ?? ''}).toList(),
          threadId: threadId,
        );
      }
      final list = rows
          .map<Map<String, String>>((r) => {
                'role': (r['role'] ?? 'assistant').toString(),
                'text': (r['content'] ?? '').toString(),
                'time': _fmtTime(r['created_at']),
              })
          .toList();
      if (!mounted || _threadId != threadId) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(list);
        _bulkLoadedCount = _msgs.length;
      });
      _saveHistory();
      _scrollDown(animate: false, reveal: true);
    } catch (_) {
      // Сеть недоступна и локальной истории тоже не было — не оставлять
      // список невидимым навсегда.
      if (mounted && !_listVisible) setState(() => _listVisible = true);
    }
  }

  String _fmtTime(dynamic iso) {
    final dt = parseServerDate(iso.toString());
    if (dt == null) return _now();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _saveHistory() {
    final threadId = _threadId;
    if (threadId == null) return;
    // Ключ и снапшот считаем ДО асинхронного разрыва: _msgs может измениться,
    // пока мы ждём SharedPreferences.
    final key = _historyKey(threadId);
    final snapshot = List<Map<String, String>>.from(_msgs);
    SharedPreferences.getInstance().then((prefs) {
      try {
        prefs.setString(key, jsonEncode(snapshot));
      } catch (_) {}
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _tips(L10n l) {
    final isKZ = l.lang == 'KZ';
    final isEN = l.lang == 'EN';
    return [
      {
        'icon': CupertinoIcons.book,
        'title': isKZ ? 'Тақырыпты түсіндір' : isEN ? 'Explain Topic' : 'Объяснить тему',
        'desc': isKZ
            ? 'Күрделі тұжырымды қарапайым сөздермен'
            : isEN
                ? 'Break down complex concepts in simple words'
                : 'Разбери сложную концепцию простыми словами',
        'prompt': l.t('tip_explain'),
      },
      {
        'icon': CupertinoIcons.lightbulb,
        'title': isKZ ? 'Тұжырымдарды ашу' : isEN ? 'Break Down Concepts' : 'Разобрать концепции',
        'desc': isKZ
            ? 'Тәсілдер арасындағы айырмашылықты түсін'
            : isEN
                ? 'Understand the difference between approaches'
                : 'Помоги понять разницу между подходами',
        'prompt': l.t('tip_concepts'),
      },
      {
        'icon': CupertinoIcons.pencil,
        'title': isKZ ? 'Тапсырмаға көмек' : isEN ? 'Help with Task' : 'Помочь с заданием',
        'desc': isKZ
            ? 'Шешімді қайдан бастау керектігін айт'
            : isEN
                ? 'Tell me where to start the solution'
                : 'Подскажи, с чего начать решение',
        'prompt': l.t('tip_help'),
      },
      {
        'icon': CupertinoIcons.exclamationmark_triangle,
        'title': isKZ ? 'Қателерді тап' : isEN ? 'Find Mistakes' : 'Найти ошибки',
        'desc': isKZ
            ? 'Кодымды тексеріп, мәселелерді көрсет'
            : isEN
                ? 'Review my code and point out issues'
                : 'Проверь мой код и укажи на проблемы',
        'prompt': l.t('tip_mistakes'),
      },
    ];
  }

  String _now() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  /// Тред создаётся лениво: первое сообщение в новом чате сначала заводит
  /// тред на бэке (обязателен thread_id для главного ассистента), потом шлёт.
  Future<int?> _ensureThread() async {
    if (_threadId != null) return _threadId;
    try {
      final t = await context.read<AiChatsProvider>().createThread();
      _threadId = t.id;
      widget.onThreadCreated(t.id);
      return t.id;
    } catch (_) {
      return null;
    }
  }

  // Future<void>, а не async void: из async void исключения не всплывают
  // к вызывающему коду и теряются.
  Future<void> _send([String? override]) async {
    final text = override ?? _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    if (_quota?.exhausted == true) {
      showToast(context, context.read<L10n>().t('ai_daily_exhausted'), error: true);
      return;
    }
    hapticLight();
    setState(() => _msgs.add({'role': 'user', 'text': text, 'time': _now()}));
    _saveHistory();
    _ctrl.clear();
    _scrollDown();
    await _requestReply();
  }

  /// Пересылает боту хвост текущей `_msgs` (последнее сообщение в списке —
  /// вопрос, на который нужен ответ) и добавляет ответ. Общая часть для
  /// обычной отправки, повтора неудачной отправки и перегенерации ответа —
  /// все три отличаются только тем, что делают с `_msgs` ДО вызова этого
  /// метода, сама отправка и обработка результата одинаковые.
  Future<void> _requestReply() async {
    setState(() => _loading = true);
    _cancelToken = CancelToken();
    // Свой id на каждый запрос — если пользователь нажмёт «Стоп», именно он
    // уходит на /ai/chat/cancel (см. _stop), отдельно от CancelToken, который
    // рвёт только клиентское соединение и не обязательно долетает до сервера.
    final requestId = '${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(_cancelToken)}';
    _pendingRequestId = requestId;
    try {
      final threadId = await _ensureThread();
      if (!mounted) return;
      if (threadId == null) throw Exception('no_thread');
      final api = context.read<ApiService>();
      final l = context.read<L10n>();
      final sysLang = l.lang == 'KZ' ? 'казахском' : l.lang == 'EN' ? 'английском' : 'русском';
      final apiMsgs = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content': 'Ты AI-ассистент образовательной платформы Chatra. Отвечай на $sysLang языке. '
              'Все математические формулы пиши в LaTeX: инлайн — между одинарными \$...\$, '
              'формулу на отдельной строке — между двойными \$\$...\$\$. Не используй другой синтаксис для формул.'
        },
        // Только хвост переписки: полная история росла без ограничений и
        // упиралась в лимит контекста модели. См. utils/ai_context.dart.
        ...aiContextWindow(_msgs),
      ];
      final data = await api.aiChat(apiMsgs, threadId: threadId, cancelToken: _cancelToken, requestId: requestId);
      if (!mounted) return;
      setState(() {
        _msgs.add({'role': 'assistant', 'text': data['content'] ?? context.read<L10n>().t('no_answer'), 'time': _now()});
        _quota = AiQuota.fromJson(data['quota']) ?? _quota;
      });
      _saveHistory();
      final newTitle = data['thread_title']?.toString();
      if (newTitle != null && newTitle.isNotEmpty) {
        context.read<AiChatsProvider>().patchLocal(threadId, title: newTitle, updatedAt: DateTime.now());
      } else {
        context.read<AiChatsProvider>().patchLocal(threadId, updatedAt: DateTime.now());
      }
    } catch (e) {
      if (!mounted) return;
      // Отменено кнопкой «Остановить» — не ошибка: без тоста, без пометки
      // сообщения неудачным, ничего не летит в Crashlytics (тут и так нет
      // логирования этой ветки).
      if (e is DioException && CancelToken.isCancel(e)) {
        // ничего не делаем — просто перестаём ждать ответ.
      } else {
        final l = context.read<L10n>();
        final resp = (e is DioException) ? e.response : null;
        final detail = (resp?.data is Map) ? resp!.data['detail']?.toString() : null;
        final errText = resp?.statusCode == 429
            ? (detail ?? l.t('ai_daily_exhausted'))
            : e.toString().contains('503')
                ? l.t('ai_not_configured')
                : l.t('connection_error');
        showToast(context, errText, error: true);
        // Раньше сюда добавлялось фейковое сообщение ассистента с текстом
        // ошибки. Теперь вместо этого помечаем последнее (не отправленное)
        // сообщение — оно рисуется приглушённым с кнопкой «Повторить»,
        // см. _userMessage.
        if (_msgs.isNotEmpty && _msgs.last['role'] == 'user') {
          setState(() => _msgs[_msgs.length - 1] = {..._msgs.last, 'failed': 'true'});
        }
        _saveHistory();
        if (resp?.statusCode == 429) _loadQuota();
      }
    }
    _cancelToken = null;
    _pendingRequestId = null;
    if (mounted) setState(() => _loading = false);
    _scrollDown();
  }

  /// Кнопка «Остановить» на композере — отменяет текущий запрос к ИИ и
  /// отдельно сообщает бэкенду не сохранять ответ, если он всё же придёт
  /// (см. ApiService.cancelAiChat — CancelToken рвёт только наше соединение,
  /// сервер не всегда это замечает).
  void _stop() {
    _cancelToken?.cancel();
    final requestId = _pendingRequestId;
    if (requestId != null) context.read<ApiService>().cancelAiChat(requestId);
  }

  /// «Повторить» под неотправленным (failed) сообщением: снимает пометку
  /// и переспрашивает тем же текстом.
  Future<void> _retryFailed(int index) async {
    if (_loading || index != _msgs.length - 1) return;
    setState(() {
      final m = Map<String, String>.from(_msgs[index])..remove('failed');
      _msgs[index] = m;
    });
    _saveHistory();
    await _requestReply();
  }

  /// «Повторить» под последним ответом ассистента: удаляет этот ответ и
  /// заново запрашивает ответ на тот же (уже стоящий в _msgs) вопрос.
  Future<void> _regenerateLast() async {
    if (_loading || _msgs.isEmpty || _msgs.last['role'] != 'assistant') return;
    hapticLight();
    setState(() => _msgs.removeLast());
    _saveHistory();
    await _requestReply();
  }

  // animate=false — мгновенный переход в конец при открытии чата/подгрузке
  // истории: если тут анимировать через animateTo, ListView.builder ещё не
  // построенные сообщения лениво создаёт прямо во время скролла, и у каждого
  // при первом построении играет своя entrance-анимация (см. _messageList) —
  // это и давало ощущение «рваного» скролла на длинной переписке. Плавную
  // анимацию оставляем только для реально нового сообщения (send/receive),
  // там дистанция маленькая и лишних вставок не происходит.
  void _scrollDown({bool animate = true, bool reveal = false}) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_scroll.hasClients) {
        if (reveal && mounted) setState(() => _listVisible = true);
        return;
      }
      if (!animate) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        // Список уже стоит на нужной позиции — теперь можно плавно проявить
        // его одним лёгким fade-in вместо резкого появления.
        if (reveal && mounted) setState(() => _listVisible = true);
        // Корректирующий джамп: если контент (картинки/markdown) доразметился
        // уже после первого прыжка, maxScrollExtent мог вырасти.
        Future.delayed(const Duration(milliseconds: 120), () {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
        return;
      }
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // watch, а не read: раньше L10n читался только внутри _emptyState, и при
    // смене языка прямо в открытом чате с перепиской (messageList, не empty
    // state) build ничего не перезапускал — дисклеймер и другие l.t() тексты
    // «зависали» на старом языке, пока экран не переоткроют.
    final l = context.watch<L10n>();

    return Column(children: [
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          // Пока грузится история уже существующего треда (threadId != null),
          // держим _messageList (пусть пока и без элементов) вместо
          // _emptyState — иначе на каждое открытие чата с перепиской
          // AnimatedSwitcher лишний раз проигрывал бы fade+slide переход
          // empty → list ровно в момент, когда сообщения появляются.
          child: (_msgs.isEmpty && widget.threadId == null)
              ? _emptyState(l)
              : AnimatedOpacity(
                  // Список уже доскроллен вниз (см. _scrollDown reveal) —
                  // остаётся только мягко проявить его одним fade-in, без
                  // отдельных анимаций на каждое сообщение.
                  opacity: _listVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: _messageList(isDark),
                ),
        ),
      ),
      // Дисклеймер живёт только в пустом чате — как только появляется первое
      // сообщение, он плавно схлопывается, освобождая место композеру.
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.bottomCenter,
        child: _msgs.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                child: Text(
                  l.t('ai_disclaimer'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: adaptiveText4(context), height: 1.35, letterSpacing: -0.1),
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
      _AiInputBar(ctrl: _ctrl, loading: _loading, quota: _quota, onSend: _send, onStop: _stop),
    ]);
  }

  Widget _emptyState(L10n l) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tips = _tips(l);
    final isKZ = l.lang == 'KZ';
    final isEN = l.lang == 'EN';
    final subtitle = isKZ
        ? 'Оқу туралы кез келген нәрсе сұраңыз'
        : isEN
            ? 'Ask anything about your studies'
            : 'Спросите что угодно об учёбе';

    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        key: const ValueKey('empty_state'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Chatra AI',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: adaptiveText1(context), letterSpacing: -0.9, height: 1.1)),
            const SizedBox(height: 8),
            Text(subtitle,
                style: TextStyle(fontSize: 16, color: adaptiveText3(context), height: 1.35, letterSpacing: -0.2),
                textAlign: TextAlign.center),
            const SizedBox(height: 28),
            // Подсказки — одна сгруппированная секция, а не стопка отдельных
            // карточек с зазорами: так они читаются как один список выбора.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? C.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: adaptiveBorder(context).withValues(alpha: 0.5), width: hairline(context)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: Column(children: [
                    for (var i = 0; i < tips.length; i++) _suggestionRow(tips[i], i, tips.length),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }

  Widget _suggestionRow(Map<String, dynamic> tip, int index, int count) {
    final primary = Theme.of(context).colorScheme.primary;
    return Entrance(
      index: index,
      rise: 0,
      child: GroupRow(
        pos: index == count - 1 ? GroupPos.last : GroupPos.middle,
        color: Colors.transparent,
        separatorInset: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () {
          hapticSelection();
          _send(tip['prompt'] as String);
        },
        child: Row(children: [
          Container(
            width: 28, height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
            child: Icon(tip['icon'] as IconData, size: 15, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tip['title'] as String,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: adaptiveText1(context), letterSpacing: -0.3)),
          ),
          const SizedBox(width: 10),
          Icon(CupertinoIcons.arrow_up_left, size: 15, color: adaptiveText4(context).withValues(alpha: 0.7)),
        ]),
      ),
    );
  }

  Widget _messageList(bool isDark) {
    // Верхний паддинг = safe-area + место под плавающую кнопку истории —
    // без отдельной полосы-хедера: это просто отступ первого сообщения
    // внутри самого скролла, он уезжает вверх при прокрутке как обычно.
    final topPad = MediaQuery.of(context).padding.top + 60;
    return ListView.builder(
      key: const ValueKey('msg_list'),
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topPad, 16, 14),
      itemCount: _msgs.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _msgs.length) return _typingIndicator();
        final m = _msgs[i];
        final isUser = m['role'] == 'user';
        final bubble = RepaintBoundary(
          child: isUser ? _userMessage(m, i) : _aiMessage(m, i, isDark),
        );
        // Уже загруженная история появляется сразу, без entrance-анимации —
        // она играла бы для каждого сообщения при каждом открытии чата
        // (см. _bulkLoadedCount). Анимация появления — только для реально
        // нового сообщения (только что отправленного/полученного).
        if (i < _bulkLoadedCount) return bubble;
        return TweenAnimationBuilder<double>(
          key: ValueKey('msg_$i'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(isUser ? 18 * (1 - t) : -18 * (1 - t), 8 * (1 - t)), child: child),
          ),
          child: bubble,
        );
      },
    );
  }

  Widget _userMessage(Map<String, String> m, int index) {
    final text = m['text'] ?? '';
    final timeStr = m['time'] ?? '';
    final failed = m['failed'] == 'true';
    final l = context.read<L10n>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18, left: 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Opacity(
          opacity: failed ? 0.5 : 1,
          // Плоская заливка акцентом без градиента, свечения и тени под
          // текстом: пузырь iMessage — это ровный цвет, а тень/градиент/
          // text-shadow заметно снижают читаемость белого текста.
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(text,
                style: const TextStyle(
                  fontSize: 16.5,
                  color: Colors.white,
                  height: 1.35,
                  letterSpacing: -0.3,
                )),
          ),
        ),
        const SizedBox(height: 5),
        if (failed)
          Tappable(
            onTap: () => _retryFailed(index),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(CupertinoIcons.exclamationmark_circle, size: 12, color: C.red),
              const SizedBox(width: 3),
              Text(l.t('not_sent'), style: const TextStyle(fontSize: 10.5, color: C.red)),
              const SizedBox(width: 6),
              Text('· ${l.t('retry')}',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Text(timeStr, style: TextStyle(fontSize: 11.5, color: adaptiveText4(context), letterSpacing: -0.1)),
          ),
      ]),
    );
  }

  Widget _aiMessage(Map<String, String> m, int index, bool isDark) {
    final text = m['text'] ?? '';
    final l = context.read<L10n>();
    final isLast = index == _msgs.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 52),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Tappable(
            onLongPress: () {
              hapticMedium();
              Clipboard.setData(ClipboardData(text: text));
              showToast(context, l.t('copied'));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? C.darkSurface2 : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(20),
                ),
                border: Border.all(color: adaptiveBorder(context).withValues(alpha: isDark ? 0.35 : 0.45), width: hairline(context)),
              ),
              child: AiMessageContent(
                text: text,
                style: TextStyle(fontSize: 16.5, height: 1.45, letterSpacing: -0.2, color: adaptiveText1(context)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 7, top: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if ((m['time'] ?? '').isNotEmpty)
                Text(m['time']!, style: TextStyle(fontSize: 11.5, color: adaptiveText4(context), letterSpacing: -0.1)),
              if (isLast && !_loading) ...[
                if ((m['time'] ?? '').isNotEmpty) const SizedBox(width: 10),
                Tappable(
                  onTap: _regenerateLast,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.arrow_2_squarepath, size: 10.5, color: C.text4.withValues(alpha: 0.8)),
                    const SizedBox(width: 3),
                    Text(l.t('retry'), style: TextStyle(fontSize: 11.5, color: adaptiveText4(context), letterSpacing: -0.1)),
                  ]),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _typingIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 52),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface2 : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(20),
            ),
            border: Border.all(color: adaptiveBorder(context).withValues(alpha: isDark ? 0.35 : 0.45), width: hairline(context)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => _Dot(delay: i * 180))),
        ),
      ),
    );
  }
}

class _AiInputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final bool loading;
  final AiQuota? quota;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const _AiInputBar({required this.ctrl, required this.loading, required this.onSend, required this.onStop, this.quota});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final l = context.read<L10n>();
    final isKZ = l.lang == 'KZ';
    final isEN = l.lang == 'EN';
    final exhausted = quota?.exhausted ?? false;
    final hint = exhausted
        ? l.t('ai_limit_reached_title')
        : isKZ
            ? 'Chatra AI-дан сұраңыз...'
            : isEN
                ? 'Ask Chatra AI...'
                : 'Спросите Chatra AI...';

    // Композер — матовое стекло поверх переписки: сообщения просвечивают
    // сквозь него на скролле, вместо непрозрачной полосы, отрезающей низ
    // экрана. Блюр + полупрозрачная заливка, светлая линия сверху = свет,
    // поймавший край материала.
    return ClipRect(
      child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, bottomBarInset(context)),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.80),
        border: Border(top: BorderSide(color: adaptiveBorder(context).withValues(alpha: 0.5), width: hairline(context))),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (exhausted) AiLimitNotice(quota: quota!),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 46),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: adaptiveBorder(context).withValues(alpha: 0.45), width: hairline(context)),
              ),
              child: TextField(
                controller: ctrl,
                enabled: !exhausted,
                style: TextStyle(fontSize: 16.5, height: 1.3, letterSpacing: -0.3, color: adaptiveText1(context)),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: adaptiveText4(context), fontSize: 16.5, letterSpacing: -0.3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onSubmitted: (_) => onSend(),
                maxLines: 4,
                minLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: ctrl,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              final active = hasText && !loading && !exhausted;
              return Tappable(
                onTap: loading ? onStop : (exhausted ? null : onSend),
                label: loading ? 'Остановить генерацию' : 'Отправить сообщение',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Плоский акцент вместо цветного свечения: в iOS активная
                    // кнопка отправки — просто залитый круг.
                    color: (active || loading) ? Theme.of(context).colorScheme.primary : adaptiveSurface2(context),
                    border: (active || loading)
                        ? null
                        : Border.all(color: adaptiveBorder(context).withValues(alpha: 0.45), width: hairline(context)),
                  ),
                  // Пока идёт генерация — квадратик "стоп" вместо крутилки: и
                  // видно, что запрос ещё летит, и его можно отменить тапом.
                  child: loading
                      ? const Center(
                          child: Icon(CupertinoIcons.stop_fill, color: Colors.white, size: 18))
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                          child: Icon(
                            CupertinoIcons.arrow_up,
                            key: ValueKey(active),
                            color: active ? Colors.white : adaptiveText4(context),
                            size: 20,
                          ),
                        ),
                ),
              );
            },
          ),
        ]),
      ]),
      ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.repeat(reverse: true);
    });
    _anim = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: adaptiveText4(context).withValues(alpha: 0.35 + _anim.value * 0.55),
            shape: BoxShape.circle,
          ),
          transform: Matrix4.translationValues(0, -4 * _anim.value, 0),
        ),
      );
}
