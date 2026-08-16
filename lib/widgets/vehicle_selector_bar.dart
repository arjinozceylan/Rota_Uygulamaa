import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../models/vehicle_workspace.dart';
import '../services/auth_service.dart';
import '../services/fleet_state.dart';

Future<void> _fetchAndSyncDrivers(BuildContext context) async {
  final response = await http.get(
    Uri.parse('${AuthService.baseUrl}/users/drivers'),
    headers: await AuthService.authHeaders(),
  );
  if (response.statusCode != 200) {
    AuthService.flagIfSessionError(response.body);
    throw Exception('Sürücü listesi alınamadı (${response.statusCode})');
  }
  final data = jsonDecode(response.body) as List;
  final drivers = data
      .cast<Map<String, dynamic>>()
      .map((d) => Driver(id: d['id'] as int, username: d['username'].toString()))
      .toList();
  if (!context.mounted) return;
  context.read<FleetState>().syncDrivers(drivers);
}

Future<void> _createDriverAccount(String username, String password) async {
  final response = await http.post(
    Uri.parse('${AuthService.baseUrl}/register'),
    headers: await AuthService.authHeaders(),
    body: jsonEncode({
      'username': username,
      'password': password,
      'role': 'driver',
    }),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    AuthService.flagIfSessionError(response.body);
    throw Exception('"$username" oluşturulamadı (${response.statusCode})');
  }
}

Future<void> _deleteDriverRoutes(int driverId) async {
  final response = await http.delete(
    Uri.parse('${AuthService.baseUrl}/routes/$driverId'),
    headers: await AuthService.authHeaders(),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    AuthService.flagIfSessionError(response.body);
    throw Exception('Rotalar silinemedi (${response.statusCode})');
  }
}

Future<void> _confirmAndDeleteDriverRoutes(
  BuildContext context,
  Driver driver,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Rotaları Sil'),
      content: Text(
        '"${driver.username}" sürücüsüne atanmış TÜM rotalar silinecek. '
        'Sürücü hesabı ve şifresi silinmeyecek, sadece geçmiş/aktif '
        'rotaları temizlenecek. Bu işlem geri alınamaz.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Rotaları Sil'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await _deleteDriverRoutes(driver.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${driver.username}" için rotalar silindi.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

Future<void> _deleteDriverAccount(int driverId) async {
  final response = await http.delete(
    Uri.parse('${AuthService.baseUrl}/users/$driverId'),
    headers: await AuthService.authHeaders(),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    AuthService.flagIfSessionError(response.body);
    String message = 'Sürücü silinemedi (${response.statusCode})';
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['error'] is String) message = decoded['error'] as String;
    } catch (_) {}
    throw Exception(message);
  }
}

Future<void> _confirmAndDeleteDriverAccount(
  BuildContext context,
  Driver driver,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sürücüyü Sil'),
      content: Text(
        '"${driver.username}" hesabı, tüm rotaları, çalışma alanı ve konum '
        'geçmişiyle birlikte kalıcı olarak silinecek. Sürücü artık mobil '
        'uygulamaya giriş yapamayacak. Bu işlem geri alınamaz.\n\n'
        'Not: "${driver.username}" sürücü1..sürücü10 hesaplarından biriyse, '
        'sunucu yeniden başlatıldığında (ör. bir sonraki deploy) otomatik '
        'olarak varsayılan şifreyle yeniden oluşturulabilir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Sürücüyü Sil'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await _deleteDriverAccount(driver.id);
    if (!context.mounted) return;
    await _fetchAndSyncDrivers(context);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${driver.username}" silindi.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

Future<void> _showAddDriverMenu(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (menuContext) => AlertDialog(
      title: const Text('Sürücü Ekle'),
      content: const Text(
        'Tek bir sürücü mü eklemek istiyorsun, yoksa route/adres verisi '
        'olmayan sürücü1..sürücü10 hesaplarını (şifre palyatif1..'
        'palyatif10) toplu mu oluşturmak istiyorsun?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(menuContext).pop(),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(menuContext).pop();
            _showCreateSingleDriverDialog(context);
          },
          child: const Text('Tek Sürücü Ekle'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(menuContext).pop();
            _showBulkCreateDriversDialog(context);
          },
          child: const Text('10 Sürücü Oluştur'),
        ),
      ],
    ),
  );
}

Future<void> _showCreateSingleDriverDialog(BuildContext context) async {
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  var submitting = false;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Yeni Sürücü Ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Kullanıcı adı'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Şifre'),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed:
                submitting ? null : () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    final username = usernameCtrl.text.trim();
                    final password = passwordCtrl.text;
                    if (username.isEmpty || password.length < 6) {
                      setDialogState(() {
                        error = 'Kullanıcı adı gerekli, şifre en az '
                            '6 karakter olmalı.';
                      });
                      return;
                    }
                    setDialogState(() {
                      submitting = true;
                      error = null;
                    });
                    try {
                      await _createDriverAccount(username, password);
                      if (!dialogContext.mounted) return;
                      await _fetchAndSyncDrivers(dialogContext);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    } catch (e) {
                      setDialogState(() {
                        submitting = false;
                        error = '$e';
                      });
                    }
                  },
            child: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Oluştur'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showBulkCreateDriversDialog(BuildContext context) async {
  var submitting = false;
  String? status;
  String? error;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('10 Sürücü Oluştur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'sürücü1..sürücü10 hesapları palyatif1..palyatif10 '
              'şifreleriyle oluşturulacak. Zaten var olan kullanıcı '
              'adları atlanır.',
            ),
            if (status != null) ...[
              const SizedBox(height: 12),
              Text(status!, style: const TextStyle(fontSize: 12.5)),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed:
                submitting ? null : () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    setDialogState(() {
                      submitting = true;
                      error = null;
                    });
                    var created = 0;
                    for (var i = 1; i <= 10; i++) {
                      setDialogState(() => status = 'sürücü$i oluşturuluyor...');
                      try {
                        await _createDriverAccount('sürücü$i', 'palyatif$i');
                        created++;
                      } catch (_) {
                        // Muhtemelen zaten var — devam et, tüm seriyi durdurma.
                      }
                    }
                    if (!dialogContext.mounted) return;
                    try {
                      await _fetchAndSyncDrivers(dialogContext);
                    } catch (e) {
                      if (dialogContext.mounted) {
                        setDialogState(() => error = '$e');
                      }
                    }
                    if (dialogContext.mounted) {
                      if (error == null) {
                        Navigator.of(dialogContext).pop();
                      } else {
                        setDialogState(() {
                          submitting = false;
                          status = '$created/10 sürücü oluşturuldu.';
                        });
                      }
                    }
                  },
            child: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Oluştur'),
          ),
        ],
      ),
    ),
  );
}

/// Uygulamanın üst kısmında gösterilecek sürücü seçim barı.
///
/// Aynı widget Home / Calendar / Reports sayfalarında tekrar kullanılabilir.
/// Sürücü listesi backend'den dinamik gelir (sabit sayıda "araç" yoktur).
class VehicleSelectorBar extends StatelessWidget {
  const VehicleSelectorBar({super.key, this.compact = false});

  /// Dar alanlarda biraz daha sıkışık görünüm için kullanılabilir.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetState>();
    final drivers = fleet.drivers;
    final active = fleet.activeDriverId;

    if (drivers.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sürücüler yükleniyor...',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF5A6A85)),
            ),
            SizedBox(width: compact ? 6 : 8),
            _AddDriverChip(
              compact: compact,
              onTap: () => _showAddDriverMenu(context),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...drivers.map((driver) {
            final isActive = driver.id == active;
            return _DriverChip(
              label: driver.label,
              selected: isActive,
              onTap: () => context.read<FleetState>().selectDriver(driver.id),
              onDeleteRoutes: () =>
                  _confirmAndDeleteDriverRoutes(context, driver),
              onDeleteAccount: () =>
                  _confirmAndDeleteDriverAccount(context, driver),
              compact: compact,
            );
          }),
          _AddDriverChip(
            compact: compact,
            onTap: () => _showAddDriverMenu(context),
          ),
        ],
      ),
    );
  }
}

class _DriverChip extends StatelessWidget {
  const _DriverChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onDeleteRoutes,
    required this.onDeleteAccount,
    required this.compact,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDeleteRoutes;
  final VoidCallback onDeleteAccount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : const Color(0xFF5A6A85);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1A3A5C) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1A3A5C)
                  : const Color(0xFFD8E1EC),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_rounded,
                size: compact ? 15 : 16,
                color: selected ? Colors.white : const Color(0xFF5A6A85),
              ),
              SizedBox(width: compact ? 6 : 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF1A2236),
                  fontSize: compact ? 12 : 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: compact ? 2 : 4),
              Tooltip(
                message: 'Bu sürücünün rotalarını sil',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onDeleteRoutes,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.route_outlined,
                      size: compact ? 14 : 15,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: 'Sürücü hesabını sil',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onDeleteAccount,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.person_remove_outlined,
                      size: compact ? 14 : 15,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddDriverChip extends StatelessWidget {
  const _AddDriverChip({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFD8E1EC),
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_rounded,
                size: compact ? 15 : 16,
                color: const Color(0xFF5A6A85),
              ),
              SizedBox(width: compact ? 4 : 6),
              Text(
                'Sürücü Ekle',
                style: TextStyle(
                  color: const Color(0xFF5A6A85),
                  fontSize: compact ? 12 : 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
