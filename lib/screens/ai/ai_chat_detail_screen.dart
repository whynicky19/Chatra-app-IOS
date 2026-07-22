import 'dart:convert';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/ai_chats_provider.dart';
import '../../services/api_service.dart';
import '../../utils/ai_quota.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ai_limit_notice.dart';
import '../../widgets/toast.dart';

/// Один чат (тред) главного ИИ-ассистента. По сути прежний экран ассистента,
/// но привязанный к конкретному thread_id и синхронизируемый по нему.
class AiChatDetailScreen extends StatefulWidget {
  final int threadId;
  final String initialTitle;
  const AiChatDetailScreen({super.key, required this.threadId, required this.initialTitle});
  @override
  State<AiChatDetailScreen> createState() => _AiChatDetailScreenState();
}

class _AiChatDetailScreenState extends State<AiChatDetailScreen> with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _msgs = [];
  bool _loading = false;
  AiQuota? _quota;
  late String _title;

  late final String _historyKey;

  @override
  void initState() {
    super.initState();
    _title = widget.initialTitle;
    final uid = context.read<AuthProvider>().userId;
    _historyKey = 'ai_chat_history_v2_${uid ?? 'anon'}_${widget.threadId}';
    _restoreHistory();
    _loadQuota();
  }

  Future<void> _restoreHistory() async {
    final local = await _loadLocal();
    if (mounted && local.isNotEmpty) {
      setState(() { _msgs..clear()..addAll(local); });
      _scrollDown();
    }
    await _syncFromServer(local);
  }

  Future<void> _refresh() async {
    await _syncFromServer(const []);
    await _loadQuota();
  }

  Future<void> _loadQuota() async {
    try {
      final q = AiQuota.fromJson(await context.read<ApiService>().getAiLimits());
      if (mounted && q != null) setState(() => _quota = q);
    } catch (_) {}
  }

  Future<List<Map<String, String>>> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _syncFromServer(List<Map<String, String>> local) async {
    try {
      final api = context.read<ApiService>();
      var rows = await api.getAiHistory(threadId: widget.threadId);
      if (rows.isEmpty && local.isNotEmpty) {
        rows = await api.importAiHistory(
          local.map((m) => {'role': m['role'] ?? 'user', 'content': m['text'] ?? ''}).toList(),
          threadId: widget.threadId,
        );
      }
      final list = rows.map<Map<String, String>>((r) => {
        'role': (r['role'] ?? 'assistant').toString(),
        'text': (r['content'] ?? '').toString(),
        'time': _fmtTime(r['created_at']),
      }).toList();
      if (!mounted) return;
      setState(() { _msgs..clear()..addAll(list); });
      _saveHistory();
      _scrollDown();
    } catch (_) {
    }
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
    SharedPreferences.getInstance().then((prefs) {
      try { prefs.setString(_historyKey, jsonEncode(_msgs)); } catch (_) {}
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
        'desc':  isKZ ? 'Күрделі тұжырымды қарапайым сөздермен' : isEN ? 'Break down complex concepts in simple words' : 'Разбери сложную концепцию простыми словами',
        'prompt': l.t('tip_explain'),
      },
      {
        'icon': CupertinoIcons.lightbulb,
        'title': isKZ ? 'Тұжырымдарды ашу' : isEN ? 'Break Down Concepts' : 'Разобрать концепции',
        'desc':  isKZ ? 'Тәсілдер арасындағы айырмашылықты түсін' : isEN ? 'Understand the difference between approaches' : 'Помоги понять разницу между подходами',
        'prompt': l.t('tip_concepts'),
      },
      {
        'icon': CupertinoIcons.pencil,
        'title': isKZ ? 'Тапсырмаға көмек' : isEN ? 'Help with Task' : 'Помочь с заданием',
        'desc':  isKZ ? 'Шешімді қайдан бастау керектігін айт' : isEN ? 'Tell me where to start the solution' : 'Подскажи, с чего начать решение',
        'prompt': l.t('tip_help'),
      },
      {
        'icon': CupertinoIcons.exclamationmark_triangle,
        'title': isKZ ? 'Қателерді тап' : isEN ? 'Find Mistakes' : 'Найти ошибки',
        'desc':  isKZ ? 'Кодымды тексеріп, мәселелерді көрсет' : isEN ? 'Review my code and point out issues' : 'Проверь мой код и укажи на проблемы',
        'prompt': l.t('tip_mistakes'),
      },
    ];
  }

  String _now() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  void _send([String? override]) async {
    final text = override ?? _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    if (_quota?.exhausted == true) {
      showToast(context, context.read<L10n>().t('ai_daily_exhausted'), error: true);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() { _msgs.add({'role': 'user', 'text': text, 'time': _now()}); _loading = true; });
    _saveHistory();
    _ctrl.clear();
    _scrollDown();
    try {
      final api = context.read<ApiService>();
      final l = context.read<L10n>();
      final sysLang = l.lang == 'KZ' ? 'казахском' : l.lang == 'EN' ? 'английском' : 'русском';
      final apiMsgs = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Ты AI-ассистент образовательной платформы Chatra. Отвечай на $sysLang языке.'},
        ..._msgs.map((m) => {'role': m['role']!, 'content': m['text']!}),
      ];
      final data = await api.aiChat(apiMsgs, threadId: widget.threadId);
      if (!mounted) return;
      setState(() {
        _msgs.add({'role': 'assistant', 'text': data['content'] ?? context.read<L10n>().t('no_answer'), 'time': _now()});
        _quota = AiQuota.fromJson(data['quota']) ?? _quota;
      });
      _saveHistory();
      // Заголовок сервер генерит после первого обмена; на каждой отправке
      // подбиваем свежесть треда в списке без полной перезагрузки.
      final newTitle = data['thread_title']?.toString();
      if (newTitle != null && newTitle.isNotEmpty) {
        setState(() => _title = newTitle);
        context.read<AiChatsProvider>().patchLocal(widget.threadId, title: newTitle, updatedAt: DateTime.now());
      } else {
        context.read<AiChatsProvider>().patchLocal(widget.threadId, updatedAt: DateTime.now());
      }
    } catch (e) {
      if (!mounted) return;
      final l = context.read<L10n>();
      final resp = (e is DioException) ? e.response : null;
      final detail = (resp?.data is Map) ? resp!.data['detail']?.toString() : null;
      final text = resp?.statusCode == 429
          ? (detail ?? l.t('ai_daily_exhausted'))
          : e.toString().contains('503') ? l.t('ai_not_configured') : l.t('connection_error');
      setState(() => _msgs.add({'role': 'assistant', 'text': text, 'time': _now()}));
      _saveHistory();
      if (resp?.statusCode == 429) _loadQuota();
    }
    if (mounted) setState(() => _loading = false);
    _scrollDown();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final l = context.watch<L10n>();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(children: [
        _buildHeader(isDark, surface, l),
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
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: Theme.of(context).colorScheme.primary,
              child: _msgs.isEmpty
                  ? _emptyState(isDark, l)
                  : _messageList(isDark),
            ),
          ),
        ),
        _AiInputBar(ctrl: _ctrl, loading: _loading, quota: _quota, onSend: _send),
      ]),
    );
  }

  Widget _buildHeader(bool isDark, Color surface, L10n l) {
    return SafeArea(bottom: false, child: Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: adaptiveBorder(context).withValues(alpha: 0.5), width: 0.5)),
      ),
      child: Row(children: [
        IconButton(
          icon: Icon(CupertinoIcons.back, color: adaptiveText1(context)),
          onPressed: () => Navigator.pop(context),
        ),
        Expanded(child: Text(
          _title.isEmpty ? l.t('untitled_chat') : _title,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4),
        )),
      ]),
    ));
  }

  Widget _emptyState(bool isDark, L10n l) {
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
            Text('Chatra AI', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: adaptiveText1(context), letterSpacing: -0.6)),
            const SizedBox(height: 10),
            Text(subtitle, style: const TextStyle(fontSize: 15, color: C.text4, height: 1.4), textAlign: TextAlign.center),
            const SizedBox(height: 28),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(children: [
                for (var i = 0; i < tips.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _suggestionRow(tips[i], isDark, i),
                ],
              ]),
            ),
          ]),
        ),
      );
    });
  }

  Widget _suggestionRow(Map<String, dynamic> tip, bool isDark, int index) {
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: adaptiveBorder(context).withValues(alpha: 0.6), width: 0.5),
            boxShadow: softShadow(isDark),
          ),
          child: Row(children: [
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
    return ListView.builder(
      key: const ValueKey('msg_list'),
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
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
      padding: const EdgeInsets.only(bottom: 16, left: 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22), topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22), bottomRight: Radius.circular(6),
            ),
            boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 5))],
          ),
          child: Text(text, style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.5)),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Text(timeStr, style: const TextStyle(fontSize: 10, color: C.text4)),
        ),
      ]),
    );
  }

  Widget _aiMessage(Map<String, String> m, bool isDark) {
    final text = m['text'] ?? '';
    final l = context.read<L10n>();
    final copied = l.lang == 'KZ' ? 'Көшірілді' : l.lang == 'EN' ? 'Copied' : 'Скопировано';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 52),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? C.darkSurface : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20), topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(6), bottomRight: Radius.circular(20),
                ),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05), blurRadius: 12, offset: const Offset(0, 3))],
              ),
              child: SelectableText(text, style: const TextStyle(fontSize: 15, height: 1.6, letterSpacing: 0.1)),
            ),
          ),
          if ((m['time'] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 4),
              child: Text(m['time']!, style: const TextStyle(fontSize: 10, color: C.text4)),
            ),
        ]),
      ),
    );
  }

  Widget _typingIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 52),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20), topRight: Radius.circular(20),
              bottomLeft: Radius.circular(6), bottomRight: Radius.circular(20),
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
        : isKZ ? 'Chatra AI-дан сұраңыз...' : isEN ? 'Ask Chatra AI...' : 'Спросите Chatra AI...';

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
              constraints: const BoxConstraints(minHeight: 46),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(24),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
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
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? Theme.of(context).colorScheme.primary : surface,
                    boxShadow: active
                        ? primaryGlow(Theme.of(context).colorScheme.primary, opacity: 0.32)
                        : softShadow(isDark),
                  ),
                  child: loading
                      ? Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Theme.of(context).colorScheme.primary)))
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
  @override State<_Dot> createState() => _DotState();
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

  @override void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: 7, height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3 + _anim.value * 0.7),
        shape: BoxShape.circle,
      ),
      transform: Matrix4.translationValues(0, -4 * _anim.value, 0),
    ),
  );
}
