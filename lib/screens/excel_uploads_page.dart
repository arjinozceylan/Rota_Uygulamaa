import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

class ExcelUploadsPage extends StatefulWidget {
  const ExcelUploadsPage({super.key});

  @override
  State<ExcelUploadsPage> createState() => _ExcelUploadsPageState();
}

class _ExcelUploadsPageState extends State<ExcelUploadsPage> {
  static const _bg = Color(0xFF0B1018);
  static const _accent = Color(0xFF53D6FF);
  static const _textLight = Color(0xFF6B7A8D);
  static const _textDark = Color(0xFFE8EDF3);

  static const String _localBackendUrl = 'http://127.0.0.1:3100';

  List<_LocalImport> _files = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImports();
  }

  Future<void> _loadImports() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final response = await http.get(
        Uri.parse('$_localBackendUrl/imports'),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Local backend ${response.statusCode}: ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! List) {
        throw Exception('Geçersiz imports cevabı');
      }

      final files = <_LocalImport>[];

      for (final item in decoded) {
        if (item is! Map) continue;

        files.add(
          _LocalImport.fromJson(
            Map<String, dynamic>.from(item),
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _files = files;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Başlık ────────────────────────────────────────────────
            Row(
              children: [
                IconButton(
                  onPressed: () => context.go('/'),
                  tooltip: 'Rota Paneline Dön',
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: _accent,
                    size: 24,
                  ),
                ),

                const SizedBox(width: 4),

                const Icon(
                  Icons.folder_copy_rounded,
                  color: _accent,
                  size: 22,
                ),

                const SizedBox(width: 10),

                const Text(
                  'Excel Yüklenenler',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const Spacer(),

                // Yenile
                IconButton(
                  onPressed: _isLoading ? null : _loadImports,
                  tooltip: 'Yenile',
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: _accent,
                  ),
                ),

                const SizedBox(width: 8),

                // Dosya sayısı
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _accent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    '${_files.length} dosya',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── İçerik ────────────────────────────────────────────────
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: _accent,
        ),
      );
    }

    if (_error != null) {
      return _buildError();
    }

    if (_files.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      onRefresh: _loadImports,
      color: _accent,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _files.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          return _FileCard(
            file: _files[index],
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.upload_file_rounded,
            size: 56,
            color: _textLight.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'Henüz yüklenen dosya yok',
            style: TextStyle(
              color: _textLight,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sol menüden "Excel Yükle" ile CSV dosyası yükleyin',
            style: TextStyle(
              color: Color(0xFF3D4D60),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 48,
          ),
          const SizedBox(height: 14),
          const Text(
            'Yükleme geçmişi okunamadı',
            style: TextStyle(
              color: _textDark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rota360 lokal servisin çalıştığından emin olun.',
            style: TextStyle(
              color: _textLight,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadImports,
            icon: const Icon(
              Icons.refresh_rounded,
              size: 18,
            ),
            label: const Text('Tekrar Dene'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(
                color: _accent.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final _LocalImport file;

  const _FileCard({
    required this.file,
  });

  static const _surface = Color(0xFF141B26);
  static const _stroke = Color(0xFF1E2A3A);
  static const _accent = Color(0xFF53D6FF);
  static const _textDark = Color(0xFFE8EDF3);
  static const _textLight = Color(0xFF6B7A8D);

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();

    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');

    return '$d.$mo.$y  $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _stroke,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _accent.withValues(alpha: 0.18),
              ),
            ),
            child: const Icon(
              Icons.table_chart_rounded,
              color: _accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.fileName,
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(file.uploadedAt),
                  style: const TextStyle(
                    color: _textLight,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A2A).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF2ECC71).withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              '${file.addressCount} adres',
              style: const TextStyle(
                color: Color(0xFF2ECC71),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalImport {
  final int id;
  final String fileName;
  final DateTime uploadedAt;
  final int addressCount;

  const _LocalImport({
    required this.id,
    required this.fileName,
    required this.uploadedAt,
    required this.addressCount,
  });

  factory _LocalImport.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawDate = json['imported_at']?.toString() ?? '';

    final normalizedDate =
        rawDate.contains(' ') ? rawDate.replaceFirst(' ', 'T') : rawDate;

    return _LocalImport(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fileName: json['file_name']?.toString() ?? 'Bilinmeyen dosya',
      uploadedAt: DateTime.tryParse(normalizedDate) ?? DateTime.now(),
      addressCount: (json['row_count'] as num?)?.toInt() ?? 0,
    );
  }
}
