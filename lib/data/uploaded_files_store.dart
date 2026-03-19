class UploadedFile {
  final String fileName;
  final int addressCount;
  final DateTime uploadedAt;

  const UploadedFile({
    required this.fileName,
    required this.addressCount,
    required this.uploadedAt,
  });
}

class UploadedFilesStore {
  static final List<UploadedFile> _files = [];

  static List<UploadedFile> get files => List.unmodifiable(_files);

  static void add(String fileName, int addressCount) {
    _files.insert(
      0,
      UploadedFile(
        fileName: fileName,
        addressCount: addressCount,
        uploadedAt: DateTime.now(),
      ),
    );
  }

  // Kayıtlı veriyi yüklerken kullan (tarih korunur)
  static void addDirect(UploadedFile file) {
    _files.add(file);
  }

  static void clear() => _files.clear();
}