import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

/// Opens the "Create AI avatar" bottom sheet. Returns true if an avatar
/// request was successfully submitted (caller should refresh its state).
Future<bool?> showCreateAvatarSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _CreateAvatarSheet(),
  );
}

class _CreateAvatarSheet extends StatefulWidget {
  const _CreateAvatarSheet();
  @override
  State<_CreateAvatarSheet> createState() => _CreateAvatarSheetState();
}

class _CreateAvatarSheetState extends State<_CreateAvatarSheet> {
  final _nameCtrl = TextEditingController();
  XFile? _photo;

  // 0 = record from mic, 1 = upload file
  int _voiceMode = 0;
  String? _recordedPath;
  PlatformFile? _uploadedVoiceFile;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _isRecording = false;
  bool _isPlaying = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  bool _submitting = false;
  double _uploadProgress = 0;

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String get _voiceSourcePath => _voiceMode == 0 ? (_recordedPath ?? '') : (_uploadedVoiceFile?.path ?? '');
  bool get _hasVoice => _voiceSourcePath.isNotEmpty;
  bool get _canSubmit => _photo != null && _hasVoice && !_submitting;

  String _fmtTimer(int secs) => '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';

  Future<void> _pickPhoto() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (img != null && mounted) setState(() => _photo = img);
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) showToast(context, context.read<L10n>().t('mic_permission_denied'), error: true);
      return;
    }
    if (!mounted) return;
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (mounted) showToast(context, context.read<L10n>().t('mic_permission_denied'), error: true);
      return;
    }
    final dir = Directory.systemTemp;
    final path = '${dir.path}/avatar_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (!mounted) return;
    setState(() { _isRecording = true; _recordSeconds = 0; _recordedPath = null; });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    _recordTimer?.cancel();
    if (!mounted) return;
    setState(() { _isRecording = false; _recordedPath = path; });
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    try {
      await _player.setFilePath(_voiceSourcePath);
      if (!mounted) return;
      setState(() => _isPlaying = true);
      unawaited(_player.play());
      _player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed && mounted) {
          setState(() => _isPlaying = false);
        }
      });
    } catch (_) {
      if (mounted) showToast(context, context.read<L10n>().t('error'), error: true);
    }
  }

  Future<void> _pickVoiceFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'wav', 'm4a']);
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _uploadedVoiceFile = result.files.first);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final l = context.read<L10n>();
    final api = context.read<ApiService>();
    setState(() { _submitting = true; _uploadProgress = 0; });
    try {
      final photoRes = await api.uploadFile(_photo!.path, _photo!.name);
      if (!mounted) return;
      setState(() => _uploadProgress = 0.5);
      final photoUrl = (photoRes['url'] ?? photoRes['file_url'] ?? photoRes['path'])?.toString();

      final voiceName = _voiceMode == 0 ? 'voice_sample.m4a' : (_uploadedVoiceFile!.name);
      final voiceRes = await api.uploadFile(_voiceSourcePath, voiceName);
      if (!mounted) return;
      setState(() => _uploadProgress = 0.85);
      final voiceUrl = (voiceRes['url'] ?? voiceRes['file_url'] ?? voiceRes['path'])?.toString();

      if (photoUrl == null || voiceUrl == null) throw Exception('upload_failed');

      await api.createMyAvatar(
        displayName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        photoUrl: photoUrl,
        voiceSampleUrl: voiceUrl,
      );
      if (!mounted) return;
      setState(() => _uploadProgress = 1);
      showToast(context, l.t('avatar_request_sent'));
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(width: 42, height: 42,
              decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
              child: Icon(CupertinoIcons.person_crop_circle_badge_plus, color: primary, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Text(l.t('create_avatar_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            GestureDetector(onTap: () => Navigator.pop(context),
              child: Container(width: 32, height: 32, decoration: BoxDecoration(color: adaptiveSurface2(context), shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.xmark, size: 16, color: C.text4))),
          ]),
          const SizedBox(height: 16),

          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: adaptivePrimaryLt(context), borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(CupertinoIcons.info_circle_fill, size: 18, color: primary),
              const SizedBox(width: 10),
              Expanded(child: Text(l.t('avatar_info_banner'), style: TextStyle(fontSize: 12.5, color: primary, height: 1.4))),
            ]),
          ),
          const SizedBox(height: 20),

          Text(l.t('avatar_display_name'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 1)),
          const SizedBox(height: 8),
          TextField(controller: _nameCtrl, decoration: InputDecoration(hintText: l.t('avatar_display_name_hint'))),
          const SizedBox(height: 20),

          Text(l.t('avatar_photo_label'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 1)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primary.withValues(alpha: 0.3), width: 1.5),
                color: _photo == null ? adaptivePrimaryLt(context).withValues(alpha: 0.3) : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: _photo == null
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(CupertinoIcons.person_crop_rectangle, size: 32, color: primary),
                      const SizedBox(height: 8),
                      Text(l.t('avatar_photo_hint'), style: TextStyle(fontSize: 12, color: C.text4), textAlign: TextAlign.center),
                    ])
                  : Stack(fit: StackFit.expand, children: [
                      Image.file(File(_photo!.path), fit: BoxFit.cover),
                      Positioned(bottom: 8, right: 8, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10)),
                        child: Text(l.t('avatar_photo_replace'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      )),
                    ]),
            ),
          ),
          const SizedBox(height: 20),

          Text(l.t('avatar_voice_label'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 1)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => setState(() => _voiceMode = 0),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(color: _voiceMode == 0 ? Theme.of(context).colorScheme.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(l.t('record_voice'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _voiceMode == 0 ? primary : C.text4)))),
              )),
              Expanded(child: GestureDetector(
                onTap: () => setState(() => _voiceMode = 1),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(color: _voiceMode == 1 ? Theme.of(context).colorScheme.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(l.t('upload_file'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _voiceMode == 1 ? primary : C.text4)))),
              )),
            ]),
          ),
          const SizedBox(height: 14),

          if (_voiceMode == 0) _buildRecordUi(l, primary, isDark) else _buildUploadUi(l, primary),

          const SizedBox(height: 24),
          if (_submitting) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: _uploadProgress, minHeight: 5, color: primary, backgroundColor: primary.withValues(alpha: 0.12))),
          ),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
            onPressed: _canSubmit ? _submit : null,
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(l.t('send_for_approval')),
          )),
        ]),
      ),
    );
  }

  Widget _buildRecordUi(L10n l, Color primary, bool isDark) {
    if (_recordedPath != null && !_isRecording) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(width: 42, height: 42,
              decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
              child: Icon(_isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, color: Colors.white, size: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(_fmtTimer(_recordSeconds), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          GestureDetector(
            onTap: () { setState(() { _recordedPath = null; _recordSeconds = 0; }); },
            child: Row(children: [
              Icon(CupertinoIcons.arrow_counterclockwise, size: 14, color: C.text4),
              const SizedBox(width: 4),
              Text(l.t('avatar_record_again'), style: const TextStyle(fontSize: 12, color: C.text4)),
            ]),
          ),
        ]),
      );
    }
    return Column(children: [
      GestureDetector(
        onTap: _isRecording ? _stopRecording : _startRecording,
        child: Container(
          width: 78, height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isRecording ? C.red : primary,
            boxShadow: primaryGlow(_isRecording ? C.red : primary, opacity: 0.35),
          ),
          child: Icon(_isRecording ? CupertinoIcons.stop_fill : CupertinoIcons.mic_fill, color: Colors.white, size: 30),
        ),
      ),
      const SizedBox(height: 10),
      Text(_isRecording ? _fmtTimer(_recordSeconds) : l.t('record_start'),
        style: TextStyle(fontSize: _isRecording ? 20 : 13, fontWeight: FontWeight.w700, color: _isRecording ? C.red : C.text4)),
      const SizedBox(height: 6),
      Text(l.t('avatar_voice_record_hint'), style: const TextStyle(fontSize: 12, color: C.text4), textAlign: TextAlign.center),
      const SizedBox(height: 2),
      Text(l.t('avatar_min_30s'), style: TextStyle(fontSize: 11, color: C.text4.withValues(alpha: 0.8))),
    ]);
  }

  Widget _buildUploadUi(L10n l, Color primary) {
    return GestureDetector(
      onTap: _pickVoiceFile,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: primary.withValues(alpha: 0.3))),
        child: Row(children: [
          Icon(CupertinoIcons.waveform, color: primary, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_uploadedVoiceFile?.name ?? l.t('upload_file'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _uploadedVoiceFile == null ? C.text4 : primary), overflow: TextOverflow.ellipsis),
            Text(l.t('avatar_voice_file_hint'), style: const TextStyle(fontSize: 11, color: C.text4)),
          ])),
          if (_uploadedVoiceFile != null)
            Icon(CupertinoIcons.checkmark_circle_fill, color: C.green, size: 20)
          else
            Icon(CupertinoIcons.chevron_right, color: C.text4, size: 18),
        ]),
      ),
    );
  }
}
