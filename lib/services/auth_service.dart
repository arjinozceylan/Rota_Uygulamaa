import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = "https://route-backend-wkiy.onrender.com";

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
        final prefs = await SharedPreferences.getInstance();

        final userId = body["user_id"];
        if (userId != null) {
          await prefs.setInt(
            "user_id",
            userId is int ? userId : int.parse(userId.toString()),
          );
        }

        return null; // giriş başarılı
      } else {
        return body["error"] ??
            body["message"] ??
            "Kullanıcı adı veya şifre hatalı";
      }
    } catch (e) {
      return "Sunucuya bağlanılamadı";
    }
  }
}
