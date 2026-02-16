class AddressStore {
  // Dropdown'da ilk eleman sabit başlık
  static final List<String> items = ['Adresler'];

  static void add(String address) {
    final a = address.trim();
    if (a.isEmpty) return;
    if (!items.contains(a)) items.add(a);
  }

  static void remove(String address) {
    final a = address.trim();
    if (a.isEmpty) return;
    if (a == 'Adresler') return;
    items.remove(a);
  }
}
