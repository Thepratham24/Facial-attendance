import 'package:face_attendance/screens/Admin%20Side/admin_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'services/api_service.dart';
import 'services/ml_service.dart';
import 'services/db_service.dart';
import 'screens/Result_StartLogin Side/login_screen.dart';


List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } catch (e) {
    print("Camera Error: $e");
  }

  // 1. Services Init
  await MLService().initialize();
  // await DBService().initialize(); // Local settings ke liye
  await ApiService.loadTokens();
  // 🔴 2. TOKEN RELOAD (Ye line zaroori hai)
  // Ye check karega aur token ko wapas variable mein daal dega
  bool userIsLoggedIn = await ApiService.tryAutoLogin();

  runApp(MyApp(startScreen: userIsLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool startScreen;

  const MyApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Face Attendance',
      theme: ThemeData(primarySwatch: Colors.indigo),
      // Agar Login hai to AttendanceScreen, nahi to LoginScreen
      home: LoginScreen(autoLogin: true,)
    );
  }
}