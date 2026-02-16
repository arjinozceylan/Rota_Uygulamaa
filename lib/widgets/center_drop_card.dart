import 'package:flutter/material.dart';
import '../models/calendar_event.dart';

class CenterDropCard extends StatelessWidget {
  final List<String> droppedAddresses;
  final void Function(String) onDropAddress;

  final String? title;
  final String? dropdownValue;
  final List<String>? dropdownItems;
  final ValueChanged<String>? onDropdownChanged;
  final String? helperText;

  final int maxCount;

  final Map<String, RepeatType>? repeatByAddress;

  // UI-only search
  final TextEditingController? searchController;
  final List<String> suggestions;
  final ValueChanged<String>? onSuggestionTap;
  final bool isSearching;

  const CenterDropCard({
    super.key,
    this.droppedAddresses = const [],
    required this.onDropAddress,
    this.title,
    this.dropdownValue,
    this.dropdownItems,
    this.onDropdownChanged,
    this.helperText,
    this.maxCount = 20,
    this.repeatByAddress,
    this.searchController,
    this.suggestions = const [],
    this.onSuggestionTap,
    this.isSearching = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onDropAddress(details.data),
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 240,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFE0F2E5) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? cs.primary : Colors.black12,
              width: isActive ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isActive ? 0.06 : 0.04),
                blurRadius: isActive ? 14 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Row(
                  children: [
                    Icon(Icons.view_day_outlined, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: cs.primary.withOpacity(0.18),
                          ),
                        ),
                        child: Text(
                          'Bırakabilirsin',
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // Search UI (mock)
              if (searchController != null) ...[
                _SearchBox(
                  controller: searchController!,
                  isSearching: isSearching,
                ),
                const SizedBox(height: 8),
                if (suggestions.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7F8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = suggestions[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.place_outlined,
                              color: cs.primary,
                            ),
                            title: Text(
                              s,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: TextButton(
                              onPressed: onSuggestionTap == null
                                  ? null
                                  : () => onSuggestionTap!(s),
                              child: const Text('Seç'),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
              ],

              if (dropdownValue != null &&
                  dropdownItems != null &&
                  onDropdownChanged != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6FAF7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: dropdownValue,
                      isExpanded: true,
                      items: dropdownItems!
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) onDropdownChanged!(v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              if (helperText != null) ...[
                Text(
                  helperText!,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 6),
              ],

              Row(
                children: [
                  Text(
                    'Seçili: ${droppedAddresses.length}/$maxCount',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Toplam süreye göre optimize edilecek',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.45),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Expanded(
                child: Center(
                  child: droppedAddresses.isEmpty
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.drag_indicator, color: cs.primary),
                            const SizedBox(width: 10),
                            const Text(
                              'Adresleri buraya sürükle',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: droppedAddresses.take(8).map((addr) {
                            final rep =
                                repeatByAddress?[addr] ?? RepeatType.none;
                            final repText = rep == RepeatType.none
                                ? null
                                : '🔁 ${rep.label}';

                            return Chip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      addr,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (repText != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      repText,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              avatar: Icon(
                                Icons.place,
                                size: 18,
                                color: cs.primary,
                              ),
                              backgroundColor: cs.primary.withOpacity(0.08),
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: cs.primary.withOpacity(0.18),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.isSearching});

  final TextEditingController controller;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Adres ara (UI demo)',
                border: InputBorder.none,
              ),
            ),
          ),
          if (isSearching)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.primary.withOpacity(0.18)),
            ),
            child: Text(
              'Google',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

//x