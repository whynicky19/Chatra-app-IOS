import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../services/api_service.dart';
import '../../../utils/ai_ask.dart';
import '../../../utils/ai_context.dart';
import '../../../utils/ai_quota.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ai_limit_notice.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/inset_group.dart';
import '../../../widgets/tappable.dart';
import '../../../widgets/toast.dart';
import '../../ai/widgets/ai_message_content.dart';
import '../widgets/quoted_fragment.dart';
import '../../../utils/haptics.dart';

class ClassAiTab extends StatefulWidget {
  final int classId;
  final String className;
  final bool isActive;
  final bool isTeacher;

  /// Вопрос по выделенному фрагменту лекции («Спросить AI»): отправляется в
  /// этот же тред класса, как обычное сообщение.
  final AiAsk? pendingAsk;
  final VoidCallback? onAskConsumed;

  const ClassAiTab({
    super.key,
    required this.classId,
    required this.className,
    this.isActive = true,
    this.isTeacher = false,
    this.pendingAsk,
    this.onAskConsumed,
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
    _historyReady;
    _loadQuota();
    if (widget.pendingAsk != null) _consumeAsk();
  }

  @override
  void didUpdateWidget(ClassAiTab old) {
    super.didUpdateWidget(old);
    // Вопрос приходит уже после того, как вкладка построена (пользователь
    // возвращается с экрана лекции), поэтому ловим его и здесь.
    if (widget.pendingAsk != null && widget.pendingAsk != old.pendingAsk) _consumeAsk();
  }

  /// Ждём синхронизацию истории: она перезаписывает _msgs целиком, и отправленный
  /// раньше вопрос просто исчез бы из переписки.
  void _consumeAsk() {
    final ask = widget.pendingAsk;
    if (ask == null) return;
    widget.onAskConsumed?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _historyReady;
      if (mounted) await _send(ask.text, ask);
    });
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

  late final Future<void> _historyReady = _loadHistory();

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
  Future<void> _send([String? override, AiAsk? ask]) async {
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
      final apiMsgs = <Map<String, dynamic>>[
        {'role': 'system', 'content':
            'Ты AI-ассистент курса "${widget.className}". Отвечай на русском.'},
        // Только хвост переписки — см. utils/ai_context.dart.
        ...aiContextWindow(_msgs),
      ];
      final data = await api.aiChat(
        apiMsgs,
        classId: widget.classId,
        // По этим полям сервер сам определяет, из какой лекции и страницы взят
        // фрагмент, и добавляет это в контекст (routers/ai.py).
        annotationId: ask?.annotationId,
        lectureId: ask?.lectureId,
        lecturePage: ask?.page,
        quote: ask?.quote,
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
    final blocked = exhausted;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Column(children: [
      Expanded(child: Stack(children: [
        _msgs.isEmpty ? _emptyState(isDark) : _messageList(isDark),
        if (_msgs.isNotEmpty) Positioned(
          top: 10, right: 14,
          child: _headerButton(
            icon: CupertinoIcons.trash,
            color: Theme.of(context).colorScheme.primary,
            label: 'Очистить историю чата',
            onTap: () { hapticLight(); _clearHistory(); },
          ),
        ),
      ])),

      ClipRect(child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
        padding: EdgeInsets.fromLTRB(14, 10, 14, MediaQuery.paddingOf(context).bottom + 10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.80),
          border: Border(top: BorderSide(color: adaptiveBorder(context).withValues(alpha: 0.5), width: hairline(context))),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (exhausted)
          AiLimitNotice(quota: _quota!),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 46),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: adaptiveBorder(context).withValues(alpha: 0.45), width: hairline(context)),
            ),
            child: TextField(
              controller: _ctrl,
              enabled: !blocked,
              style: TextStyle(fontSize: 16.5, height: 1.3, letterSpacing: -0.3, color: adaptiveText1(context)),
              decoration: InputDecoration(
                hintText: exhausted
                    ? context.read<L10n>().t('ai_limit_reached_title')
                    : context.read<L10n>().t('ask_about_course'),
                hintStyle: TextStyle(fontSize: 16.5, letterSpacing: -0.3, color: adaptiveText4(context)),
                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                filled: false, contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              onSubmitted: (_) => _send(),
              // Тот же потолок, что и в общем ИИ-чате (см. ai_conversation_view).
              maxLines: 6, minLines: 1,
            ),
          )),
          const SizedBox(width: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _ctrl,
            builder: (context, value, _) {
              final has = value.text.trim().isNotEmpty;
              final active = has && !_loading && !blocked;
              return Tappable(
                onTap: blocked ? null : _send,
                label: 'Отправить сообщение',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? Theme.of(context).colorScheme.primary : adaptiveSurface2(context),
                    border: active
                        ? null
                        : Border.all(color: adaptiveBorder(context).withValues(alpha: 0.45), width: hairline(context)),
                  ),
                  child: _loading
                      ? Center(child: CupertinoActivityIndicator(radius: 10, color: Theme.of(context).colorScheme.primary))
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
      )),
    ]));
  }

  Widget _headerButton({required IconData icon, required Color color, required VoidCallback onTap, required String label}) {
    return Tappable(
      onTap: onTap,
      label: label,
      child: Container(
        width: 40, height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), shape: BoxShape.circle),
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
              Text(context.read<L10n>().t('course_chat'),
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.9, height: 1.1, color: adaptiveText1(context))),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
                child: Text(shortName,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600, letterSpacing: -0.1)),
              ),
              const SizedBox(height: 26),
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
                      for (var i = 0; i < _tips.length; i++) _suggestionRow(_tips[i], i, _tips.length),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _suggestionRow(String tipKey, int index, int count) {
    final text = context.read<L10n>().t(tipKey);
    return Entrance(
      index: index,
      rise: 0,
      child: GroupRow(
        pos: index == count - 1 ? GroupPos.last : GroupPos.middle,
        color: Colors.transparent,
        separatorInset: 16,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () {
          hapticSelection();
          _send(text);
        },
        child: Row(children: [
          Expanded(child: Text(text,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: adaptiveText1(context), letterSpacing: -0.3))),
          const SizedBox(width: 10),
          Icon(CupertinoIcons.arrow_up_left, size: 15, color: adaptiveText4(context).withValues(alpha: 0.7)),
        ]),
      ),
    );
  }

  Widget _messageList(bool isDark) {
    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _refresh),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          sliver: SliverList(delegate: SliverChildBuilderDelegate(
            childCount: _msgs.length + (_loading ? 1 : 0),
            (ctx, i) {
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
          )),
        ),
      ],
    );
  }

  Widget _userBubble(String text) {
    // Вопрос по выделенному фрагменту показываем цитатой из материала:
    // подсветка + карточка источника (см. QuotedFragment).
    final quoted = QuotedFragment.tryParse(text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 48),
      child: Align(
        alignment: Alignment.centerRight,
        child: quoted != null
            ? QuotedFragmentBubble(
                fragment: quoted,
                bubbleColor: Theme.of(context).colorScheme.primary,
                pageLabel: context.read<L10n>().t('hl_page'),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20), topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6),
                  ),
                ),
                child: Text(text, style: const TextStyle(fontSize: 16.5, color: Colors.white, height: 1.35, letterSpacing: -0.3)),
              ),
      ),
    );
  }

  Widget _aiBubble(String text, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 14, right: 52),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Tappable(
        onLongPress: () {
          hapticMedium();
          Clipboard.setData(ClipboardData(text: text));
          showToast(context, context.read<L10n>().t('copied'));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface2 : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20), topRight: Radius.circular(20),
              bottomLeft: Radius.circular(6), bottomRight: Radius.circular(20),
            ),
            border: Border.all(color: adaptiveBorder(context).withValues(alpha: isDark ? 0.35 : 0.45), width: hairline(context)),
          ),
          child: AiMessageContent(text: text,
              style: TextStyle(fontSize: 16.5, height: 1.45, letterSpacing: -0.2, color: adaptiveText1(context))),
        ),
      ),
    ),
  );

  Widget _typingIndicator(bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 14, right: 52),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
        decoration: BoxDecoration(
          color: isDark ? C.darkSurface2 : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20), topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6), bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: adaptiveBorder(context).withValues(alpha: isDark ? 0.35 : 0.45), width: hairline(context)),
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
    decoration: BoxDecoration(color: adaptiveText4(context).withValues(alpha: 0.35 + _a.value * 0.55), shape: BoxShape.circle),
    transform: Matrix4.translationValues(0, -4 * _a.value, 0),
  ));
}
