import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:dio/dio.dart' show DioException, Options;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/toast.dart';

/// Downloads a remote file to the temp dir and opens it with the native
/// viewer. Shows a modal spinner while downloading, reuses a cached copy,
/// reports a missing file honestly instead of dumping the user into the
/// browser (where ngrok's interstitial would greet them).
Future<void> openRemoteFile(BuildContext context, ApiService api, String url, String name) async {
  final cleanUrl = url.split('#').first;

  var dialogClosed = false;
  showCupertinoDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const CupertinoAlertDialog(
      content: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: CupertinoActivityIndicator(radius: 14),
      ),
    ),
  );
  void closeDialog() {
    if (!dialogClosed && context.mounted) {
      dialogClosed = true;
      Navigator.pop(context);
    }
  }

  try {
    final dir = await getTemporaryDirectory();
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${dir.path}/${cleanUrl.hashCode.toRadixString(16)}_$safeName';
    final file = File(filePath);

    if (!await file.exists()) {
      await api.dio.download(cleanUrl, filePath,
          options: Options(receiveTimeout: const Duration(minutes: 5)));
    }
    if (!context.mounted) return;
    closeDialog();

    final result = await OpenFile.open(filePath);
    if (result.type != ResultType.done && context.mounted) {
      await launchUrl(Uri.parse(cleanUrl), mode: LaunchMode.externalApplication);
    }
  } on DioException catch (e) {
    if (!context.mounted) return;
    closeDialog();
    if (e.response?.statusCode == 404) {
      showToast(context, 'Файл не найден на сервере — возможно, он был удалён', error: true);
      return;
    }
    try { await launchUrl(Uri.parse(cleanUrl), mode: LaunchMode.externalApplication); } catch (_) {}
  } catch (_) {
    if (!context.mounted) return;
    closeDialog();
    try { await launchUrl(Uri.parse(cleanUrl), mode: LaunchMode.externalApplication); } catch (_) {}
  }
}
