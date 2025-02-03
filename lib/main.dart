import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => DatabaseHelper()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

// ----------------------
// Home Screen
// ----------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext context = this.context;
      Provider.of<DatabaseHelper>(context, listen: false).initDatabase();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance App')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                final BuildContext context = this.context;
                final auth = Provider.of<AuthService>(context, listen: false);
                final location = Provider.of<LocationService>(context, listen: false);
                final db = Provider.of<DatabaseHelper>(context, listen: false);

                // Authenticate with fingerprint
                bool authenticated = await auth.authenticate();
                if (!authenticated) return;

                // Get current location
                Position? position = await location.getCurrentLocation();
                if (position == null) return;

                // Record attendance
                await db.insertAttendance(
                  checkIn: DateTime.now(),
                  latitude: position.latitude,
                  longitude: position.longitude,
                );

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Checked in successfully!')),
                );
              },
              child: const Text('Check In'),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------
// Auth Service (Fingerprint)
// ----------------------
class AuthService extends ChangeNotifier {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Authenticate to check in',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } catch (e) {
      return false;
    }
  }
}

// ----------------------
// Location Service
// ----------------------
class LocationService extends ChangeNotifier {
  Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          return null;
        }
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      return null;
    }
  }
}

// ----------------------
// Database Helper
// ----------------------
class DatabaseHelper extends ChangeNotifier {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'attendance.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            check_in TEXT,
            latitude REAL,
            longitude REAL
          )
        ''');
      },
    );
  }

  Future<void> initDatabase() async {
    await database;
  }

  Future<void> insertAttendance({
    required DateTime checkIn,
    required double latitude,
    required double longitude,
  }) async {
    final db = await database;
    await db.insert('attendance', {
      'check_in': checkIn.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
    });
    notifyListeners();
  }
}