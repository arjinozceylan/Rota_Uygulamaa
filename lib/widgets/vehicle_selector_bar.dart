import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vehicle_workspace.dart';
import '../services/fleet_state.dart';

/// Uygulamanın üst kısmında gösterilecek araç seçim barı.
///
/// Aynı widget Home / Calendar / Reports sayfalarında tekrar kullanılabilir.
class VehicleSelectorBar extends StatelessWidget {
  const VehicleSelectorBar({super.key, this.compact = false});

  /// Dar alanlarda biraz daha sıkışık görünüm için kullanılabilir.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetState>();
    final active = fleet.activeVehicle;

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
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: VehicleId.values.map((id) {
          final isActive = id == active;
          return _VehicleChip(
            label: id.label,
            selected: isActive,
            onTap: () => context.read<FleetState>().selectVehicle(id),
            compact: compact,
          );
        }).toList(),
      ),
    );
  }
}

class _VehicleChip extends StatelessWidget {
  const _VehicleChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
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
                Icons.local_shipping_rounded,
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
            ],
          ),
        ),
      ),
    );
  }
}
