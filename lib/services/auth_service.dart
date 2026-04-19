import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static const String baseUrl = "https://route-backend-wkiy.onrender.com";
  static Future<String?> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );

      final body = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return null; // hata yok
      } else {
        return body["error"] ?? "Bilinmeyen hata";
      }
    } catch (e) {
      return "Sunucuya bağlanılamadı";
    }
  }
}
