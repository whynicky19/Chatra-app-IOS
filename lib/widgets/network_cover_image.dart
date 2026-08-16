import 'package:flutter/widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Сетевая обложка (класс/лекция) без отдельного compositing-слоя: у
/// CachedNetworkImage свой AnimatedSwitcher, и внутри ClipRRect его слой
/// расходился с фоном на 1-2px, оставляя полоску у края.
class NetworkCoverImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final int? memCacheWidth;
  final WidgetBuilder? placeholderBuilder;
  final WidgetBuilder? errorBuilder;

  const NetworkCoverImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  /// Бэкенд подписывает файловые URL параметрами exp/sig и переподписывает их
  /// заново при КАЖДОМ ответе (см. file_urls.py: sign_uploads_in_text) — сама
  /// подпись не имеет отношения к содержимому файла. Если кэшировать по
  /// полному URL как есть, каждое открытие экрана получает новый exp/sig →
  /// новый "URL" → мимо диск-кэша → обложка перекачивается заново каждый раз.
  /// Путь файла (без query) стабилен, пока обложку не перезалили — поэтому
  /// именно он служит ключом кэша, а полный URL с подписью используется
  /// только для самого запроса.
  String get _stableCacheKey {
    final i = url.indexOf('?');
    return i == -1 ? url : url.substring(0, i);
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ResizeImage.resizeIfNeeded(
        memCacheWidth,
        null,
        CachedNetworkImageProvider(url, cacheKey: _stableCacheKey),
      ),
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      errorBuilder: (ctx, _, __) =>
          (errorBuilder ?? placeholderBuilder)?.call(ctx) ?? const SizedBox.shrink(),
      frameBuilder: (ctx, child, frame, wasSyncLoaded) {
        if (frame == null && !wasSyncLoaded) {
          return placeholderBuilder?.call(ctx) ?? const SizedBox.shrink();
        }
        return child;
      },
    );
  }
}
