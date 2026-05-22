import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A player in a Bonken game session.
///
/// Each player is assigned a stable [id] (UUID v4) at creation time that
/// never changes even if the player is renamed or reordered. The application
/// keys all per-round data (scores, chooser references) to [id] rather than
/// to seat indices, so reordering players does not corrupt historical data.
class Player {
  Player({required this.name}) : id = _uuid.v4();
  Player._({required this.id, required this.name});

  final String id;
  final String name;

  Player copyWith({String? name}) => Player._(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Player.fromJson(Map<String, dynamic> json) =>
      Player._(id: json['id'] as String, name: json['name'] as String);

  @override
  bool operator ==(Object other) =>
      other is Player && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'Player(id: $id, name: $name)';
}

/// Returns the seat index of the player with [id] within [players].
/// Returns 0 when [id] is not found — guards against corrupt/missing IDs.
int seatIndexOf(List<Player> players, String id) {
  final i = players.indexWhere((p) => p.id == id);
  return i < 0 ? 0 : i;
}

/// Returns [players] rotated so the player with [firstDealerId] is first,
/// with subsequent players in their original seat order. The returned list
/// is unmodifiable. Falls back to starting at index 0 when [firstDealerId]
/// is not found.
List<Player> rotatedFromDealer(List<Player> players, String firstDealerId) {
  final start = seatIndexOf(players, firstDealerId);
  return List.unmodifiable([
    for (int i = 0; i < players.length; i++)
      players[(start + i) % players.length],
  ]);
}
