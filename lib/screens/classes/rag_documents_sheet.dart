import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/toast.dart';

void showRagDocumentsSheet(BuildContext context, {required int classId}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _RagDocumentsSheet(classId: classId),
  );
}

class _RagDocumentsSheet extends StatefulWidget {
  final int classId;
  const _RagDocumentsSheet({required this.classId});
  @override
  State<_RagDocumentsSheet> createState() => _RagDocumentsSheetState();
}

class _RagDocumentsSheetState extends State<_RagDocumentsSheet> {
  bool _loading = true;
  bool _uploading = false;
  List<dynamic> _docs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final docs = await context.read<ApiService>().ragDocuments(classId: widget.classId);
    if (!mounted) return;
    setState(() { _docs = docs; _loading = false; });
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (!mounted || result == null || result.files.isEmpty || result.files.first.path == null) return;
    final l = context.read<L10n>();
    final api = context.read<ApiService>();
    final file = result.files.first;
    setState(() => _uploading = true);
    try {
      final res = await api.ragIngest(file.path!, file.name, classId: widget.classId);
      if (!mounted) return;
      final chunks = (res['chunks'] as num?)?.toInt() ?? 0;
      showToast(context, '${l.t('ai_documents_processed')}: $chunks ${l.t('ai_documents_fragments')}');
      await _load();
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(dynamic doc) async {
    final l = context.read<L10n>();
    final ok = await showConfirmDialog(context,
      title: l.t('ai_documents_delete_confirm'),
      icon: CupertinoIcons.trash,
      danger: true,
      confirmText: l.t('delete'),
      cancelText: l.t('cancel'));
    if (ok != true || !mounted) return;
    final id = (doc['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await context.read<ApiService>().deleteRagDocument(id);
      if (!mounted) return;
      showToast(context, l.t('class_deleted'));
      _load();
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    }
  }

  String _fmtDate(String? d) {
    if (d == null || d.isEmpty) return '';
    try {
      final dt = DateTime.parse(d);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return d;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.4,
      builder: (ctx, sc) => Column(children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(children: [
            Container(width: 42, height: 42,
              decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
              child: Icon(CupertinoIcons.doc_text_search, color: primary, size: 21)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('ai_documents'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(l.t('ai_documents_sub'), style: const TextStyle(fontSize: 12, color: C.text4)),
            ])),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 48), child: ElevatedButton.icon(
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(CupertinoIcons.arrow_up_doc, size: 18, color: Colors.white),
            label: Text(_uploading ? l.t('ai_documents_uploading') : l.t('ai_documents_upload')),
          )),
        ),
        const SizedBox(height: 8),
        Expanded(child: _loading
            ? Center(child: CircularProgressIndicator(color: primary, strokeWidth: 2.5))
            : _docs.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(CupertinoIcons.doc_text, size: 44, color: C.text4),
                    const SizedBox(height: 10),
                    Text(l.t('ai_documents_empty'), style: const TextStyle(color: C.text4, fontSize: 14, fontWeight: FontWeight.w600)),
                  ]))
                : ListView.separated(
                    controller: sc,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    itemCount: _docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final doc = _docs[i];
                      final filename = (doc['filename'] ?? '').toString();
                      final chunks = (doc['chunks_count'] as num?)?.toInt();
                      final date = _fmtDate(doc['created_at']?.toString());
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadii.tile), boxShadow: softShadow(isDark)),
                        child: Row(children: [
                          Container(width: 40, height: 40, decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(11)),
                            child: Icon(CupertinoIcons.doc_text, color: primary, size: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(filename.isEmpty ? '—' : filename, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text([if (date.isNotEmpty) date, if (chunks != null) '$chunks ${l.t('ai_documents_fragments')}'].join(' · '),
                              style: const TextStyle(fontSize: 11, color: C.text4)),
                          ])),
                          GestureDetector(onTap: () => _delete(doc),
                            child: const Padding(padding: EdgeInsets.all(6), child: Icon(CupertinoIcons.trash, size: 17, color: C.red))),
                        ]),
                      );
                    },
                  )),
      ]),
    );
  }
}
