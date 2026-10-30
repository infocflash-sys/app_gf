import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/portal_api.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../util/nav.dart';
import '../widgets/brand_logo.dart';
import 'welcome_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Cerrar sesión'),
        content: const Text('Vas a tener que ingresar de nuevo con tu usuario y contraseña.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await portal.logout();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(fadeRoute(const WelcomeScreen()), (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = portal.profile;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text('Perfil', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Brand.navy, Brand.black],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                child: const Icon(LucideIcons.building2, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p?.cliente ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                  const SizedBox(height: 3),
                  Text('Cliente Grupo Flash',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13)),
                ]),
              ),
            ]),
          ),
          if ((p?.clientes.length ?? 0) > 1) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cuentas vinculadas', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
                  const SizedBox(height: 8),
                  for (final c in p!.clientes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('• $c', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Apariencia',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeController,
            builder: (_, mode, _) => SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(LucideIcons.sun, size: 18), label: Text('Día')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(LucideIcons.moon, size: 18), label: Text('Noche')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(LucideIcons.smartphone, size: 18), label: Text('Auto')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => themeController.set(s.first),
            ),
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: StatusColors.novedad,
              side: const BorderSide(color: StatusColors.novedad),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(LucideIcons.logOut),
            label: const Text('Cerrar sesión'),
          ),
          const SizedBox(height: 28),
          Center(
            child: Column(children: [
              const BrandLogo(size: 30, light: false),
              const SizedBox(height: 6),
              Text('Portal Clientes · v0.2',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12)),
            ]),
          ),
        ],
      ),
    );
  }
}
