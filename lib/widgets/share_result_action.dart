import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/io_failure.dart';
import '../state/calculator_provider.dart';
import '../state/platform_io_providers.dart';
import '../utils.dart';
import 'share_result_card.dart';
import 'timed_snackbar.dart';

enum _ShareDialogResult { shareImage, shareText, saveImage, copyText }

// Generic failure messages — shown only when something actually went wrong (a
// benign share/save cancellation surfaces nothing). The one user-fixable case,
// running out of storage, uses the shared [kOutOfSpaceMessage] instead.
const String _kShareFailedMessage = 'Het is mislukt om de uitslag te delen.';
const String _kSaveFailedMessage =
    'Het is mislukt om de afbeelding op te slaan.';
const String _kCopyFailedMessage = 'Het is mislukt om de tekst te kopiëren.';

/// The finished-game share action: an AppBar [IconButton] that owns the whole
/// result-sharing subsystem (off-screen capture, format dispatch, share / save
/// / copy I/O via the platform providers, and the format-picker dialog).
///
/// A plain tap shares the result as an image (web browsers without the Web
/// Share API fall back to a PNG download — handled by `share_plus`, not here); a
/// long-press (touch) or a screen-reader custom action opens the format picker
/// — a niche affordance, so it stays out of the way of the common case.
class ShareResultAction extends ConsumerStatefulWidget {
  const ShareResultAction({super.key});

  @override
  ConsumerState<ShareResultAction> createState() => _ShareResultActionState();
}

class _ShareResultActionState extends ConsumerState<ShareResultAction> {
  @override
  Widget build(BuildContext context) {
    return TooltipTheme(
      // `manual` disables only the *touch* trigger, so a long-press opens the
      // dialog without the tooltip racing it; mouse hover still shows it.
      data: TooltipTheme.of(
        context,
      ).copyWith(triggerMode: TooltipTriggerMode.manual),
      // Merge so the long-press and the custom actions fold into the
      // IconButton's single labeled button node — otherwise they would surface
      // as separate, unlabeled tappable nodes.
      child: MergeSemantics(
        child: Semantics(
          customSemanticsActions: {
            const CustomSemanticsAction(label: 'Deel als afbeelding'): () =>
                unawaited(_shareImage()),
            const CustomSemanticsAction(label: 'Deel als tekst'): () =>
                unawaited(_shareText()),
            const CustomSemanticsAction(label: 'Bewaar als afbeelding'): () =>
                unawaited(_saveImage()),
            const CustomSemanticsAction(label: 'Kopieer als tekst'): () =>
                unawaited(_copyText()),
          },
          child: IconButton(
            icon: const Icon(Symbols.share),
            tooltip: 'Deel uitslag',
            onPressed: () => unawaited(_shareImage()),
            onLongPress: () => unawaited(_showShareDialog()),
          ),
        ),
      ),
    );
  }

  void _snack(String message) =>
      showTimedSnackBar(ScaffoldMessenger.of(context), content: Text(message));

  /// Runs an I/O [body] that may fail, mapping the two user-relevant failure
  /// modes to a snackbar: out-of-space → the actionable [kOutOfSpaceMessage],
  /// anything else → [failMessage]. A benign cancellation (the share sheet or
  /// file picker dismissed) returns normally and shows nothing. Centralizes the
  /// catch every share/save/copy action shares.
  Future<void> _runIo(
    Future<void> Function() body, {
    required String failMessage,
  }) async {
    try {
      await body();
    } on OutOfSpaceException {
      if (mounted) _snack(kOutOfSpaceMessage);
    } on Object {
      if (mounted) _snack(failMessage);
    }
  }

  /// Popup dialog (consistent with the app's dialog/popup convention — no menus)
  /// letting the user pick format and action. Reached by long-press or the
  /// screen-reader custom action; a plain tap never opens it.
  Future<void> _showShareDialog() async {
    final result = await showDialog<_ShareDialogResult>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Zero horizontal padding so the option rows span the dialog width;
        // each ListTile keeps its own inset.
        semanticLabel: 'Uitslag delen',
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        actionsPadding: const EdgeInsetsDirectional.only(
          start: 16,
          end: 16,
          bottom: 8,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _shareOption(
              dialogContext,
              icon: Symbols.image,
              title: 'Afbeelding',
              actions: const [
                (
                  Symbols.share,
                  'Afbeelding delen',
                  _ShareDialogResult.shareImage,
                ),
                (
                  Symbols.download,
                  'Afbeelding opslaan',
                  _ShareDialogResult.saveImage,
                ),
              ],
            ),
            const Divider(height: 1),
            _shareOption(
              dialogContext,
              icon: Symbols.article,
              title: 'Tekst',
              actions: const [
                (Symbols.share, 'Tekst delen', _ShareDialogResult.shareText),
                (
                  Symbols.content_copy,
                  'Tekst kopiëren',
                  _ShareDialogResult.copyText,
                ),
              ],
            ),
            const Divider(height: 1),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuleren'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case _ShareDialogResult.shareImage:
        await _shareImage();
      case _ShareDialogResult.shareText:
        await _shareText();
      case _ShareDialogResult.saveImage:
        await _saveImage();
      case _ShareDialogResult.copyText:
        await _copyText();
    }
  }

  /// Shares the result as an image. On web browsers without the Web Share API,
  /// `share_plus` itself falls back to a PNG download — we don't switch formats.
  Future<void> _shareImage() => _runIo(() async {
    // Read the provider before the capture await: ref is unsafe once the
    // widget is unmounted (e.g. the user navigates away mid-capture).
    final share = ref.read(shareFileProvider);
    final text = _buildShareText();
    final Uint8List? bytes = await _captureShareCard();
    if (bytes == null) {
      // Capturing the card failed — an unexpected failure.
      if (mounted) _snack(_kShareFailedMessage);
      return;
    }
    // Returns normally whether the user shared or dismissed the sheet — both
    // are benign and need no feedback. A real failure throws to _runIo.
    await share(
      bytes: bytes,
      filename: 'bonken-uitslag.png',
      mimeType: 'image/png',
      subject: 'Bonken uitslag',
      text: text,
    );
  }, failMessage: _kShareFailedMessage);

  Future<void> _shareText() => _runIo(
    () => ref.read(shareTextProvider)(
      text: _buildShareText(),
      subject: 'Bonken uitslag',
    ),
    failMessage: _kShareFailedMessage,
  );

  Future<void> _copyText() => _runIo(() async {
    await Clipboard.setData(ClipboardData(text: _buildShareText()));
    if (!mounted) return;
    _snack('Tekst gekopieerd naar klembord');
  }, failMessage: _kCopyFailedMessage);

  Future<void> _saveImage() => _runIo(() async {
    final scoredAt = ref.read(activeSessionProvider).scoredAt;
    final save = ref.read(saveImageFileProvider);
    final bytes = await _captureShareCard();
    if (!mounted) return;
    if (bytes == null) {
      // Capturing the card failed — an unexpected failure, not a cancellation.
      _snack(_kSaveFailedMessage);
      return;
    }
    final saved = await save(
      bytes: bytes,
      filename: 'bonken-uitslag-${formatFileDate(scoredAt)}.png',
    );
    if (!mounted) return;
    // saved == false → the user cancelled the picker → no feedback.
    if (saved && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _snack('Afbeelding opgeslagen in Bestanden → Bonken');
    }
  }, failMessage: _kSaveFailedMessage);

  /// Renders [ShareResultCard] off-screen just long enough to capture it as a
  /// PNG, then removes it. Built on demand (only when an image is actually
  /// needed) via an [OverlayEntry] rather than permanently composited. Returns
  /// null if rendering/capture fails.
  Future<Uint8List?> _captureShareCard() async {
    // Decode the embedded icon up front: the overlay only waits one frame
    // before capture, too short for a cold asset, which would otherwise be
    // captured blank on the first share. Best-effort — a precache failure must
    // not abort the share (the capture would just render the icon blank, as it
    // did before this guard), so it's swallowed.
    try {
      await precacheImage(const AssetImage(shareIconAsset), context);
    } on Object catch (_) {
      // ignore: proceed to capture regardless.
    }
    if (!mounted) return null;
    final boundaryKey = GlobalKey();
    final overlay = Overlay.of(context);
    final mediaQuery = MediaQuery.of(context);
    final entry = OverlayEntry(
      // Off-screen (clipped to zero size) and excluded from the a11y tree, but a
      // real composited layer so toImage() captures it. textScaler is pinned so
      // the exported image is independent of the user's font-scale setting.
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        child: ExcludeSemantics(
          child: ClipRect(
            child: SizedBox.shrink(
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: MediaQuery(
                    data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
                    child: const ShareResultCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      // Let the entry lay out and paint before capturing.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      final object = boundaryKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return null;
      final image = await object.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } on Object catch (_) {
      return null;
    } finally {
      entry.remove();
    }
  }

  String _buildShareText() {
    final session = ref.read(activeSessionProvider);
    return buildShareText(
      gameName: session.gameName,
      scoredAt: session.scoredAt,
      entries: rankScores(session.history, session.displayedPlayers),
    );
  }
}

/// One format row in the share dialog: a leading icon + title, with a trailing
/// group of action buttons that each pop [dialogContext] with their result.
Widget _shareOption(
  BuildContext dialogContext, {
  required IconData icon,
  required String title,
  required List<(IconData, String, _ShareDialogResult)> actions,
}) {
  return ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (actionIcon, tooltip, result) in actions)
          IconButton(
            icon: Icon(actionIcon),
            tooltip: tooltip,
            onPressed: () => Navigator.of(dialogContext).pop(result),
          ),
      ],
    ),
  );
}
