/// Entry of the PLC tag table. Only BOOL tags exist; the type follows from the address.
final class Tag {
  const Tag({required this.name, required this.address, this.comment = ''});

  final String name;

  /// Absolute address as entered by the user, e.g. `%I0.0`. Validated by the compiler.
  final String address;
  final String comment;
}
