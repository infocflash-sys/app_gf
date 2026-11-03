import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config.dart';
import '../data/portal_api.dart';
import '../theme/app_theme.dart';
import '../util/nav.dart';
import '../widgets/brand_logo.dart';
import '../widgets/double_back.dart';
import '../widgets/photo_backdrop.dart';
import 'greeting_screen.dart';
import 'guest_tracking_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.notice});

  /// Aviso inicial (por ejemplo, cuenta desactivada que obligó a cerrar la sesión).
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _hide = true;
  bool _loading = false;
  late String? _error = widget.notice;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await portal.login(_user.text, _pass.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        fadeRoute(GreetingScreen(cliente: p.cliente), ms: 600),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _forgot() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(LucideIcons.keyRound, size: 30),
        title: const Text('Recuperar contraseña'),
        content: const Text.rich(TextSpan(children: [
          TextSpan(text: 'Para recuperar tu clave, intentalo desde la web de acceso a clientes en nuestra web comercial '),
          TextSpan(text: AppConfig.webComercial, style: TextStyle(fontWeight: FontWeight.w800)),
        ])),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 46)),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      DoubleBackToMinimize(enabled: !Navigator.of(context).canPop(), child: _page(context));

  Widget _page(BuildContext context) {
    // El formulario va siempre sobre fondo oscuro con foto: se usa el tema oscuro en la tarjeta.
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: Brand.black,
        resizeToAvoidBottomInset: true,
        body: PhotoBackdrop(
          blur: 8,
          child: SafeArea(
            child: Column(children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: Navigator.of(context).canPop() ? () => Navigator.of(context).pop() : null,
                  icon: Icon(LucideIcons.arrowLeft,
                      color: Navigator.of(context).canPop() ? Colors.white : Colors.transparent),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const BrandLogo(size: 52)
                          .animate()
                          .fadeIn(duration: 500.ms)
                          .scale(begin: const Offset(0.92, 0.92), curve: Curves.easeOutBack),
                      const SizedBox(height: 28),
                      GlassCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Ingresá a tu cuenta',
                              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('Accedé a las piezas de tu empresa',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                          const SizedBox(height: 22),
                          TextField(
                            controller: _user,
                            enabled: !_loading,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                                labelText: 'Usuario', prefixIcon: Icon(LucideIcons.user)),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _pass,
                            enabled: !_loading,
                            obscureText: _hide,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(LucideIcons.lock),
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _hide = !_hide),
                                icon: Icon(_hide ? LucideIcons.eye : LucideIcons.eyeOff),
                              ),
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            alignment: Alignment.topCenter,
                            child: _error == null
                                ? const SizedBox(width: double.infinity)
                                : Padding(
                                    padding: const EdgeInsets.only(top: 14),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Icon(LucideIcons.circleAlert, size: 16, color: Color(0xFFFF7A7F)),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_error!,
                                            style: const TextStyle(
                                                color: Color(0xFFFF7A7F), fontWeight: FontWeight.w600)),
                                      ),
                                    ]),
                                  ),
                          ),
                          const SizedBox(height: 22),
                          FilledButton(
                            onPressed: _loading ? null : _submit,
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.white, foregroundColor: Brand.navy),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _loading
                                  ? const SizedBox(
                                      key: ValueKey('l'),
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Brand.navy))
                                  : const Text('Ingresar', key: ValueKey('t')),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton(
                              onPressed: _loading ? null : _forgot,
                              child: Text('¿Olvidaste tu contraseña?',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                            ),
                          ),
                        ]),
                      ).animate().fadeIn(delay: 150.ms, duration: 500.ms).slideY(begin: 0.08, end: 0),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).push(fadeRoute(const GuestTrackingScreen())),
                        icon: Icon(LucideIcons.packageSearch, size: 18, color: Colors.white.withValues(alpha: 0.75)),
                        label: Text('Acceso como Destinatario',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w600)),
                      ).animate().fadeIn(delay: 250.ms, duration: 500.ms),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
