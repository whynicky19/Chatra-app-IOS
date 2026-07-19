import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/toast.dart';

/// Админ-вкладка «Жалобы» (UGC-модерация). Показывает жалобы пользователей
/// (POST /reports), позволяет пометить обработанной и заблокировать нарушителя.
class AdminReportsTab extends StatefulWidget {
  final bool isActive;
  final void Function(int openCount) onOpenCountChanged;
  const AdminReportsTab({super.key, required this.isActive, required this.onOpenCountChanged});

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  bool _loading = true;
  bool _triggered = false;
  List<dynamic> _reports = [];

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(AdminReportsTab old) {
    super.didUpdateWidget(old);
    if (!old.isActive && widget.isActive && !_triggered) _load();
  }

  Future<void> _load() async {
    _triggered = true;
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await context.read<ApiService>().getReports();
      if (!mounted) return;
      setState(() { _reports = rows; _loading = false; });
      _notifyOpenCount();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notifyOpenCount() {
    final open = _reports.where((r) => r['status'] == 'open').length;
    widget.onOpenCountChanged(open);
  }

  Future<void> _resolve(dynamic r) async {
    final id = (r['id'] as num).toInt();
    try {
      await context.read<ApiService>().resolveReport(id);
      if (!mounted) return;
      setState(() => r['status'] = 'resolved');
      _notifyOpenCount();
    } catch (_) {
      if (mounted) showToast(context, context.read<L10n>().t('error'), error: true);
    }
  }

  Future<void> _blockReported(dynamic r) async {
    final l = context.read<L10n>();
    final api = context.read<ApiService>();
    final uid = (r['reported_user_id'] as num).toInt();
    final ok = await showConfirmDialog(context,
      title: l.t('block_user_q'),
      message: l.t('block_user_msg'),
      icon: CupertinoIcons.nosign,
      danger: true,
      confirmText: l.t('block'),
      cancelText: l.t('cancel'));
    if (ok != true) return;
    try {
      await api.adminBlock(uid);
      if (!mounted) return;
      setState(() => r['reported_user_active'] = false);
      showToast(context, l.t('user_blocked_toast'));
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    }
  }

  String _fmtDate(dynamic iso) {
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_reports.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          Center(child: Column(children: [
            Icon(CupertinoIcons.checkmark_shield, size: 44, color: C.text4.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(l.t('no_reports'), style: const TextStyle(fontSize: 15, color: C.text4, fontWeight: FontWeight.w600)),
          ])),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
        itemCount: _reports.length,
        itemBuilder: (_, i) => _reportCard(_reports[i], l, isDark),
      ),
    );
  }

  Widget _reportCard(dynamic r, L10n l, bool isDark) {
    final open = r['status'] == 'open';
    final blocked = r['reported_user_active'] == false;
    final reason = (r['reason'] ?? 'report_other').toString();
    final content = (r['content'] ?? '').toString();
    final reportedName = (r['reported_user_name'] ?? '#${r['reported_user_id']}').toString();
    final reporterName = (r['reporter_name'] ?? '#${r['reporter_id']}').toString();
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? C.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: cardShadow(isDark),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Reason + status
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: C.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(l.t(reason), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.red)),
          ),
          const Spacer(),
          Text(open ? l.t('report_status_open') : l.t('report_status_resolved'),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: open ? const Color(0xFFF59E0B) : C.green)),
        ]),
        const SizedBox(height: 10),
        _row(l.t('report_on_label'), reportedName, danger: true, struck: blocked),
        const SizedBox(height: 3),
        _row(l.t('report_by_label'), reporterName),
        if (content.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(10)),
            child: Text(content, style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
        const SizedBox(height: 6),
        Text(_fmtDate(r['created_at']), style: const TextStyle(fontSize: 10, color: C.text4)),
        if (open) ...[
          const SizedBox(height: 12),
          Row(children: [
            if (!blocked)
              Expanded(child: GestureDetector(
                onTap: () => _blockReported(r),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(color: C.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(l.t('block'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.red))),
                ),
              )),
            if (!blocked) const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: () => _resolve(r),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text(l.t('report_resolve'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
              ),
            )),
          ]),
        ],
      ]),
    );
  }

  Widget _row(String label, String value, {bool danger = false, bool struck = false}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 12, color: C.text4, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
          color: danger ? C.red : adaptiveText1(context),
          decoration: struck ? TextDecoration.lineThrough : null))),
    ]);
  }
}
