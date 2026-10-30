import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Estado de la pieza: azul si es definitivo, verde si sigue en gestión.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.definitivo, this.compact = false});
  final String label;
  final bool definitivo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context, definitivo: definitivo);
    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 190 : 280),
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(definitivo ? LucideIcons.circleCheck : LucideIcons.loader, size: compact ? 13 : 16, color: c),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: compact ? 11.5 : 13)),
        ),
      ]),
    );
  }
}
