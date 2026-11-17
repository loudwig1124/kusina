/// The single local kitchen profile (`docs/06` §4). No accounts, no network.
///
/// Phase A fixtures carry no timestamps at all ("no calendar dates anywhere"),
/// so [createdAt] and [updatedAt] stay null until a storage layer assigns them.
library;

class Kitchen {
  const Kitchen({
    required this.uid,
    required this.name,
    this.createdAt,
    this.updatedAt,
  });

  /// Stable local identity (`kitchens.kitchen_uid`); never shown to the cook.
  final String uid;

  /// Display name, e.g. `Maria's Kitchen`.
  final String name;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  Kitchen copyWith({String? name, DateTime? createdAt, DateTime? updatedAt}) {
    return Kitchen(
      uid: uid,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
