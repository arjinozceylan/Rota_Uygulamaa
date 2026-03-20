import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nasıl Kullanılır?"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık
            const Text(
              "🚀 Hoş Geldin!",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Bu uygulama ile adresleri ekleyip en kısa ve en verimli rotayı oluşturabilirsin.",
              style: TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 20),

            _buildStep(
              icon: Icons.location_on,
              title: "Adres Ekle",
              desc:
                  "Ortadaki listeden adres seç veya haritadan yeni adres ekle.",
            ),

            _buildStep(
              icon: Icons.home,
              title: "Başlangıç Noktası",
              desc: "Ev konumunu seçerek rotanın başlangıcını belirle.",
            ),

            _buildStep(
              icon: Icons.route,
              title: "Rota Oluştur",
              desc: "Adresleri seçtikten sonra rota oluştur butonuna bas.",
            ),

            _buildStep(
              icon: Icons.directions_car,
              title: "Araç Seç",
              desc: "Üst kısımdan aktif aracı seçebilirsin.",
            ),

            _buildStep(
              icon: Icons.check_circle,
              title: "Sonuç",
              desc:
                  "Uygulama sana en kısa süre ve mesafeye göre optimize edilmiş rotayı gösterir.",
            ),

            _buildStep(
              icon: Icons.calendar_today,
              title: "Takvim (Planlama)",
              desc:
                  "Haftalık takvimde araçların günlük planlarını görüntüleyebilirsin. Sabah ve öğleden sonra olmak üzere görev dağılımını buradan yönetirsin.",
            ),

            _buildStep(
              icon: Icons.bar_chart,
              title: "Raporlar",
              desc:
                  "Toplam rota, mesafe, süre ve transfer gibi istatistikleri buradan takip edebilirsin. Performans analizi için kullanılır.",
            ),

            _buildStep(
              icon: Icons.map,
              title: "Oluşturulan Rotalar",
              desc:
                  "Daha önce oluşturduğun tüm rotaları burada görebilirsin. Süre, mesafe ve durak sayısı bilgileri listelenir.",
            ),
            const SizedBox(height: 20),

            const Divider(),

            const SizedBox(height: 10),

            const Text(
              "💡 İpucu",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              "Daha doğru sonuçlar için adresleri eksiksiz seçmeye dikkat et.",
              style: TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            child: Icon(icon, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
