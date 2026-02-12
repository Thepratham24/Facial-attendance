import 'package:face_attendance/screens/Admin%20Side/admin_dashboard_screen.dart';

import 'package:flutter/material.dart';

import 'package:device_info_plus/device_info_plus.dart';

import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../services/api_service.dart';

import '../Employee Side/employee_login_screen.dart';

import '../Admin Side/admin_login_screen.dart';

import '../Employee Side/employee_dashboard.dart';

import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  final bool autoLogin; // 🔴 Control Auto Login Logic

// Default true taaki App start hone par check kare

  const LoginScreen({super.key, this.autoLogin = true});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // static const String ADMIN_DEVICE_ID = "V1TDS35H.83-20-5-9";

  bool _isAdminDevice = false;

  bool _isLoading = true;

  final ApiService _apiService = ApiService();

  late AnimationController _controller;

  late Animation<double> _fadeAnimation;

  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _startInitialization();

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }
  Future<void> _startInitialization() async {
    setState(() => _isLoading = true); // Loader on

    // Step 1: Pehle device verify hone ka intezar karein
    await _checkDevice();

    // Step 2: Confirmation ke baad navigation check karein
    if (widget.autoLogin) {
      _checkAutoLogin();
    } else {
      setState(() => _isLoading = false);
    }
  }
// void _checkAutoLogin() async {

// SharedPreferences prefs = await SharedPreferences.getInstance();

//

// String? empId = prefs.getString('_id');

// String? empName = prefs.getString('emp_name');

// String? token = prefs.getString('token');

// String? adminToken = prefs.getString('adminToken');

//

// if (mounted) {

// if (empId != null && empName != null && token != null) {

// Navigator.pushReplacement(

// context,

// MaterialPageRoute(builder: (context) => EmployeeDashboard(

// employeeName: empName,

// employeeId: empId

// )),

// );

// } else if (adminToken != null) {

// Navigator.pushReplacement(

// context,

// MaterialPageRoute(builder: (context) => const AdminDashboard()),

// );

// } else {

// setState(() => _isLoading = false);

// }

// }

// }

// changedddd

  void _checkAutoLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

// Data Load Karo

    String? token = prefs.getString('token');

    String? empName = prefs.getString('emp_name');

    String? empId = prefs.getString('employeeId'); // Standard Key

// Admin Check

    String? adminToken = prefs.getString('saved_token');

    if (mounted) {
// ✅ Agar Employee ka sara data hai, to dashboard bhejo

      if (token != null && empId != null && empName != null) {
        print("✅ Auto Login: Employee ($empName)");

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  EmployeeDashboard(employeeName: empName, employeeId: empId)),
        );
      }

// ✅ Agar Admin hai

      else if (adminToken != null) {
        print("✅ Auto Login: Admin");

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboard()),
        );
      }

// ❌ Koi nahi hai

      else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkDevice() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    String currentId = '';

    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

        currentId = androidInfo.id; // Unique ID for Android
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;

        currentId = iosInfo.identifierForVendor ?? '';
      }

// 🔴 API Call to verify admin status

      bool isDeviceAdmin = await _apiService.checkAdminDevice(currentId);

// Shared Preferences mein save karo

      SharedPreferences prefs = await SharedPreferences.getInstance();

      await prefs.setBool('is_admin_device', isDeviceAdmin);

      if (mounted) {
        setState(() {
          _isAdminDevice = isDeviceAdmin;

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("------------Device Check Error: $e");

      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _checkAllPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (mounted) {
        _showStubbornDialog("GPS Required", "Please enable GPS to proceed.",
            () => Geolocator.openLocationSettings());
      }

      return false;
    }

    LocationPermission locPermission = await Geolocator.checkPermission();

    if (locPermission == LocationPermission.denied) {
      locPermission = await Geolocator.requestPermission();

      if (locPermission == LocationPermission.denied) {
        if (mounted) {
          _showStubbornDialog(
              "Location Permission",
              "We need Location access to verify attendance.",
              () => Geolocator.openAppSettings());
        }

        return false;
      }
    }

    if (locPermission == LocationPermission.deniedForever) {
      if (mounted) {
        _showStubbornDialog(
            "Location Blocked",
            "Location is permanently denied. Go to Settings and allow it.",
            () => Geolocator.openAppSettings());
      }

      return false;
    }

    var camStatus = await Permission.camera.status;

    if (!camStatus.isGranted) {
      camStatus = await Permission.camera.request();

      if (!camStatus.isGranted) {
        if (mounted) {
          _showStubbornDialog(
              "Camera Permission",
              "We need Camera access to scan faces.",
              () => Geolocator.openAppSettings());
        }

        return false;
      }
    }

    return true;
  }

  Future<void> _handleEmployeeClick() async {
    bool hasPermissions = await _checkAllPermissions();

    if (!hasPermissions) return;

    if (mounted) {
      Navigator.push(context,
          MaterialPageRoute(builder: (context) => const EmployeeLoginScreen()));
    }
  }

  void _handleAdminClick() async {
    bool hasPermissions = await _checkAllPermissions();

    if (!hasPermissions) return;

// Admin ke liye hum check kar lete hain agar already session valid hai

    bool isLoggedIn = await ApiService.tryAutoLogin();

    if (!mounted) return;

    if (isLoggedIn) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AdminDashboard()),
        (route) => false,
      );
    } else {
      Navigator.push(context,
          MaterialPageRoute(builder: (context) => const AdminLoginScreen()));
    }
  }

  void _showStubbornDialog(
      String title, String message, Function onOpenSettings) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF252A40),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title,
              style: const TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => onOpenSettings(),
              child: const Text("Open Settings",
                  style: TextStyle(color: Color(0xFF6C63FF))),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("I have Enabled it"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1F38),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1F38),
      body: Stack(
        children: [
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              height: 250,
              width: 250,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6C63FF).withOpacity(0.15)),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -80,
            child: Container(
              height: 300,
              width: 300,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2E93FF).withOpacity(0.1)),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 150,
                            width: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6C63FF), Color(0xFF2E93FF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: const Color(0xFF6C63FF)
                                        .withOpacity(0.4),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                    offset: const Offset(0, 10))
                              ],
                            ),
                            child: const Icon(Icons.face_unlock_rounded,
                                size: 75, color: Colors.white),
                          ),
                          const SizedBox(height: 40),
                          const Text("Face Attendance",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15, vertical: 8),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.1))),
                            child: const Text("Secure • Fast • Contactless",
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5)),
                          ),
                          const SizedBox(height: 60),
                          _buildPremiumCard(
                            title: "Employee Login",
                            subtitle: "Mark Attendance",
                            icon: Icons.fingerprint,
                            gradientColors: [
                              const Color(0xFF6C63FF),
                              const Color(0xFF8B5CF6)
                            ],
                            onTap: _handleEmployeeClick,
                          ),
                          const SizedBox(height: 20),
                          if (_isAdminDevice)
                            _buildPremiumCard(
                              title: "Admin Portal",
                              subtitle: "Dashboard & Reports",
                              icon: Icons.shield_outlined,
                              gradientColors: [
                                const Color(0xFF2E93FF),
                                const Color(0xFF00BFA5)
                              ],
                              onTap: _handleAdminClick,
                            ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumCard(
      {required String title,
      required String subtitle,
      required IconData icon,
      required List<Color> gradientColors,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: const Color(0xFF252A40),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 15,
                  offset: const Offset(0, 8))
            ]),
        child: Row(
          children: [
            Container(
              height: 55,
              width: 55,
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: gradientColors[0].withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ]),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5), fontSize: 13))
                  ]),
            ),
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white70, size: 14)),
          ],
        ),
      ),
    );
  }
}

// import 'package:face_attendance/screens/Admin%20Side/admin_dashboard_screen.dart';
// import 'package:flutter/material.dart';
// import 'package:device_info_plus/device_info_plus.dart';
// import 'dart:io';
// import 'package:geolocator/geolocator.dart';
// import 'package:permission_handler/permission_handler.dart';
// import '../../services/api_service.dart';
// import '../Employee Side/employee_login_screen.dart';
// import '../Admin Side/admin_login_screen.dart';
// import '../Employee Side/employee_dashboard.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// class LoginScreen extends StatefulWidget {
//   final bool autoLogin; // 🔴 Control Auto Login Logic
//
//   // Default true taaki App start hone par check kare
//   const LoginScreen({super.key, this.autoLogin = true});
//
//   @override
//   State<LoginScreen> createState() => _LoginScreenState();
// }
//
// class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
//   static const String ADMIN_DEVICE_ID = "V1TDS35H.83-20-5-8";
//   bool _isAdminDevice = false;
//   bool _isLoading = true;
//
//   late AnimationController _controller;
//   late Animation<double> _fadeAnimation;
//   late Animation<Offset> _slideAnimation;
//
//   @override
//   void initState() {
//     super.initState();
//     _controller = AnimationController(
//       duration: const Duration(milliseconds: 1000),
//       vsync: this,
//     );
//     _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
//       CurvedAnimation(parent: _controller, curve: Curves.easeIn),
//     );
//     _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
//       CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
//     );
//
//     _checkDevice();
//
//     // 🔴 AGAR AutoLogin TRUE HAI TO HI CHECK KARO
//     if (widget.autoLogin) {
//       _checkAutoLogin();
//     } else {
//       setState(() => _isLoading = false);
//     }
//
//     _controller.forward();
//   }
//
//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }
//
//   // void _checkAutoLogin() async {
//   //   SharedPreferences prefs = await SharedPreferences.getInstance();
//   //
//   //   String? empId = prefs.getString('_id');
//   //   String? empName = prefs.getString('emp_name');
//   //   String? token = prefs.getString('token');
//   //   String? adminToken = prefs.getString('adminToken');
//   //
//   //   if (mounted) {
//   //     if (empId != null && empName != null && token != null) {
//   //       Navigator.pushReplacement(
//   //         context,
//   //         MaterialPageRoute(builder: (context) => EmployeeDashboard(
//   //             employeeName: empName,
//   //             employeeId: empId
//   //         )),
//   //       );
//   //     } else if (adminToken != null) {
//   //       Navigator.pushReplacement(
//   //         context,
//   //         MaterialPageRoute(builder: (context) => const AdminDashboard()),
//   //       );
//   //     } else {
//   //       setState(() => _isLoading = false);
//   //     }
//   //   }
//   // }
//
//
//   // changedddd
//   void _checkAutoLogin() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//
//     // Data Load Karo
//     String? token = prefs.getString('token');
//     String? empName = prefs.getString('emp_name');
//     String? empId = prefs.getString('employeeId'); // Standard Key
//
//     // Admin Check
//     String? adminToken = prefs.getString('saved_token');
//
//     if (mounted) {
//       // ✅ Agar Employee ka sara data hai, to dashboard bhejo
//       if (token != null && empId != null && empName != null) {
//         print("✅ Auto Login: Employee ($empName)");
//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(builder: (context) => EmployeeDashboard(
//               employeeName: empName,
//               employeeId: empId
//           )),
//         );
//       }
//       // ✅ Agar Admin hai
//       else if (adminToken != null) {
//         print("✅ Auto Login: Admin");
//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(builder: (context) => const AdminDashboard()),
//         );
//       }
//       // ❌ Koi nahi hai
//       else {
//         setState(() => _isLoading = false);
//       }
//     }
//   }
//
//   void _checkDevice() async {
//     final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
//     String currentId = '';
//     try {
//       if (Platform.isAndroid) {
//         AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
//         currentId = androidInfo.id;
//       } else if (Platform.isIOS) {
//         IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
//         currentId = iosInfo.identifierForVendor ?? '';
//       }
//     } catch (e) {
//       debugPrint("Device Check Error: $e");
//     }
//
//     if (mounted) {
//       setState(() {
//         _isAdminDevice = (currentId == ADMIN_DEVICE_ID);
//       });
//     }
//   }
//
//   Future<bool> _checkAllPermissions() async {
//     bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
//     if (!serviceEnabled) {
//       if (mounted) {
//         _showStubbornDialog("GPS Required", "Please enable GPS to proceed.", () => Geolocator.openLocationSettings());
//       }
//       return false;
//     }
//
//     LocationPermission locPermission = await Geolocator.checkPermission();
//     if (locPermission == LocationPermission.denied) {
//       locPermission = await Geolocator.requestPermission();
//       if (locPermission == LocationPermission.denied) {
//         if (mounted) {
//           _showStubbornDialog("Location Permission", "We need Location access to verify attendance.", () => Geolocator.openAppSettings());
//         }
//         return false;
//       }
//     }
//     if (locPermission == LocationPermission.deniedForever) {
//       if (mounted) {
//         _showStubbornDialog("Location Blocked", "Location is permanently denied. Go to Settings and allow it.", () => Geolocator.openAppSettings());
//       }
//       return false;
//     }
//
//     var camStatus = await Permission.camera.status;
//     if (!camStatus.isGranted) {
//       camStatus = await Permission.camera.request();
//       if (!camStatus.isGranted) {
//         if (mounted) {
//           _showStubbornDialog("Camera Permission", "We need Camera access to scan faces.", () => Geolocator.openAppSettings());
//         }
//         return false;
//       }
//     }
//     return true;
//   }
//
//   Future<void> _handleEmployeeClick() async {
//     bool hasPermissions = await _checkAllPermissions();
//     if (!hasPermissions) return;
//     if (mounted) {
//       Navigator.push(context, MaterialPageRoute(builder: (context) => const EmployeeLoginScreen()));
//     }
//   }
//
//   void _handleAdminClick() async {
//     bool hasPermissions = await _checkAllPermissions();
//     if (!hasPermissions) return;
//
//     // Admin ke liye hum check kar lete hain agar already session valid hai
//     bool isLoggedIn = await ApiService.tryAutoLogin();
//     if (!mounted) return;
//
//     if (isLoggedIn) {
//       Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const AdminDashboard()),(route) => false,);
//     } else {
//       Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminLoginScreen()));
//     }
//   }
//
//   void _showStubbornDialog(String title, String message, Function onOpenSettings) {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (ctx) => PopScope(
//         canPop: false,
//         child: AlertDialog(
//           backgroundColor: const Color(0xFF252A40),
//           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//           title: Text(title, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
//           content: Text(message, style: const TextStyle(color: Colors.white70)),
//           actions: [
//             TextButton(
//               onPressed: () => onOpenSettings(),
//               child: const Text("Open Settings", style: TextStyle(color: Color(0xFF6C63FF))),
//             ),
//             FilledButton(
//               style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
//               onPressed: () => Navigator.pop(ctx),
//               child: const Text("I have Enabled it"),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (_isLoading) {
//       return const Scaffold(
//         backgroundColor: Color(0xFF1A1F38),
//         body: Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
//       );
//     }
//
//     return Scaffold(
//       backgroundColor: const Color(0xFF1A1F38),
//       body: Stack(
//         children: [
//           Positioned(
//             top: -60, left: -60,
//             child: Container(
//               height: 250, width: 250,
//               decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF6C63FF).withOpacity(0.15)),
//             ),
//           ),
//           Positioned(
//             bottom: -80, right: -80,
//             child: Container(
//               height: 300, width: 300,
//               decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2E93FF).withOpacity(0.1)),
//             ),
//           ),
//           SafeArea(
//             child: Center(
//               child: SingleChildScrollView(
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 30),
//                   child: FadeTransition(
//                     opacity: _fadeAnimation,
//                     child: SlideTransition(
//                       position: _slideAnimation,
//                       child: Column(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           Container(
//                             height: 150, width: 150,
//                             decoration: BoxDecoration(
//                               shape: BoxShape.circle,
//                               gradient: const LinearGradient(
//                                 colors: [Color(0xFF6C63FF), Color(0xFF2E93FF)],
//                                 begin: Alignment.topLeft, end: Alignment.bottomRight,
//                               ),
//                               boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.4), blurRadius: 30, spreadRadius: 5, offset: const Offset(0, 10))],
//                             ),
//                             child: const Icon(Icons.face_unlock_rounded, size: 75, color: Colors.white),
//                           ),
//                           const SizedBox(height: 40),
//                           const Text("Face Attendance", style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
//                           const SizedBox(height: 10),
//                           Container(
//                             padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
//                             decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.1))),
//                             child: const Text("Secure  •  Fast  •  Contactless", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
//                           ),
//                           const SizedBox(height: 60),
//                           _buildPremiumCard(
//                             title: "Employee Login", subtitle: "Mark Attendance", icon: Icons.fingerprint,
//                             gradientColors: [const Color(0xFF6C63FF), const Color(0xFF8B5CF6)],
//                             onTap: _handleEmployeeClick,
//                           ),
//                           const SizedBox(height: 20),
//                           if (_isAdminDevice)
//                             _buildPremiumCard(
//                               title: "Admin Portal", subtitle: "Dashboard & Reports", icon: Icons.shield_outlined,
//                               gradientColors: [const Color(0xFF2E93FF), const Color(0xFF00BFA5)],
//                               onTap: _handleAdminClick,
//                             ),
//                           const SizedBox(height: 30),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildPremiumCard({required String title, required String subtitle, required IconData icon, required List<Color> gradientColors, required VoidCallback onTap}) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         padding: const EdgeInsets.all(22),
//         decoration: BoxDecoration(color: const Color(0xFF252A40), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white.withOpacity(0.08)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 15, offset: const Offset(0, 8))]),
//         child: Row(
//           children: [
//             Container(
//               height: 55, width: 55,
//               decoration: BoxDecoration(gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: gradientColors[0].withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]),
//               child: Icon(icon, color: Colors.white, size: 28),
//             ),
//             const SizedBox(width: 20),
//             Expanded(
//               child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)), const SizedBox(height: 4), Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13))]),
//             ),
//             Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle), child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14)),
//           ],
//         ),
//       ),
//     );
//   }
// }
//
//
//
//
//
//
//
//
//
//
// // import 'package:face_attendance/screens/Admin%20Side/admin_dashboard_screen.dart';
// // import 'package:flutter/material.dart';
// // import 'package:device_info_plus/device_info_plus.dart';
// // import 'dart:io';
// // import 'package:geolocator/geolocator.dart';
// // import 'package:permission_handler/permission_handler.dart';
// // import '../../services/api_service.dart';
// // import '../Employee Side/employee_login_screen.dart';
// // import '../Admin Side/admin_login_screen.dart';
// //
// // class LoginScreen extends StatefulWidget {
// //   const LoginScreen({super.key});
// //
// //   @override
// //   State<LoginScreen> createState() => _LoginScreenState();
// // }
// //
// // class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
// //   static const String ADMIN_DEVICE_ID = "V1TDS35H.83-20-5-8";
// //   bool _isAdminDevice = false;
// //   bool _isLoading = true;
// //
// //   // Animation Controller
// //   late AnimationController _controller;
// //   late Animation<double> _fadeAnimation;
// //   late Animation<Offset> _slideAnimation;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _controller = AnimationController(
// //       duration: const Duration(milliseconds: 1000),
// //       vsync: this,
// //     );
// //     _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
// //       CurvedAnimation(parent: _controller, curve: Curves.easeIn),
// //     );
// //     _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
// //       CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
// //     );
// //
// //     _checkDevice();
// //     _controller.forward();
// //   }
// //
// //   @override
// //   void dispose() {
// //     _controller.dispose();
// //     super.dispose();
// //   }
// //
// //   void _checkDevice() async {
// //     final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
// //     String currentId = '';
// //     try {
// //       if (Platform.isAndroid) {
// //         AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
// //         currentId = androidInfo.id;
// //       } else if (Platform.isIOS) {
// //         IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
// //         currentId = iosInfo.identifierForVendor ?? '';
// //       }
// //     } catch (e) {
// //       debugPrint("Device Check Error: $e");
// //     }
// //
// //     if (mounted) {
// //       setState(() {
// //         _isAdminDevice = (currentId == ADMIN_DEVICE_ID);
// //         _isLoading = false;
// //       });
// //     }
// //   }
// //
// //   // --- PERMISSION LOGIC ---
// //   Future<bool> _checkAllPermissions() async {
// //     bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
// //     if (!serviceEnabled) {
// //       if (mounted) {
// //         setState(() => _isLoading = false);
// //         _showStubbornDialog("GPS Required", "Please enable GPS to proceed.", () => Geolocator.openLocationSettings());
// //       }
// //       return false;
// //     }
// //
// //     LocationPermission locPermission = await Geolocator.checkPermission();
// //     if (locPermission == LocationPermission.denied) {
// //       locPermission = await Geolocator.requestPermission();
// //       if (locPermission == LocationPermission.denied) {
// //         if (mounted) {
// //           setState(() => _isLoading = false);
// //           _showStubbornDialog("Location Permission", "We need Location access to verify attendance.", () => Geolocator.openAppSettings());
// //         }
// //         return false;
// //       }
// //     }
// //     if (locPermission == LocationPermission.deniedForever) {
// //       if (mounted) {
// //         setState(() => _isLoading = false);
// //         _showStubbornDialog("Location Blocked", "Location is permanently denied. Go to Settings and allow it.", () => Geolocator.openAppSettings());
// //       }
// //       return false;
// //     }
// //
// //     var camStatus = await Permission.camera.status;
// //     if (!camStatus.isGranted) {
// //       camStatus = await Permission.camera.request();
// //       if (!camStatus.isGranted) {
// //         if (mounted) {
// //           setState(() => _isLoading = false);
// //           _showStubbornDialog("Camera Permission", "We need Camera access to scan faces.", () => Geolocator.openAppSettings());
// //         }
// //         return false;
// //       }
// //     }
// //     return true;
// //   }
// //
// //   Future<void> _handleEmployeeClick() async {
// //     setState(() => _isLoading = true);
// //     bool hasPermissions = await _checkAllPermissions();
// //     if (!hasPermissions) return;
// //     if (mounted) {
// //       setState(() => _isLoading = false);
// //       Navigator.push(context, MaterialPageRoute(builder: (context) => const EmployeeLoginScreen()));
// //     }
// //   }
// //
// //   void _handleAdminClick() async {
// //     setState(() => _isLoading = true);
// //     bool hasPermissions = await _checkAllPermissions();
// //     if (!hasPermissions) return;
// //
// //     bool isLoggedIn = await ApiService.tryAutoLogin();
// //     if (mounted) setState(() => _isLoading = false);
// //     if (!mounted) return;
// //
// //     if (isLoggedIn) {
// //       Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminDashboard()));
// //     } else {
// //       Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminLoginScreen()));
// //     }
// //   }
// //
// //   void _showStubbornDialog(String title, String message, Function onOpenSettings) {
// //     showDialog(
// //       context: context,
// //       barrierDismissible: false,
// //       builder: (ctx) => PopScope(
// //         canPop: false,
// //         child: AlertDialog(
// //           backgroundColor: const Color(0xFF252A40),
// //           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
// //           title: Text(title, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
// //           content: Text(message, style: const TextStyle(color: Colors.white70)),
// //           actions: [
// //             TextButton(
// //               onPressed: () => onOpenSettings(),
// //               child: const Text("Open Settings", style: TextStyle(color: Color(0xFF6C63FF))),
// //             ),
// //             FilledButton(
// //               style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
// //               onPressed: () => Navigator.pop(ctx),
// //               child: const Text("I have Enabled it"),
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     if (_isLoading) {
// //       return const Scaffold(
// //         backgroundColor: Color(0xFF1A1F38),
// //         body: Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
// //       );
// //     }
// //
// //     return Scaffold(
// //       backgroundColor: const Color(0xFF1A1F38), // Deep Dark Background
// //       body: Stack(
// //         children: [
// //           // 1. Decorative Background Elements
// //           Positioned(
// //             top: -60,
// //             left: -60,
// //             child: Container(
// //               height: 250,
// //               width: 250,
// //               decoration: BoxDecoration(
// //                 shape: BoxShape.circle,
// //                 color: const Color(0xFF6C63FF).withOpacity(0.15),
// //               ),
// //             ),
// //           ),
// //           Positioned(
// //             bottom: -80,
// //             right: -80,
// //             child: Container(
// //               height: 300,
// //               width: 300,
// //               decoration: BoxDecoration(
// //                 shape: BoxShape.circle,
// //                 color: const Color(0xFF2E93FF).withOpacity(0.1),
// //               ),
// //             ),
// //           ),
// //
// //           // 2. Main Content
// //           SafeArea(
// //             child: Center(
// //               child: SingleChildScrollView(
// //                 child: Padding(
// //                   padding: const EdgeInsets.symmetric(horizontal: 30),
// //                   child: FadeTransition(
// //                     opacity: _fadeAnimation,
// //                     child: SlideTransition(
// //                       position: _slideAnimation,
// //                       child: Column(
// //                         mainAxisAlignment: MainAxisAlignment.center,
// //                         children: [
// //                           // --- Hero Section ---
// //                           Container(
// //                             height: 150,
// //                             width: 150,
// //                             decoration: BoxDecoration(
// //                               shape: BoxShape.circle,
// //                               gradient: const LinearGradient(
// //                                 colors: [Color(0xFF6C63FF), Color(0xFF2E93FF)],
// //                                 begin: Alignment.topLeft,
// //                                 end: Alignment.bottomRight,
// //                               ),
// //                               boxShadow: [
// //                                 BoxShadow(
// //                                     color: const Color(0xFF6C63FF).withOpacity(0.4),
// //                                     blurRadius: 30,
// //                                     spreadRadius: 5,
// //                                     offset: const Offset(0, 10)
// //                                 ),
// //                               ],
// //                             ),
// //                             child: const Icon(Icons.face_unlock_rounded, size: 75, color: Colors.white),
// //                           ),
// //                           const SizedBox(height: 40),
// //
// //                           // --- Updated Titles ---
// //                           const Text(
// //                             "Face Attendance",
// //                             style: TextStyle(
// //                                 color: Colors.white,
// //                                 fontSize: 34,
// //                                 fontWeight: FontWeight.w800,
// //                                 letterSpacing: 1.0
// //                             ),
// //                           ),
// //                           const SizedBox(height: 10),
// //                           Container(
// //                             padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
// //                             decoration: BoxDecoration(
// //                                 color: Colors.white.withOpacity(0.05),
// //                                 borderRadius: BorderRadius.circular(20),
// //                                 border: Border.all(color: Colors.white.withOpacity(0.1))
// //                             ),
// //                             child: const Text(
// //                               "Secure  •  Fast  •  Contactless",
// //                               style: TextStyle(
// //                                   color: Colors.white70,
// //                                   fontSize: 13,
// //                                   fontWeight: FontWeight.w500,
// //                                   letterSpacing: 0.5
// //                               ),
// //                             ),
// //                           ),
// //
// //                           const SizedBox(height: 60),
// //
// //                           // --- Employee Card ---
// //                           _buildPremiumCard(
// //                             title: "Employee Login",
// //                             subtitle: "Mark Attendance",
// //                             icon: Icons.fingerprint,
// //                             gradientColors: [const Color(0xFF6C63FF), const Color(0xFF8B5CF6)],
// //                             onTap: _handleEmployeeClick,
// //                           ),
// //
// //                           const SizedBox(height: 20),
// //
// //                           // --- Admin Card (Conditional) ---
// //                           if (_isAdminDevice)
// //                             _buildPremiumCard(
// //                               title: "Admin Portal",
// //                               subtitle: "Dashboard & Reports",
// //                               icon: Icons.shield_outlined,
// //                               gradientColors: [const Color(0xFF2E93FF), const Color(0xFF00BFA5)],
// //                               onTap: _handleAdminClick,
// //                             ),
// //
// //                           const SizedBox(height: 30),
// //                         ],
// //                       ),
// //                     ),
// //                   ),
// //                 ),
// //               ),
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   // --- UPDATED: PREMIUM SOLID CARD ---
// //   Widget _buildPremiumCard({
// //     required String title,
// //     required String subtitle,
// //     required IconData icon,
// //     required List<Color> gradientColors,
// //     required VoidCallback onTap,
// //   }) {
// //     return GestureDetector(
// //       onTap: onTap,
// //       child: Container(
// //         padding: const EdgeInsets.all(22),
// //         decoration: BoxDecoration(
// //             color: const Color(0xFF252A40), // Solid Dark Grey/Blue
// //             borderRadius: BorderRadius.circular(25),
// //             border: Border.all(color: Colors.white.withOpacity(0.08)),
// //             boxShadow: [
// //               BoxShadow(
// //                   color: Colors.black.withOpacity(0.25),
// //                   blurRadius: 15,
// //                   offset: const Offset(0, 8)
// //               ),
// //             ]
// //         ),
// //         child: Row(
// //           children: [
// //             // Icon Box with Gradient Background (More Attractive)
// //             Container(
// //               height: 55,
// //               width: 55,
// //               decoration: BoxDecoration(
// //                   gradient: LinearGradient(
// //                     colors: gradientColors,
// //                     begin: Alignment.topLeft,
// //                     end: Alignment.bottomRight,
// //                   ),
// //                   borderRadius: BorderRadius.circular(18),
// //                   boxShadow: [
// //                     BoxShadow(
// //                       color: gradientColors[0].withOpacity(0.4),
// //                       blurRadius: 10,
// //                       offset: const Offset(0, 4),
// //                     )
// //                   ]
// //               ),
// //               child: Icon(icon, color: Colors.white, size: 28),
// //             ),
// //             const SizedBox(width: 20),
// //             // Text
// //             Expanded(
// //               child: Column(
// //                 crossAxisAlignment: CrossAxisAlignment.start,
// //                 children: [
// //                   Text(
// //                     title,
// //                     style: const TextStyle(
// //                         color: Colors.white,
// //                         fontSize: 18,
// //                         fontWeight: FontWeight.bold,
// //                         letterSpacing: 0.5
// //                     ),
// //                   ),
// //                   const SizedBox(height: 4),
// //                   Text(
// //                     subtitle,
// //                     style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
// //                   ),
// //                 ],
// //               ),
// //             ),
// //             // Arrow
// //             Container(
// //               padding: const EdgeInsets.all(8),
// //               decoration: BoxDecoration(
// //                 color: Colors.white.withOpacity(0.05),
// //                 shape: BoxShape.circle,
// //               ),
// //               child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// // }
