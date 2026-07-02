import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_constraints.dart';
import '../models/game_session.dart';
import '../services/screen_brightness_service.dart';
import '../state/calculator_provider.dart';
import '../state/game_qr_codec.dart';
import '../state/platform_io_providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/game_name_field.dart' show kGameNameSectionTitle;
import '../widgets/qr_code_view.dart';
import '../widgets/scoreboard_card.dart';

/// AppBar title of the QR share screen.
const String kShareGameTitle = 'Deel spel';

/// Soft prompt shown in place of the game name when the game is unnamed.
const String kGameNamePrompt = 'Geef dit spel een naam';

/// Full-screen "share this game as a QR code" surface, reached from the game
/// screen. Renders the current session as a QR code (regenerated whenever the
/// session changes), lets the user set/clear the game name inline, and shows a
/// read-only scorecard below.
///
/// Screen brightness is driven to maximum while this screen is visible so the
/// code scans easily, and restored on leave / background / while the rename
/// dialog is open. On iOS `UIScreen.brightness` is global, so the lifecycle
/// handling below is load-bearing, not just polish.
class QrDisplayScreen extends ConsumerStatefulWidget {
  const QrDisplayScreen({super.key});

  @override
  ConsumerState<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends ConsumerState<QrDisplayScreen>
    with WidgetsBindingObserver {
  late final ScreenBrightness _brightness;

  /// While the rename dialog is open we want the screen dimmed; suppress the
  /// resume-time re-brighten so returning to the app doesn't fight the dialog.
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _brightness = ref.read(screenBrightnessProvider);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_brightness.setMax());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_brightness.reset());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_dialogOpen) unawaited(_brightness.setMax());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_brightness.reset());
    }
  }

  Future<void> _editName(GameSession session) async {
    _dialogOpen = true;
    // A text field is easier to read at normal brightness; dim while editing.
    await _brightness.reset();
    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _RenameGameDialog(initialName: session.gameName ?? ''),
    );
    _dialogOpen = false;
    if (!mounted) return;
    unawaited(_brightness.setMax());
    // A non-null result means "Opslaan" (cancel pops null). Normalizing an empty
    // field to null lets the user clear the name.
    if (result != null) {
      ref
          .read(calculatorProvider.notifier)
          .setGameName(normalizeGameName(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch so the QR + scorecard regenerate whenever the session changes
    // (e.g. an inline name edit).
    ref.watch(activeSessionProvider);
    final session = ref.read(calculatorProvider.notifier).buildSession();
    if (session == null) return const SizedBox.shrink();

    return AppScaffold(
      appBar: AppBar(title: const Text(kShareGameTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: QrCodeView(
                      data: GameQrCodec.encode(session),
                      semanticLabel: 'QR-code om dit spel te delen',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _GameNameButton(
                  gameName: session.gameName,
                  onPressed: () => unawaited(_editName(session)),
                ),
                const SizedBox(height: 8),
                ScoreboardCard(
                  roundsPlayed: session.rounds.length,
                  playerNames: session.displayedPlayerNames,
                  scores: session.displayedScores,
                  winners: session.isFinished
                      ? session.displayedWinnerIndices
                      : const <int>[],
                  scoredAt: session.scoredAt,
                  gameName: session.gameName,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline, optional game-name control: shows the name (or a soft prompt when
/// unnamed) and opens the rename dialog. Never forces naming — sharing works
/// with no name at all.
class _GameNameButton extends StatelessWidget {
  const _GameNameButton({required this.gameName, required this.onPressed});

  final String? gameName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final named = gameName != null;
    final label = named ? gameName! : kGameNamePrompt;
    final style = named
        ? theme.textTheme.titleMedium
        : theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          );
    return TextButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, style: style, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          const Icon(Symbols.edit, size: 18),
        ],
      ),
    );
  }
}

/// Small dialog to set/clear the game name. Owns its own [TextEditingController]
/// (disposed with the dialog's own State) — sharing one from the caller and
/// disposing it as soon as `showDialog` returns crashes on the route's exit
/// animation, which still reads the controller.
///
/// Pops `null` on cancel and the entered text on save; the caller normalizes an
/// empty string to a cleared name.
class _RenameGameDialog extends StatefulWidget {
  const _RenameGameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameGameDialog> createState() => _RenameGameDialogState();
}

class _RenameGameDialogState extends State<_RenameGameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(kGameNameSectionTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: kGameNameMaxLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(counterText: ''),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Opslaan'),
        ),
      ],
    );
  }
}
