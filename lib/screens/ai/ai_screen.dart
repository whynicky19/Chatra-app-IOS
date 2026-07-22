import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/ai_thread.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/ai_chats_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/toast.dart';
import 'ai_chat_detail_screen.dart';

/// Список чатов (тредов) главного ИИ-ассистента. Каждый тред — отдельная
/// переписка, синхронизируемая с бэкендом между устройствами.
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});
  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AiChatsProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openThread(AiThread t) async {
    HapticFeedback.lightImpact();
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AiChatDetailScreen(threadId: t.id, initialTitle: t.title),
    ));
  }

  Future<void> _createAndOpen() async {
    if (_busy) return;
    setState(() => _busy = true);
    final provider = context.read<AiChatsProvider>();
    final l = context.read<L10n>();
    try {
      final t = await provider.createThread();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => AiChatDetailScreen(threadId: t.id, initialTitle: t.title),
      ));
    } catch (_) {
      if (mounted) showToast(context, l.t('connection_error'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(AiThread t) async {
    final l = context.read<L10n>();
    final ok = await showConfirmDialog(context,
      title: l.t('delete_chat_q'),
      message: l.t('delete_chat_msg'),
      icon: CupertinoIcons.trash,
      danger: true,
      confirmText: l.t('delete'),
      cancelText: l.t('cancel'));
    if (ok == true && mounted) {
      HapticFeedback.mediumImpact();
      context.read<AiChatsProvider>().delete(t.id);
    }
  }

  Future<void> _rename(AiThread t) async {
    final l = context.read<L10n>();
    final name = await showInputDialog(context,
      title: l.t('rename_chat'),
      icon: CupertinoIcons.pencil,
      hint: l.t('untitled_chat'),
      maxLines: 1,
      confirmText: l.t('save'),
      cancelText: l.t('cancel'));
    if (name != null && name.isNotEmpty && mounted) {
      context.read<AiChatsProvider>().rename(t.id, name);
      showToast(context, l.t('chat_renamed'));
    }
  }

  void _showActions(AiThread t) {
    final l = context.read<L10n>();
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final surface = Theme.of(ctx).colorScheme.surface;
        return SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              Container(width: 38, height: 4, decoration: BoxDecoration(
                color: C.text4.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 8),
              _sheetAction(ctx, CupertinoIcons.pencil, l.t('rename_chat'), () {
                Navigator.pop(ctx); _rename(t);
              }),
              _sheetAction(ctx, t.pinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin,
                  t.pinned ? l.t('unpin_chat') : l.t('pin_chat'), () {
                Navigator.pop(ctx);
                HapticFeedback.selectionClick();
                context.read<AiChatsProvider>().togglePin(t.id);
              }),
              _sheetAction(ctx, CupertinoIcons.trash, l.t('delete'), () {
                Navigator.pop(ctx); _confirmDelete(t);
              }, danger: true),
              const SizedBox(height: 6),
            ]),
          ),
        ));
      },
    );
  }

  Widget _sheetAction(BuildContext ctx, IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
    final color = danger ? C.red : adaptiveText1(ctx);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }

  String _relTime(DateTime dt, L10n l) {
    final isKZ = l.lang == 'KZ';
    final isEN = l.lang == 'EN';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return isKZ ? 'қазір' : isEN ? 'now' : 'сейчас';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return isEN ? '${m}m ago' : isKZ ? '$m мин' : '$m мин назад';
    }
    if (diff.inHours < 24 && now.day == dt.day) {
      String p(int n) => n.toString().padLeft(2, '0');
      return '${p(dt.hour)}:${p(dt.minute)}';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays == 0 ? 1 : diff.inDays;
      return isEN ? '${d}d ago' : isKZ ? '$d күн' : '$d дн назад';
    }
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(dt.day)}.${p(dt.month)}.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final provider = context.watch<AiChatsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    final all = provider.threads;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all.where((t) => t.title.toLowerCase().contains(q)).toList();
    final pinned = filtered.where((t) => t.pinned).toList();
    final rest = filtered.where((t) => !t.pinned).toList();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(children: [
        _buildHeader(isDark, surface, l),
        _buildSearch(surface, l),
        Expanded(
          child: provider.loading && all.isEmpty
              ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2.5))
              : RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  onRefresh: () => context.read<AiChatsProvider>().load(),
                  child: all.isEmpty
                      ? _emptyState(l)
                      : filtered.isEmpty
                          ? _noResults(l)
                          : _list(pinned, rest, l, isDark),
                ),
        ),
      ]),
    );
  }

  Widget _buildHeader(bool isDark, Color surface, L10n l) {
    final isKZ = l.lang == 'KZ';
    final isEN = l.lang == 'EN';
    final subtitle = isKZ ? 'Сіздің оқу көмекшіңіз' : isEN ? 'Your learning assistant' : 'Ваш учебный ассистент';
    return SafeArea(bottom: false, child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: adaptiveBorder(context).withValues(alpha: 0.5), width: 0.5)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.t('ai_chats_title'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: C.text4, fontWeight: FontWeight.w500)),
        ])),
        GestureDetector(
          onTap: _createAndOpen,
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(CupertinoIcons.add, color: Theme.of(context).colorScheme.primary, size: 22),
          ),
        ),
      ]),
    ));
  }

  Widget _buildSearch(Color surface, L10n l) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: softShadow(isDark),
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: l.t('search_chats'),
            hintStyle: const TextStyle(color: C.text4, fontSize: 15),
            prefixIcon: const Icon(CupertinoIcons.search, size: 20, color: C.text4),
            suffixIcon: _query.isEmpty ? null : GestureDetector(
              onTap: () { _searchCtrl.clear(); setState(() => _query = ''); },
              child: const Icon(CupertinoIcons.clear_circled_solid, size: 18, color: C.text4)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
    );
  }

  Widget _list(List<AiThread> pinned, List<AiThread> rest, L10n l, bool isDark) {
    final items = <dynamic>[];
    if (pinned.isNotEmpty) {
      items.add(l.t('pinned_section'));
      items.addAll(pinned);
    }
    items.addAll(rest);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        if (item is String) {
          return Padding(
            padding: EdgeInsets.only(left: 6, top: i == 0 ? 2 : 14, bottom: 8),
            child: Text(item.toUpperCase(), style: const TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w800, color: C.text4, letterSpacing: 1.0)),
          );
        }
        final t = item as AiThread;
        return TweenAnimationBuilder<double>(
          key: ValueKey('thread_${t.id}'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 320 + (i.clamp(0, 8)) * 45),
          curve: Curves.easeOutCubic,
          builder: (_, tv, child) => Opacity(opacity: tv, child: Transform.translate(offset: Offset(0, 14 * (1 - tv)), child: child)),
          child: RepaintBoundary(child: Dismissible(
            key: ValueKey('dismiss_${t.id}'),
            direction: DismissDirection.endToStart,
            dismissThresholds: const {DismissDirection.endToStart: 0.4},
            confirmDismiss: (_) async {
              final ok = await showConfirmDialog(context,
                title: l.t('delete_chat_q'),
                message: l.t('delete_chat_msg'),
                icon: CupertinoIcons.trash,
                danger: true,
                confirmText: l.t('delete'),
                cancelText: l.t('cancel'));
              return ok == true;
            },
            onDismissed: (_) {
              HapticFeedback.mediumImpact();
              context.read<AiChatsProvider>().delete(t.id);
            },
            background: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(CupertinoIcons.trash, color: Colors.white, size: 24),
                const SizedBox(height: 4),
                Text(l.t('delete'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
            child: _threadRow(t, l, isDark),
          )),
        );
      },
    );
  }

  Widget _threadRow(AiThread t, L10n l, bool isDark) {
    final surface = Theme.of(context).colorScheme.surface;
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => _openThread(t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: cardShadow(isDark),
        ),
        child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [primary.withValues(alpha: 0.85), primary],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(AppRadii.tile),
              boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.28), blurRadius: 9, spreadRadius: -2, offset: const Offset(0, 3))],
            ),
            child: const Icon(CupertinoIcons.sparkles, size: 20, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (t.pinned) Padding(padding: const EdgeInsets.only(right: 5),
                child: Icon(CupertinoIcons.pin_fill, size: 12, color: primary)),
              Expanded(child: Text(t.title.isEmpty ? l.t('untitled_chat') : t.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: adaptiveText1(context), letterSpacing: -0.2))),
            ]),
            const SizedBox(height: 3),
            Text(_relTime(t.updatedAt, l), style: const TextStyle(fontSize: 12.5, color: C.text4)),
          ])),
          GestureDetector(
            onTap: () => _showActions(t),
            behavior: HitTestBehavior.opaque,
            child: const Padding(padding: EdgeInsets.only(left: 6),
              child: Icon(CupertinoIcons.ellipsis, size: 20, color: C.text4)),
          ),
        ])),
      ),
    );
  }

  Widget _emptyState(L10n l) {
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 76, height: 76,
                decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(22)),
                child: Icon(CupertinoIcons.sparkles, size: 34, color: adaptiveText1(context).withValues(alpha: 0.4))),
              const SizedBox(height: 16),
              Text(l.t('no_chats'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: adaptiveText1(context).withValues(alpha: 0.8))),
              const SizedBox(height: 6),
              SizedBox(width: 280, child: Text(l.t('no_chats_sub'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.5, color: adaptiveText1(context).withValues(alpha: 0.5)))),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _createAndOpen,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: primaryGlow(Theme.of(context).colorScheme.primary, opacity: 0.30),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(CupertinoIcons.add, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(l.t('new_chat'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          )),
        ),
      );
    });
  }

  Widget _noResults(L10n l) {
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 60, 32, 60),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(CupertinoIcons.search, size: 40, color: adaptiveText1(context).withValues(alpha: 0.35)),
              const SizedBox(height: 14),
              Text(l.t('no_search_results'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(context).withValues(alpha: 0.55))),
            ]),
          )),
        ),
      );
    });
  }
}
