import 'dart:convert';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../providers/ai_chats_provider.dart';
import '../../../services/api_service.dart';
import '../../../utils/ai_quota.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ai_limit_notice.dart';
import '../../../widgets/toast.dart';
import 'ai_message_content.dart';

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
  AiQuota? _quota;
  int? _threadId;

  @override
  void initState() {
    super.initState();
    _threadId = widget.threadId;
    if (_threadId != null) _restoreHistory(_threadId!);
    _loadQuota();
  }

  String _historyKey(int threadId) {
    final uid = context.read<AuthProvider>().userId;
    return 'ai_chat_history_v2_${uid ?? 'anon'}_$threadId';
  }

  Future<void> _restoreHistory(int threadId) async {
    final local = await _loadLocal(threadId);
    if (mounted && local.isNotEmpty) {
      setState(() {
        _msgs
          ..clear()
          ..addAll(local);
      });
      _scrollDown();
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
      });
      _saveHistory();
      _scrollDown();
    } catch (_) {}
  }

  String _fmtTime(dynamic iso) {
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return _now();
    }
  }

  void _saveHistory() {
    final threadId = _threadId;
    if (threadId == null) return;
    SharedPreferences.getInstance().then((prefs) {
      try {
        prefs.setString(_historyKey(threadId), jsonEncode(_msgs));
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

  void _send([String? override]) async {
    final text = override ?? _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    if (_quota?.exhausted == true) {
      showToast(context, context.read<L10n>().t('ai_daily_exhausted'), error: true);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _msgs.add({'role': 'user', 'text': text, 'time': _now()});
      _loading = true;
    });
    _saveHistory();
    _ctrl.clear();
    _scrollDown();
    try {
      final threadId = await _ensureThread();
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
        ..._msgs.map((m) => {'role': m['role']!, 'content': m['text']!}),
      ];
      final data = await api.aiChat(apiMsgs, threadId: threadId);
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
      final l = context.read<L10n>();
      final resp = (e is DioException) ? e.response : null;
      final detail = (resp?.data is Map) ? resp!.data['detail']?.toString() : null;
      final text = resp?.statusCode == 429
          ? (detail ?? l.t('ai_daily_exhausted'))
          : e.toString().contains('503')
              ? l.t('ai_not_configured')
              : l.t('connection_error');
      setState(() => _msgs.add({'role': 'assistant', 'text': text, 'time': _now()}));
      _saveHistory();
      if (resp?.statusCode == 429) _loadQuota();
    }
    if (mounted) setState(() => _loading = false);
    _scrollDown();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          child: _msgs.isEmpty ? _emptyState(context.watch<L10n>()) : _messageList(isDark),
        ),
      ),
      _AiInputBar(ctrl: _ctrl, loading: _loading, quota: _quota, onSend: _send),
    ]);
  }

  Widget _emptyState(L10n l) {
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
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: adaptiveText1(context), letterSpacing: -0.6)),
            const SizedBox(height: 10),
            Text(subtitle, style: const TextStyle(fontSize: 15, color: C.text4, height: 1.4), textAlign: TextAlign.center),
            const SizedBox(height: 30),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(children: [
                for (var i = 0; i < tips.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _suggestionRow(tips[i], i),
                ],
              ]),
            ),
          ]),
        ),
      );
    });
  }

  Widget _suggestionRow(Map<String, dynamic> tip, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 320 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _send(tip['prompt'] as String);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: adaptiveBorder(context).withValues(alpha: 0.5), width: 0.5),
            boxShadow: softShadow(isDark),
          ),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: adaptiveTealLt(context),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(tip['icon'] as IconData, size: 17, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(tip['title'] as String,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(context), letterSpacing: -0.2)),
            ),
            const SizedBox(width: 12),
            Icon(CupertinoIcons.arrow_up_left, size: 16, color: C.text4.withValues(alpha: 0.7)),
          ]),
        ),
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
        return TweenAnimationBuilder<double>(
          key: ValueKey('msg_$i'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(isUser ? 18 * (1 - t) : -18 * (1 - t), 8 * (1 - t)), child: child),
          ),
          child: RepaintBoundary(
            child: isUser ? _userMessage(m) : _aiMessage(m, isDark),
          ),
        );
      },
    );
  }

  Widget _userMessage(Map<String, String> m) {
    final text = m['text'] ?? '';
    final timeStr = m['time'] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 18, left: 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(7),
            ),
            boxShadow: [
              BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.26), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: Text(text, style: const TextStyle(fontSize: 15.5, color: Colors.white, height: 1.55, letterSpacing: -0.1)),
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Text(timeStr, style: const TextStyle(fontSize: 10.5, color: C.text4)),
        ),
      ]),
    );
  }

  Widget _aiMessage(Map<String, String> m, bool isDark) {
    final text = m['text'] ?? '';
    final l = context.read<L10n>();
    final copied = l.lang == 'KZ' ? 'Көшірілді' : l.lang == 'EN' ? 'Copied' : 'Скопировано';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 52),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onLongPress: () {
              HapticFeedback.mediumImpact();
              Clipboard.setData(ClipboardData(text: text));
              showToast(context, copied);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
              decoration: BoxDecoration(
                color: isDark ? C.darkSurface : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                  bottomLeft: Radius.circular(7),
                  bottomRight: Radius.circular(22),
                ),
                border: Border.all(color: adaptiveBorder(context).withValues(alpha: isDark ? 0.4 : 0.5), width: 0.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.04), blurRadius: 14, offset: const Offset(0, 4))],
              ),
              child: AiMessageContent(
                text: text,
                style: TextStyle(fontSize: 15.5, height: 1.6, letterSpacing: 0.05, color: adaptiveText1(context)),
              ),
            ),
          ),
          if ((m['time'] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 7, top: 5),
              child: Text(m['time']!, style: const TextStyle(fontSize: 10.5, color: C.text4)),
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
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
              bottomLeft: Radius.circular(7),
              bottomRight: Radius.circular(22),
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04), blurRadius: 10)],
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

  const _AiInputBar({required this.ctrl, required this.loading, required this.onSend, this.quota});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, bottomBarInset(context)),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: adaptiveBorder(context).withValues(alpha: 0.5), width: 0.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (exhausted) AiLimitNotice(quota: quota!),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: adaptiveBorder(context).withValues(alpha: 0.4), width: 0.5),
                boxShadow: softShadow(isDark),
              ),
              child: TextField(
                controller: ctrl,
                enabled: !exhausted,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(color: C.text4, fontSize: 15),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
              return GestureDetector(
                onTap: exhausted ? null : onSend,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? Theme.of(context).colorScheme.primary : surface,
                    boxShadow: active ? primaryGlow(Theme.of(context).colorScheme.primary, opacity: 0.32) : softShadow(isDark),
                  ),
                  child: loading
                      ? Center(
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Theme.of(context).colorScheme.primary)))
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                          child: Icon(
                            CupertinoIcons.arrow_up,
                            key: ValueKey(active),
                            color: active ? Colors.white : C.text4,
                            size: 21,
                          ),
                        ),
                ),
              );
            },
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          l.t('ai_disclaimer'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: C.text4, height: 1.3),
        ),
      ]),
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
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3 + _anim.value * 0.7),
            shape: BoxShape.circle,
          ),
          transform: Matrix4.translationValues(0, -4 * _anim.value, 0),
        ),
      );
}
