import 'package:flutter/material.dart';
import '../services/home_page.dart';
import '../services/auth_service.dart';
import 'package:go_router/go_router.dart';

enum _LoginMode { guest, existing }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.initialAddressCards = const []});
  final List<String> initialAddressCards;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const accent = Color(0xFF53D6FF);

  _LoginMode mode = _LoginMode.guest;

  final TextEditingController usernameCtrl = TextEditingController();
  final TextEditingController passwordCtrl = TextEditingController();

  bool hidePassword = true;
  bool isSubmitting = false;

  @override
  void dispose() {
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }

  void _goHome() {
    context.go('/');
  }

  Future<void> _loginExisting() async {
    final username = usernameCtrl.text.trim();
    final password = passwordCtrl.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Kullanıcı adı ve şifre girin")),
      );
      return;
    }

    setState(() => isSubmitting = true);

    final errorMessage = await AuthService.login(username, password);
    setState(() => isSubmitting = false);

    if (errorMessage == null) {
      _goHome();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _DarkBackground(),
          Row(
            children: [
              // Left sidebar - brand panel
              Container(
                width: 280,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1624).withOpacity(0.85),
                  border: Border(
                    right: BorderSide(
                      color: Colors.white.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                ),
                child: const _LeftBrandPanel(),
              ),

              // Right content area
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: _DarkGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 22,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _RightHeader(),
                              const SizedBox(height: 14),
                              _ModeSwitch(
                                mode: mode,
                                accent: accent,
                                onChanged: (m) => setState(() => mode = m),
                              ),
                              const SizedBox(height: 12),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, anim) {
                                  return FadeTransition(
                                    opacity: anim,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.03),
                                        end: Offset.zero,
                                      ).animate(anim),
                                      child: child,
                                    ),
                                  );
                                },
                                child: mode == _LoginMode.existing
                                    ? _ExistingForm(
                                        key: const ValueKey('existingForm'),
                                        usernameCtrl: usernameCtrl,
                                        passwordCtrl: passwordCtrl,
                                        hidePassword: hidePassword,
                                        onToggleHide: () => setState(
                                          () => hidePassword = !hidePassword,
                                        ),
                                        onLogin: isSubmitting
                                            ? null
                                            : _loginExisting,
                                        isSubmitting: isSubmitting,
                                        accent: accent,
                                      )
                                    : _GuestBlock(
                                        key: const ValueKey('guestBlock'),
                                        accent: accent,
                                        onContinue: _goHome,
                                      ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Not: Mevcut kullanıcı hesapları uygulama geliştiricileri tarafından tanımlanır.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.42),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* --------------------------- Background --------------------------- */

class _DarkBackground extends StatelessWidget {
  const _DarkBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A0F18), Color(0xFF0E1726)],
            ),
          ),
        ),

        // Soft neon blobs
        Positioned(
          left: -140,
          top: -160,
          child: _NeonBlob(size: 420, color: Color(0xFF53D6FF), opacity: 0.10),
        ),
        Positioned(
          right: -160,
          bottom: -170,
          child: _NeonBlob(size: 470, color: Color(0xFF6F7CFF), opacity: 0.10),
        ),
        Positioned(
          right: 120,
          top: 80,
          child: _NeonBlob(size: 240, color: Color(0xFF53D6FF), opacity: 0.07),
        ),

        // vignette
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.2,
                  colors: [Colors.white.withOpacity(0.06), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NeonBlob extends StatelessWidget {
  const _NeonBlob({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(opacity),
        boxShadow: [
          BoxShadow(
            blurRadius: 90,
            spreadRadius: 14,
            offset: const Offset(0, 20),
            color: color.withOpacity(opacity * 0.9),
          ),
        ],
      ),
    );
  }
}

/* --------------------------- Card --------------------------- */

class _DarkGlassCard extends StatelessWidget {
  const _DarkGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xFF0F1624).withOpacity(0.90),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 50,
            offset: Offset(0, 22),
            color: Color(0x55000000),
          ),
        ],
      ),
      child: child,
    );
  }
}

/* --------------------------- Left Panel --------------------------- */

class _LeftBrandPanel extends StatelessWidget {
  const _LeftBrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0E1626),
            const Color(0xFF0E1626).withOpacity(0.65),
          ],
        ),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withOpacity(0.06),
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
                ),
                child: Icon(
                  Icons.route_rounded,
                  color: Colors.white.withOpacity(0.85),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rota Desktop',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withOpacity(0.88),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Planla • Düzenle • Takip Et',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.50),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Günün rotasını\ntek ekranda yönet.',
                style: TextStyle(
                  fontSize: 28,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withOpacity(0.92),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Adres havuzunu düzenle, takvime oturt, rota oluştur.\n'
                'Masaüstünde hızlı ve temiz bir akış.',
                style: TextStyle(
                  fontSize: 13.2,
                  height: 1.35,
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _Chip(icon: Icons.calendar_month_rounded, text: 'Takvim'),
              _Chip(icon: Icons.location_on_rounded, text: 'Adres Havuzu'),
              _Chip(icon: Icons.auto_awesome_rounded, text: 'Rota'),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'İpucu: Misafir modunda planlar cihazda tutulur.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white.withOpacity(0.80)),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: Colors.white.withOpacity(0.86),
            ),
          ),
        ],
      ),
    );
  }
}

/* --------------------------- Right Header --------------------------- */

class _RightHeader extends StatelessWidget {
  const _RightHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Icon(
            Icons.login_rounded,
            color: Colors.white.withOpacity(0.85),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Giriş',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withOpacity(0.90),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: const Color(0xFF53D6FF).withOpacity(0.12),
                      border: Border.all(
                        color: const Color(0xFF53D6FF).withOpacity(0.28),
                      ),
                    ),
                    child: const Text(
                      'beta',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Color(0xFF53D6FF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Hızlı ve düzenli şekilde başla',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* --------------------------- Mode Switch --------------------------- */

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.mode,
    required this.accent,
    required this.onChanged,
  });

  final _LoginMode mode;
  final Color accent;
  final ValueChanged<_LoginMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Choice(
              selected: mode == _LoginMode.guest,
              icon: Icons.person_outline_rounded,
              title: 'Misafir',
              subtitle: '(Kayıt olmadan)',
              onTap: () => onChanged(_LoginMode.guest),
              accent: accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Choice(
              selected: mode == _LoginMode.existing,
              icon: Icons.lock_outline_rounded,
              title: 'Mevcut Kullanıcı',
              subtitle: 'Kullanıcı adı/şifre',
              onTap: () => onChanged(_LoginMode.existing),
              accent: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.accent,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? accent.withOpacity(0.10) : Colors.transparent;
    final br =
        selected ? accent.withOpacity(0.40) : Colors.white.withOpacity(0.10);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: bg,
          border: Border.all(color: br),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? accent : Colors.white.withOpacity(0.75),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withOpacity(0.88),
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: accent,
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.52),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* --------------------------- Guest --------------------------- */

class _GuestBlock extends StatelessWidget {
  const _GuestBlock({
    super.key,
    required this.accent,
    required this.onContinue,
  });

  final Color accent;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withOpacity(0.04),
            border: Border.all(color: accent.withOpacity(0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Misafir modunda planlar cihazda tutulur. İstersen sonra mevcut kullanıcı ile giriş yapabilirsin.',
                  style: TextStyle(
                    height: 1.35,
                    color: Colors.white.withOpacity(0.72),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text(
              'Misafir Olarak Devam Et',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withOpacity(0.55), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}

/* --------------------------- Existing Form --------------------------- */

class _ExistingForm extends StatelessWidget {
  const _ExistingForm({
    super.key,
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.hidePassword,
    required this.onToggleHide,
    required this.onLogin,
    required this.isSubmitting,
    required this.accent,
  });

  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final bool hidePassword;
  final VoidCallback onToggleHide;
  final Future<void> Function()? onLogin;
  final bool isSubmitting;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModernTextField(
          controller: usernameCtrl,
          label: 'Kullanıcı adı',
          hint: 'örn. admin',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 10),
        _ModernTextField(
          controller: passwordCtrl,
          label: 'Şifre',
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscureText: hidePassword,
          trailing: IconButton(
            onPressed: onToggleHide,
            tooltip: hidePassword ? 'Göster' : 'Gizle',
            icon: Icon(
              hidePassword
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: onLogin == null
                ? null
                : () async {
                    FocusScope.of(context).unfocus();
                    await onLogin!();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: accent.withOpacity(0.16),
              foregroundColor: accent,
              side: BorderSide(color: accent.withOpacity(0.55), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Text(
                    'Giriş Yap',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ModernTextField extends StatelessWidget {
  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.trailing,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: TextStyle(color: Colors.white.withOpacity(0.88)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: trailing,
      ),
    );
  }
}
