// import 'package:hive_flutter/hive_flutter.dart';
//
// class DBService {
//   static final DBService _instance = DBService._internal();
//   factory DBService() => _instance;
//   DBService._internal();
//
//   late Box _userBox;
//   late Box _logBox;
//   double getOfficeLat() => _userBox.get('office_lat', defaultValue: 31.313343298262293);
//   double getOfficeLng() => _userBox.get('office_lng', defaultValue: 75.5911486688739);
//   Future<void> initialize() async {
//     await Hive.initFlutter();
//     _userBox = await Hive.openBox('users');
//     _logBox = await Hive.openBox('attendance_logs'); // New box for history
//   }
//
//   // Save user face data
//   Future<void> registerUser(String name, List<double> faceEmbedding) async {
//     await _userBox.put(name, faceEmbedding);
//   }
//   Future<void> saveOfficeLocation(double lat, double lng) async {
//     await _userBox.put('office_lat', lat);
//     await _userBox.put('office_lng', lng);
//   }
//
//
//   // Save the attendance time
//   Future<void> saveAttendanceLog(String name) async {
//     List<String> logs = List<String>.from(_logBox.get(name, defaultValue: []));
//
//     // Get current date and time
//     DateTime now = DateTime.now();
//     String formattedDate = "${now.day}/${now.month}/${now.year} at ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
//
//     logs.add(formattedDate);
//     await _logBox.put(name, logs);
//   }
//
//   Map<dynamic, dynamic> getAllUsers() => _userBox.toMap();
//
//   List<String> getUserLogs(String name) {
//     return List<String>.from(_logBox.get(name, defaultValue: []));
//   }
//
//   Future<void> deleteUser(String name) async {
//     await _userBox.delete(name);
//     await _logBox.delete(name); // Clear history if user is deleted
//   }
// }