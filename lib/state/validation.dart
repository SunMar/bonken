import 'package:flutter/material.dart' show ThemeMode;

import '../models/game_constraints.dart';
import '../models/game_invariants.dart';
import '../models/game_session.dart';
import '../models/hearts_variant.dart';
import '../models/starter_variant.dart';
import 'settings_migrations.dart';

/// Thrown by the import validation layer when data fails a structural or
/// business-rule check. The [message] is human-readable but not user-facing
/// (the UI shows a generic "corrupt backup" string; [message] aids debugging).
class ValidationError implements Exception {
  const ValidationError(this.message);
  final String message;

  @override
  String toString() => 'ValidationError: $message';
}

// ---------------------------------------------------------------------------
// Manifest
// ---------------------------------------------------------------------------

/// Validates a decoded manifest map (§5.3). Throws [ValidationError] on any
/// violation. Does not check `version` against [currentBackupVersion] — that
/// comparison is the caller's responsibility; this function only verifies
/// structural correctness.
void validateManifest(Map<String, dynamic> json) {
  // version: integer >= 1
  final version = json['version'];
  if (version is! int || version < 1) {
    throw const ValidationError('Manifest: "version" must be an integer >= 1.');
  }

  // appVersion: non-empty string, optional (absent for dev builds)
  final appVersion = json['appVersion'];
  if (appVersion != null && (appVersion is! String || appVersion.isEmpty)) {
    throw const ValidationError(
      'Manifest: "appVersion" must be a non-empty string if present.',
    );
  }

  // buildNumber: non-empty string, optional
  final buildNumber = json['buildNumber'];
  if (buildNumber != null && (buildNumber is! String || buildNumber.isEmpty)) {
    throw const ValidationError(
      'Manifest: "buildNumber" must be a non-empty string if present.',
    );
  }

  // exportedAt: valid ISO-8601
  final exportedAt = json['exportedAt'];
  if (exportedAt is! String || !_isValidIso8601(exportedAt)) {
    throw const ValidationError(
      'Manifest: "exportedAt" must be a valid ISO-8601 timestamp.',
    );
  }

  // utcOffset: "+HH:MM" or "-HH:MM"
  final utcOffset = json['utcOffset'];
  if (utcOffset is! String ||
      !RegExp(r'^[+-]\d{2}:\d{2}$').hasMatch(utcOffset)) {
    throw const ValidationError(
      'Manifest: "utcOffset" must be a UTC offset string like "+02:00".',
    );
  }

  // contains: non-empty array of known keys
  final contains = json['contains'];
  if (contains is! List ||
      contains.isEmpty ||
      !contains.every((c) => c == 'games' || c == 'settings')) {
    throw const ValidationError(
      'Manifest: "contains" must be a non-empty array of '
      '"games" and/or "settings".',
    );
  }

  // hashes: each key in contains has a valid sha256 hash entry
  final hashes = json['hashes'];
  if (hashes is! Map<String, dynamic>) {
    throw const ValidationError('Manifest: "hashes" must be an object.');
  }
  for (final key in contains.cast<String>()) {
    final entry = hashes[key];
    if (entry is! Map<String, dynamic>) {
      throw ValidationError('Manifest: missing hash entry for "$key".');
    }
    final algo = entry['algo'];
    if (algo != 'sha256') {
      throw ValidationError(
        'Manifest: hash for "$key" uses unsupported algorithm '
        '"$algo" (expected "sha256").',
      );
    }
    final hash = entry['hash'];
    if (hash is! String || hash.length != 64 || !_isValidHex(hash)) {
      throw ValidationError(
        'Manifest: hash for "$key" must be a 64-char lowercase hex digest.',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Games
// ---------------------------------------------------------------------------

/// Migrates (if needed) and validates a decoded games envelope, returning the
/// parsed [GameSession] list. Throws [ValidationError] on any failure.
///
/// Calls [GameSession.fromJson] (the real load path) for structural validation,
/// then [assertGameInvariants] for the business rules the engine checks with
/// debug-only asserts. Duplicate game IDs are also rejected here.
List<GameSession> validateMigratedGames(List<dynamic> rawGames) {
  final seenIds = <String>{};
  return [
    for (final raw in rawGames)
      _parseAndCheck(raw as Map<String, dynamic>, seenIds),
  ];
}

/// Validates a single [GameSession] — player names, game name, and engine
/// invariants. Throws [ValidationError] on any violation.
///
/// Called by both [validateMigratedGames] (import path) and the write path in
/// [GameHistoryNotifier.saveGame] so the same rules gate both paths.
void validateGameSession(GameSession game) {
  _checkGameId(game);
  _checkPlayerIds(game);
  _checkPlayerNames(game);
  _checkGameName(game);
  try {
    assertGameInvariants(game);
  } on GameInvariantError catch (e) {
    throw ValidationError(e.message);
  }
}

GameSession _parseAndCheck(Map<String, dynamic> raw, Set<String> seenIds) {
  final game = GameSession.fromJson(raw);
  if (!seenIds.add(game.id)) {
    throw ValidationError('Duplicate game id "${game.id}".');
  }
  validateGameSession(game);
  return game;
}

// UUID v4: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx (y in [89ab])
final _uuidV4Re = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void _checkGameId(GameSession game) {
  if (!_uuidV4Re.hasMatch(game.id)) {
    throw ValidationError('Game "${game.id}": id is not a valid UUID v4.');
  }
}

void _checkPlayerIds(GameSession game) {
  final seenIds = <String>{};
  for (final p in game.players) {
    if (!_uuidV4Re.hasMatch(p.id)) {
      throw ValidationError(
        'Game ${game.id}: player id "${p.id}" is not a valid UUID v4.',
      );
    }
    if (!seenIds.add(p.id)) {
      throw ValidationError('Game ${game.id}: duplicate player id "${p.id}".');
    }
  }
}

void _checkPlayerNames(GameSession game) {
  for (final p in game.players) {
    final trimmed = normalizePlayerName(p.name);
    if (trimmed.isEmpty) {
      throw ValidationError(
        'Game ${game.id}: player name must not be empty or whitespace-only.',
      );
    }
    if (!playerNameLengthValid(p.name)) {
      throw ValidationError(
        'Game ${game.id}: player name "${p.name}" exceeds '
        '$kPlayerNameMaxLength characters.',
      );
    }
  }
  final names = [for (final p in game.players) p.name];
  final dups = duplicatePlayerNameIndices(names);
  if (dups.isNotEmpty) {
    throw ValidationError(
      'Game ${game.id}: duplicate player name '
      '"${normalizePlayerName(names[dups.first])}" (case-insensitive).',
    );
  }
}

void _checkGameName(GameSession game) {
  final name = game.gameName;
  if (name == null) return;
  if (name.isEmpty) {
    throw ValidationError(
      'Game ${game.id}: gameName must be null, not an empty string.',
    );
  }
  if (name.trim().isEmpty) {
    throw ValidationError(
      'Game ${game.id}: gameName must not be whitespace-only.',
    );
  }
  if (!gameNameLengthValid(name)) {
    throw ValidationError(
      'Game ${game.id}: gameName "$name" exceeds $kGameNameMaxLength characters.',
    );
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

/// Validates a settings envelope **after migration** (§5.5). The version field
/// must equal [currentSettingsVersion]; all required fields must be present
/// with valid enum values. Throws [ValidationError] on any violation.
void validateMigratedSettings(Map<String, dynamic> json) {
  final version = json['version'];
  if (version != currentSettingsVersion) {
    throw ValidationError(
      'Settings: expected version $currentSettingsVersion after migration, '
      'got $version.',
    );
  }

  final themeMode = json['themeMode'];
  if (_enumByNameOrNull(ThemeMode.values, themeMode as String?) == null) {
    throw ValidationError(
      'Settings: invalid themeMode "$themeMode". '
      'Expected one of: ${ThemeMode.values.map((e) => e.name).join(', ')}.',
    );
  }

  final ruleVariants = json['ruleVariants'];
  if (ruleVariants is! Map<String, dynamic>) {
    throw const ValidationError('Settings: "ruleVariants" must be an object.');
  }

  final starterVariant = ruleVariants['starterVariant'];
  if (_enumByNameOrNull(StarterVariant.values, starterVariant as String?) ==
      null) {
    throw ValidationError(
      'Settings: invalid starterVariant "$starterVariant". '
      'Expected one of: '
      '${StarterVariant.values.map((e) => e.name).join(', ')}.',
    );
  }

  final heartsVariant = ruleVariants['heartsVariant'];
  if (_enumByNameOrNull(HeartsVariant.values, heartsVariant as String?) ==
      null) {
    throw ValidationError(
      'Settings: invalid heartsVariant "$heartsVariant". '
      'Expected one of: '
      '${HeartsVariant.values.map((e) => e.name).join(', ')}.',
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

T? _enumByNameOrNull<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

bool _isValidIso8601(String s) {
  try {
    DateTime.parse(s);
    return true;
  } on FormatException {
    return false;
  }
}

bool _isValidHex(String s) => RegExp(r'^[a-f0-9]+$').hasMatch(s);
