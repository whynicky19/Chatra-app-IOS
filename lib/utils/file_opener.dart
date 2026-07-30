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

  // Ссылку на навигатор берём ДО первого await: если экран закроют во время
  // скачивания, context станет невалидным, а модалку всё равно нужно снять —
  // иначе пользователь остаётся с barrierDismissible:false спиннером навсегда.
  final nav = Navigator.of(context, rootNavigator: true);
  final l = context.read<L10n>();

  var dialogClosed = false;
  void closeDialog() {
    if (dialogClosed) return;
    dialogClosed = true;
    if (nav.canPop()) nav.pop();
  }

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

  Future<void> openInBrowser() async {
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) return;
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
  }

  try {
    final dir = await getTemporaryDirectory();
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    // Кэш-ключ уходит в имя ПАПКИ, а не файла: иначе он торчит перед названием
    // в системном вьюере/шаринге при открытии (юзер видел "a3f9c1_Отчёт.pdf").
    final cacheDir = Directory('${dir.path}/dl_${fileCacheKey(cleanUrl)}');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    final filePath = '${cacheDir.path}/$safeName';
    final file = File(filePath);

    if (!await file.exists()) {
      // Чужой хост (R2/CDN) качаем клиентом без Authorization — токен наружу
      // уходить не должен.
      await api.clientForUrl(cleanUrl).download(cleanUrl, filePath,
          options: Options(receiveTimeout: const Duration(minutes: 5)));
    }
    closeDialog();

    final result = await OpenFile.open(filePath);
    if (result.type != ResultType.done) await openInBrowser();
  } on DioException catch (e) {
    closeDialog();
    final code = e.response?.statusCode;
    if (code == 404) {
      if (context.mounted) showToast(context, l.t('file_not_found_server'), error: true);
      return;
    }
    // 403 = подпись истекла; в браузере юзер увидит сырой JSON, поэтому говорим честно.
    if (code == 403) {
      if (context.mounted) showToast(context, l.t('file_link_expired'), error: true);
      return;
    }
    await openInBrowser();
  } catch (_) {
    closeDialog();
    await openInBrowser();
  }
}
