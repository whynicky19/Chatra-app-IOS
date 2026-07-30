import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../models/ai_thread.dart';
import '../../../providers/l10n_provider.dart';
import '../../../providers/ai_chats_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/toast.dart';

/// История чатов главного ИИ-ассистента — не отдельный экран, а drawer,
/// открывающийся поверх текущей переписки (свайпом с левого края или по
/// иконке в шапке). Выбор треда закрывает drawer и сразу возвращает к чату.
class AiHistoryDrawer extends StatefulWidget {
  final int? activeThreadId;
  final ValueChanged<AiThread> onSelect;
  final VoidCallback onCreate;

  const AiHistoryDrawer({
    super.key,
    required this.activeThreadId,
    required this.onSelect,
    required this.onCreate,
  });

  @override
  State<AiHistoryDrawer> createState() => _AiHistoryDrawerState();
}

class _AiHistoryDrawerState extends State<AiHistoryDrawer> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
        return SafeArea(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: C.text4.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(AppRadii.chip))),
              const SizedBox(height: 8),
              _sheetAction(ctx, CupertinoIcons.pencil, l.t('rename_chat'), () {
                Navigator.pop(ctx);
                _rename(t);
              }),
              _sheetAction(ctx, t.pinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin,
                  t.pinned ? l.t('unpin_chat') : l.t('pin_chat'), () {
                Navigator.pop(ctx);
                HapticFeedback.selectionClick();
                context.read<AiChatsProvider>().togglePin(t.id);
              }),
              _sheetAction(ctx, CupertinoIcons.trash, l.t('delete'), () {
                Navigator.pop(ctx);
                _confirmDelete(t);
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
      borderRadius: BorderRadius.circular(AppRadii.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
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
    final filtered = q.isEmpty ? all : all.where((t) => t.title.toLowerCase().contains(q)).toList();
    final pinned = filtered.where((t) => t.pinned).toList();
    final rest = filtered.where((t) => !t.pinned).toList();

    return Drawer(
      width: 300,
      backgroundColor: surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(children: [
          _buildHeader(l),
          _buildSearch(surface, isDark, l),
          Expanded(
            child: provider.loading && all.isEmpty
                ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2.5))
                : all.isEmpty
                    ? _emptyState(l)
                    : filtered.isEmpty
                        ? _noResults(l)
                        : _list(pinned, rest, l, isDark),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(L10n l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
      child: Row(children: [
        Expanded(
          child: Text(l.t('ai_chats_title'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        ),
        GestureDetector(
          onTap: widget.onCreate,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadii.tile)),
            child: Icon(CupertinoIcons.add, color: Theme.of(context).colorScheme.primary, size: 22),
          ),
        ),
      ]),
    );
  }

  Widget _buildSearch(Color surface, bool isDark, L10n l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: l.t('search_chats'),
            hintStyle: const TextStyle(color: C.text4, fontSize: 15),
            prefixIcon: const Icon(CupertinoIcons.search, size: 20, color: C.text4),
            suffixIcon: _query.isEmpty
                ? null
                : GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        if (item is String) {
          return Padding(
            padding: EdgeInsets.only(left: 8, top: i == 0 ? 2 : 14, bottom: 8),
            child: Text(item.toUpperCase(),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.text4, letterSpacing: 1.0)),
          );
        }
        final t = item as AiThread;
        return TweenAnimationBuilder<double>(
          key: ValueKey('thread_${t.id}'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 260 + (i.clamp(0, 8)) * 35),
          curve: Curves.easeOutCubic,
          builder: (_, tv, child) => Opacity(opacity: tv, child: Transform.translate(offset: Offset(0, 10 * (1 - tv)), child: child)),
          child: RepaintBoundary(
              child: Dismissible(
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
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 22),
              child: const Icon(CupertinoIcons.trash, color: Colors.white, size: 20),
            ),
            child: _threadRow(t, l),
          )),
        );
      },
    );
  }

  Widget _threadRow(AiThread t, L10n l) {
    final primary = Theme.of(context).colorScheme.primary;
    final active = t.id == widget.activeThreadId;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onSelect(t);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: active ? adaptiveTealLt(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.tile),
        ),
        child: Row(children: [
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (t.pinned)
                Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Icon(CupertinoIcons.pin_fill, size: 11, color: primary)),
              Expanded(
                  child: Text(t.title.isEmpty ? l.t('untitled_chat') : t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: active ? primary : adaptiveText1(context),
                          letterSpacing: -0.1))),
            ]),
            const SizedBox(height: 2),
            Text(_relTime(t.updatedAt, l), style: const TextStyle(fontSize: 11, color: C.text4)),
          ])),
          GestureDetector(
            onTap: () => _showActions(t),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
                padding: EdgeInsets.only(left: 4), child: Icon(CupertinoIcons.ellipsis, size: 18, color: C.text4)),
          ),
        ]),
      ),
    );
  }

  Widget _emptyState(L10n l) {
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.card)),
                  child: Icon(CupertinoIcons.sparkles, size: 30, color: adaptiveText1(context).withValues(alpha: 0.4))),
              const SizedBox(height: 14),
              Text(l.t('no_chats'),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: adaptiveText1(context).withValues(alpha: 0.8))),
              const SizedBox(height: 6),
              SizedBox(
                  width: 240,
                  child: Text(l.t('no_chats_sub'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, height: 1.5, color: adaptiveText1(context).withValues(alpha: 0.5)))),
            ]),
          )),
        ),
      );
    });
  }

  Widget _noResults(L10n l) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 60, 28, 60),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.search, size: 36, color: adaptiveText1(context).withValues(alpha: 0.35)),
          const SizedBox(height: 12),
          Text(l.t('no_search_results'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(context).withValues(alpha: 0.55))),
        ]),
      ),
    );
  }
}
