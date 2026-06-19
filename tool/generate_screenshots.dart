#!/usr/bin/env -S fvm dart
// ignore_for_file: avoid_print

// Generate store screenshots for one or all device sizes.
//
// Usage:
//   ./tool/generate_screenshots.dart --android phone|tablet|all
//   ./tool/generate_screenshots.dart --ios iphone|ipad|all
//   (append --ci           to use PATH flutter/dart instead of fvm,
//                             and to skip AVD management on Android)
//   (append --clean         force a cold boot: wipes userdata (-wipe-data),
//                             skips snapshot (-no-snapshot), and deletes saved
//                             snapshots so the next normal run also starts fresh;
//                             on iOS: erases the simulator (simctl erase);
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
// Output: screenshots/<platform>_<device-type>_<num>_<name>.png  (8 PNGs per device size)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _screenshotMarker = 'SCREENSHOT:';
const _outputDir = 'screenshots';

class _ScriptException implements Exception {
  _ScriptException(this.message);
  final String message;
}

class _ScriptCancelledException implements Exception {}

// ── Device / locale config ────────────────────────────────────────────────────

const _androidApiLevel = '37.0';
const _androidTarget = 'google_apis_playstore_ps16k';
const _androidPhoneProfile = 'pixel_9';
const _androidTabletProfile = 'pixel_tablet';
const _iosIphoneSim = 'iPhone 17 Pro Max';
const _iosIpadSim = 'iPad Pro 13-inch (M5)';
const _iosRuntime = 'iOS-26-2';

const _androidLocale = 'nl-NL'; // BCP47 — for `cmd locale set-system-locale`
const _iosLocale = 'nl_NL'; // POSIX — for NSGlobalDomain AppleLocale
const _iosLanguage = 'nl'; // for NSGlobalDomain AppleLanguages

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
    _await(
      Process.run(
        cmd.first,
        cmd.sublist(1),
        stdoutEncoding: binary ? null : utf8,
        stderrEncoding: utf8,
        environment: _env,
      ),
    );

Future<void> _captureOrThrow(List<String> cmd) async {
  final r = await _capture(cmd);
  if (r.exitCode != 0) {
    throw _ScriptException(
      '${cmd.join(' ')} failed (exit ${r.exitCode}): ${r.stderr}',
    );
  }
}

Future<int> _run(List<String> cmd, {Duration? timeout}) async {
  final p = await _await(
    Process.start(
      cmd.first,
      cmd.sublist(1),
      environment: _env,
      mode: ProcessStartMode.inheritStdio,
    ),
  );
  if (timeout == null) return _await(p.exitCode);
  try {
    return await _await(p.exitCode).timeout(timeout);
  } on TimeoutException {
    p.kill();
    await p.exitCode;
    throw _ScriptException(
      '${cmd.first} ${cmd.sublist(1).join(' ')} timed out after ${timeout.inMinutes}m',
    );
  }
}

// ── Screenshot capture (triggered by SCREENSHOT:name markers in flutter output)

Future<void> _captureAndroid(
  String name,
  String uuid,
  String ackPath,
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
  if (r.exitCode != 0) {
    throw _ScriptException(
      'adb screencap failed (exit ${r.exitCode}): ${r.stderr}',
    );
  }
  File('$_outputDir/$name.png').writeAsBytesSync(r.stdout as List<int>);
  print('==> Screenshot: $name.png');
  await _captureOrThrow([
    'adb',
    '-s',
    serial,
    'shell',
    'echo $uuid > $ackPath',
  ]);
}

Future<void> _captureIos(
  String name,
  String uuid,
  String ackPath,
  String udid,
) async {
  final r = await _capture([
    'xcrun',
    'simctl',
    'io',
    udid,
    'screenshot',
    '$_outputDir/$name.png',
  ]);
  if (r.exitCode != 0) {
    throw _ScriptException(
      'simctl screenshot failed (exit ${r.exitCode}): ${r.stderr}',
    );
  }
  print('==> Screenshot: $name.png');
  // Write the ack directly on the host: dart:io in the iOS Simulator reads
  // from the host macOS filesystem at /tmp, not from the simulator's sandboxed
  // container that `simctl spawn` would write into.
  File(ackPath).writeAsStringSync(uuid);
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

  final proc = await _await(
    Process.start(cmd.first, cmd.sublist(1), environment: _env),
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

  final code = await _await(proc.exitCode);
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

  await demo('-e command enter');
  // Wait for the demo mode to fully initialize
  // or some of the broadcast commands may be silently ignored.
  await _delayed(const Duration(seconds: 30));
  await demo('-e command clock -e hhmm 2100');
  await demo('-e command battery -e level 100 -e plugged false');
  await demo('-e command notifications -e visible false');
  await demo('-e command network -e wifi show -e level 4 -e fully true');
  // Wait for the wifi configuration to be handled before setting the mobile
  // network, or the mobile network configuration may be silently ignored.
  await _delayed(const Duration(seconds: 10));
  await demo(
    '-e command network -e mobile show -e level 4 -e datatype 5g -e slot 0',
  );
  await _delayed(const Duration(seconds: 60));
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
final _cancelled = Completer<void>();

Future<T> _await<T>(Future<T> f) async {
  if (_cancelled.isCompleted) throw _ScriptCancelledException();
  final v = await f;
  if (_cancelled.isCompleted) throw _ScriptCancelledException();
  return v;
}

Future<void> _delayed(Duration d) =>
    _await(Future.any([Future<void>.delayed(d), _cancelled.future]));

Future<void> _shutdown({bool force = false}) async {
  if (!force && _cancelled.isCompleted) return;
  if (_emulatorProcess != null) {
    print('==> Shutting down Android emulator...');
    if (_emulatorSerial != null) {
      await Process.run('adb', [
        '-s',
        _emulatorSerial!,
        'emu',
        'kill',
      ], environment: _env);
    }
    _emulatorProcess!.kill();
    await _emulatorProcess!.exitCode;
  }
  if (_iosSimUdid != null) {
    print('==> Shutting down iOS simulator...');
    await Process.run('xcrun', [
      'simctl',
      'shutdown',
      _iosSimUdid!,
    ], environment: _env);
  }
  if (!force) {
    _emulatorProcess = null;
    _emulatorSerial = null;
    _iosSimUdid = null;
  }
}

Future<void> _runAndroid(
  String dev, {
  required bool ci,
  required bool debug,
  required bool clean,
}) async {
  if (dev != 'phone' && dev != 'tablet') {
    throw _ScriptException(
      "unknown Android device type '$dev' (expected phone|tablet|all)",
    );
  }

  final avdName = _avdName(dev);

  if (!ci) {
    final profile = _androidProfile(dev);
    const sysimg =
        'system-images;android-$_androidApiLevel;$_androidTarget;x86_64';
    final avdHome =
        Platform.environment['ANDROID_AVD_HOME'] ??
        '${Platform.environment['HOME']}/.android/avd';

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
      final sdkCode = await _run(['sdkmanager', sysimg]);
      if (sdkCode != 0) {
        throw _ScriptException('sdkmanager failed with exit code $sdkCode');
      }
    }

    // ── AVD ───────────────────────────────────────────────────────────────────
    Future<void> createAvd() async {
      final avdCode = await _run([
        'avdmanager',
        'create',
        'avd',
        '--name',
        avdName,
        '--package',
        sysimg,
        '--device',
        profile,
        '--force',
      ]);
      if (avdCode != 0) {
        throw _ScriptException('avdmanager failed with exit code $avdCode');
      }
    }

    final avdList = await _capture(['avdmanager', 'list', 'avd']);
    if (!(avdList.stdout as String).contains('Name: $avdName')) {
      print("==> Creating AVD '$avdName' (profile: $profile)");
      await createAvd();
    } else {
      // Verify the existing AVD uses the expected system image and device profile.
      final existingConfig = File('$avdHome/$avdName.avd/config.ini');
      if (existingConfig.existsSync()) {
        final ini = existingConfig.readAsStringSync();
        const expectedSysdir =
            'system-images/android-$_androidApiLevel/$_androidTarget/x86_64/';
        final sysdir =
            RegExp(r'image\.sysdir\.1\s*=\s*(\S+)').firstMatch(ini)?.group(1) ??
            '';
        final device =
            RegExp(r'hw\.device\.name\s*=\s*(\S+)').firstMatch(ini)?.group(1) ??
            '';
        if (!sysdir.contains(expectedSysdir) || device != profile) {
          print(
            "==> AVD '$avdName' has wrong image or profile — recreating...\n"
            '    Expected: $profile + $expectedSysdir\n'
            '    Found:    $device + $sysdir',
          );
          await createAvd();
        }
      }
    }

    // ── AVD config patches ────────────────────────────────────────────────────
    String setConfig(String content, String key, String value) {
      final pattern = RegExp('${RegExp.escape(key)}\\s*=\\S*');
      return pattern.hasMatch(content)
          ? content.replaceAll(pattern, '$key=$value')
          : '${content.trimRight()}\n$key=$value\n';
    }

    final configFile = File('$avdHome/$avdName.avd/config.ini');
    if (!configFile.existsSync()) {
      throw _ScriptException('AVD config not found: ${configFile.path}');
    }
    var content = configFile.readAsStringSync();
    // Without a real SIM, demo mode adds exactly one mobile indicator with no
    // stale telephony entries to clash with.
    content = setConfig(content, 'hw.telephony', 'no');
    content = setConfig(content, 'hw.ramSize', '4G');
    configFile.writeAsStringSync(content);

    // ── Check not already running ─────────────────────────────────────────────
    final existing = await _findEmulatorSerial(avdName);
    if (existing != null) {
      throw _ScriptException(
        "emulator '$avdName' is already running ($existing) — stop it first:\n"
        '  adb -s $existing emu kill',
      );
    }

    // ── Boot ──────────────────────────────────────────────────────────────────
    if (clean) {
      // Delete the saved Quickboot snapshot so the next normal run also cold-boots
      // rather than restoring the pre-clean state.
      print('==> Deleting saved snapshots...');
      final snapshotsDir = Directory('$avdHome/$avdName.avd/snapshots');
      if (snapshotsDir.existsSync()) {
        snapshotsDir.deleteSync(recursive: true);
      }
    }

    print(
      "==> Starting Android emulator '$avdName'${clean ? ' (wiping user data)' : ''}...",
    );
    _emulatorProcess = await Process.start(
      'emulator',
      [
        '-avd',
        avdName,
        '-no-window',
        '-no-audio',
        '-no-boot-anim',
        if (clean) '-wipe-data',
        if (clean) '-no-snapshot',
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
    for (var i = 0; i < 300; i++) {
      _emulatorSerial = await _findEmulatorSerial(avdName);
      if (_emulatorSerial != null) break;
      final died = await Future.any([
        Future.delayed(const Duration(seconds: 1), () => false),
        exitCodeFuture.then((_) => true),
      ]);
      if (died) {
        throw _ScriptException(
          'emulator exited early (exit code ${await exitCodeFuture})',
        );
      }
    }
    if (_emulatorSerial == null) {
      throw _ScriptException('timeout waiting for emulator to appear in ADB');
    }

    // ── Wait for boot to complete ────────────────────────────────────────────
    print('==> Waiting for boot to complete...');
    var booted = false;
    for (var i = 0; i < 300; i++) {
      final r = await _capture([
        'adb',
        '-s',
        _emulatorSerial!,
        'shell',
        'getprop',
        'sys.boot_completed',
      ]);
      if ((r.stdout as String).replaceAll('\r', '').trim() == '1') {
        booted = true;
        break;
      }
      await _delayed(const Duration(seconds: 1));
    }
    if (!booted) throw _ScriptException('timeout waiting for emulator to boot');
  } else {
    // android-emulator-runner names its AVD "test", not bonken_phone/bonken_tablet,
    // so name-based lookup fails; use the $ANDROID_SERIAL it exports instead.
    _emulatorSerial = Platform.environment['ANDROID_SERIAL'];
  }

  if (_emulatorSerial == null) {
    throw _ScriptException("could not find serial for AVD '$avdName'");
  }
  final serial = _emulatorSerial!;

  print('==> Normalizing device settings...');
  // These all trigger a SystemUI restart; batch them and wait once.
  await _adbShell(serial, 'cmd locale set-system-locale $_androidLocale');
  await _adbShell(serial, 'cmd uimode night yes');
  await _adbShell(serial, 'settings put secure navigation_mode 2');
  await _adbShell(serial, 'settings put system font_scale 1.0');
  await _adbShell(serial, 'settings put global window_animation_scale 0.0');
  await _adbShell(serial, 'settings put global transition_animation_scale 0.0');
  await _adbShell(serial, 'settings put global animator_duration_scale 0.0');
  await _adbShell(serial, 'settings put system time_12_24 24');
  await _delayed(const Duration(seconds: 30));

  print('==> Entering demo mode...');
  await _enterAndroidDemoMode(serial);

  print('==> Taking Android screenshots ($dev)...');
  Directory(_outputDir).createSync(recursive: true);
  final prefix = 'android_$dev';
  final driveCode = await _flutterDrive(
    ['-d', serial, '--flavor', 'current'],
    onScreenshot: (name, uuid, ackPath) =>
        _captureAndroid('${prefix}_$name', uuid, ackPath, serial),
  );
  if (driveCode == 0) {
    print('==> Screenshots saved to $_outputDir/');
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

  String? udid;
  final available = <String>[];

  for (final entry in rawDevices.entries) {
    final runtime = entry.key;
    final devices = entry.value;
    if (devices is! List<dynamic>) continue;
    for (final device in devices) {
      if (device is! Map<String, dynamic>) continue;
      if (device['isAvailable'] != true) continue;
      final name = device['name'];
      final id = device['udid'];
      if (name is! String || id is! String) continue;
      available.add('  $name  [$runtime]');
      if (udid == null &&
          runtime == 'com.apple.CoreSimulator.SimRuntime.$_iosRuntime' &&
          name == simName) {
        udid = id;
      }
    }
  }

  available.sort();
  print('==> Available iOS simulators:\n${available.join('\n')}');

  if (udid != null) return udid;

  throw _ScriptException(
    "simulator '$simName' not found under runtime 'com.apple.CoreSimulator.SimRuntime.$_iosRuntime'",
  );
}

Future<void> _runIos(
  String dev, {
  required bool clean,
  required bool debug,
}) async {
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

  if (clean) {
    print("==> Erasing iOS simulator '$simName'...");
    await _run(['xcrun', 'simctl', 'shutdown', simUdid]); // no-op if not booted
    await _run(['xcrun', 'simctl', 'erase', simUdid]);
  }

  Process? logProc;
  if (debug) {
    print('==> Streaming CoreSimulator logs...');
    logProc = await Process.start('log', [
      'stream',
      '--predicate',
      'subsystem == "com.apple.CoreSimulator"',
      '--style',
      'compact',
      '--level',
      'debug',
    ]);
    logProc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stdout.writeln);
    unawaited(logProc.stderr.drain<void>());
  }

  try {
    print("==> Booting iOS simulator '$simName' ($simUdid)...");
    await _run(['xcrun', 'simctl', 'boot', simUdid]); // ok if already booted
    _iosSimUdid = simUdid;

    final stateResult = await _capture(['xcrun', 'simctl', 'list', 'devices']);
    final stateLine = (stateResult.stdout as String)
        .split('\n')
        .firstWhere((l) => l.contains(simUdid), orElse: () => '(not found)');
    print('==> Simulator state: ${stateLine.trim()}');

    await _run([
      'xcrun',
      'simctl',
      'bootstatus',
      simUdid,
      '-b',
    ], timeout: const Duration(minutes: 5));
    print('==> Simulator ready.');

    print('==> Setting locale ($_iosLocale)...');
    await _captureOrThrow([
      'xcrun',
      'simctl',
      'spawn',
      simUdid,
      'defaults',
      'write',
      'NSGlobalDomain',
      'AppleLocale',
      _iosLocale,
    ]);
    await _captureOrThrow([
      'xcrun',
      'simctl',
      'spawn',
      simUdid,
      'defaults',
      'write',
      'NSGlobalDomain',
      'AppleLanguages',
      '-array',
      _iosLanguage,
    ]);
    await _captureOrThrow([
      'xcrun',
      'simctl',
      'spawn',
      simUdid,
      'launchctl',
      'kickstart',
      '-k',
      'system/com.apple.SpringBoard',
    ]);

    // SpringBoard restart (for locale) resets status bar state, so wait for it
    // to come back up before applying dark mode and status bar overrides.
    print('==> Waiting for SpringBoard to restart...');
    await _delayed(const Duration(seconds: 20));

    print('==> Enabling dark mode...');
    await _captureOrThrow([
      'xcrun',
      'simctl',
      'ui',
      simUdid,
      'appearance',
      'dark',
    ]);

    print('==> Configuring iOS status bar...');
    await _captureOrThrow([
      'xcrun',
      'simctl',
      'status_bar',
      simUdid,
      'override',
      '--time',
      '2026-07-01T21:00:00.000+00:00',
      '--operatorName',
      'Bonken',
      '--dataNetwork',
      '5g',
      '--cellularBars',
      '4',
      '--wifiBars',
      '3',
      '--batteryState',
      'discharging',
      '--batteryLevel',
      '100',
    ]);

    print('==> Taking iOS screenshots ($dev)...');
    Directory(_outputDir).createSync(recursive: true);
    final prefix = 'ios_$dev';

    final driveCode = await _flutterDrive(
      ['-d', simName],
      onScreenshot: (name, uuid, ackPath) =>
          _captureIos('${prefix}_$name', uuid, ackPath, simUdid),
    );

    if (driveCode == 0) {
      print('==> Screenshots saved to $_outputDir/');
    } else {
      throw _ScriptException('flutter drive failed with exit code $driveCode');
    }
  } finally {
    logProc?.kill();
    if (logProc != null) await logProc.exitCode;
  }
}

// ── main ─────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  String? platform;
  String? deviceType;
  var ci = false;
  var debug = false;
  var clean = false;

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
      case '--clean':
        clean = true;
      case '--print-env':
        // Print Android device config as KEY=VALUE lines for use in CI
        // (append to $GITHUB_ENV so android-emulator-runner can read them).
        print('ANDROID_API_LEVEL=$_androidApiLevel');
        print('ANDROID_TARGET=$_androidTarget');
        print('ANDROID_PHONE_PROFILE=$_androidPhoneProfile');
        print('ANDROID_TABLET_PROFILE=$_androidTabletProfile');
        return;
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

  _resolveFlutter(ci);

  final sigSubs = <StreamSubscription<ProcessSignal>>[];
  for (final sig in [
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
    ProcessSignal.sighup,
  ]) {
    sigSubs.add(
      sig.watch().listen((s) async {
        if (!_cancelled.isCompleted) _cancelled.complete();
        await _shutdown(force: true);
        exit(128 + s.signalNumber);
      }),
    );
  }

  Future<void> runOne(String dev) => switch (platform) {
    'android' => _runAndroid(dev, ci: ci, debug: debug, clean: clean),
    'ios' => _runIos(dev, clean: clean, debug: debug),
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
      if (_cancelled.isCompleted) return;
      stderr.writeln('error: ${e.message}');
      failed = true;
    } on _ScriptCancelledException {
      return; // signal handler will complete _shutdown() and call exit()
    } finally {
      await _shutdown();
    }
    if (failed) exit(1);
  }

  for (final sub in sigSubs) {
    await sub.cancel();
  }
}
