import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Marca provisoria hasta contar con el logo vectorial oficial.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 40, this.light = true, this.showText = true});
  final double size;
  final bool light; // texto claro (sobre fondos oscuros)
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final fg = light ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          gradient: const LinearGradient(
            colors: [Brand.navySoft, Brand.navyDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Icon(LucideIcons.zap, color: Brand.flash, size: size * 0.55),
      ),
      if (showText) ...[
        SizedBox(width: size * 0.3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('GRUPO FLASH',
                style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.36,
                    letterSpacing: 1.2,
                    height: 1.1)),
            Text('Logística y Postal',
                style: TextStyle(
                    color: fg.withValues(alpha: 0.65),
                    fontSize: size * 0.27,
                    letterSpacing: 0.4)),
          ],
        ),
      ],
    ]);
  }
}
