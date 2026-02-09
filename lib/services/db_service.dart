// import 'package:hive_flutter/hive_flutter.dart';
//
// class DBService {
//   // Singleton Pattern
//   static final DBService _instance = DBService._internal();
//   factory DBService() => _instance;
//   DBService._internal();
//
//   // 🔴 CHANGE 1: 'late' hata diya, ab ye Nullable (?) hai (Crash Proof)
//   Box? _userBox;
//   Box? _logBox;
//   Box? _sessionBox;
//
//   // Cooldown Map (RAM mein)
//   final Map<String, DateTime> _cooldownMap = {};
//
//   // --- INITIALIZE ---
//   Future<void> initialize() async {
//     try {
//       await Hive.initFlutter();
//       _userBox = await Hive.openBox('users');
//       _logBox = await Hive.openBox('attendance_logs');
//       _sessionBox = await Hive.openBox('session');
//       print("✅ Local DB Initialized (Safe Mode)");
//     } catch (e) {
//       print("⚠️ DB Init Error: $e");
//     }
//   }
//
//   // --- 1. OFFICE LOCATION (Crash Fix) ---
//   double getOfficeLat() {
//     // Agar DB load nahi hua, toh Default value return karo (Crash nahi hoga)
//     if (_userBox == null) return 31.313761999832224;
//     return _userBox!.get('office_lat', defaultValue: 31.313761999832224);
//   }
//
//   double getOfficeLng() {
//     if (_userBox == null) return 75.59098547554379;
//     return _userBox!.get('office_lng', defaultValue: 75.59098547554379);
//   }
//
//   Future<void> saveOfficeLocation(double lat, double lng) async {
//     if (_userBox == null) await initialize();
//     await _userBox!.put('office_lat', lat);
//     await _userBox!.put('office_lng', lng);
//   }
//
//   // --- 2. ATTENDANCE THROTTLE (Baar baar attendance rokne ke liye) ---
//   bool canMarkAttendance(String name) {
//     // Check RAM Map
//     if (_cooldownMap.containsKey(name)) {
//       final lastTime = _cooldownMap[name]!;
//       final difference = DateTime.now().difference(lastTime).inMinutes;
//
//       // Agar 5 Minute se kam hua hai, toh False bhejo
//       if (difference < 5) {
//         return false;
//       }
//     }
//     // Time update karo
//     _cooldownMap[name] = DateTime.now();
//     return true;
//   }
//
//   // --- 3. LOGS (UI History ke liye Local rakh sakte hain) ---
//   Future<String> saveAttendanceLog(String name) async {
//     if (_logBox == null) return "Error"; // Safety check
//
//     List<String> logs = List<String>.from(_logBox!.get(name, defaultValue: []));
//     DateTime now = DateTime.now();
//
//     String todayDate = "${now.day}/${now.month}/${now.year}";
//     bool alreadyPunchedIn = logs.any((log) => log.contains(todayDate));
//
//     String status = !alreadyPunchedIn ? "Punch IN" : "Punch OUT";
//     String formattedLog = "$todayDate at ${now.hour}:${now.minute.toString().padLeft(2, '0')} - $status";
//
//     logs.add(formattedLog);
//     await _logBox!.put(name, logs);
//
//     return status;
//   }
//
//   // --- 4. SERVER MODE (Local Functions ko Dummy bana diya) ---
//
//   // Ab hum local users save nahi karenge, kyunki data Server par hai
//   Future<void> registerUser(String name, List<double> faceEmbedding) async {
//     print("⚠️ Local Registration Skipped (Using Server)");
//   }
//
//   // Local se users mat uthao, khali list bhejo
//   Map<dynamic, dynamic> getAllUsers() {
//     return {};
//   }
//
//   List<String> getUserLogs(String name) {
//     if (_logBox == null) return [];
//     return List<String>.from(_logBox!.get(name, defaultValue: []));
//   }
//
//   // --- 5. SESSION MANAGEMENT ---
//   String? getCurrentEmployee() {
//     if (_sessionBox == null) return null;
//     return _sessionBox!.get('current_user');
//   }
//
//   Future<void> loginEmployee(String name) async {
//     if (_sessionBox == null) await initialize();
//     await _sessionBox!.put('current_user', name);
//   }
//
//   Future<void> logoutEmployee() async {
//     if (_sessionBox == null) return;
//     await _sessionBox!.delete('current_user');
//   }
//
//
//   Future<void> deleteUser(String name) async {
//     // Agar DB load nahi hai to pehle load karo
//     if (_userBox == null || _logBox == null) await initialize();
//
//     // User aur uske logs delete karo
//     await _userBox?.delete(name);
//     await _logBox?.delete(name);
//     print("🗑️ User '$name' deleted from Local DB");
//   }
// }
//
//
//
//
// // import 'package:hive_flutter/hive_flutter.dart';
// //
// // class DBService {
// //   final Map<String, DateTime> _cooldownMap = {};
// //   static final DBService _instance = DBService._internal();
// //   factory DBService() => _instance;
// //   DBService._internal();
// //
// //   late Box _userBox;
// //   late Box _logBox;
// //   late Box _sessionBox;
// //
// //   // Default location (Change as needed)
// //   double getOfficeLat() => _userBox.get('office_lat', defaultValue: 31.313761999832224);
// //   double getOfficeLng() => _userBox.get('office_lng', defaultValue: 75.59098547554379);
// //  // double getOfficeLat() => _userBox.get('office_lat', defaultValue:  31.313721876483562);
// //  //  double getOfficeLng() => _userBox.get('office_lng', defaultValue: 75.59103262615385);
// //
// //   Future<void> initialize() async {
// //     await Hive.initFlutter();
// //     _userBox = await Hive.openBox('users');
// //     _logBox = await Hive.openBox('attendance_logs');
// //     _sessionBox = await Hive.openBox('session');
// //   }
// //
// //   bool canMarkAttendance(String name) {
// //     // 1. Check karo kya isne pehle attendance lagayi hai?
// //     if (_cooldownMap.containsKey(name)) {
// //       final lastTime = _cooldownMap[name]!;
// //       final difference = DateTime.now().difference(lastTime).inMinutes;
// //
// //       // 2. Agar 10 Minute se kam hua hai, toh False bhejo (MAT LAGAO)
// //       if (difference < 1) {
// //         return false;
// //       }
// //     }
// //
// //     // 3. Agar time ho gaya hai (ya pehli baar hai), toh abhi ka time note karo
// //     _cooldownMap[name] = DateTime.now();
// //     return true; // True bhejo (ATTENDANCE LAGAO)
// //   }
// //
// //   Future<void> registerUser(String name, List<double> faceEmbedding) async {
// //     await _userBox.put(name, faceEmbedding);
// //   }
// //
// //   Future<void> saveOfficeLocation(double lat, double lng) async {
// //     await _userBox.put('office_lat', lat);
// //     await _userBox.put('office_lng', lng);
// //   }
// //
// //   // --- UPDATED FUNCTION ---
// //   // Ab ye void nahi, Future<String> return karega (Message batane ke liye)
// //   Future<String> saveAttendanceLog(String name) async {
// //     List<String> logs = List<String>.from(_logBox.get(name, defaultValue: []));
// //     DateTime now = DateTime.now();
// //
// //     // Aaj ki tareekh banao (e.g., "28/1/2026")
// //     String todayDate = "${now.day}/${now.month}/${now.year}";
// //
// //     // Check karo: Kya aaj ki date wala koi log pehle se hai?
// //     bool alreadyPunchedIn = logs.any((log) => log.contains(todayDate));
// //
// //     String status = "";
// //     if (!alreadyPunchedIn) {
// //       status = "Punch IN";
// //     } else {
// //       status = "Punch OUT";
// //     }
// //
// //     // Save format: "28/1/2026 at 10:30 - Punch IN"
// //     String formattedLog = "$todayDate at ${now.hour}:${now.minute.toString().padLeft(2, '0')} - $status";
// //
// //     logs.add(formattedLog);
// //     await _logBox.put(name, logs);
// //
// //     return status; // UI ko batao ki kya hua
// //   }
// //
// //   Map<dynamic, dynamic> getAllUsers() => _userBox.toMap();
// //
// //   List<String> getUserLogs(String name) {
// //     return List<String>.from(_logBox.get(name, defaultValue: []));
// //   }
// //
// //   Future<void> deleteUser(String name) async {
// //     await _userBox.delete(name);
// //     await _logBox.delete(name);
// //   }
// //
// //   String? getCurrentEmployee() {
// //     return _sessionBox.get('current_user'); // Naam return karega ya null
// //   }
// //
// //   Future<void> loginEmployee(String name) async {
// //     await _sessionBox.put('current_user', name);
// //   }
// //
// //   Future<void> logoutEmployee() async {
// //     await _sessionBox.delete('current_user');
// //   }
// // }
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// //
// // // import 'package:hive_flutter/hive_flutter.dart';
// // //
// // // class DBService {
// // //   // Singleton Pattern
// // //   static final DBService _instance = DBService._internal();
// // //   factory DBService() => _instance;
// // //   DBService._internal();
// // //
// // //   // RAM Memory for Cooldown (Jaisa tumne bheja tha)
// // //   final Map<String, DateTime> _cooldownMap = {};
// // //
// // //   late Box _userBox;
// // //   late Box _logBox;
// // //
// // //   Future<void> initialize() async {
// // //     await Hive.initFlutter();
// // //     _userBox = await Hive.openBox('users');
// // //     _logBox = await Hive.openBox('attendance_logs');
// // //   }
// // //
// // //   // --- 1. LOCATION (Future laga diya taaki baad me Cloud se fetch ho sake) ---
// // //   Future<double> getOfficeLat() async {
// // //     // ABHI: Hive se le raha hai
// // //     return _userBox.get('office_lat', defaultValue: 31.313343);
// // //     // BAAD MEIN: await firestore.get('config').lat;
// // //   }
// // //
// // //   Future<double> getOfficeLng() async {
// // //     return _userBox.get('office_lng', defaultValue: 75.591148);
// // //   }
// // //
// // //   // --- 2. COOLDOWN CHECK (Future laga diya) ---
// // //   // Note: Abhi ye RAM use kar raha hai, par 'Future' hone se
// // //   // baad me hum isse Server Time check karwa sakte hain bina UI tode.
// // //   Future<bool> canMarkAttendance(String name) async {
// // //     if (_cooldownMap.containsKey(name)) {
// // //       final lastTime = _cooldownMap[name]!;
// // //       final difference = DateTime.now().difference(lastTime).inMinutes;
// // //       if (difference < 10) {
// // //         return false;
// // //       }
// // //     }
// // //     _cooldownMap[name] = DateTime.now();
// // //     return true;
// // //   }
// // //
// // //   // --- 3. REGISTRATION ---
// // //   Future<void> registerUser(String name, List<double> faceEmbedding) async {
// // //     await _userBox.put(name, faceEmbedding);
// // //   }
// // //
// // //   // --- 4. ATTENDANCE LOG (Punch In/Out) ---
// // //   Future<String> saveAttendanceLog(String name) async {
// // //     // Note: await lagaya kyunki getUserLogs ab Future hai
// // //     List<String> logs = await getUserLogs(name);
// // //     DateTime now = DateTime.now();
// // //
// // //     String todayDate = "${now.day}/${now.month}/${now.year}";
// // //     bool alreadyPunchedIn = logs.any((log) => log.contains(todayDate));
// // //
// // //     String status = !alreadyPunchedIn ? "Punch IN" : "Punch OUT";
// // //     String formattedLog = "$todayDate at ${now.hour}:${now.minute.toString().padLeft(2, '0')} - $status";
// // //
// // //     logs.add(formattedLog);
// // //     await _logBox.put(name, logs);
// // //
// // //     return status;
// // //   }
// // //
// // //   // --- 5. GET ALL USERS (Heavy Data) ---
// // //   // Isko Future banana bohot zaroori tha, Firebase me ye time leta hai
// // //   Future<Map<dynamic, dynamic>> getAllUsers() async {
// // //     return _userBox.toMap();
// // //   }
// // //
// // //   // --- 6. HISTORY ---
// // //   Future<List<String>> getUserLogs(String name) async {
// // //     return List<String>.from(_logBox.get(name, defaultValue: []));
// // //   }
// // //
// // //   Future<void> saveOfficeLocation(double lat, double lng) async {
// // //     await _userBox.put('office_lat', lat);
// // //     await _userBox.put('office_lng', lng);
// // //   }
// // //   Future<void> deleteUser(String name) async {
// // //     await _userBox.delete(name);
// // //     await _logBox.delete(name);
// // //   }
// // // }
