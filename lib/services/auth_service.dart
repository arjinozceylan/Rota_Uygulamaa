import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = "https://route-backend-jeu7.onrender.com";

  static Future<String?> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );

      final body = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', body['user_id'] as int);
        await prefs.setString('username', body['username']?.toString() ?? username);
        await prefs.setBool('is_guest', false);
        return null; // hata yok
      } else {
        return body["error"] ?? "Bilinmeyen hata";
      }
    } catch (e) {
      return "Sunucuya bağlanılamadı";
    }
  }

  static Future<void> continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest', true);
    await prefs.remove('user_id');
  }
}