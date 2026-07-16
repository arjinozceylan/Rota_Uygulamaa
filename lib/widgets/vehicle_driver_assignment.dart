import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/vehicle_workspace.dart';
import '../services/auth_service.dart';

/// Aktif araca hangi personelin atandığını gösteren ve değiştirmeye
/// yarayan küçük bir seçici. Backend'deki /users/drivers ve
/// /users/{id}/assign-vehicle endpoint'lerini kullanır. Ayrıca yönetici
/// bu ekrandan seçili personelin şifresini sıfırlayabilir.
class VehicleDriverAssignment extends StatefulWidget {
  const VehicleDriverAssignment({super.key, required this.vehicleId});

  final VehicleId vehicleId;

  @override
  State<VehicleDriverAssignment> createState() =>
      _VehicleDriverAssignmentState();
}

class _VehicleDriverAssignmentState extends State<VehicleDriverAssignment> {
  bool _loading = true;
  List<Map<String, dynamic>> _drivers = [];
  int? _assignedUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VehicleDriverAssignment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicleId != widget.vehicleId) {
      _load();
    }
  }

  int get _vehicleNumber => widget.vehicleId.index;

  String? get _assignedUsername {
    if (_assignedUserId == null) return null;
    final match = _drivers.firstWhere(
      (d) => d['id'] == _assignedUserId,
      orElse: () => {},
    );
    return match.isEmpty ? null : match['username'] as String?;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/users/drivers'),
        headers: await AuthService.authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        final drivers = data.cast<Map<String, dynamic>>();
        final assigned = drivers.firstWhere(
          (d) => d['vehicle_id'] == _vehicleNumber,
          orElse: () => {},
        );
        if (!mounted) return;
        setState(() {
          _drivers = drivers;
          _assignedUserId = assigned.isEmpty ? null : assigned['id'] as int;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _loading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _assign(int? userId) async {
    setState(() => _loading = true);
    try {
      for (final d in _drivers) {
        if (d['vehicle_id'] == _vehicleNumber && d['id'] != userId) {
          await http.post(
            Uri.parse('${AuthService.baseUrl}/users/${d['id']}/assign-vehicle'),
            headers: await AuthService.authHeaders(),
            body: jsonEncode({'vehicle_id': null}),
          );
        }
      }
      if (userId != null) {
        await http.post(
          Uri.parse('${AuthService.baseUrl}/users/$userId/assign-vehicle'),
          headers: await AuthService.authHeaders(),
          body: jsonEncode({'vehicle_id': _vehicleNumber}),
        );
      }
      await _load();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_assignedUserId == null) return;
    final username = _assignedUsername ?? 'personel';

    final newPassword = await showDialog<String>(
      context: context,
      builder: (ctx) => _ResetPasswordDialog(username: username),
    );

    if (newPassword == null || newPassword.isEmpty) return;
    if (!mounted) return;

    try {
      final response = await http.post(
        Uri.parse(
          '${AuthService.baseUrl}/users/$_assignedUserId/admin-reset-password',
        ),
        headers: await AuthService.authHeaders(),
        body: jsonEncode({'newPassword': newPassword}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$username kullanıcısının şifresi güncellendi.')),
        );
      } else {
        final body = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body['error'] ?? 'Şifre sıfırlanamadı.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunucuya bağlanılamadı.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD8E1EC)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: _assignedUserId,
              isDense: true,
              icon: const Icon(Icons.arrow_drop_down_rounded, size: 18),
              hint: const Text(
                'Personel ata',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF6B7A8D)),
              ),
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF1A2236),
                fontWeight: FontWeight.w700,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('— Atanmadı —'),
                ),
                ..._drivers.map(
                  (d) => DropdownMenuItem<int?>(
                    value: d['id'] as int,
                    child: Text(d['username'].toString()),
                  ),
                ),
              ],
              onChanged: (value) => _assign(value),
            ),
          ),
        ),
        if (_assignedUserId != null) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: 'Şifreyi Sıfırla',
            child: InkWell(
              onTap: _resetPassword,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFD9A0)),
                ),
                child: const Icon(
                  Icons.lock_reset_rounded,
                  size: 16,
                  color: Color(0xFFB8460E),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.username});

  final String username;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _controller = TextEditingController();
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.length < 6) {
      setState(() => _error = 'Şifre en az 6 karakter olmalı');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.username} — Şifreyi Sıfırla'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bu personel için yeni bir şifre belirleyin. '
              'Yeni şifreyi kendisine iletmeniz gerekir.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              obscureText: _hidePassword,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Yeni şifre',
                errorText: _error,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Şifreyi Değiştir'),
        ),
      ],
    );
  }
}
