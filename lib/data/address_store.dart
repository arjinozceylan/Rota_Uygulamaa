import '../core/models/address.dart';

class AddressStore {
  static final List<Address> _items = [];

  static List<Address> get items => List.unmodifiable(_items);

  // placeId VEYA address metni eşleşirse duplicate sayılır. Önceden ikisi
  // de doluysa sadece placeId karşılaştırılıyordu — aynı adres canlı
  // TomTom'dan mı ("tomtom:...") yoksa local geocode-cache'den mi
  // ("local-cache:...") geldiğine göre farklı placeId formatı aldığı için,
  // aynı Excel dosyası ikinci kez yüklendiğinde (ilk seferde cache'e
  // yazılmış adresler artık cache'den dönüyor) bu format farkı yüzünden
  // duplicate yakalanamıyor, her satır ikinci kez ekleniyordu.
  // Gerçekten yeni eklendiyse true, zaten var olduğu için atlandıysa false
  // döner — toplu içe aktarımda "N yeni eklendi / M zaten vardı" gibi bir
  // özet göstermek için kullanılır.
  static bool add(Address address) {
    final incomingText = address.address.trim();
    final exists = _items.any((a) {
      if (a.placeId != null &&
          address.placeId != null &&
          a.placeId == address.placeId) {
        return true;
      }
      return a.address.trim() == incomingText;
    });
    if (exists) return false;
    _items.add(address);
    return true;
  }

  // address metni ile sil (UI string kullandığı için gerekli)
  static void removeByAddress(String addressText) {
    final t = addressText.trim();
    _items.removeWhere((a) => a.address.trim() == t);
  }

  // placeId ile silmek istersen (OSM/Google sonuçları için)
  static void removeByPlaceId(String placeId) {
    _items.removeWhere((a) => a.placeId == placeId);
  }

  static void clear() => _items.clear();
}
