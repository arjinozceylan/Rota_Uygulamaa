import 'package:flutter/material.dart';

class TopActionBar extends StatelessWidget {
  const TopActionBar({
    super.key,
    required this.filterValue,
    required this.filterItems,
    required this.onFilterChanged,
    required this.primaryColor,
    required this.onUploadPressed,
    required this.onCalendarPressed,
    this.onInfoPressed, // ✅ NEW
    this.selectedCount = 0,
    this.maxCount = 20,
    this.syncStatus = '', // ✅ SADECE BU YAZI KALDIRILDI
  });

  final String filterValue;
  final List<String> filterItems;
  final ValueChanged<String> onFilterChanged;

  final Color primaryColor;
  final VoidCallback onUploadPressed;
  final VoidCallback onCalendarPressed;

  final VoidCallback? onInfoPressed; // ✅ NEW

  final int selectedCount;
  final int maxCount;
  final String syncStatus;

  @override
  Widget build(BuildContext context) {
    final c = primaryColor;

    final warn = selectedCount >= (maxCount - 3) && selectedCount < maxCount;
    final full = selectedCount >= maxCount;
    final badgeColor = full
        ? Colors.red
        : warn
            ? Colors.orange
            : c;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 6),
            color: Colors.black12,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7F8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: filterItems.contains(filterValue)
                      ? filterValue
                      : filterItems.first,
                  isExpanded: true,
                  icon: const Icon(Icons.expand_more),
                  items: filterItems
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e,
                          child: Text(e, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onFilterChanged(v);
                  },
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          _Pill(
            icon: Icons.playlist_add_check,
            text: '$selectedCount/$maxCount',
            color: badgeColor,
          ),

          const SizedBox(width: 12),

          // ✅ NEW: Info button (opsiyonel)
          if (onInfoPressed != null) ...[
            _ActionIconButton(
              tooltip: 'Uygulama Bilgisi',
              icon: Icons.info_outline,
              color: c,
              onPressed: onInfoPressed!,
            ),
            const SizedBox(width: 8),
          ],

          _ActionIconButton(
            tooltip: 'Excel Yükle',
            icon: Icons.upload_file,
            color: c,
            onPressed: onUploadPressed,
          ),
          const SizedBox(width: 8),
          _ActionIconButton(
            tooltip: 'Takvim',
            icon: Icons.calendar_month,
            color: c,
            onPressed: onCalendarPressed,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatefulWidget {
  const _ActionIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  State<_ActionIconButton> createState() => _ActionIconButtonState();
}

class _ActionIconButtonState extends State<_ActionIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.withOpacity(_hover ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withOpacity(_hover ? 0.35 : 0.25)),
              boxShadow: _hover
                  ? const [
                      BoxShadow(
                        blurRadius: 10,
                        offset: Offset(0, 6),
                        color: Colors.black12,
                      ),
                    ]
                  : const [],
            ),
            child: Icon(widget.icon, color: c),
          ),
        ),
      ),
    );
  }
}