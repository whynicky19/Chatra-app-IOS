import 'dart:convert';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../services/api_service.dart';
import '../../../utils/ai_context.dart';
import '../../../utils/ai_quota.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ai_limit_notice.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/tappable.dart';
import '../../../widgets/toast.dart';
import '../../ai/widgets/ai_message_content.dart';

class ClassAiTab extends StatefulWidget {
  final int classId;
  final String className;
  final String lectureContext;
  final List<String> lectureImageUrls;
  final bool isActive;
  final bool isTeacher;
  const ClassAiTab({
    super.key,
    required this.classId,
    required this.className,
    this.lectureContext = '',
    this.lectureImageUrls = const [],
    this.isActive = true,
    this.isTeacher = false,
  });
  @override State<ClassAiTab> createState() => _ClassAiTabState();
}

class _ClassAiTabState extends State<ClassAiTab> with TickerProviderStateMixin {
  final _ctrl   = TextEditingController();
  final List<Map<String, String>> _msgs = [];
  bool _loading = false;
  AiQuota? _quota;
  late final AnimationController _fadeCtrl;
  late final ScrollController _scrollCtrl;
  late final String _historyKey;

  static const _tips = ['tip_explain', 'tip_concepts', 'tip_help', 'tip_mistakes'];

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _fadeCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
    final uid = context.read<AuthProvider>().userId?.toString() ?? 'anon';
    _historyKey = 'ai_chat_history_${widget.classId}_$uid';
    _loadHistory();
    _loadQuota();
  }

  /// Свайп сверху вниз: подтягиваем тред этого класса и квоту с сервера —
  /// история общая с сайтом.
  Future<void> _refresh() async {
    // Пустой local: refresh не должен ре-импортировать локальную историю,
    // иначе очистка треда с другого устройства «воскресала» бы здесь.
    await _syncFromServer(const []);
    await _loadQuota();
  }

  /// Дневная квота ИИ — серверная, общая с сайтом и глобальным ИИ-экраном.
  Future<void> _loadQuota() async {
    try {
      final q = AiQuota.fromJson(await context.read<ApiService>().getAiLimits());
      if (mounted && q != null) setState(() => _quota = q);
    } catch (_) {}
  }

  @override
  void dispose() { _scrollCtrl.dispose(); _fadeCtrl.dispose(); _ctrl.dispose(); super.dispose(); }

  Future<void> _loadHistory() async {
    final local = await _loadLocal();
    if (mounted && local.isNotEmpty) {
      setState(() { _msgs..clear()..addAll(local); });
    }
    await _syncFromServer(local);
  }

  Future<List<Map<String, String>>> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw != null && raw.isNotEmpty) {
        return (jsonDecode(raw) as List).map((e) => Map<String, String>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _syncFromServer(List<Map<String, String>> local) async {
    try {
      final api = context.read<ApiService>();
      var rows = await api.getAiHistory(classId: widget.classId);
      if (rows.isEmpty && local.isNotEmpty) {
        rows = await api.importAiHistory(
          local.map((m) => {'role': m['role'] ?? 'user', 'content': m['text'] ?? ''}).toList(),
          classId: widget.classId,
        );
      }
      final list = rows.map<Map<String, String>>((r) => {
        'role': (r['role'] ?? 'assistant').toString(),
        'text': (r['content'] ?? '').toString(),
      }).toList();
      if (!mounted) return;
      setState(() { _msgs..clear()..addAll(list); });
      _saveHistory();
      _scrollToBottom();
    } catch (_) {}
  }

  void _saveHistory() {
    // Снапшот до асинхронного разрыва: _msgs может измениться (новый ответ ИИ,
    // очистка чата), пока мы ждём SharedPreferences — тогда jsonEncode сериализует
    // промежуточное состояние или упадёт на конкурентной модификации.
    final snapshot = List<Map<String, String>>.from(_msgs);
    SharedPreferences.getInstance().then((prefs) {
      try { prefs.setString(_historyKey, jsonEncode(snapshot)); } catch (_) {}
    }).catchError((_) {});
  }

  Future<void> _clearHistory() async {
    final api = context.read<ApiService>();
    final l = context.read<L10n>();
    final ok = await showConfirmDialog(context,
      title: l.t('clear_chat_q'),
      message: l.t('clear_chat_msg'),
      icon: CupertinoIcons.trash,
      danger: true,
      confirmText: l.t('clear'),
      cancelText: l.t('cancel'));
    if (ok == true && mounted) {
      setState(() => _msgs.clear());
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_historyKey);
      } catch (_) {}
      try { api.clearAiHistory(classId: widget.classId); } catch (_) {}
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
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
    setState(() { _msgs.add({'role': 'user', 'text': text}); _loading = true; });
    _ctrl.clear();
    _scrollToBottom();
    _saveHistory();
    try {
      final api = context.read<ApiService>();
      final lectureBlock = widget.lectureContext.isNotEmpty
          ? '\n\nМАТЕРИАЛЫ КУРСА (используй эти знания при ответах):\n${widget.lectureContext}' : '';
      final imgs = widget.lectureImageUrls;
      final List<Map<String, dynamic>> visionPre = imgs.isNotEmpty ? [
        {'role': 'user', 'content': [
          {'type': 'text', 'text': 'Прикреплённые файлы-изображения из материалов курса:'},
          ...imgs.map((url) => {'type': 'image_url', 'image_url': {'url': url, 'detail': 'low'}}),
        ]},
        {'role': 'assistant', 'content': 'Ознакомился с прикреплёнными материалами курса.'},
      ] : [];
      final apiMsgs = <Map<String, dynamic>>[
        {'role': 'system', 'content':
            'Ты AI-ассистент курса "${widget.className}". Отвечай на русском. '
            'Материалы курса ниже помечены заголовками вида "### Лекция N: <тема>" — '
            'если студент просит объяснить материал по номеру (например "объясни '
            '2 лекцию"), найди блок с этим номером и объясняй именно его. Объясняй '
            'подробно: раскрывай ключевые понятия, приводи примеры и связи между '
            'идеями, а не просто пересказывай заголовок. Математические формулы '
            'записывай в LaTeX: инлайн — \$...\$ или \\(...\\), блочные — \$\$...\$\$ '
            'или \\[...\\]. Код — в блоках ```язык.$lectureBlock'},
        ...visionPre,
        // Только хвост переписки — см. utils/ai_context.dart. В классном чате
        // это особенно важно: к истории добавляется ещё и lectureContext.
        ...aiContextWindow(_msgs),
      ];
      final data = await api.aiChat(
        apiMsgs,
        classId: widget.classId,
        lectureContext: widget.lectureContext.isNotEmpty ? widget.lectureContext : null,
      );
      if (mounted) {
        setState(() {
          _msgs.add({'role': 'assistant', 'text': data['content'] ?? context.read<L10n>().t('no_answer')});
          _quota = AiQuota.fromJson(data['quota']) ?? _quota;
        });
        _saveHistory(); _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        final resp = (e is DioException) ? e.response : null;
        final detail = (resp?.data is Map) ? resp!.data['detail']?.toString() : null;
        setState(() => _msgs.add({
          'role': 'assistant',
          'text': resp?.statusCode == 429
              ? (detail ?? context.read<L10n>().t('ai_daily_exhausted'))
              : context.read<L10n>().t('connection_error'),
        }));
        _saveHistory(); _scrollToBottom();
        if (resp?.statusCode == 429) _loadQuota();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final exhausted = _quota?.exhausted ?? false;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Column(children: [
      Expanded(child: Stack(children: [
        RefreshIndicator(
          onRefresh: _refresh,
          color: Theme.of(context).colorScheme.primary,
          child: _msgs.isEmpty ? _emptyState(isDark) : _messageList(isDark),
        ),
        if (_msgs.isNotEmpty) Positioned(
          top: 10, right: 14,
          child: _headerButton(
            icon: CupertinoIcons.trash,
            color: Theme.of(context).colorScheme.primary,
            onTap: () { HapticFeedback.lightImpact(); _clearHistory(); },
          ),
        ),
      ])),

      Container(
        padding: EdgeInsets.fromLTRB(14, 10, 14, MediaQuery.of(context).padding.bottom + 10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: adaptiveBorder(context).withValues(alpha: 0.5), width: 0.5)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (exhausted) AiLimitNotice(quota: _quota!),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 46),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: softShadow(isDark),
            ),
            child: TextField(
              controller: _ctrl,
              enabled: !exhausted,
              decoration: InputDecoration(
                hintText: exhausted
                    ? context.read<L10n>().t('ai_limit_reached_title')
                    : context.read<L10n>().t('ask_about_course'),
                hintStyle: const TextStyle(fontSize: 15, color: C.text4),
                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                filled: false, contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              ),
              onSubmitted: (_) => _send(),
              maxLines: 4, minLines: 1,
            ),
          )),
          const SizedBox(width: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _ctrl,
            builder: (context, value, _) {
              final has = value.text.trim().isNotEmpty;
              final active = has && !_loading && !exhausted;
              return Tappable(
                onTap: exhausted ? null : _send,
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
                  child: _loading
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
        ]),
      ),
    ]));
  }

  Widget _headerButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return Tappable(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Widget _emptyState(bool isDark) {
    final shortName = widget.className.length > 22 ? '${widget.className.substring(0, 22)}…' : widget.className;
    return FadeTransition(
      opacity: _fadeCtrl,
      child: LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(context.read<L10n>().t('course_chat'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: adaptiveText1(context))),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
                child: Text(shortName, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(children: [
                  for (var i = 0; i < _tips.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _suggestionRow(_tips[i], isDark, i),
                  ],
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _suggestionRow(String tipKey, bool isDark, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 320 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
      ),
      child: Tappable(
        onTap: () => _send(context.read<L10n>().t(tipKey)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: adaptiveBorder(context).withValues(alpha: 0.6), width: 0.5),
            boxShadow: softShadow(isDark),
          ),
          child: Text(context.read<L10n>().t(tipKey),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(context), letterSpacing: -0.2)),
        ),
      ),
    );
  }

  Widget _messageList(bool isDark) {
    return ListView.builder(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      itemCount: _msgs.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _msgs.length) return _typingIndicator(isDark);
        final m   = _msgs[i];
        final isU = m['role'] == 'user';
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(
            offset: Offset(isU ? 16*(1-t) : -16*(1-t), 6*(1-t)), child: child)),
          child: RepaintBoundary(child: isU ? _userBubble(m['text'] ?? '') : _aiBubble(m['text'] ?? '', isDark)),
        );
      },
    );
  }

  Widget _userBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 48),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
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
      ),
    );
  }

  Widget _aiBubble(String text, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 14, right: 52),
    child: Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          Clipboard.setData(ClipboardData(text: text));
          showToast(context, context.read<L10n>().t('copied'));
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
          child: AiMessageContent(text: text, style: const TextStyle(fontSize: 15, height: 1.6, letterSpacing: 0.1)),
        ),
      ),
    ),
  );

  Widget _typingIndicator(bool isDark) => Padding(
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
        child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => _ClassAiDot(delay: i * 180))),
      ),
    ),
  );
}

class _ClassAiDot extends StatefulWidget {
  final int delay;
  const _ClassAiDot({required this.delay});
  @override State<_ClassAiDot> createState() => _ClassAiDotState();
}
class _ClassAiDotState extends State<_ClassAiDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    Future.delayed(Duration(milliseconds: widget.delay), () { if (mounted) _c.repeat(reverse: true); });
    _a = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _a, builder: (_, __) => Container(
    width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3 + _a.value * 0.7), shape: BoxShape.circle),
    transform: Matrix4.translationValues(0, -4 * _a.value, 0),
  ));
}
