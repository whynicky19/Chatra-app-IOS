import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:dio/dio.dart' show DioException, Options;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/l10n_provider.dart';
import '../screens/classes/class_detail_utils.dart' show fileCacheKey;
import '../services/api_service.dart';
import '../widgets/toast.dart';

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
    final filePath = '${dir.path}/${fileCacheKey(cleanUrl)}_$safeName';
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
    final code = e.response?.statusCode;
    if (code == 404) {
      showToast(context, context.read<L10n>().t('file_not_found_server'), error: true);
      return;
    }
    // 403 = подпись истекла; в браузере юзер увидит сырой JSON, поэтому говорим честно.
    if (code == 403) {
      showToast(context, context.read<L10n>().t('file_link_expired'), error: true);
      return;
    }
    try { await launchUrl(Uri.parse(cleanUrl), mode: LaunchMode.externalApplication); } catch (_) {}
  } catch (_) {
    if (!context.mounted) return;
    closeDialog();
    try { await launchUrl(Uri.parse(cleanUrl), mode: LaunchMode.externalApplication); } catch (_) {}
  }
}
