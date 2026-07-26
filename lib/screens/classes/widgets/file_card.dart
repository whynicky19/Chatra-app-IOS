import 'package:flutter/cupertino.dart';
import 'detail_page_theme.dart';

class FileTypeVisual {
  final IconData icon;
  final Color color;
  const FileTypeVisual(this.icon, this.color);
}

FileTypeVisual fileTypeVisual(String ext) {
  switch (ext) {
    case 'pdf':
      return const FileTypeVisual(CupertinoIcons.doc_text_fill, Color(0xFFE5484D));
    case 'pptx':
    case 'ppt':
      return const FileTypeVisual(CupertinoIcons.film, Color(0xFFF2A93B));
    case 'doc':
    case 'docx':
      return const FileTypeVisual(CupertinoIcons.doc_text_fill, Color(0xFF3B9FF2));
    case 'xlsx':
    case 'xls':
      return const FileTypeVisual(CupertinoIcons.square_grid_2x2_fill, Color(0xFF3BBF6E));
    case 'txt':
    case 'md':
      return const FileTypeVisual(CupertinoIcons.doc_plaintext, Color(0xFFA681E8));
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
      return const FileTypeVisual(CupertinoIcons.photo_fill, Color(0xFF3BB6F2));
    case 'mp4':
    case 'mov':
    case 'avi':
      return const FileTypeVisual(CupertinoIcons.play_circle_fill, Color(0xFFC46BE0));
    default:
      return const FileTypeVisual(CupertinoIcons.doc_fill, Color(0xFF9A9A9A));
  }
}

/// Карточка вложенного файла в духе Apple Files: своя независимая карточка,
/// крупная иконка типа файла, имя, тип, шеврон открытия, лёгкая press-анимация.
class FileCard extends StatefulWidget {
  final String name;
  final String? sizeLabel;
  final VoidCallback onTap;

  const FileCard({super.key, required this.name, this.sizeLabel, required this.onTap});

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ext = widget.name.contains('.') ? widget.name.split('.').last.toLowerCase() : '';
    final visual = fileTypeVisual(ext);
    final typeLabel = ext.isNotEmpty ? ext.toUpperCase() : '';
    final subtitle = widget.sizeLabel != null && widget.sizeLabel!.isNotEmpty
        ? '$typeLabel • ${widget.sizeLabel}'
        : typeLabel;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _pressed ? detailSurface(context).withValues(alpha: 0.7) : detailSurface(context),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: detailBorder(context)),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(visual.icon, size: 22, color: visual.color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.name,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: detailText1(context)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: detailText2(context), letterSpacing: 0.2)),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right, size: 17, color: detailText2(context)),
          ]),
        ),
      ),
    );
  }
}
