#!/usr/bin/env -S fvm dart
// ignore_for_file: avoid_print

// Generate store screenshots for one or all device sizes.
//
// Usage:
//   ./tool/generate_screenshots.dart --android phone|tablet|all
//   ./tool/generate_screenshots.dart --ios iphone|ipad|all
//   (append --ci           to use PATH flutter/dart instead of fvm,
//                             and to skip AVD management on Android)
//   (append --wipe          to start with a clean user data partition, erasing
//                             any state from previous runs;
//                             silently ignored when combined with --ci)
//   (append --debug         show full emulator stdout; by default it is suppressed)
//
// Android local mode: manages the full AVD lifecycle (dependency checks,
//                     create + boot + test + kill).
// Android CI mode:    device already running via android-emulator-runner;
//                     script skips AVD management and runs flutter drive only.
// iOS (local + CI):   script always manages the simulator lifecycle via xcrun.
//                     --ci only switches fvm flutter → PATH flutter.
//
// Output: screenshots/<platform>/<device-type>/<name>.png  (8 PNGs per device size)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _screenshotMarker = 'SCREENSHOT:';
const _pollAttempts = 150;
const _pollInterval = Duration(seconds: 2);

class _ScriptException implements Exception {
  _ScriptException(this.message);
  final String message;
}

// ── Config (loaded from tool/generate_screenshots.env) ───────────────────────

late int _androidApiLevel;
late String _locale;
late String _androidPhoneProfile;
late String _androidTabletProfile;
late String _iosIphoneSim;
late String _iosIpadSim;

void _loadConfig() {
  final file = File('tool/generate_screenshots.env');
  if (!file.existsSync()) {
    stderr.writeln(
      'error: tool/generate_screenshots.env not found — run from repo root',
    );
    exit(1);
  }
  final map = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final eq = t.indexOf('=');
    if (eq < 0) continue;
    map[t.substring(0, eq)] = t.substring(eq + 1);
  }
  _androidApiLevel = int.parse(map['ANDROID_API_LEVEL']!);
  _locale = map['LOCALE']!;
  _androidPhoneProfile = map['ANDROID_PHONE_PROFILE']!;
  _androidTabletProfile = map['ANDROID_TABLET_PROFILE']!;
  _iosIphoneSim = map['IOS_IPHONE_SIM']!;
  _iosIpadSim = map['IOS_IPAD_SIM']!;
}

// ── Flutter command ───────────────────────────────────────────────────────────

late List<String> _flutter;

void _resolveFlutter(bool ci) {
  if (ci) {
    _flutter = ['flutter'];
    return;
  }
  if (Process.runSync('which', ['fvm']).exitCode == 0) {
    _flutter = ['fvm', 'flutter'];
    return;
  }
  stderr.writeln(
    'error: fvm not found — install fvm or pass --ci if running in CI',
  );
  exit(1);
}

// ── Process helpers ───────────────────────────────────────────────────────────
// _env is null (inherit parent env) except in Android local mode, where it
// gets the Android SDK tool directories prepended to PATH.

Map<String, String>? _env;

Future<ProcessResult> _capture(List<String> cmd, {bool binary = false}) =>
    Process.run(
      cmd.first,
      cmd.sublist(1),
      stdoutEncoding: binary ? null : utf8,
      stderrEncoding: utf8,
      environment: _env,
    );

Future<int> _run(List<String> cmd) async {
  final p = await Process.start(
    cmd.first,
    cmd.sublist(1),
    environment: _env,
    mode: ProcessStartMode.inheritStdio,
  );
  return p.exitCode;
}

// ── Screenshot capture (triggered by SCREENSHOT:name markers in flutter output)

Future<void> _captureAndroid(
  String name,
  String uuid,
  String ackPath,
  String outputDir,
  String serial,
) async {
  final r = await _capture([
    'adb',
    '-s',
    serial,
    'exec-out',
    'screencap',
    '-p',
  ], binary: true);
  if (r.exitCode != 0) return;
  File('$outputDir/$name.png').writeAsBytesSync(r.stdout as List<int>);
  print('==> Screenshot: $name.png');
  await _capture(['adb', '-s', serial, 'shell', 'echo $uuid > $ackPath']);
}

Future<void> _captureIos(
  String name,
  String uuid,
  String ackPath,
  String outputDir,
  String udid,
) async {
  final r = await _capture([
    'xcrun',
    'simctl',
    'io',
    udid,
    'screenshot',
    '$outputDir/$name.png',
  ]);
  if (r.exitCode != 0) return;
  print('==> Screenshot: $name.png');
  await _capture([
    'xcrun',
    'simctl',
    'spawn',
    udid,
    'sh',
    '-c',
    'echo $uuid > $ackPath',
  ]);
}

// ── flutter drive with SCREENSHOT:name stdout monitoring ─────────────────────

Future<int> _flutterDrive(
  List<String> extraArgs, {
  required Future<void> Function(String name, String uuid, String ackPath)
  onScreenshot,
}) async {
  final cmd = [
    ..._flutter,
    'drive',
    '--driver=test_driver/screenshot_driver.dart',
    '--target=integration_test/screenshot_test.dart',
    ...extraArgs,
  ];

  final proc = await Process.start(
    cmd.first,
    cmd.sublist(1),
    environment: _env,
  );
  proc.stderr.listen(stderr.add);

  await for (final line
      in proc.stdout.transform(utf8.decoder).transform(const LineSplitter())) {
    stdout.writeln(line);
    final idx = line.indexOf(_screenshotMarker);
    if (idx >= 0) {
      final rest = line.substring(idx + _screenshotMarker.length).trim();
      final first = rest.indexOf(':');
      final second = first >= 0 ? rest.indexOf(':', first + 1) : -1;
      final name = first >= 0 ? rest.substring(0, first) : rest;
      final ackPath = second >= 0 ? rest.substring(first + 1, second) : '';
      final uuid = second >= 0 ? rest.substring(second + 1) : '';
      await onScreenshot(name, uuid, ackPath);
    }
  }

  final code = await proc.exitCode;
  if (code != 0) stderr.writeln('error: flutter drive exited with code $code');
  return code;
}

// ── Android Demo Mode ─────────────────────────────────────────────────────────
// Produces a clean status bar (fixed time, full battery/WiFi, no notifications)
// using Android's built-in demo mode — no special permissions required.

const _demoAction = 'com.android.systemui.demo';

Future<void> _adbShell(String serial, String cmd) =>
    _capture(['adb', '-s', serial, 'shell', cmd]);

Future<void> _enterAndroidDemoMode(String serial) async {
  Future<void> demo(String args) =>
      _adbShell(serial, 'am broadcast -a $_demoAction $args');

  await _adbShell(serial, 'settings put global sysui_demo_allowed 1');
  await _adbShell(serial, 'settings put system time_12_24 24');
  await _adbShell(serial, 'cmd uimode night yes');

  await demo('-e command enter');
  // Wait for the demo mode to fully initialize or some of the broadcast commands may be silently ignored.
  await Future<void>.delayed(const Duration(seconds: 30));
  await demo('-e command clock -e hhmm 2100');
  await demo('-e command battery -e level 100 -e plugged false');
  await demo('-e command notifications -e visible false');
  await demo('-e command network -e wifi show -e level 4 -e fully true');
  await Future<void>.delayed(const Duration(seconds: 1));
  // Wait for the wifi configuration to be handled before setting the mobile network, otherwise the mobile network configuration may be silently ignored.
  await demo(
    '-e command network -e mobile show -e level 4 -e datatype 5g -e slot 0',
  );
  await Future<void>.delayed(const Duration(seconds: 30));
}

// ── Android ───────────────────────────────────────────────────────────────────

String _avdName(String dev) => switch (dev) {
  'phone' => 'bonken_phone',
  'tablet' => 'bonken_tablet',
  _ => throw ArgumentError(dev),
};

String _androidProfile(String dev) => switch (dev) {
  'phone' => _androidPhoneProfile,
  'tablet' => _androidTabletProfile,
  _ => throw ArgumentError(dev),
};

Future<String?> _findEmulatorSerial(String avdName) async {
  final r = await _capture(['adb', 'devices']);
  for (final line in (r.stdout as String).split('\n')) {
    final serial = line.split('\t').first.trim();
    if (!serial.startsWith('emulator-')) continue;
    final nr = await _capture(['adb', '-s', serial, 'emu', 'avd', 'name']);
    final name = (nr.stdout as String)
        .split('\n')
        .first
        .replaceAll('\r', '')
        .trim();
    if (name == avdName) return serial;
  }
  return null;
}

Process? _emulatorProcess;
String? _emulatorSerial;
String? _iosSimUdid;

Future<void> _shutdown() async {
  final proc = _emulatorProcess;
  if (proc != null) {
    print('==> Shutting down Android emulator...');
    final serial = _emulatorSerial;
    _emulatorProcess = null;
    _emulatorSerial = null;
    if (serial != null) {
      await _run(['adb', '-s', serial, 'emu', 'kill']);
    }
    proc.kill();
    await proc.exitCode;
  }
  final udid = _iosSimUdid;
  if (udid != null) {
    print('==> Shutting down iOS simulator...');
    _iosSimUdid = null;
    await _run(['xcrun', 'simctl', 'shutdown', udid]);
  }
}

Future<void> _runAndroid(
  String dev, {
  required bool ci,
  required bool debug,
  required bool wipe,
}) async {
  if (dev != 'phone' && dev != 'tablet') {
    throw _ScriptException(
      "unknown Android device type '$dev' (expected phone|tablet|all)",
    );
  }

  final avdName = _avdName(dev);
  final profile = _androidProfile(dev);
  final sysimg = 'system-images;android-$_androidApiLevel;google_apis;x86_64';

  String? serial;

  if (!ci) {
    // ── SDK path resolution ───────────────────────────────────────────────────
    final sdk =
        Platform.environment['ANDROID_HOME'] ??
        Platform.environment['ANDROID_SDK_ROOT'] ??
        '${Platform.environment['HOME']}/Android/Sdk';
    if (Directory(sdk).existsSync()) {
      _env = {
        ...Platform.environment,
        'PATH':
            '$sdk/platform-tools:$sdk/emulator:$sdk/cmdline-tools/latest/bin'
            ':${Platform.environment['PATH'] ?? ''}',
      };
    }

    // ── Dependency checks ─────────────────────────────────────────────────────
    bool hasTool(String name) =>
        Process.runSync('which', [name], environment: _env).exitCode == 0;

    var anyMissing = false;
    void check(String cmd, String install) {
      if (!hasTool(cmd)) {
        stderr.writeln('error: $cmd not found — install $install');
        anyMissing = true;
      }
    }

    check(
      'adb',
      'Android SDK platform-tools  (https://developer.android.com/tools/releases/platform-tools)',
    );
    check(
      'avdmanager',
      'Android SDK cmdline-tools   (Android Studio → SDK Manager → SDK Tools → Android SDK Command-line Tools)',
    );
    check(
      'emulator',
      'Android SDK emulator package (Android Studio → SDK Manager → SDK Tools → Android Emulator)',
    );
    check(
      'sdkmanager',
      'Android SDK cmdline-tools   (Android Studio → SDK Manager → SDK Tools → Android SDK Command-line Tools)',
    );
    if (anyMissing) {
      throw _ScriptException('required tools are missing — see errors above');
    }

    // ── System image ──────────────────────────────────────────────────────────
    final installed = await _capture(['sdkmanager', '--list_installed']);
    if (!(installed.stdout as String).contains(sysimg)) {
      print('==> Installing Android system image: $sysimg');
      final p = await Process.start(
        'sdkmanager',
        [sysimg],
        environment: _env,
        mode: ProcessStartMode.inheritStdio,
      );
      final sdkCode = await p.exitCode;
      if (sdkCode != 0) {
        throw _ScriptException('sdkmanager failed with exit code $sdkCode');
      }
    }

    // ── AVD ───────────────────────────────────────────────────────────────────
    final avdList = await _capture(['avdmanager', 'list', 'avd']);
    if (!(avdList.stdout as String).contains('Name: $avdName')) {
      print("==> Creating AVD '$avdName' (profile: $profile)");
      final p = await Process.start(
        'avdmanager',
        [
          'create',
          'avd',
          '--name',
          avdName,
          '--package',
          sysimg,
          '--device',
          profile,
          '--force',
        ],
        environment: _env,
        mode: ProcessStartMode.inheritStdio,
      );
      final avdCode = await p.exitCode;
      if (avdCode != 0) {
        throw _ScriptException('avdmanager failed with exit code $avdCode');
      }
    }

    // ── Disable telephony hardware ────────────────────────────────────────────
    // Without a real SIM, the Kairos pipeline starts with an empty subscription list.
    // Demo mode then adds exactly one indicator with no stale entries to clash with.
    final avdHome =
        Platform.environment['ANDROID_AVD_HOME'] ??
        '${Platform.environment['HOME']}/.android/avd';
    final configFile = File('$avdHome/$avdName.avd/config.ini');
    if (!configFile.existsSync()) {
      throw _ScriptException('AVD config not found: ${configFile.path}');
    }
    var content = configFile.readAsStringSync();
    if (RegExp(r'hw\.telephony\s*=').hasMatch(content)) {
      content = content.replaceAll(
        RegExp(r'hw\.telephony\s*=\S*'),
        'hw.telephony=no',
      );
    } else {
      content = '${content.trimRight()}\nhw.telephony=no\n';
    }
    configFile.writeAsStringSync(content);

    // ── Check not already running ─────────────────────────────────────────────
    final existing = await _findEmulatorSerial(avdName);
    if (existing != null) {
      throw _ScriptException(
        "emulator '$avdName' is already running ($existing) — stop it first:\n"
        '  adb -s $existing emu kill',
      );
    }
  }

  // ── flutter drive + screenshots ───────────────────────────────────────────
  print('==> Taking Android screenshots ($dev)...');
  final outputDir = 'screenshots/android/$dev';
  Directory(outputDir).createSync(recursive: true);

  if (!ci) {
    // ── Boot ──────────────────────────────────────────────────────────────────
    print(
      "==> Starting Android emulator '$avdName'${wipe ? ' (with -wipe-data)' : ''}...",
    );
    _emulatorProcess = await Process.start(
      'emulator',
      [
        '-avd',
        avdName,
        '-no-window',
        '-no-audio',
        '-no-boot-anim',
        if (wipe) '-wipe-data',
      ],
      environment: _env,
      mode: debug ? ProcessStartMode.inheritStdio : ProcessStartMode.normal,
    );
    if (!debug) {
      unawaited(_emulatorProcess!.stdout.drain<void>());
      _emulatorProcess!.stderr.listen(stderr.add);
    }
    final exitCodeFuture = _emulatorProcess!.exitCode;

    // ── Wait for ADB registration ────────────────────────────────────────────
    print('==> Waiting for device...');
    var found = false;
    for (var i = 0; i < _pollAttempts; i++) {
      serial = await _findEmulatorSerial(avdName);
      if (serial != null) {
        found = true;
        break;
      }
      final died = await Future.any([
        Future.delayed(_pollInterval, () => false),
        exitCodeFuture.then((_) => true),
      ]);
      if (died) {
        throw _ScriptException(
          'emulator exited early (exit code ${await exitCodeFuture})',
        );
      }
    }
    if (!found) {
      throw _ScriptException('timeout waiting for emulator to appear in ADB');
    }
    _emulatorSerial = serial!;

    // ── Wait for boot to complete ────────────────────────────────────────────
    print('==> Waiting for boot to complete...');
    var booted = false;
    for (var i = 0; i < _pollAttempts; i++) {
      final r = await _capture([
        'adb',
        '-s',
        serial,
        'shell',
        'getprop',
        'sys.boot_completed',
      ]);
      if ((r.stdout as String).replaceAll('\r', '').trim() == '1') {
        booted = true;
        break;
      }
      await Future<void>.delayed(_pollInterval);
    }
    if (!booted) throw _ScriptException('timeout waiting for emulator to boot');
    print('==> Emulator ready.');

    print('==> Setting locale ($_locale)...');
    final bcp47 = _locale.replaceAll('_', '-');
    await _adbShell(serial, 'cmd locale set-system-locale $bcp47');
    await Future<void>.delayed(const Duration(seconds: 60));
  }

  // ── Resolve emulator serial (CI: emulator managed by android-emulator-runner)
  // android-emulator-runner names its AVD "test", not bonken_phone/bonken_tablet,
  // so name-based lookup fails; use the $ANDROID_SERIAL it exports instead.
  serial ??= ci
      ? Platform.environment['ANDROID_SERIAL']
      : await _findEmulatorSerial(avdName);
  if (serial == null) {
    throw _ScriptException("could not find serial for AVD '$avdName'");
  }
  final resolvedSerial = serial;

  print('==> Entering demo mode...');
  await _enterAndroidDemoMode(resolvedSerial);

  print('==> Running flutter drive...');
  final driveCode = await _flutterDrive(
    ['-d', resolvedSerial],
    onScreenshot: (name, uuid, ackPath) =>
        _captureAndroid(name, uuid, ackPath, outputDir, resolvedSerial),
  );
  if (driveCode == 0) {
    print('==> Screenshots saved to $outputDir/');
  } else {
    throw _ScriptException('flutter drive failed with exit code $driveCode');
  }
}

// ── iOS ───────────────────────────────────────────────────────────────────────

String _iosSimName(String dev) => switch (dev) {
  'iphone' => _iosIphoneSim,
  'ipad' => _iosIpadSim,
  _ => throw ArgumentError(dev),
};

Future<String> _findIosSimulatorUdid(String simName) async {
  final r = await _capture([
    'xcrun',
    'simctl',
    'list',
    'devices',
    'available',
    '-j',
  ]);
  if (r.exitCode != 0) {
    throw _ScriptException('xcrun simctl failed:\n${r.stderr}');
  }

  final Map<String, dynamic> data;
  try {
    data = jsonDecode(r.stdout as String) as Map<String, dynamic>;
  } on Object catch (e) {
    throw _ScriptException('could not parse xcrun output as JSON: $e');
  }

  final rawDevices = data['devices'];
  if (rawDevices is! Map<String, dynamic>) {
    throw _ScriptException(
      'unexpected xcrun JSON structure: missing or invalid "devices" key',
    );
  }

  final available = <String>{};
  String? udid;

  for (final list in rawDevices.values) {
    if (list is! List<dynamic>) continue;
    for (final device in list) {
      if (device is! Map<String, dynamic>) continue;
      if (device['isAvailable'] != true) continue;
      final name = device['name'];
      final id = device['udid'];
      if (name is! String || id is! String) continue;
      available.add(name);
      if (name == simName) udid = id;
    }
  }

  if (udid != null) return udid;

  final list = (available.toList()..sort()).map((n) => '  $n').join('\n');
  throw _ScriptException(
    "simulator '$simName' not found, available simulators:\n$list",
  );
}

Future<void> _runIos(String dev, {required bool wipe}) async {
  if (dev != 'iphone' && dev != 'ipad') {
    throw _ScriptException(
      "unknown iOS device type '$dev' (expected iphone|ipad|all)",
    );
  }

  if (Process.runSync('which', ['xcrun']).exitCode != 0) {
    throw _ScriptException(
      'xcrun not found — iOS screenshots require macOS with Xcode installed',
    );
  }

  final simName = _iosSimName(dev);
  final simUdid = await _findIosSimulatorUdid(simName);

  if (wipe) {
    print("==> Erasing iOS simulator '$simName'...");
    await _run(['xcrun', 'simctl', 'shutdown', simUdid]); // no-op if not booted
    await _run(['xcrun', 'simctl', 'erase', simUdid]);
  }

  print("==> Booting iOS simulator '$simName' ($simUdid)...");
  await _run(['xcrun', 'simctl', 'boot', simUdid]); // ok if already booted
  _iosSimUdid = simUdid;
  await _run(['xcrun', 'simctl', 'bootstatus', simUdid, '-b']);
  print('==> Simulator ready.');

  print('==> Configuring iOS status bar...');
  await _capture([
    'xcrun',
    'simctl',
    'status_bar',
    simUdid,
    'override',
    '--time',
    '21:00',
    '--dataNetwork',
    '5g',
    '--cellularBars',
    '4',
    '--wifiBars',
    '3',
    '--batteryState',
    'charged',
    '--batteryLevel',
    '100',
  ]);

  print('==> Enabling dark mode...');
  await _capture(['xcrun', 'simctl', 'ui', simUdid, 'appearance', 'dark']);

  print('==> Setting locale ($_locale)...');
  final lang = _locale.split('_').first;
  await _capture([
    'xcrun',
    'simctl',
    'spawn',
    simUdid,
    'defaults',
    'write',
    'NSGlobalDomain',
    'AppleLocale',
    _locale,
  ]);
  await _capture([
    'xcrun',
    'simctl',
    'spawn',
    simUdid,
    'defaults',
    'write',
    'NSGlobalDomain',
    'AppleLanguages',
    '-array',
    lang,
  ]);
  await _capture([
    'xcrun',
    'simctl',
    'spawn',
    simUdid,
    'launchctl',
    'kickstart',
    '-k',
    'system/com.apple.SpringBoard',
  ]);

  print('==> Taking iOS screenshots ($dev)...');
  final outputDir = 'screenshots/ios/$dev';
  Directory(outputDir).createSync(recursive: true);

  final driveCode = await _flutterDrive(
    ['-d', simName],
    onScreenshot: (name, uuid, ackPath) =>
        _captureIos(name, uuid, ackPath, outputDir, simUdid),
  );

  if (driveCode == 0) {
    print('==> Screenshots saved to $outputDir/');
  } else {
    throw _ScriptException('flutter drive failed with exit code $driveCode');
  }
}

// ── main ─────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  String? platform;
  String? deviceType;
  var ci = false;
  var debug = false;
  var wipe = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--android':
        platform = 'android';
        if (++i >= args.length) {
          stderr.writeln(
            'error: --android requires a device type (phone|tablet|all)',
          );
          exit(2);
        }
        deviceType = args[i];
      case '--ios':
        platform = 'ios';
        if (++i >= args.length) {
          stderr.writeln(
            'error: --ios requires a device type (iphone|ipad|all)',
          );
          exit(2);
        }
        deviceType = args[i];
      case '--ci':
        ci = true;
      case '--debug':
        debug = true;
      case '--wipe':
        wipe = true;
      default:
        stderr.writeln("error: unknown argument '${args[i]}'");
        exit(2);
    }
  }

  if (platform == null) {
    stderr.writeln('error: specify --android or --ios');
    exit(2);
  }
  if (deviceType == null) {
    stderr.writeln('error: specify a device type');
    exit(2);
  }
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('error: run from the repo root (pubspec.yaml not found)');
    exit(1);
  }

  _loadConfig();
  _resolveFlutter(ci);

  final sigSubs = <StreamSubscription<ProcessSignal>>[];
  for (final sig in [
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
    ProcessSignal.sighup,
  ]) {
    sigSubs.add(
      sig.watch().listen((s) async {
        await _shutdown();
        exit(128 + s.signalNumber);
      }),
    );
  }

  Future<void> runOne(String dev) => switch (platform) {
    'android' => _runAndroid(dev, ci: ci, debug: debug, wipe: wipe),
    'ios' => _runIos(dev, wipe: wipe),
    _ => Future.value(),
  };

  final devs = deviceType == 'all'
      ? switch (platform) {
          'android' => ['phone', 'tablet'],
          'ios' => ['iphone', 'ipad'],
          _ => <String>[],
        }
      : [deviceType];

  for (final dev in devs) {
    var failed = false;
    try {
      await runOne(dev);
    } on _ScriptException catch (e) {
      stderr.writeln('error: ${e.message}');
      failed = true;
    } finally {
      await _shutdown();
    }
    if (failed) exit(1);
  }

  for (final sub in sigSubs) {
    await sub.cancel();
  }
}
