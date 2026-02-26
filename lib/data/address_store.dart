import '../core/models/address.dart';

class AddressStore {
  static final List<Address> _items = [];

  static List<Address> get items => List.unmodifiable(_items);

  // placeId varsa placeId ile, yoksa address metni ile duplicate engeller.
  static void add(Address address) {
    final exists = _items.any((a) {
      final aPid = a.placeId;
      final bPid = address.placeId;
      if (aPid != null && bPid != null) return aPid == bPid;
      return a.address.trim() == address.address.trim();
    });
    if (!exists) _items.add(address);
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
