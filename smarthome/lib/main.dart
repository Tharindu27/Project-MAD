import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'models/floor_model.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/floors/floor_detail_screen.dart';
import 'screens/floors/floors_screen.dart';
import 'screens/security/security_screen.dart';
import 'screens/usage_reports/usage_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(SmartHomeApp(authService: AuthService()));
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home Monitoring',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      routes: {
        '/home': (context) => HomeShell(authService: authService),
        '/login': (context) => LoginScreen(authService: authService),
        '/register': (context) => RegisterScreen(authService: authService),
        '/floors': (context) => FloorsScreen(),
        '/floor': (context) {
          final floor = ModalRoute.of(context)?.settings.arguments;
          if (floor is FloorModel) {
            return FloorDetailScreen(floor: floor);
          }
          return const Scaffold(body: Center(child: Text('Floor not found')));
        },
      },
      home: AuthGate(authService: authService),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user == null) {
          return LoginScreen(authService: authService);
        }
        return HomeShell(authService: authService);
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.authService});

  final AuthService authService;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription<List<Map<String, dynamic>>>? _safetyAlertSubscription;
  final Set<String> _shownSafetyAlertIds = <String>{};
  bool _isAlertDialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firestoreService.startSafetyWatchdog();
    _startSafetyAlertListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _firestoreService.startSafetyWatchdog();
      _firestoreService.enforceSafetyCutoffsNow();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Best-effort final sweep before app is suspended/killed.
      _firestoreService.enforceSafetyCutoffsNow();
      _firestoreService.stopSafetyWatchdog();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _firestoreService.stopSafetyWatchdog();
    _safetyAlertSubscription?.cancel();
    super.dispose();
  }

  void _startSafetyAlertListener() {
    _safetyAlertSubscription?.cancel();
    _safetyAlertSubscription = _firestoreService.safetyCutoffAlertsStream().listen((alerts) {
      if (!mounted || alerts.isEmpty) return;

      alerts.sort((a, b) {
        final aTs = a['createdAt'];
        final bTs = b['createdAt'];
        final aMillis = aTs is DateTime
            ? aTs.millisecondsSinceEpoch
            : (aTs?.millisecondsSinceEpoch ?? 0);
        final bMillis = bTs is DateTime
            ? bTs.millisecondsSinceEpoch
            : (bTs?.millisecondsSinceEpoch ?? 0);
        return bMillis.compareTo(aMillis);
      });

      for (final alert in alerts) {
        final id = (alert['id'] ?? '').toString();
        if (id.isEmpty || _shownSafetyAlertIds.contains(id)) {
          continue;
        }
        _shownSafetyAlertIds.add(id);
        if (_isAlertDialogVisible) {
          _showSafetyAlertSnackBar(alert);
        } else {
          _showSafetyAlertDialog(alert);
        }
        break;
      }
    });
  }

  Future<void> _showSafetyAlertSnackBar(Map<String, dynamic> alert) async {
    if (!mounted) return;

    final alertId = (alert['id'] ?? '').toString();
    final floorName = (alert['floorName'] ?? 'Unknown Floor').toString();
    final deviceName = (alert['deviceName'] ?? 'Unknown Device').toString();
    final message = (alert['message'] ??
            'Safety Cutoff Triggered: [$floorName] [$deviceName] was turned OFF automatically due to exceeding max_on_duration.')
        .toString();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
        ),
      );

    if (alertId.isNotEmpty) {
      await _firestoreService.acknowledgeSafetyAlert(alertId);
    }
  }

  Future<void> _showSafetyAlertDialog(Map<String, dynamic> alert) async {
    if (!mounted || _isAlertDialogVisible) return;
    _isAlertDialogVisible = true;

    final alertId = (alert['id'] ?? '').toString();
    final floorName = (alert['floorName'] ?? 'Unknown Floor').toString();
    final deviceName = (alert['deviceName'] ?? 'Unknown Device').toString();
    final message = (alert['message'] ??
            'Safety Cutoff Triggered: [$floorName] [$deviceName] was turned OFF automatically due to exceeding max_on_duration.')
        .toString();

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Safety Cutoff Triggered'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      _isAlertDialogVisible = false;
      if (alertId.isNotEmpty) {
        await _firestoreService.acknowledgeSafetyAlert(alertId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      FloorsScreen(),
      SecurityScreen(),
      UsageScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Home Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await widget.authService.signOut();
              if (mounted) Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_work), label: 'Floors'),
          NavigationDestination(icon: Icon(Icons.videocam), label: 'Security'),
          NavigationDestination(icon: Icon(Icons.analytics), label: 'Usage'),
        ],
      ),
    );
  }
}