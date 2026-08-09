import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/fleet_state.dart';
import 'data/app_storage.dart';
import 'data/uploaded_files_store.dart';
import 'services/reports_page.dart';
import 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Kayıtlı verileri yükle
  final stored = await AppStorage.instance.loadAll();

  // RouteStore'a rotaları yükle
  for (final r in stored.routes) {
    RouteStore.instance.add(r);
  }

  // UploadedFilesStore'a yüklenen dosyaları yükle
  for (final f in stored.uploads) {
    UploadedFilesStore.addDirect(f);
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => FleetState(fleet: stored.fleet),
      child: MyApp(initialAddressCards: stored.addressCards),
    ),
  );
}

class MyApp extends StatefulWidget {
  final List<String> initialAddressCards;
  const MyApp({super.key, required this.initialAddressCards});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const accent = Color(0xFF53D6FF);

  @override
  void initState() {
    super.initState();
    AuthService.sessionExpired.addListener(_handleSessionExpiry);
  }

  // Backend 401/403 döndüğünde (token süresi dolmuş/iptal edilmiş) oturumu
  // temizleyip kullanıcıyı login'e atar — aksi halde "giriş yapmış" görünen
  // ama hiçbir isteği çalışmayan bir panelde takılı kalınırdı.
  void _handleSessionExpiry() {
    if (!AuthService.sessionExpired.value) return;
    AuthService.sessionExpired.value = false;
    AuthService.logout().then((_) => router.go('/login'));
  }

  @override
  void dispose() {
    AuthService.sessionExpired.removeListener(_handleSessionExpiry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    );

    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: const Color(0xFF0B1018),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            foregroundColor: Colors.white,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF141B26).withValues(alpha: 0.85),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: accent, width: 1.6),
          ),
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.40)),
          prefixIconColor: Colors.white.withValues(alpha: 0.70),
          suffixIconColor: Colors.white.withValues(alpha: 0.70),
        ),
      ),
    );
  }
}
