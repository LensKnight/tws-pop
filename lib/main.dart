import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;

const overlayChannel = MethodChannel('tws_pop/overlay');
const eqChannel = MethodChannel('tws_pop/eq');

/// Brand seed colour. Material 3 builds the whole light/dark palette from it.
const accent = Color(0xFF1A73E8);

// The popup is always light, so its previews use fixed light colours.
const _popupSurface = Color(0xFFF1F3F5);
const _popupBorder = Color(0xFFDADCE0);
const _popupTonal = Color(0xFFD3E3FD);

/// Address of the "latest release" of the GitHub repo that hosts your APK.
const kUpdateUrl =
    'https://api.github.com/repos/LensKnight/tws-pop/releases/latest';

/// App theme mode (system / light / dark).
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
);

ThemeMode _themeModeFromName(String? name) {
  switch (name) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'Roboto',
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await PrefsStore.load();
  themeModeNotifier.value = _themeModeFromName(
    PrefsStore.data['themeMode']?.toString(),
  );

  runApp(const TwsPopApp());
}

/// App version name (for example 1.0.1), read natively. Empty if unknown.
Future<String> appVersionName() async {
  try {
    return await overlayChannel.invokeMethod<String>('getAppVersion') ?? '';
  } on MissingPluginException {
    return '';
  } on PlatformException {
    return '';
  }
}

/// Opens a link in the phone's browser, handled natively.
Future<bool> openExternalUrl(String url) async {
  try {
    return await overlayChannel.invokeMethod<bool>('openUrl', {'url': url}) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
}

// -----------------------------------------------------------------------------
// Saved data (stored natively on the device, no plugin needed)
// -----------------------------------------------------------------------------

class PrefsStore {
  static Map<String, dynamic> _data = {};
  static bool _loaded = false;

  static Map<String, dynamic> get data => _data;

  static Future<void> load() async {
    if (_loaded) return;

    try {
      final raw = await overlayChannel.invokeMethod<String>('loadPrefs');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) _data = Map<String, dynamic>.from(decoded);
      }
    } on MissingPluginException {
      // Native method not available.
    } on PlatformException {
      // Ignore.
    } catch (_) {
      // Corrupt data: start fresh.
    }

    _loaded = true;
  }

  static Future<void> update(Map<String, dynamic> patch) async {
    _data.addAll(patch);

    try {
      await overlayChannel.invokeMethod('savePrefs', jsonEncode(_data));
    } on MissingPluginException {
      // Native method not available.
    } on PlatformException {
      // Ignore.
    }
  }
}

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

class PopupStyle {
  const PopupStyle(this.id, this.label);
  final String id;
  final String label;
}

/// All popup styles are light. The native popup must ignore the app theme.
const popupStyles = [
  PopupStyle('classic', 'Classic'),
  PopupStyle('tonal', 'Tonal'),
  PopupStyle('minimal', 'Minimal'),
  PopupStyle('compact', 'Compact'),
];

class HistoryEntry {
  const HistoryEntry(this.name, this.connected, this.time);

  final String name;
  final bool connected;
  final DateTime time;

  Map<String, dynamic> toJson() => {
    'n': name,
    'c': connected,
    't': time.millisecondsSinceEpoch,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      json['n']?.toString() ?? 'Device',
      json['c'] == true,
      DateTime.fromMillisecondsSinceEpoch((json['t'] as num?)?.toInt() ?? 0),
    );
  }
}

class EqState {
  EqState({
    this.available = false,
    this.enabled = false,
    this.min = -1500,
    this.max = 1500,
    List<int>? freqs,
    List<int>? levels,
    List<String>? presets,
    this.bass = 0,
    this.bassSupported = false,
    this.sessions = 0,
    this.global = false,
    this.serviceRunning = false,
  }) : freqs = freqs ?? [],
       levels = levels ?? [],
       presets = presets ?? [];

  bool available;
  bool enabled;
  int min;
  int max;
  List<int> freqs;
  List<int> levels;
  List<String> presets;
  int bass;
  bool bassSupported;
  int sessions;
  bool global;
  bool serviceRunning;
  int preset = -1;

  factory EqState.fromMap(Map<dynamic, dynamic> m) {
    final bands = (m['bands'] as List?) ?? const [];

    return EqState(
      available: m['available'] == true,
      enabled: m['enabled'] == true,
      min: (m['min'] as num?)?.toInt() ?? -1500,
      max: (m['max'] as num?)?.toInt() ?? 1500,
      freqs: bands.map((b) => ((b as Map)['freq'] as num).toInt()).toList(),
      levels: bands.map((b) => ((b as Map)['level'] as num).toInt()).toList(),
      presets: ((m['presets'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      bass: (m['bass'] as num?)?.toInt() ?? 0,
      bassSupported: m['bassSupported'] == true,
      sessions: (m['sessions'] as num?)?.toInt() ?? 0,
      global: m['global'] == true,
      serviceRunning: m['serviceRunning'] == true,
    );
  }
}

// -----------------------------------------------------------------------------
// App updates
// -----------------------------------------------------------------------------

enum UpdateStatus { upToDate, available, error, notConfigured }

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.downloadUrl,
  });

  final String version;
  final String notes;
  final String pageUrl;
  final String? downloadUrl;
}

class UpdateResult {
  const UpdateResult(this.status, {this.info, this.currentVersion = ''});

  final UpdateStatus status;
  final UpdateInfo? info;
  final String currentVersion;
}

class UpdateChecker {
  static bool get configured => !kUpdateUrl.contains('YOUR_');

  static List<int> _parts(String version) {
    final cleaned = version
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first
        .split('-')
        .first;

    return cleaned
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  /// True when [remote] is a higher version than [local] (1.10.0 > 1.9.0).
  static bool isNewer(String remote, String local) {
    final a = _parts(remote);
    final b = _parts(local);
    final length = math.max(a.length, b.length);

    for (var i = 0; i < length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static Future<UpdateResult> check() async {
    if (!configured) return const UpdateResult(UpdateStatus.notConfigured);

    var current = '';

    try {
      current = await appVersionName();
      if (current.isEmpty) {
        return UpdateResult(UpdateStatus.error, currentVersion: current);
      }

      final response = await http
          .get(
            Uri.parse(kUpdateUrl),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return UpdateResult(UpdateStatus.error, currentVersion: current);
      }

      final json = jsonDecode(response.body);
      if (json is! Map) {
        return UpdateResult(UpdateStatus.error, currentVersion: current);
      }

      final version = (json['tag_name'] ?? json['version'])?.toString().trim();
      if (version == null || version.isEmpty) {
        return UpdateResult(UpdateStatus.error, currentVersion: current);
      }

      if (!isNewer(version, current)) {
        return UpdateResult(UpdateStatus.upToDate, currentVersion: current);
      }

      String? download;
      final assets = json['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;

          final name = asset['name']?.toString().toLowerCase() ?? '';
          final url = asset['browser_download_url']?.toString();

          if (url != null && name.endsWith('.apk')) {
            download = url;
            break;
          }
        }
      }
      download ??= json['download_url']?.toString();

      final page = (json['html_url'] ?? json['url'])?.toString() ?? '';
      if (download == null && page.isEmpty) {
        return UpdateResult(UpdateStatus.error, currentVersion: current);
      }

      return UpdateResult(
        UpdateStatus.available,
        currentVersion: current,
        info: UpdateInfo(
          version: version,
          notes: (json['body'] ?? json['notes'])?.toString().trim() ?? '',
          pageUrl: page,
          downloadUrl: download,
        ),
      );
    } catch (_) {
      return UpdateResult(UpdateStatus.error, currentVersion: current);
    }
  }
}

Future<void> showUpdateDialog(
  BuildContext context,
  UpdateResult result, {
  bool allowSkip = false,
}) async {
  final info = result.info;
  if (info == null) return;

  final notes = info.notes.length > 500
      ? '${info.notes.substring(0, 500)}...'
      : info.notes;

  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final cs = Theme.of(dialogContext).colorScheme;
      final tt = Theme.of(dialogContext).textTheme;

      return AlertDialog(
        icon: const Icon(Icons.system_update_rounded),
        title: const Text('Update available'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version ${info.version} is ready. You have '
                '${result.currentVersion}.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    child: Text(notes, style: tt.bodySmall),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (allowSkip)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'skip'),
              child: const Text('Skip'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'later'),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'update'),
            child: const Text('Update'),
          ),
        ],
      );
    },
  );

  if (action == 'skip') {
    await PrefsStore.update({'skippedVersion': info.version});
    return;
  }

  if (action == 'update') {
    final target = info.downloadUrl ?? info.pageUrl;
    final opened = await openExternalUrl(target);

    if (!opened && context.mounted) {
      showToast(context, 'Could not open the download link');
    }
  }
}

// -----------------------------------------------------------------------------
// App shell: loading screen -> welcome (name) -> home
// -----------------------------------------------------------------------------

class TwsPopApp extends StatelessWidget {
  const TwsPopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'TWS POP',
          themeMode: mode,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          builder: (context, child) {
            final dark = Theme.of(context).brightness == Brightness.dark;
            final icons = dark ? Brightness.light : Brightness.dark;

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
                statusBarIconBrightness: icons,
                systemNavigationBarIconBrightness: icons,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const AppRoot(),
        );
      },
    );
  }
}

enum AppStage { splash, welcome, home }

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  AppStage stage = AppStage.splash;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Future.wait<void>([
      PrefsStore.load(),
      Future<void>.delayed(const Duration(milliseconds: 2200)),
    ]);

    if (!mounted) return;

    final name = PrefsStore.data['userName']?.toString().trim();
    final goHome = name != null && name.isNotEmpty;

    setState(() {
      stage = goHome ? AppStage.home : AppStage.welcome;
    });

    if (goHome) _checkForUpdate();
  }

  /// Quiet check at most once every 12 hours.
  Future<void> _checkForUpdate() async {
    if (!UpdateChecker.configured) return;

    final last = (PrefsStore.data['lastUpdateCheck'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(hours: 12).inMilliseconds) return;

    await Future<void>.delayed(const Duration(milliseconds: 1200));

    final result = await UpdateChecker.check();

    if (result.status == UpdateStatus.error ||
        result.status == UpdateStatus.notConfigured) {
      return;
    }

    await PrefsStore.update({'lastUpdateCheck': now});

    final info = result.info;
    if (!mounted || result.status != UpdateStatus.available || info == null) {
      return;
    }
    if (PrefsStore.data['skippedVersion'] == info.version) return;

    await showUpdateDialog(context, result, allowSkip: true);
  }

  Future<void> _saveName(String name) async {
    await PrefsStore.update({'userName': name});
    if (!mounted) return;
    setState(() => stage = AppStage.home);
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;

    switch (stage) {
      case AppStage.splash:
        child = const SplashScreen(key: ValueKey('splash'));
      case AppStage.welcome:
        child = WelcomeScreen(
          key: const ValueKey('welcome'),
          onDone: _saveName,
        );
      case AppStage.home:
        child = const HomeScreen(key: ValueKey('home'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        color: cs.onPrimary,
        size: size * 0.54,
      ),
    );
  }
}

/// Animated sound bars used as the loader.
class SoundBars extends StatefulWidget {
  const SoundBars({super.key});

  @override
  State<SoundBars> createState() => _SoundBarsState();
}

class _SoundBarsState extends State<SoundBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: 5,
                  height:
                      10 +
                      24 *
                          (0.5 +
                              0.5 *
                                  math.sin(
                                    2 *
                                        math.pi *
                                        (_controller.value + i * 0.17),
                                  )),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutBack,
              builder: (context, t, child) {
                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
                );
              },
              child: const LogoMark(size: 104),
            ),
            const SizedBox(height: 28),
            Text(
              'TWS POP',
              style: tt.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your audio companion',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 48),
            const SizedBox(height: 40, child: SoundBars()),
          ],
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});

  final Future<void> Function(String name) onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String name) async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.onDone(name);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = _controller.text.trim();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LogoMark(size: 64),
                const SizedBox(height: 32),
                Text(
                  'What should we call you?',
                  style: tt.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your name stays on this device. You can change it anytime '
                  'in settings.',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _controller,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _submit(v.trim());
                  },
                  decoration: const InputDecoration(
                    counterText: '',
                    labelText: 'Your name',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: (name.isEmpty || _saving)
                        ? null
                        : () => _submit(name),
                    child: const Text('Continue'),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: _saving ? null : () => _submit('Guest'),
                    child: const Text('Continue as guest'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared widgets
// -----------------------------------------------------------------------------

/// Flat Material 3 card (tonal surface, no border, no shadow).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 28,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: color ?? cs.surfaceContainer,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Round tonal icon container, like the leading icons in Android settings.
class TonalIcon extends StatelessWidget {
  const TonalIcon(this.icon, {super.key, this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size * 0.5, color: cs.onSecondaryContainer),
    );
  }
}

/// Small coloured section title, like "Network & internet" headers.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Fades and slides a child in when the screen opens. Higher index = later.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + index * 110),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Home
// -----------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const bluetoothChannel = EventChannel('tws_pop/bluetooth');
  static const int _maxHistory = 20;

  StreamSubscription<dynamic>? _bluetoothSubscription;
  late final AnimationController _floatController;
  late final AnimationController _pulseController;

  final Map<String, int> _pendingBattery = {};
  final List<HistoryEntry> history = [];

  String userName = 'Guest';

  String deviceName = 'No earbuds connected';
  bool isConnected = false;
  String status = 'Waiting for connection';
  String permissionStatus = 'Checking floating popup permission...';
  bool overlayGranted = false;
  bool bluetoothOn = true;
  bool bluetoothPermissionGranted = true;
  bool bluetoothPermissionBlocked = false;
  bool watcherEnabled = true;
  bool batteryExempt = true;

  int? batteryLevel;

  // Saved settings
  bool popupEnabled = true;
  bool floatingAnimation = true;
  double popupDuration = 10.0;
  String popupStyle = 'classic';

  // Equalizer
  EqState? eq;

  // App version and updates
  String appVersion = '';
  bool checkingUpdate = false;

  ColorScheme get cs => Theme.of(context).colorScheme;
  TextTheme get tt => Theme.of(context).textTheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _applySavedPrefs();
    _listenForBluetoothEvents();
    _refreshPermission();
    _initNative();
    _loadEq();
    _loadVersion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bluetoothSubscription?.cancel();
    _floatController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  Future<void> _onResumed() async {
    _refreshPermission();
    _refreshEq();
    _loadBackgroundState();

    final hadPermission = bluetoothPermissionGranted;
    await _checkBluetoothPermission();

    if (!hadPermission && bluetoothPermissionGranted) {
      await _onBluetoothGranted();
    } else {
      _loadBluetoothState();
    }
  }

  // ---------------------------------------------------------------------------
  // Saved data
  // ---------------------------------------------------------------------------

  void _applySavedPrefs() {
    final data = PrefsStore.data;

    final loaded = <HistoryEntry>[];
    final list = data['history'];
    if (list is List) {
      for (final item in list) {
        if (item is Map) {
          loaded.add(HistoryEntry.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final styleId = data['style']?.toString();
    final duration = data['duration'];
    final savedName = data['userName']?.toString().trim();

    if (savedName != null && savedName.isNotEmpty) userName = savedName;

    popupEnabled = data['popupEnabled'] != false;
    floatingAnimation = data['floating'] != false;
    if (duration is num) {
      popupDuration = duration.toDouble().clamp(5.0, 15.0).toDouble();
    }
    // Old removed styles (midnight, glow) fall back to classic.
    if (styleId != null && popupStyles.any((s) => s.id == styleId)) {
      popupStyle = styleId;
    }
    history
      ..clear()
      ..addAll(loaded.take(_maxHistory));
  }

  Future<void> _savePrefs() {
    return PrefsStore.update({
      'popupEnabled': popupEnabled,
      'floating': floatingAnimation,
      'duration': popupDuration,
      'style': popupStyle,
      'history': history.map((x) => x.toJson()).toList(),
    });
  }

  void _setThemeMode(ThemeMode mode) {
    HapticFeedback.selectionClick();
    themeModeNotifier.value = mode;
    PrefsStore.update({'themeMode': mode.name});
  }

  void _syncAnimations() {
    final animate = floatingAnimation && isConnected;

    if (animate) {
      if (!_floatController.isAnimating) {
        _floatController.repeat(reverse: true);
      }
      if (!_pulseController.isAnimating) {
        _pulseController.repeat();
      }
    } else {
      _floatController.stop();
      _floatController.value = 0;
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Name
  // ---------------------------------------------------------------------------

  Future<void> _editName([VoidCallback? after]) async {
    final controller = TextEditingController(
      text: userName == 'Guest' ? '' : userName,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Your name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Guest',
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = controller.text.trim();
                Navigator.pop(dialogContext, v.isEmpty ? 'Guest' : v);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null || !mounted) return;

    setState(() => userName = result);
    after?.call();
    await PrefsStore.update({'userName': result});
  }

  // ---------------------------------------------------------------------------
  // Updates
  // ---------------------------------------------------------------------------

  Future<void> _loadVersion() async {
    final version = await appVersionName();
    if (!mounted) return;
    setState(() => appVersion = version);
  }

  Future<void> _manualUpdateCheck([VoidCallback? after]) async {
    if (checkingUpdate) return;

    setState(() => checkingUpdate = true);
    after?.call();

    final result = await UpdateChecker.check();

    if (!mounted) return;
    setState(() => checkingUpdate = false);
    after?.call();

    switch (result.status) {
      case UpdateStatus.available:
        await PrefsStore.update({
          'lastUpdateCheck': DateTime.now().millisecondsSinceEpoch,
        });
        if (!mounted) return;
        await showUpdateDialog(context, result);
      case UpdateStatus.upToDate:
        await PrefsStore.update({
          'lastUpdateCheck': DateTime.now().millisecondsSinceEpoch,
        });
        _toast('You are up to date (v${result.currentVersion})');
      case UpdateStatus.notConfigured:
        _toast('Update source is not set yet');
      case UpdateStatus.error:
        _toast('Could not check for updates. Check your internet.');
    }
  }

  // ---------------------------------------------------------------------------
  // Connection state
  // ---------------------------------------------------------------------------

  void _addHistory(String name, bool connected) {
    history.insert(0, HistoryEntry(name, connected, DateTime.now()));
    if (history.length > _maxHistory) {
      history.removeRange(_maxHistory, history.length);
    }
  }

  void _markConnected(String name) {
    setState(() {
      deviceName = name;
      isConnected = true;
      status = 'Connected';
      batteryLevel = _pendingBattery.remove(name.toLowerCase());
      _addHistory(name, true);
    });
    _syncAnimations();
    _savePrefs();

    if (popupEnabled) _requestAndShowPopup(name);
  }

  void _markDisconnected() {
    setState(() {
      _addHistory(deviceName, false);
      isConnected = false;
      status = 'Disconnected';
      batteryLevel = null;
    });
    _syncAnimations();
    _savePrefs();
  }

  void _listenForBluetoothEvents() {
    _bluetoothSubscription = bluetoothChannel.receiveBroadcastStream().listen(
      (event) {
        if (!mounted || event is! Map) return;

        final type = event['type']?.toString();

        if (type == 'bluetoothState') {
          final enabled = event['enabled'] == true;
          setState(() => bluetoothOn = enabled);
          if (!enabled && isConnected) _markDisconnected();
          return;
        }

        final rawName = event['name']?.toString();
        final key = rawName?.toLowerCase();

        if (type == 'battery') {
          final battery = event['battery'];
          if (battery is! int || battery < 0 || battery > 100) return;

          if (key == null) {
            if (isConnected) setState(() => batteryLevel = battery);
          } else if (isConnected && key == deviceName.toLowerCase()) {
            setState(() => batteryLevel = battery);
          } else {
            _pendingBattery[key] = battery;
          }
          return;
        }

        final name = rawName ?? 'Bluetooth device';
        final connected = event['connected'] == true;
        final sameDevice =
            isConnected && name.toLowerCase() == deviceName.toLowerCase();

        if (!connected) {
          _pendingBattery.remove(name.toLowerCase());
          if (!sameDevice) return;
          _markDisconnected();
          return;
        }

        if (sameDevice) return;

        _markConnected(name);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => status = 'Bluetooth listener error');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Native calls: Bluetooth, permission, popup
  // ---------------------------------------------------------------------------

  Future<void> _initNative() async {
    _loadBackgroundState();
    await _checkBluetoothPermission();

    if (!bluetoothPermissionGranted) {
      await _requestBluetoothPermission();
    } else {
      await _onBluetoothGranted();
    }
  }

  Future<void> _checkBluetoothPermission() async {
    try {
      final granted =
          await overlayChannel.invokeMethod<bool>('hasBluetoothPermission') ??
          true;
      if (!mounted) return;
      setState(() {
        bluetoothPermissionGranted = granted;
        if (granted) bluetoothPermissionBlocked = false;
      });
    } on MissingPluginException {
      // Native method not added yet.
    } on PlatformException {
      // Ignore.
    }
  }

  Future<void> _requestBluetoothPermission() async {
    try {
      if (bluetoothPermissionBlocked) {
        await overlayChannel.invokeMethod('openAppSettings');
        return;
      }

      final res = await overlayChannel.invokeMethod<Map<dynamic, dynamic>>(
        'requestBluetoothPermission',
      );
      if (!mounted || res == null) return;

      final granted = res['granted'] == true;

      setState(() {
        bluetoothPermissionGranted = granted;
        bluetoothPermissionBlocked = !granted && res['permanent'] == true;
      });

      if (granted) await _onBluetoothGranted();
    } on MissingPluginException {
      // Native method not added yet.
    } on PlatformException {
      // Ignore.
    }
  }

  Future<void> _onBluetoothGranted() async {
    try {
      await overlayChannel.invokeMethod('refreshReceivers');
    } on MissingPluginException {
      // Native method not added yet.
    } on PlatformException {
      // Ignore.
    }

    _loadBluetoothState();
    _loadInitialDevice();
  }

  /// Notice card used for permission / background prompts.
  Widget _noticeCard({
    required IconData icon,
    required String title,
    required String body,
    required List<Widget> actions,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      color: cs.secondaryContainer.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: tt.bodySmall?.copyWith(
              color: cs.onSecondaryContainer,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Row(children: actions),
        ],
      ),
    );
  }

  Widget _buildBluetoothPermissionCard() {
    return _noticeCard(
      icon: Icons.bluetooth_disabled_rounded,
      title: 'Bluetooth access needed',
      body: bluetoothPermissionBlocked
          ? 'Open app settings, tap Permissions, and allow "Nearby devices" '
                'so TWS POP can see your earbuds.'
          : 'Allow "Nearby devices" so TWS POP can detect when your earbuds '
                'connect and read their battery.',
      actions: [
        Expanded(
          child: FilledButton(
            onPressed: _requestBluetoothPermission,
            child: Text(
              bluetoothPermissionBlocked ? 'Open app settings' : 'Allow access',
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Running in the background
  // ---------------------------------------------------------------------------

  Future<void> _loadBackgroundState([VoidCallback? after]) async {
    try {
      final enabled =
          await overlayChannel.invokeMethod<bool>('isWatcherEnabled') ?? true;
      final exempt =
          await overlayChannel.invokeMethod<bool>('isBatteryExempt') ?? true;
      if (!mounted) return;

      setState(() {
        watcherEnabled = enabled;
        batteryExempt = exempt;
      });
      after?.call();
    } on MissingPluginException {
      // Native method not added yet.
    } on PlatformException {
      // Ignore.
    }
  }

  Future<void> _setWatcher(bool value, [VoidCallback? after]) async {
    HapticFeedback.selectionClick();
    setState(() => watcherEnabled = value);
    after?.call();

    try {
      await overlayChannel.invokeMethod('setWatcher', {'enabled': value});
    } on MissingPluginException {
      _toast('Background mode needs native setup');
    } on PlatformException {
      // Ignore.
    }
  }

  Future<void> _requestBatteryExemption() async {
    try {
      await overlayChannel.invokeMethod('requestBatteryExemption');
    } on MissingPluginException {
      _toast('Background mode needs native setup');
    } on PlatformException {
      // Ignore.
    }
  }

  Future<void> _openAutostart() async {
    try {
      final opened =
          await overlayChannel.invokeMethod<bool>('openAutostartSettings') ??
          false;
      if (!opened) {
        _toast('Find TWS POP here and allow autostart / background activity');
      }
    } on MissingPluginException {
      _toast('Background mode needs native setup');
    } on PlatformException {
      // Ignore.
    }
  }

  Widget _buildBackgroundCard() {
    return _noticeCard(
      icon: Icons.battery_saver_rounded,
      title: 'Keep running in background',
      body:
          'Your phone may stop TWS POP after you swipe it away. Allow '
          'unrestricted battery use so the popup keeps working.',
      actions: [
        Expanded(
          child: FilledButton(
            onPressed: _requestBatteryExemption,
            child: const Text('Allow'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            onPressed: _openAutostart,
            child: const Text('Autostart'),
          ),
        ),
      ],
    );
  }

  /// Standard Android-style settings row.
  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    EdgeInsetsGeometry contentPadding = EdgeInsets.zero,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: contentPadding,
      leading: TonalIcon(icon),
      title: Text(
        title,
        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: trailing,
    );
  }

  Future<void> _loadBluetoothState() async {
    try {
      final on = await overlayChannel.invokeMethod<bool>('isBluetoothEnabled');
      if (!mounted || on == null) return;
      setState(() => bluetoothOn = on);
    } on MissingPluginException {
      // Native method not added yet.
    } on PlatformException {
      // Ignore.
    }
  }

  Future<void> _toggleBluetooth(bool value) async {
    HapticFeedback.selectionClick();

    try {
      final direct =
          await overlayChannel.invokeMethod<bool>('setBluetooth', {
            'enable': value,
          }) ??
          false;
      if (!mounted) return;
      if (!direct) _toast('Opening Bluetooth settings...');
    } on MissingPluginException {
      _toast('Bluetooth toggle needs native setup');
    } on PlatformException catch (error) {
      _toast(error.message ?? 'Could not change Bluetooth');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    showToast(context, message);
  }

  Future<void> _loadInitialDevice() async {
    try {
      final result = await overlayChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getConnectedDevice',
      );
      if (!mounted || result == null || isConnected) return;

      final name = result['name']?.toString();
      if (name == null || name.isEmpty) return;

      final battery = result['battery'];

      setState(() {
        deviceName = name;
        isConnected = true;
        status = 'Connected';
        batteryLevel = (battery is int && battery >= 0 && battery <= 100)
            ? battery
            : _pendingBattery.remove(name.toLowerCase());
      });
      _syncAnimations();
    } on MissingPluginException {
      // Native method not added yet.
    } on PlatformException {
      // Ignore; live events will still update the UI.
    }
  }

  Future<void> _refreshPermission() async {
    try {
      final granted =
          await overlayChannel.invokeMethod<bool>('hasOverlayPermission') ??
          false;
      if (!mounted) return;

      setState(() {
        overlayGranted = granted;
        permissionStatus = granted
            ? 'Floating popup permission granted'
            : 'Floating popup permission needed';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        permissionStatus = 'Floating popup permission may be required';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        permissionStatus = 'Permission error: ${error.message ?? "Unknown"}';
      });
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await overlayChannel.invokeMethod('requestOverlayPermission');

      if (!mounted) return;

      setState(() {
        permissionStatus = 'Overlay permission request opened';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;

      setState(() {
        permissionStatus = 'Permission error: ${error.message ?? "Unknown"}';
      });
    } on MissingPluginException {
      if (!mounted) return;

      setState(() {
        permissionStatus = 'Native overlay method is unavailable';
      });
    }
  }

  Future<void> _requestAndShowPopup(String name) async {
    try {
      await overlayChannel.invokeMethod('showPopup', {
        'deviceName': name,
        'durationMs': (popupDuration * 1000).round(),
        'floatingAnimation': floatingAnimation,
        'style': popupStyle,
      });
    } on PlatformException catch (error) {
      if (!mounted) return;

      setState(() {
        permissionStatus =
            'Popup error: ${error.message ?? "Native setup incomplete"}';
      });
    } on MissingPluginException {
      if (!mounted) return;

      setState(() {
        permissionStatus = 'Native popup method needs setup';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Equalizer
  // ---------------------------------------------------------------------------

  Future<void> _eqCall(String method, [Map<String, dynamic>? args]) async {
    try {
      await eqChannel.invokeMethod(method, args);
    } on MissingPluginException {
      // Native equalizer not set up.
    } on PlatformException {
      // Ignore.
    }
  }

  Future<void> _loadEq() async {
    try {
      final raw = await eqChannel.invokeMethod<Map<dynamic, dynamic>>('getEq');
      if (raw == null || !mounted) return;

      final state = EqState.fromMap(raw);

      if (state.available && state.enabled && !state.serviceRunning) {
        await _eqCall('startService');
      }

      if (!mounted) return;
      setState(() => eq = state);
    } on MissingPluginException {
      // Native equalizer not set up.
    } on PlatformException {
      // Ignore.
    } catch (_) {
      // Unexpected data: skip equalizer.
    }
  }

  Future<void> _refreshEq([VoidCallback? after]) async {
    try {
      final raw = await eqChannel.invokeMethod<Map<dynamic, dynamic>>('getEq');
      if (raw == null || !mounted) return;

      final fresh = EqState.fromMap(raw);
      final current = eq;

      setState(() {
        if (current == null) {
          eq = fresh;
        } else {
          current.enabled = fresh.enabled;
          current.sessions = fresh.sessions;
          current.global = fresh.global;
          current.serviceRunning = fresh.serviceRunning;
        }
      });
      after?.call();
    } on MissingPluginException {
      // Native equalizer not set up.
    } on PlatformException {
      // Ignore.
    }
  }

  Future<void> _setEqEnabled(bool value, [VoidCallback? after]) async {
    final e = eq;

    if (e == null || !e.available) {
      _toast('Equalizer is not available on this phone');
      return;
    }

    HapticFeedback.selectionClick();
    setState(() => e.enabled = value);
    after?.call();

    await _eqCall('setEqEnabled', {'enabled': value});

    await Future<void>.delayed(const Duration(milliseconds: 600));
    _refreshEq(after);
  }

  String _bandLabel(int hz) {
    if (hz >= 1000) {
      final k = hz / 1000;
      return hz % 1000 == 0
          ? '${k.toStringAsFixed(0)}k'
          : '${k.toStringAsFixed(1)}k';
    }
    return '$hz';
  }

  String _eqStatus(EqState e) {
    if (!e.enabled) {
      return 'Off. Turn it on to apply the equalizer to music from other apps.';
    }
    if (!e.serviceRunning) return 'Starting...';

    final apps =
        '${e.sessions} app session${e.sessions == 1 ? '' : 's'} attached';
    final global = e.global
        ? 'Global audio mix: attached'
        : 'Global audio mix: not supported on this phone';
    return '$global  ·  $apps';
  }

  Future<void> _openSheet(
    Widget Function(BuildContext context, StateSetter setSheetState) builder,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => builder(context, setSheetState),
        );
      },
    );
  }

  void _openEqualizer() {
    _refreshEq();

    _openSheet((sheetContext, setSheetState) {
      final e = eq;
      final ready = e != null && e.available;

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Equalizer',
                      style: tt.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (ready)
                    Switch(
                      value: e.enabled,
                      onChanged: (v) =>
                          _setEqEnabled(v, () => setSheetState(() {})),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Shape the sound of music from your other apps.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (!ready)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Equalizer is not available. Make sure the native files '
                    'are added, then restart the app.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: e.presets.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      return ChoiceChip(
                        label: Text(e.presets[i]),
                        selected: e.preset == i,
                        showCheckmark: false,
                        onSelected: (_) async {
                          try {
                            final levels = await eqChannel
                                .invokeMethod<List<dynamic>>('usePreset', {
                                  'index': i,
                                });
                            if (levels == null || levels.isEmpty) return;
                            setState(() {
                              e.preset = i;
                              e.levels = levels
                                  .map((x) => (x as num).toInt())
                                  .toList();
                            });
                            setSheetState(() {});
                          } on MissingPluginException {
                            // Ignore.
                          } on PlatformException {
                            // Ignore.
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < e.levels.length; i++)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${(e.levels[i] / 100).toStringAsFixed(1)} dB',
                              style: tt.labelSmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(
                              height: 170,
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Slider(
                                  value: e.levels[i]
                                      .clamp(e.min, e.max)
                                      .toDouble(),
                                  min: e.min.toDouble(),
                                  max: e.max.toDouble(),
                                  onChanged: (v) {
                                    setState(() {
                                      e.levels[i] = v.round();
                                      e.preset = -1;
                                    });
                                    setSheetState(() {});
                                    _eqCall('setBand', {
                                      'band': i,
                                      'level': v.round(),
                                    });
                                  },
                                ),
                              ),
                            ),
                            Text(
                              _bandLabel(e.freqs[i]),
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (e.bassSupported) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Bass boost',
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${(e.bass / 10).round()}%',
                        style: tt.labelLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: e.bass.toDouble().clamp(0.0, 1000.0).toDouble(),
                    min: 0,
                    max: 1000,
                    divisions: 20,
                    onChanged: (v) {
                      setState(() => e.bass = v.round());
                      setSheetState(() {});
                      _eqCall('setBass', {'strength': v.round()});
                    },
                  ),
                ],
              ],
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: cs.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Status',
                            style: tt.labelLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              _refreshEq(() => setSheetState(() {})),
                          tooltip: 'Refresh',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                        ),
                      ],
                    ),
                    Text(
                      ready ? _eqStatus(e) : 'Unavailable',
                      style: tt.bodySmall?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start music in your player app, then tap refresh. If '
                      'app sessions stays at 0, that app does not share its '
                      'audio with system equalizers.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String get deviceImage {
    final name = deviceName.toLowerCase();

    if (name.contains('airdopes 219') || name.contains('airdopes219')) {
      return 'assets/images/airdopes219.png';
    }

    if (name.contains('airdopes 131') || name.contains('airdopes131')) {
      return 'assets/images/airdopes131.png';
    }

    if (name.contains('oneplus nord buds 2r') ||
        name.contains('nord buds 2r')) {
      return 'assets/images/oneplus_nord_buds_2r.png';
    }

    // Sony WH-CH720N shows up as "WH-CH720N", so match that spelling too.
    if (name.contains('wh-ch720n') ||
        name.contains('wh720n') ||
        name.contains('wh-720n')) {
      return 'assets/images/sony_heaphones.png';
    }

    if (name.contains('stone 193 pro') || name.contains('stone193pro')) {
      return 'assets/images/stone_193_pro.png';
    }

    // Generic boAt brand detection
    if (name.contains('boat') ||
        name.contains('airdopes') ||
        name.contains('stone ') ||
        name.contains('stone-') ||
        name.contains('nirvana') ||
        name.contains('immortal') ||
        name.contains('rockerz') ||
        name.contains('bassheads')) {
      return 'assets/images/boat_logo.png';
    }

    // OnePlus
    if (name.contains('oneplus') ||
        name.contains('one plus') ||
        name.contains('nord buds')) {
      return 'assets/images/oneplus_logo.png';
    }

    // Noise
    if (name.contains('noise') ||
        name.contains('buds vs') ||
        name.contains('air buds')) {
      return 'assets/images/noise_logo.png';
    }

    // Hammer
    if (name.contains('hammer')) {
      return 'assets/images/hammer_logo.png';
    }

    // Apple
    if (name.contains('airpods') ||
        name.contains('airpods pro') ||
        name.contains('airpods max') ||
        name.contains('apple')) {
      return 'assets/images/apple_logo.png';
    }

    // Nothing
    if (name.contains('nothing') || name.contains('cmf')) {
      return 'assets/images/nothing_logo.png';
    }

    // JBL
    if (name.contains('jbl')) {
      return 'assets/images/jbl_logo.png';
    }

    // Realme
    if (name.contains('realme')) {
      return 'assets/images/realme_logo.png';
    }

    // Redmi / Xiaomi / Poco
    if (name.contains('redmi') ||
        name.contains('xiaomi') ||
        name.contains('poco')) {
      return 'assets/images/xiaomi_logo.png';
    }

    // Samsung
    if (name.contains('samsung') || name.contains('galaxy buds')) {
      return 'assets/images/samsung_logo.png';
    }

    // Oppo
    if (name.contains('oppo') || name.contains('enco')) {
      return 'assets/images/oppo_logo.png';
    }

    // Vivo
    if (name.contains('vivo') || name.contains('tws air')) {
      return 'assets/images/vivo_logo.png';
    }

    // Boult
    if (name.contains('boult')) {
      return 'assets/images/boult_logo.png';
    }

    // Zebronics
    if (name.contains('zebronics') || name.contains('zeb')) {
      return 'assets/images/zebronics_logo.png';
    }

    return 'assets/images/default_earbuds.png';
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? '$hh:$mm' : '${t.day}/${t.month} $hh:$mm';
  }

  // ---------------------------------------------------------------------------
  // Settings sheet
  // ---------------------------------------------------------------------------

  /// Popup previews are always light, because the popup itself is always light.
  Widget _stylePreview(String id) {
    switch (id) {
      case 'tonal':
        return Container(
          width: 38,
          height: 26,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 5),
          decoration: BoxDecoration(
            color: _popupTonal,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
        );
      case 'minimal':
        return Container(
          width: 38,
          height: 26,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _popupBorder),
          ),
        );
      case 'compact':
        return Container(
          width: 38,
          height: 14,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(7),
          ),
        );
      default:
        return Container(
          width: 38,
          height: 26,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    }
  }

  Widget _styleOption(PopupStyle style, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _popupSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? cs.primary : cs.outlineVariant,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: Center(child: _stylePreview(style.id)),
            ),
            const SizedBox(height: 6),
            Text(
              style.label,
              style: tt.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    _openSheet((sheetContext, setSheetState) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              AppCard(
                padding: EdgeInsets.zero,
                radius: 24,
                color: cs.surfaceContainerHighest,
                child: ListTile(
                  onTap: () => _editName(() => setSheetState(() {})),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    child: Text(
                      userName.isEmpty
                          ? '?'
                          : userName.characters.first.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(
                    userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text('Tap to change your name'),
                  trailing: Icon(Icons.edit_rounded, color: cs.primary),
                ),
              ),

              // ---- Appearance ----
              const SectionLabel('Appearance'),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {themeModeNotifier.value},
                  onSelectionChanged: (s) {
                    _setThemeMode(s.first);
                    setSheetState(() {});
                  },
                ),
              ),

              // ---- Background ----
              const SectionLabel('Background'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep running in background'),
                subtitle: const Text(
                  'Detect earbuds and show the popup even when the app is '
                  'closed',
                ),
                value: watcherEnabled,
                onChanged: (v) => _setWatcher(v, () => setSheetState(() {})),
              ),
              _tile(
                icon: Icons.battery_charging_full_rounded,
                title: 'Battery optimization',
                subtitle: batteryExempt
                    ? 'Unrestricted'
                    : 'Restricted, tap to allow',
                onTap: _requestBatteryExemption,
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
              _tile(
                icon: Icons.rocket_launch_rounded,
                title: 'Autostart',
                subtitle: 'Needed on Xiaomi, Oppo, Vivo, Realme, Samsung',
                onTap: _openAutostart,
                trailing: const Icon(Icons.chevron_right_rounded),
              ),

              // ---- Popup ----
              const SectionLabel('Popup'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Connection popup'),
                subtitle: const Text(
                  'Show the popup when an audio device connects',
                ),
                value: popupEnabled,
                onChanged: (value) {
                  setState(() => popupEnabled = value);
                  setSheetState(() {});
                  _savePrefs();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Floating artwork animation'),
                subtitle: const Text('Keep the gentle artwork movement'),
                value: floatingAnimation,
                onChanged: (value) {
                  setState(() => floatingAnimation = value);
                  setSheetState(() {});
                  _syncAnimations();
                  _savePrefs();
                },
              ),
              const SizedBox(height: 14),
              Text(
                'Popup style',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'The popup always uses a light design.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final style in popupStyles)
                    _styleOption(style, popupStyle == style.id, () {
                      setState(() => popupStyle = style.id);
                      setSheetState(() {});
                      _savePrefs();
                    }),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Popup display duration',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${popupDuration.toStringAsFixed(1)} sec',
                    style: tt.labelLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Slider(
                value: popupDuration,
                min: 5,
                max: 15,
                divisions: 20,
                onChanged: (value) {
                  setState(() => popupDuration = value);
                  setSheetState(() {});
                },
                onChangeEnd: (_) => _savePrefs(),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _requestAndShowPopup(
                    isConnected ? deviceName : 'Test Earbuds',
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Preview popup'),
                ),
              ),

              // ---- About ----
              const SectionLabel('About'),
              _tile(
                icon: Icons.system_update_rounded,
                title: 'Check for updates',
                subtitle: checkingUpdate
                    ? 'Checking...'
                    : appVersion.isEmpty
                    ? 'Tap to check'
                    : 'Version $appVersion  ·  tap to check',
                onTap: () => _manualUpdateCheck(() => setSheetState(() {})),
                trailing: checkingUpdate
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  Widget _historyRow(HistoryEntry e) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: TonalIcon(
        e.connected ? Icons.link_rounded : Icons.link_off_rounded,
        size: 36,
      ),
      title: Text(
        e.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        e.connected ? 'Connected' : 'Disconnected',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: Text(
        _formatTime(e.time),
        style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }

  void _openHistory() {
    _openSheet((sheetContext, setSheetState) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Connection history',
                      style: tt.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (history.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(history.clear);
                        setSheetState(() {});
                        _savePrefs();
                      },
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (history.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'No connections yet',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: history.map(_historyRow).toList(),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Home widgets
  // ---------------------------------------------------------------------------

  Widget _buildBluetoothPill() {
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            bluetoothOn
                ? Icons.bluetooth_rounded
                : Icons.bluetooth_disabled_rounded,
            size: 18,
            color: bluetoothOn ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 2),
          SizedBox(
            width: 46,
            height: 32,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(value: bluetoothOn, onChanged: _toggleBluetooth),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceArtwork() {
    final Widget artwork = AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: isConnected
          ? Image.asset(
              deviceImage,
              key: ValueKey(deviceImage),
              width: 130,
              height: 130,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.headphones_rounded,
                  key: const ValueKey('fallback'),
                  size: 76,
                  color: cs.primary,
                );
              },
            )
          : Icon(
              bluetoothOn
                  ? Icons.bluetooth_searching_rounded
                  : Icons.bluetooth_disabled_rounded,
              key: ValueKey('disconnected-$bluetoothOn'),
              size: 76,
              color: bluetoothOn ? cs.primary : cs.onSurfaceVariant,
            ),
    );

    return AnimatedBuilder(
      animation: _floatController,
      child: artwork,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_floatController.value);
        return Transform.translate(offset: Offset(0, -7 * t), child: child);
      },
    );
  }

  Widget _buildArtworkStage() {
    return SizedBox(
      width: 200,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isConnected && floatingAnimation)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final t = _pulseController.value;
                return Opacity(
                  opacity: ((1 - t) * 0.5).clamp(0.0, 1.0),
                  child: Container(
                    width: 150 + 40 * t,
                    height: 150 + 40 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary, width: 1.5),
                    ),
                  ),
                );
              },
            ),
          Container(
            width: 160,
            height: 160,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer.withValues(
                alpha: isConnected ? 0.55 : 0.3,
              ),
            ),
            child: _buildDeviceArtwork(),
          ),
        ],
      ),
    );
  }

  Widget _buildBatterySection() {
    if (!isConnected) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 20),
        Divider(color: cs.outlineVariant, height: 1),
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(Icons.battery_6_bar_rounded, color: cs.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Device battery',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            Text(
              batteryLevel == null ? '--' : '$batteryLevel%',
              style: tt.titleMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (batteryLevel != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: batteryLevel! / 100,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          if (batteryLevel! <= 20) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.battery_alert_rounded, color: cs.primary, size: 16),
                const SizedBox(width: 7),
                Text(
                  'Battery running low',
                  style: tt.bodySmall?.copyWith(color: cs.primary),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDeviceCard() {
    return AppCard(
      padding: const EdgeInsets.all(22),
      radius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _buildArtworkStage()),
          const SizedBox(height: 10),
          Text(
            isConnected ? 'Current device' : 'Ready when you are',
            style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            deviceName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? cs.primary : cs.outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          _buildBatterySection(),
        ],
      ),
    );
  }

  Widget _buildEqTile() {
    final e = eq;
    final available = e != null && e.available;
    final on = available && e.enabled;

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      radius: 24,
      child: _tile(
        icon: Icons.equalizer_rounded,
        title: 'Equalizer',
        subtitle: !available
            ? 'Tap to set up'
            : on
            ? 'On  ·  works across your apps'
            : 'Off  ·  tap to tune your sound',
        onTap: _openEqualizer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        trailing: available
            ? Switch(value: e.enabled, onChanged: (v) => _setEqEnabled(v))
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Widget _buildHistoryCard() {
    final recent = history.take(4).toList();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Recent activity',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (history.isNotEmpty)
                TextButton(
                  onPressed: _openHistory,
                  child: const Text('View all'),
                ),
            ],
          ),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  'No connections yet',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            ...recent.map(_historyRow),
        ],
      ),
    );
  }

  Widget _buildStyleTile() {
    final label = popupStyles
        .firstWhere((s) => s.id == popupStyle, orElse: () => popupStyles.first)
        .label;

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      radius: 24,
      child: _tile(
        icon: Icons.auto_awesome_rounded,
        title: 'Popup style',
        subtitle: '$label  ·  tap to change',
        onTap: _openSettings,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Reveal(
                index: 0,
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const LogoMark(size: 38),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'TWS POP',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                    _buildBluetoothPill(),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _openSettings,
                      tooltip: 'Settings',
                      icon: const Icon(Icons.settings_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Reveal(
                index: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _editName,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        'Hello, $userName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Every connection. A little more personal.',
                      style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (!bluetoothPermissionGranted) ...[
                _buildBluetoothPermissionCard(),
                const SizedBox(height: 12),
              ],
              Reveal(index: 2, child: _buildDeviceCard()),
              const SizedBox(height: 12),
              if (watcherEnabled && !batteryExempt) ...[
                _buildBackgroundCard(),
                const SizedBox(height: 12),
              ],
              Reveal(index: 3, child: _buildEqTile()),
              const SizedBox(height: 12),
              Reveal(index: 4, child: _buildHistoryCard()),
              const SizedBox(height: 12),
              Reveal(index: 5, child: _buildStyleTile()),
              const SizedBox(height: 20),
              Reveal(
                index: 6,
                child: Column(
                  children: [
                    if (overlayGranted)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            permissionStatus,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: requestOverlayPermission,
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Enable floating popup'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        permissionStatus,
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Made for your everyday sound',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
