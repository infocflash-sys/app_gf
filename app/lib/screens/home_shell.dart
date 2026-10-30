import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/resume.dart';
import '../util/nav.dart';
import '../widgets/double_back.dart';
import 'piece_detail_screen.dart';
import 'pieces_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.resume});

  /// Si la app se cerró en segundo plano, se vuelve a la pieza (y al mapa) que se estaba viendo.
  final ResumePoint? resume;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final r = widget.resume;
    if (r != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(fadeRoute(PieceDetailScreen.byId(r.pieceId, mapOpen: r.mapOpen), ms: 250));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DoubleBackToMinimize(
      // desde "Perfil", "atrás" vuelve primero a "Mis piezas"
      onBack: () {
        if (_index == 0) return false;
        setState(() => _index = 0);
        return true;
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: const [PiecesScreen(), SettingsScreen()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(LucideIcons.package),
              selectedIcon: Icon(LucideIcons.packageOpen),
              label: 'Mis piezas',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.userRound),
              selectedIcon: Icon(LucideIcons.userRoundCheck),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}
