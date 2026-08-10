import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = "https://route-backend-1.onrender.com";

  // Backend, token süresi dolmuş/iptal edilmiş durumları gövdede
  // code: "SESSION_EXPIRED" ile işaretler (bkz. server.js authenticateToken).
  // 403 ayrıca sahiplik/rol reddi için de kullanıldığından (canAccessUser,
  // requireRole) sadece statusCode'a bakmak yanlış pozitiflere yol açardı —
  // artık sadece gerçek SESSION_EXPIRED işaretinde tetikleniyor.
  static final ValueNotifier<bool> sessionExpired = ValueNotifier(false);
  static void flagIfSessionError(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded['code'] == 'SESSION_EXPIRED') {
        sessionExpired.value = true;
      }
    } catch (_) {}
  }
  static Future<String?> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "username": username,
          "password": password,
        }),
      );

      final body = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Sürücü hesapları web/masaüstü paneline giremez — bu panel sadece
        // admin rolü içindir (backend'de dispatcher rolü kaldırıldı, bkz.
        // server.js STAFF_ROLES — Nehir'in isteği). "dispatcher" burada da
        // kabul edilseydi, böyle bir hesap panele girebilir ama her gerçek
        // işlemde backend'den 403 alırdı.
        final role = body['role'] as String?;
        if (role != 'admin') {
          return 'Bu hesap bu panele giriş yapamaz. Sürücü hesapları yalnızca mobil uygulamayı kullanabilir.';
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', body['user_id'] as int);
        await prefs.setString(
            'username', body['username']?.toString() ?? username);
        final authToken = body['token'];
        if (authToken != null) {
          await prefs.setString('auth_token', authToken.toString());
        }
        return null; // hata yok
      } else {
        return body["error"] ??
            body["message"] ??
            "Kullanıcı adı veya şifre hatalı";
      }
    } catch (e) {
      return "Sunucuya bağlanılamadı";
    }
  }

  /// Oturumu kapatır. "Çıkış Yap" login'e yönlendirmekle yetiniyordu,
  /// auth_token hiç silinmiyordu — paylaşımlı (hastane) bilgisayarlarda
  /// önceki oturumun token'ı cihazda kalmaya devam ediyordu.
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('username');
    await prefs.remove('auth_token');
  }

  /// Backend isteklerinde kullanılacak, token içeren standart header'lar.
  static Future<Map<String, String>> authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}