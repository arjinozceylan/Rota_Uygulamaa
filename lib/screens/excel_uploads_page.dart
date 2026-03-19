import 'package:flutter/material.dart';
import '../data/uploaded_files_store.dart';

class ExcelUploadsPage extends StatefulWidget {
  const ExcelUploadsPage({super.key});

  @override
  State<ExcelUploadsPage> createState() => _ExcelUploadsPageState();
}

class _ExcelUploadsPageState extends State<ExcelUploadsPage> {
  static const _bg = Color(0xFF0B1018);
  static const _surface = Color(0xFF141B26);
  static const _stroke = Color(0xFF1E2A3A);
  static const _accent = Color(0xFF53D6FF);
  static const _textLight = Color(0xFF6B7A8D);
  static const _textDark = Color(0xFFE8EDF3);

  @override
  Widget build(BuildContext context) {
    final files = UploadedFilesStore.files;

    return Scaffold(
      backgroundColor: _bg,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık
            Row(
              children: [
                const Icon(Icons.folder_copy_rounded, color: _accent, size: 22),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accent.withOpacity(0.25)),
                  ),
                  child: Text(
                    '${files.length} dosya',
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

            // İçerik
            Expanded(
              child: files.isEmpty
                  ? _buildEmpty()
                  : ListView.separated(
                      itemCount: files.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final f = files[index];
                        return _FileCard(file: f);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.upload_file_rounded, size: 56, color: _textLight.withOpacity(0.4)),
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
            style: TextStyle(color: Color(0xFF3D4D60), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final UploadedFile file;
  const _FileCard({required this.file});

  static const _surface = Color(0xFF141B26);
  static const _stroke = Color(0xFF1E2A3A);
  static const _accent = Color(0xFF53D6FF);
  static const _textDark = Color(0xFFE8EDF3);
  static const _textLight = Color(0xFF6B7A8D);

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$d.$mo.$y  $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _stroke),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _accent.withOpacity(0.18)),
            ),
            child: const Icon(Icons.table_chart_rounded, color: _accent, size: 22),
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
                  style: const TextStyle(color: _textLight, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A2A).withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2ECC71).withOpacity(0.25)),
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