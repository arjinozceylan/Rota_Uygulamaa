import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  static const accent = Color(0xFF53D6FF);
  static const _bg1 = Color(0xFF0A0F18);
  static const _bg2 = Color(0xFF0E1726);
  static const _card = Color(0xFF0F1624);

  // 1 = kullanıcı adı + e-posta gir, 2 = kod + yeni şifre gir
  int _step = 1;
  bool _isSubmitting = false;

  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _hidePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  void _showMessage(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : const Color(0xFF1A3A5C),
      ),
    );
  }

  Future<void> _sendCode() async {
    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (username.isEmpty || email.isEmpty) {
      _showMessage('Kullanıcı adı ve e-posta girin');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'email': email}),
      );
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() => _step = 2);
        _showMessage('Doğrulama kodu e-postanıza gönderildi', isError: false);
      } else {
        _showMessage(body['error'] ?? 'Kod gönderilemedi');
      }
    } catch (e) {
      _showMessage('Sunucuya bağlanılamadı');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resetPassword() async {
    final username = _usernameCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;

    if (code.isEmpty || newPassword.isEmpty) {
      _showMessage('Kod ve yeni şifre girin');
      return;
    }
    if (newPassword != confirm) {
      _showMessage('Şifreler eşleşmiyor');
      return;
    }
    if (newPassword.length < 6) {
      _showMessage('Şifre en az 6 karakter olmalı');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'code': code,
          'newPassword': newPassword,
        }),
      );
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (!mounted) return;
        _showMessage('Şifreniz güncellendi, giriş yapabilirsiniz', isError: false);
        context.go('/login');
      } else {
        _showMessage(body['error'] ?? 'Şifre güncellenemedi');
      }
    } catch (e) {
      _showMessage('Sunucuya bağlanılamadı');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bg1, _bg2],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: _card.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 40,
                      offset: Offset(0, 16),
                      color: Color(0x55000000),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => context.go('/login'),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _step == 1 ? 'Şifremi Unuttum' : 'Kodu Doğrula',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withOpacity(0.92),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 48),
                      child: Text(
                        _step == 1
                            ? 'Kullanıcı adınızı ve e-posta adresinizi girin, size bir doğrulama kodu gönderelim.'
                            : 'E-postanıza gelen 6 haneli kodu ve yeni şifrenizi girin.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withOpacity(0.55),
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (_step == 1) ..._buildStepOne() else ..._buildStepTwo(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStepOne() {
    return [
      _field(
        controller: _usernameCtrl,
        label: 'Kullanıcı adı',
        icon: Icons.person_outline_rounded,
      ),
      const SizedBox(height: 12),
      _field(
        controller: _emailCtrl,
        label: 'E-posta adresi',
        icon: Icons.email_outlined,
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 18),
      _submitButton(
        label: 'Kod Gönder',
        onPressed: _isSubmitting ? null : _sendCode,
      ),
    ];
  }

  List<Widget> _buildStepTwo() {
    return [
      _field(
        controller: _codeCtrl,
        label: 'Doğrulama Kodu',
        icon: Icons.pin_outlined,
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 12),
      _field(
        controller: _newPasswordCtrl,
        label: 'Yeni Şifre',
        icon: Icons.lock_outline_rounded,
        obscureText: _hidePassword,
        trailing: IconButton(
          onPressed: () => setState(() => _hidePassword = !_hidePassword),
          icon: Icon(
            _hidePassword
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
          ),
        ),
      ),
      const SizedBox(height: 12),
      _field(
        controller: _confirmPasswordCtrl,
        label: 'Yeni Şifre (Tekrar)',
        icon: Icons.lock_outline_rounded,
        obscureText: _hidePassword,
      ),
      const SizedBox(height: 18),
      _submitButton(
        label: 'Şifreyi Güncelle',
        onPressed: _isSubmitting ? null : _resetPassword,
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: _isSubmitting ? null : () => setState(() => _step = 1),
        child: Text(
          'Kodu tekrar gönder',
          style: TextStyle(color: accent.withOpacity(0.85)),
        ),
      ),
    ];
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? trailing,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(color: Colors.white.withOpacity(0.88)),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: trailing,
        filled: true,
        fillColor: const Color(0xFF141B26).withOpacity(0.85),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: accent, width: 1.6),
        ),
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
      ),
    );
  }

  Widget _submitButton({required String label, required VoidCallback? onPressed}) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent.withOpacity(0.16),
          foregroundColor: accent,
          side: BorderSide(color: accent.withOpacity(0.55), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}