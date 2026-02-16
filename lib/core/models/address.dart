class Address {
  final String code; // A001
  final String address;
  final String? note;

  const Address({
    required this.code,
    required this.address,
    this.note,
  });
}