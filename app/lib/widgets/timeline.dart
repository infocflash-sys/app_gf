import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import 'auth_image.dart';

/// Línea de tiempo del tracking. Cada evento puede traer su foto y su firma.
class TrackingTimeline extends StatelessWidget {
  const TrackingTimeline({super.key, required this.pieceId, required this.events, required this.onOpenImage});
  final int pieceId;
  final List<TrackEvent> events;
  final void Function(TrackEvent event, String kind) onOpenImage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 34,
                child: Column(children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: StatusColors.of(context, definitivo: events[i].definitivo)
                          .withValues(alpha: i == 0 ? 1 : 0.16),
                    ),
                    child: Icon(
                      events[i].definitivo ? LucideIcons.circleCheck : LucideIcons.circleDot,
                      size: 16,
                      color: i == 0
                          ? Colors.white
                          : StatusColors.of(context, definitivo: events[i].definitivo),
                    ),
                  ),
                  if (i < events.length - 1)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: cs.outlineVariant,
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(events[i].estado,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    if (events[i].fecha != null)
                      Text(fmtDateTime(events[i].fecha!),
                          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55), fontSize: 12.5)),
                    if (events[i].foto || events[i].firma) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        if (events[i].foto) _Thumb(pieceId, events[i], 'foto', 'Foto', onOpenImage),
                        if (events[i].foto && events[i].firma) const SizedBox(width: 10),
                        if (events[i].firma) _Thumb(pieceId, events[i], 'firma', 'Firma', onOpenImage),
                      ]),
                    ],
                  ]),
                ),
              ),
            ])
                .animate(delay: (70 * i.clamp(0, 10)).ms)
                .fadeIn(duration: 320.ms)
                .slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.pieceId, this.event, this.kind, this.label, this.onOpen);
  final int pieceId;
  final TrackEvent event;
  final String kind;
  final String label;
  final void Function(TrackEvent, String) onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onOpen(event, kind),
      child: Hero(
        tag: 'img-$pieceId-${event.id}-$kind',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 128,
            height: 96,
            child: Stack(fit: StackFit.expand, children: [
              AuthImage(pieceId: pieceId, eventId: event.id, kind: kind),
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(kind == 'foto' ? LucideIcons.camera : LucideIcons.penLine,
                        size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
