import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/vehicle_workspace.dart';
import '../services/auth_service.dart';

/// Aktif araca hangi personelin atandığını gösteren ve değiştirmeye
/// yarayan küçük bir seçici. Backend'deki /users/drivers ve
/// /users/{id}/assign-vehicle endpoint'lerini kullanır.
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

  int get _vehicleNumber => widget.vehicleId.index + 1;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/users/drivers'),
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
      // Bu araca daha önce atanmış başka bir personel varsa atamasını kaldır
      // (bir araca aynı anda tek personel atanmış olsun).
      for (final d in _drivers) {
        if (d['vehicle_id'] == _vehicleNumber && d['id'] != userId) {
          await http.post(
            Uri.parse('${AuthService.baseUrl}/users/${d['id']}/assign-vehicle'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'vehicle_id': null}),
          );
        }
      }
      if (userId != null) {
        await http.post(
          Uri.parse('${AuthService.baseUrl}/users/$userId/assign-vehicle'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'vehicle_id': _vehicleNumber}),
        );
      }
      await _load();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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

    return Container(
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
    );
  }
}