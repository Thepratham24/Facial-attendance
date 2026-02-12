import 'dart:convert';
import 'dart:io';import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // 🔴 URL Updated: Admin hata diya, sirf base IP rakhi hai
  final String baseUrl = "http://192.168.10.85:6002";

  static String? adminToken;
  static String? employeeToken;

  // --- 1. ADMIN LOGIN ---
  Future<bool> adminLogin(String email, String password) async {
    try {
      // Admin login usually /admin ke andar hota hai, agar ye bhi bahar hai to '/admin' hata dena
      var response = await http.post(
        Uri.parse("$baseUrl/admin/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password}),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['success'] == true) {
          adminToken = data['token'];
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_token', adminToken!);
          await prefs.setBool('is_logged_in', true);

          return true;
          return true;
        }
      }
      return false;
    } catch (e) {
      print("🔥--------------------------------------------------------------- Admin Login Error: $e");
      return false;
    }
  }
  static Future<bool> tryAutoLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // Check karo memory mein token hai ya nahi
    if (prefs.containsKey('saved_token')) {
      adminToken = prefs.getString('saved_token'); // RAM mein wapas lao
      return true; // LOGIN HAI
    }
    return false; // LOGIN NAHI HAI
  }
  static Future<bool> isLoggedIn() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool status = prefs.getBool('is_logged_in') ?? false;

    if (status) {
      adminToken = prefs.getString('saved_token'); // Token wapas memory mein lao
      return true;
    }
    return false;
  }

  // 3. LOGOUT (Sab saaf karne ke liye)
  static Future<void> logoutAdmin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Sirf Admin ki keys delete karo
    await prefs.remove('saved_token');
    await prefs.remove('is_logged_in');

    // Static variable bhi clear karo
    adminToken = null;

    print("✅ Admin Logged Out (Employee session safe)");
  }

  // 🔴 2. SIRF EMPLOYEE LOGOUT (Admin ko touch nahi karega)
  static Future<void> logoutEmployee() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // ✅ Sirf tab delete hoga jab user Logout dabayega
    await prefs.remove('token');
    await prefs.remove('employee_token');
    await prefs.remove('_id');
    await prefs.remove('emp_name');
    await prefs.remove('emp_id');
    await prefs.remove('is_employee_logged_in');

    employeeToken = null;
    print("✅ Employee Logged Out & Data Cleared");
  }

  Future<String> _getDeviceId1() async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        print(("device id----------------------------------------$androidInfo"));
        return androidInfo.id; // Unique Android ID
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? "unknown_ios_id";
      }
    } catch (e) {
      print("Device ID Error: $e");
    }
    return "unknown_device_id";
  }
  // --- 2. REGISTER EMPLOYEE ---
  // --- 2. REGISTER EMPLOYEE (Updated with Token Check + New Fields) ---
  Future<Map<String, dynamic>> registerEmployee({
    required String name,
    required String email,
    required String phone,
    required int gender,
    required String designation,
    required String departmentId,
    required File imageFile,
    required List<double> faceEmbedding,

    required List<String> locationIds,
    required String shiftId,
    required String joiningDate,
  }) async {
    try {
      // 🔴 FIX: If Token is null (app restarted), try to load from phone memory
      if (adminToken == null) {
        print("⚠️-------------------------------------------------- Token is null, checking storage...");
        await tryAutoLogin();
      }

      // If still null, then fail
      if (adminToken == null) {
        print("❌-------------------------------------------------- Error: Token not found even in storage. Please Login.");
        return {"success": false, "message": "Token Missing. Please Login."};
      }

      // String deviceId = await _getDeviceId1();
      // print("📱-------------------------------------------------- Registering from Device ID: $deviceId");

      var request = http.MultipartRequest('POST', Uri.parse("$baseUrl/admin/employee/create"));

      request.headers.addAll({
        "Authorization": adminToken ?? "",
      });

      // FormData Fields
      request.fields['name'] = name;
      request.fields['email'] = email;
      request.fields['phone'] = phone;
      request.fields['gender'] = gender.toString();
      request.fields['designation'] = designation;
      request.fields['departmentId'] = departmentId;
      request.fields['joiningDate'] = joiningDate;
      request.fields['faceModelVersion'] = "mobilefacenet_v1";
      // request.fields['deviceId'] = deviceId;

      // 🔴 NEW: Send Location and Shift IDs to Server
      // request.fields['locationIds'] = jsonEncode(locationIds);
      request.fields['shiftId'] = shiftId;

      for (int i = 0; i < faceEmbedding.length; i++) {
        request.fields['faceEmbedding[$i]'] = faceEmbedding[i].toString();
      }
print("------------------------locations $locationIds");
      for (String id in locationIds) {
          request.files.add(http.MultipartFile.fromString('locations[]', id));
        }

      // Photo File upload
      var stream = http.ByteStream(imageFile.openRead());
      var length = await imageFile.length();
      var multipartFile = http.MultipartFile(
          'employee_image', // 🔴 Verify if backend needs 'faceImage' or 'employee_image'
          stream,
          length,
          filename: "${name}_face.jpg"
      );

      request.files.add(multipartFile);

      print("📦 -------------------------------------------------- Sending Data to Server...");
      var response = await request.send();
      print("----------------------------------------------------data gea bhaaiiiiiii");
      var finalResult = await response.stream.bytesToString();

      print("📩-------------------------------------------------- Response Status: ${response.statusCode}");
      print("📩 --------------------------------------------------Response Body: $finalResult");

      try {
        var data = jsonDecode(finalResult);
        // 🟢 Server ka message aur status wapas bhejo
        return{
          "success": data['success'] ?? false,
          "message": data['message'] ?? "Unknown Server Response"
        };
      } catch (e) {
        // Agar HTML error (404/500) aaya
        return {"success": false, "message": "Server Error: ${response.statusCode}"};
      }
    } catch (e) {
      print("🔥-------------------------------------------------- Request Error: $e");
      return {"success": false, "message": "Connection Error: $e"};
    }
  }

  // 🔴 3. EMPLOYEE ATTENDANCE / LOGIN (Sahi Logic for '/employee/login')
  // List download mat karo. Seedha embedding bhejo aur server se poocho ye kaun hai.
  // Future<Map<String, dynamic>?> authenticateEmployee(List<double> faceEmbedding) async {
  //   try {
  //     // URL wahi jo Sir ne bola: /employee/login
  //     var url = Uri.parse("$baseUrl/employee/login");
  //
  //     print("📡 🔥--------------------------------------------------------------- Admin Login Error: Sending Face to Server: $url");
  //
  //     // 🔴 Login hamesha POST hota hai
  //     var response = await http.post(
  //       url,
  //       headers: {
  //         "Content-Type": "application/json",
  //         // Usually employee login public hota hai, agar token chahiye to uncomment karo:
  //         // "Authorization": "Bearer $adminToken",
  //       },
  //       // Body mein embedding bhejo
  //       body: jsonEncode({
  //         "faceEmbedding": faceEmbedding
  //       }),
  //     );
  //
  //     print("📩🔥--------------------------------------------------------------- Employee Login :  Response: ${response.statusCode} - ${response.body}");
  //
  //     if (response.statusCode == 200) {
  //       var data = jsonDecode(response.body);
  //       if (data['success'] == true) {
  //
  //         // 🟢 FIX: Token Nikalo aur Save Karo
  //         if (data.containsKey('token')) {
  //           String token = data['token'];
  //           employeeToken = token; // Static variable update
  //
  //           SharedPreferences prefs = await SharedPreferences.getInstance();
  //           // Note: Consistency ke liye wohi key use karein jo UI me use kar rahe hain ('token' ya 'employee_token')
  //           await prefs.setString('token', token);
  //           await prefs.setString('employee_token', token); // Backup key
  //           await prefs.setBool('is_employee_logged_in', true);
  //
  //           print("✅ ------------------------------------------------------Token Saved inside ApiService: $token");
  //         }
  //
  //         return data;
  //       }
  //     }
  //     return null; // Match nahi hua
  //   } catch (e) {
  //     print("🔥🔥--------------------------------------------------------------- Employee Login Error:  Auth Error: $e");
  //     return null;
  //   }
  // }



  Future<Map<String, dynamic>?> authenticateEmployee(List<double> faceEmbedding) async {
    try {
      var url = Uri.parse("$baseUrl/employee/login");
      String deviceId = await _getDeviceId1();
      var response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(
            {"faceEmbedding": faceEmbedding,
              "deviceId": deviceId
        }),
      );
      print("📩--------------------------------------------------Device id in authenticate : ${deviceId}");
      print("📩-------------------------------------------------- Response Status: ${response.statusCode}");
      print("📩 --------------------------------------------------authenticate Response Body: ${response.body}");
      print("📩 --------------------------------------------------");
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (data.containsKey('token')) {
            String token = data['token'];


            employeeToken = token;
            // String employeeId =data['employeeId'];

            // ✅ Token ko 'token' key se save kar rahe hain (Standard)
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString('token', token);
            await prefs.setString('employee_token', token); // Backup
            await prefs.setBool('is_employee_logged_in', true);
            // await prefs.setString('employeeId',employeeId);

            print("✅--------------------------- Token Saved Successfully: $token");

            if (data['location'] != null && data['location'] is List) {
              List<dynamic> locArray = data['location'];
              // List ko String banakar save karo
              await prefs.setString('location_ids', jsonEncode(locArray));
              print("✅ --------------------------------Location Array Saved: $locArray");
            } else {
              print("⚠️------------------------------------ Location Array missing in Face Login");
            }
          }
          return data;
        }
      }

      if (response.body.isNotEmpty) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print("Auth Error: $e");
      return null;
    }
  }


  Future<bool> employeeLogin(String email, String password) async {
    try {
      var url = Uri.parse("$baseUrl/employee/login");

      var response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password}),
      );

      print("--------------------------------------------Employee Login Response: ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['success'] == true) {
          employeeToken = data['token'];

          SharedPreferences prefs = await SharedPreferences.getInstance();

          // 1. Token Save
          await prefs.setString('token', employeeToken!);
          await prefs.setBool('is_employee_logged_in', true);

          // 🔴 2. FIX: SAVE LOCATION ID & EMPLOYEE DETAILS
          // Backend response structure usually 'employee' ya 'user' key mein data deta hai
          var user = data['employee'] ?? data['user'] ?? data['data'];

          if (user != null) {
            // ID aur Name bhi save kar lo (Dashboard me kaam ayega)
            if (user['_id'] != null) await prefs.setString('emp_id', user['_id']);
            if (user['name'] != null) await prefs.setString('emp_name', user['name']);

            // Location ID Logic
            var locationData = data['location'] ?? user['location'];

            if (locationData != null && locationData is List) {
              await prefs.setString('location_ids', jsonEncode(locationData));
              print("✅---------------------- Email Login: Location Array Saved: $locationData");
            } else {
              print("⚠️-------------------------- Email Login: Location Array not found");
            }
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      print("Employee Login Error: $e");
      return false;
    }
  }


  static Future<void> loadTokens() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Admin Token Load
    if (prefs.containsKey('token')) {
      employeeToken = prefs.getString('token');
      print("✅ Employee Token Restored from Storage");
    } else if (prefs.containsKey('employee_token')) {
      employeeToken = prefs.getString('employee_token');
      print("✅ Employee Token Restored from Backup Key");
    }

    // Admin Token Load
    if (prefs.containsKey('saved_token')) {
      adminToken = prefs.getString('saved_token');
    }
  }
  Future<List<dynamic>> getLocations() async {
    try {
      if (adminToken == null) await tryAutoLogin(); // Token check

      var response = await http.post(
        Uri.parse("$baseUrl/admin/location/allMini"),
        headers: {
          "Authorization": adminToken ?? "", // Token zaroori hai
          "Content-Type": "application/json",
        },
          body: jsonEncode({
            "isBlocked": false
          }),
      );
      print("📩🔥---------------------------------------------------------------get location allmini:  Response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data']; // List return kar rahe hain
        }
      }
      return [];
    } catch (e) {
      print("--------------------------------------------------------Error fetching locations: $e");
      return [];
    }
  }

  Future<List<dynamic>> getLocationsForEmployee() async {
    try {
      if (adminToken == null) await tryAutoLogin(); // Token check

      var response = await http.post(
        Uri.parse("$baseUrl/admin/location/allMini"),
        headers: {
          "Authorization": employeeToken ?? "", // Token zaroori hai
          "Content-Type": "application/json",
        },
          body: jsonEncode({
            "isBlocked": false
          }),
      );
      print("📩🔥---------------------------------------------------------------Location Error:  Response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data']; // List return kar rahe hain
        }
      }
      return [];
    } catch (e) {
      print("--------------------------------------------------------Error fetching locations: $e");
      return [];
    }
  }


  Future<List<dynamic>> getDepartments() async {
    try {
      if (adminToken == null) await tryAutoLogin(); // Token check

      var response = await http.post(
        Uri.parse("$baseUrl/admin/department/allMini"),
        headers: {
          "Authorization": adminToken ?? "", // Token zaroori hai
          "Content-Type": "application/json",
        },
          body: jsonEncode({
            "isBlocked": false
          }),
      );
      print("📩🔥---------------------------------------------------------------get Department :  Response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data']; // List return kar rahe hain
        }
      }
      return [];
    } catch (e) {
      print("--------------------------------------------------------Error fetching locations: $e");
      return [];
    }
  }

  Future<List<dynamic>> getDepartmentForEmployee() async {
    try {
      if (adminToken == null) await tryAutoLogin(); // Token check

      var response = await http.post(
        Uri.parse("$baseUrl/admin/department/allMini"),
        headers: {
          "Authorization": employeeToken ?? "", // Token zaroori hai
          "Content-Type": "application/json",
        },
          body: jsonEncode({
            "isBlocked": false
          }),
      );
      print("📩🔥---------------------------------------------------------------get Department :  Response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data']; // List return kar rahe hain
        }
      }
      return [];
    } catch (e) {
      print("--------------------------------------------------------Error fetching locations: $e");
      return [];
    }
  }

  // --- 5. FETCH SHIFTS (Dropdown ke liye) ---
  Future<List<dynamic>> getShifts() async {
    try {
      if (adminToken == null) await tryAutoLogin();

      var response = await http.post(
        Uri.parse("$baseUrl/admin/shift/allMini"),
        headers: {
          "Authorization": adminToken ?? "",
          "Content-Type": "application/json",
        },
          body: jsonEncode({
            "isBlocked": false
          }),
      );
      print("📩🔥--------------------------------------------------------------- Shift Error:  Response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data']; // List return kar rahe hain
        }
      }
      return [];
    } catch (e) {
      print("------------------------------------------------------------------------Error fetching shifts: $e");
      return [];
    }
  }



  Future<List<dynamic>> getAllEmployees() async {
    try {
      if (adminToken == null) await tryAutoLogin();

      // 🔴 URL Check kar lena (Shayad '/admin/employee/all' ho)
      var response = await http.post(
        Uri.parse("$baseUrl/admin/employee/all"),
        headers: {
          "Authorization": adminToken ?? "",
          "Content-Type": "application/json",
        },
      );

      print("👥-------------------------------------------------------------------- Get all employees status: ${response.statusCode} ");
      print("👥-------------------------------------------------------------------- Get all employees body ye dash me b chlta ahi vse bhi : ${response.body}  ");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data']; // Ye wo List return karega jo tumne bheji
        }
      }
      return [];
    } catch (e) {
      print("Error fetching employees: $e");
      return [];
    }
  }
  Future<Map<String, String>> _getDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String deviceId = "Unknown";
    String deviceModel = "Unknown";

    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
        deviceModel = androidInfo.model; // e.g. Moto G64
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? "Unknown";
        deviceModel = iosInfo.model; // e.g. iPhone 13
      }
    } catch (e) {
      print("Device Info Error: $e");
    }
    return {"id": deviceId, "model": deviceModel};
  }



  // api_service.dart

  // api_service.dart

  // api_service.dart

  Future<Map<String, dynamic>?> getSingleEmployee(String targetId) async {
    print("🔥 API CALL: Fetching Single Employee: '$targetId'");

    try {
      var response = await http.post(
          Uri.parse("$baseUrl/admin/employee/single"), // ✅ Naya Endpoint
          headers: {
            "Content-Type": "application/json",
            "Authorization": adminToken ?? "", // Agar token chahiye to uncomment karein
          },
          body: jsonEncode({
            "_id": targetId // ✅ Naya Key (_id)
          })
      );

      print("🌐 Status: ${response.statusCode}");
      print("---------------------------------------${targetId}");
      print("---------------------------------------${adminToken}");
      print("👥-------------------------------------------------------------------- Employee List Status: ${response.statusCode}  --${response.body}");

      if (response.statusCode == 200) {
        var jsonData = jsonDecode(response.body);

        // ✅ Check: Ab hum List nahi, seedha Map check kar rahe hain
        if (jsonData['success'] == true && jsonData['data'] != null) {
          print("✅ DATA RECEIVED: ${jsonData['data']['name']}");
          return jsonData['data']; // Seedha Object return kiya
        }
      }
      print("❌ API FAILURE: ${response.body}");
      return null;
    } catch (e) {
      print("⚠️ EXCEPTION: $e");
      return null;
    }
  }

  // --- 6. MARK ATTENDANCE (Embedding + Location) ---
  Future<Map<String, dynamic>> markAttendance({
    required List<double> faceEmbedding,
    required double latitude,
    required double longitude,

    required bool isFromAdminPhone,
    required String deviceDate,


  }) async {
    try {
      Map<String, String> deviceData = await _getDeviceInfo();
      // 🔴 URL Check kar lena (Backend par '/attendance/mark' hai ya '/employee/identify')
      // Main assume kar raha hu yeh endpoint hai:
      var url = Uri.parse("$baseUrl/employee/attendance/create");

      var body = {
        "faceEmbedding": faceEmbedding,
        "latitude": latitude,
        "longitude": longitude,

        "deviceId": deviceData['id'],
        "deviceModel": deviceData['model'],
        "isFromAdminPhone": isFromAdminPhone,
        "deviceDate": deviceDate
      };
      print("📡----------------------------------------------------- deviceID in mark attendnace: $deviceData['id']");
      print("📡----------------------------------------------------- deviceDatwe: $deviceDate");

      print("📡----------------------------------------------------- Sending Attendance Request: Lat: $latitude, Lng: $longitude");

      var response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          // Agar token chahiye header mein toh ye uncomment karo:
          "Authorization": adminToken ?? "",
        },
        body: jsonEncode(body),
      );

      print("📩📡----------------------------------------------------- Attendance ResponseCode: ${response.statusCode}");
      print("📩📡----------------------------------------------------- Attendance Response: ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        return {
          "success": data['success'] ?? false,
          "message": data['message'] ?? "Unknown",
          "data": data['data'] // User details (Name, Photo etc.)
        };
      } else {
        return {"success": false, "message": "Server Error: ${response.statusCode}"};
      }
    } catch (e) {
      print("🔥-------------------------------------- Mark Attendance Error: $e");
      return {"success": false, "message": "Connection Error"};
    }
  }




  // --- 7. GET ALL ATTENDANCE HISTORY (Admin) ---



  // --- 7. GET ATTENDANCE LOGS (Universal Function) ---
  // Agar empId null hai -> Sabki attendance aayegi
  // Agar empId diya hai -> Sirf uski attendance aayegi
  Future<List<dynamic>> getAttendanceLogs({String? empId}) async {
    try {
      if (adminToken == null) await loadTokens();

      // 🔴 Endpoint wahi 'attendance/all' wala
      var url = Uri.parse("$baseUrl/admin/attendance/all");

      // 🔴 Logic: Agar ID hai to body me daalo, nahi to khali body
      Map<String, dynamic> body = {};
      if (empId != null) {
        body['employeeId'] = empId;
      }
print('employee id=---------------------------------$empId');
      print("token-----------------------$adminToken");
      var response = await http.post(
          url,
          headers: {
            "Content-Type": "application/json",
            "Authorization": adminToken ?? ""
          },
          body: jsonEncode(body)
      );
      print("📩📡----------------------------------------------------- Get all employees Attendance status: ${response.statusCode}");
      print("📩📡-----------------------------------------------------Get all employees  Attendance Response: ${response.body}");
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        if (data['success'] == true) {
          return data['data']; // List return karega
        }
      }
      return [];
    } catch (e) {
      print("---------------------------------------------History Fetch Error: $e");
      return [];
    }
  }


  Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      // 1. Saare employees mangwao
      List<dynamic> allEmployees = await getAllEmployees();
      // 2. Aaj ke logs mangwao
      List<dynamic> logs = await getAttendanceLogs(empId: null);

      String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Sirf aaj ke unique present employees count karo
      Set<String> presentIds = {};
      for (var log in logs) {
        if (log['dayKey'] == todayKey) {
          var eId = (log['employeeId'] is Map) ? log['employeeId']['_id'] : log['employeeId'];
          if (eId != null) presentIds.add(eId);
        }
      }

      int total = allEmployees.length;
      int present = presentIds.length;
      int absent = total - present;
      print("📩📡----------------------------------------------------- Get Dashboard attendace  Attendance ResponseCode:");
      print("📩📡-----------------------------------------------------Get all  Attendance Response");
      return {
        "total": total,
        "present": present,
        "absent": absent,
      };
    } catch (e) {
      print("Stats Error: $e");
      return {"total": 0, "present": 0, "absent": 0};
    }
  }



  // 🔴 NEW: Get Monthly Report
  // ... class ke andar ...

  // Future<Map<String, dynamic>?> getMonthlyReport(String empId, String month,String locationId) async {
  //   try {
  //     var url = Uri.parse("$baseUrl/admin/monthlyEmployeeReport");
  //
  //     // 🔴 STEP 1: Admin Token nikalo (Jo login ke waqt save kiya tha)
  //     SharedPreferences prefs = await SharedPreferences.getInstance();
  //
  //     // Note: Check karlena ki login ke waqt key 'adminToken' thi ya sirf 'token'
  //     String? token = prefs.getString('adminToken');
  //
  //     print("📦 --------------------------------------------------Sending Data to Server: $url");
  //     print("👤---------------------------------------------------------- Employee ID: $empId");
  //     print("📅 ----------------------------------------------------------Month: $month");
  //     print("🔑---------------------------------------------------------- Token: $adminToken");
  //     var response = await http.post(
  //       url,
  //       headers: {
  //         "Content-Type": "application/json",
  //         // 🔴 STEP 2: Token ko Header mein bhejo (Bearer Token)
  //         "Authorization": "$adminToken",
  //       },
  //       body: jsonEncode({
  //         "employeeId": empId,
  //         "month": month // Format: "YYYY-MM"
  //       }),
  //     );
  //
  //     print("📡 ----------------------------------History Response Code: ${response.statusCode}");
  //     print("📩--------------------------------------- History Response Body: ${response.body}");
  //
  //     if (response.statusCode == 200) {
  //       var data = jsonDecode(response.body);
  //       if (data['success'] == true && data['data'] != null && (data['data'] as List).isNotEmpty) {
  //         return data['data'][0];
  //       }
  //     }
  //     return null;
  //   } catch (e) {
  //     print("❌ Report Error: $e");
  //     return null;
  //   }
  // }

  Future<Map<String, dynamic>?> getMonthlyReport(String empId, String month, String locationId, String departmentId) async {
    try {
      var url = Uri.parse("$baseUrl/admin/monthlyEmployeeReport");

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      print("📦---------------------------------Location id: $locationId");
      print("📦--------------------------------- department id : $departmentId");
      print("-------------------------Payload: {employeeId: $empId, locationId: $locationId, month: $month}");

      var response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "$adminToken",
        },
        body: jsonEncode({
          "employeeId": empId,
          "locationId": locationId,
          "month": month,
          "departmentId": departmentId
        }),
      );

      print("📡-------------------------------------- monthly Response Code: ${response.statusCode}");
      print("----------------------------------------------📩 Response Body: ${response.body}"); // Debugging ke liye hata diya hai taaki console na bhare

        if(response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true) {
          var data = jsonResponse['data'];
          return jsonDecode(response.body);
          // API array bhej raha hai, humein pehla object chahiye
          // if (data is List && data.isNotEmpty) {
          //   return data[0];
          // }
        }
      }
      return null;
    } catch (e) {
      debugPrint("❌ API Error: $e");
      return null;
    }
  }

  // 🔴 SPECIALIZED FUNCTION: EMPLOYEE APNI HISTORY KHUD DEKH RAHA HAI
  // Future<Map<String, dynamic>?> getEmployeeOwnHistory(String empId, String month) async {
  //   try {
  //     // ⚠️ IMPORTANT:
  //     // Agar backend par Admin aur Employee ka URL same hai, toh ye line aise hi rehne do.
  //     // Agar Employee ka alag route hai (e.g., /employee/getReport), toh yahan change karlena.
  //     // Filhal main maan ke chal raha hu ki URL /admin/ wala hi hai lekin Token Employee ka jayega.
  //
  //     // OPTION A: Agar same URL hai
  //     // var url = Uri.parse("$baseUrl/admin/monthlyEmployeeReport");
  //
  //     // OPTION B (Most Likely): Employee ka alag route hoga
  //     var url = Uri.parse("$baseUrl/admin/monthlyEmployeeReport");
  //
  //     SharedPreferences prefs = await SharedPreferences.getInstance();
  //     String? token = prefs.getString('token');
  //
  //     // 🔴 STEP 1: Employee wala Token nikalo (Jo login karte waqt save kiya tha)
  //     // String? token = prefs.getString('employeeToken');
  //
  //     if (employeeToken == null) {
  //       print("❌ ----------------------------------------------------------Error: Employee Token not found.");
  //       return null;
  //     }
  //
  //     print("🚀 ----------------------------------------------------------FETCHING OWN HISTORY: $url");
  //     print("👤---------------------------------------------------------- Employee ID: $empId");
  //     print("📅 ----------------------------------------------------------Month: $month");
  //     print("🔑------------------------------------------ his---------------- Token: $employeeToken");
  //
  //     var response = await http.post(
  //       url,
  //       headers: {
  //         "Content-Type": "application/json",
  //         "Authorization": "$token", // 🔴 Employee Token Bheja
  //       },
  //       body: jsonEncode({
  //         "employeeId": empId,
  //         "month": month
  //       }),
  //     );
  //
  //     print("📡---------------------------------------------------------- Status Code: ${response.statusCode}");
  //     print("📩 ----------------------------------------------------------Body: ${response.body}");
  //
  //     if (response.statusCode == 200) {
  //       var data = jsonDecode(response.body);
  //       if (data['success'] == true && data['data'] != null && (data['data'] as List).isNotEmpty) {
  //         return data['data'][0];
  //       }
  //     }
  //     return null;
  //   } catch (e) {
  //     print("❌ ----------------------------------------------------------API Error: $e");
  //     return null;
  //   }
  // }
  Future<List<dynamic>?> fetchUserLocationId(String empId) async {
    try {
      var url = Uri.parse("$baseUrl/employee/get/$empId");
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      if (token == null) return null;

      var response = await http.get(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Data structure check karo
          if (data['location'] != null && data['location'] is List) {
            return data['location'];
          }
        }
      }
    } catch (e) {
      print("Profile Fetch Error: $e");
    }
    return null;
  }

  // ==========================================
  // 2. HISTORY: MONTHLY REPORT
  // ==========================================
  Future<Map<String, dynamic>?> getEmployeeOwnHistory(String empId, String month, String locationId,String departmentId) async {
    try {
      var url = Uri.parse("$baseUrl/admin/monthlyEmployeeReport");
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      if (token == null) return null;

      print("📦 Fetching History -> ID: $empId, Loc: $locationId, Month: $month");

      var response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "$token",
        },
        body: jsonEncode({
          "employeeId": empId,
          "month": month,
          "locationId": locationId, // ✅ Sending Location ID
          "departmentId": departmentId
        }),
      );
print("------------------------------dept------------------$departmentId");
      print("📡-------------------------------------- employe monthly report emplyee side Response Code: ${response.statusCode}");
      print("----------------------------------------------📩employe monthly report emplyee side Response Body: ${response.body}"); // Debugging ke liye hata diya hai taaki console na bhare

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true) {
          var listData = jsonResponse['data'] ?? jsonResponse['employees'];
          if (listData != null && listData is List && listData.isNotEmpty) {
            return listData[0];
          }
        }
      } else {
        print("❌ API Error: ${response.body}");
      }
      return null;
    } catch (e) {
      print("API Exception: $e");
      return null;
    }
  }







  // this changed
  // 🔴 UPDATED: Accepts locationId now
  // Future<Map<String, dynamic>?> getEmployeeOwnHistory(String empId, String month) async {
  //   try {
  //     var url = Uri.parse("$baseUrl/admin/monthlyEmployeeReport");
  //
  //     SharedPreferences prefs = await SharedPreferences.getInstance();
  //     String? token = prefs.getString('token');
  //
  //     if (token == null || token.isEmpty) {
  //       print("❌❌------------------------------------------------ Token Missing");
  //       return null;
  //     }
  //
  //     // print("📦 Fetching for: $empId, Loc: $locationId, Month: $month");
  //
  //     var response = await http.post(
  //       url,
  //       headers: {
  //         "Content-Type": "application/json",
  //         "Authorization": "$employeeToken",
  //       },
  //       body: jsonEncode({
  //         "employeeId": empId,
  //         "month": month,
  //
  //       }),
  //     );
  //     print("📡--------------------------------------getEmployeeOwnHistory Response Code: ${response.statusCode}");
  //     print("----------------------------------------------📩getEmployeeOwnHistory Response Body: ${response.body}");
  //     if (response.statusCode == 200) {
  //       var jsonResponse = jsonDecode(response.body);
  //
  //       if (jsonResponse['success'] == true) {
  //         var listData = jsonResponse['data'] ?? jsonResponse['employees'];
  //         if (listData != null && listData is List && listData.isNotEmpty) {
  //           return listData[0];
  //         }
  //       }
  //     } else {
  //       print("❌------------------------------------------------ API Error: ${response.body}");
  //     }
  //     return null;
  //   } catch (e) {
  //     print("API Exception: $e");
  //     return null;
  //   }
  // }
// 🔴 Check if Face Already Exists (Pre-check)
// 🔴 Check if Face Already Exists (With Admin Token)
//   Future<int> checkFaceExistence(List<double> faceEmbedding) async {
//     try {
//       var url = Uri.parse("$baseUrl/admin/employee/create");
//
//       // 1. Token nikalo storage se
//       SharedPreferences prefs = await SharedPreferences.getInstance();
//       String? saved_token = prefs.getString('saved_token'); // Admin ka token yahan save hota hai
//
//       print("🔍 Checking Face with Token: $saved_token");
//
//       var response = await http.post(
//         url,
//         headers: {
//           "Content-Type": "application/json",
//           // 🔴 HEADER MEIN TOKEN ADD KIYA
//           "Authorization": "$adminToken",
//         },
//         body: jsonEncode({
//           "faceEmbedding": faceEmbedding,
//         }),
//       );
//
//       print("🔍------------------------------------------------ Face Check Status: ${response.statusCode}");
//       print("🔍------------------------------------------------ Response: ${response.body}"); // Debugging ke liye
//       var data = jsonDecode(response.body);
//
//       if (data['status'] != null) {
//         return data['status']; // ✅ Ye 422 return karega
//       } else {
//         return response.statusCode; // Fallback
//       }
//
//     } catch (e) {
//       print("------------------------------------------------Face Check Error: $e");
//       return 500; // Error aya to safe side form khol denge
//     }
//   }
// 🔴 Change return type to Map (Code + Message ke liye)
  Future<Map<String, dynamic>> checkFaceExistence(List<double> faceEmbedding) async {
    try {
      // ⚠️ IMPORTANT: Agar backend sir ne alag search API di hai to wo use karo.
      // Agar nahi di, to filhal ye '/create' shayad 400 error dega.
      var url = Uri.parse("$baseUrl/admin/employee/create");

      SharedPreferences prefs = await SharedPreferences.getInstance();

      // Token getter logic (Ensure token variable name matches your project)
      // Agar global variable 'adminToken' use kar rahe ho to wo use karo
      // String? token = prefs.getString('saved_token');

      print("🔍 Checking Face...");

      var response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "$adminToken", // Global variable use kiya hai
        },
        body: jsonEncode({
          "faceEmbedding": faceEmbedding,
        }),
      );

      print("🔍----------------------------------------- face match Status: ${response.statusCode}");
      print("🔍----------------------------------------- face match  Body: ${response.body}");

      var data = jsonDecode(response.body);

      // 🔴 Return Both Code & Message
      return {
        'code': data['status'] ?? response.statusCode,
        'message': data['message'] ?? "Unknown response"
      };

    } catch (e) {
      print("Face Check Error: $e");
      return {'code': 500, 'message': "Connection Error"};
    }
  }


  // 🔴 NEW: Get Attendance by Date & Location
  Future<List<dynamic>> getAttendanceByDateAndLocation(String date, String locationId) async {
    try {
      var url = Uri.parse("$baseUrl/admin/employeeAttendanceByDate");

      SharedPreferences prefs = await SharedPreferences.getInstance();
      // String? token = prefs.getString('token');

      var response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "$adminToken",
        },
        body: jsonEncode({
          "date": date,        // "yyyy-MM-dd"
          "locationId": locationId
        }),
      );
      print("🔍------------------------------------------------ date: ${date}, location : $locationId");
      print("🔍------------------------------------------------ get attendance By date and location Status: ${response.statusCode}");
      print("🔍------------------------------------------------ get attendance By date and location response: ${response.body}"); // Debugging ke liye
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        // Maan ke chal rahe hain response { success: true, data: [...] } hai
        return data['data'] ?? [];
      } else {
        return [];
      }
    } catch (e) {
      print("------------Error fetching daily report: $e");
      return [];
    }
  }
  Future<Map<String, dynamic>?> getDailyAttendance(String empId, String locationId, String date) async {
    try {
      var url = Uri.parse("$baseUrl/admin/employeeAttendanceByDate");
      SharedPreferences prefs = await SharedPreferences.getInstance();

      // 🔴 FIX: Token key confirm karein. Usually 'saved_token' use ho raha tha.
      String? token = prefs.getString('saved_token') ?? prefs.getString('token');

      if (token == null) {
        print("❌------------------------ Token Not Found");
        return null;
      }

      var bodyData = {
        "locationId": locationId, // Make sure ye valid MongoDB ID ho
        "employeeId": empId,
        "date": date
      };

      var response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "$token",
        },
        body: jsonEncode(bodyData),
      );

      print("🔍--------------------------- Dashboard employee API Response Code: ${response.statusCode}");
      print("🔍-------------------------------Dashboard employee  API Response Body: ${response.body}");

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);

        // 🔴 FIX: Check success structure
        if (jsonResponse['success'] == true) {
          // Data list hai ya map, safe check lagayein
          var responseData = jsonResponse['data'];

          if (responseData is List && responseData.isNotEmpty) {
            return responseData[0]; // List ka pehla item (Attendance Object)
          } else if (responseData is Map<String, dynamic>) {
            return responseData; // Agar direct object hai
          }
        }
      }
      return null;
    } catch (e) {
      print("API Error: $e");
      return null;
    }
  }

  // Face Update Function
  Future<bool> updateEmployeeFace(String id, List<double> embedding) async {
    try {
      var url = Uri.parse("$baseUrl/admin/employee/update");

      var response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "$adminToken",
        },
        body: jsonEncode({
          "_id": id, // Backend requirement
          "faceEmbedding": embedding // New Face Data
        }),
      );
      print("------------------id $id, \n adminTOken   $embedding");
      debugPrint("-----------------------------------------Update Done: ${response.statusCode}");
      debugPrint("-----------------------------------------Update Done: ${response.body}");
      if (response.statusCode == 200) {
        return true;
      } else {
        debugPrint("-----------------------------------------Update Failed: ${response.statusCode}");
        debugPrint("-----------------------------------------Update Failed: ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("------------------------------------------------API Error: $e");
      return false;
    }
  }



  Future<List<dynamic>> getHolidays() async {
    try {
      var url = Uri.parse("$baseUrl/admin/holiday/all");
      var response = await http.post(url, headers: {
        "Authorization": adminToken ?? "",
        "Content-Type": "application/json"
      });
      debugPrint("-----------------------------------------Holiday Done: ${response.statusCode}");
      debugPrint("-----------------------------------------Holiday Done: ${response.body}");
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        // Agar response { success: true, data: [...] } format me hai
        if (data is Map && data.containsKey('data')) {
          return data['data'];
        }
        // Agar direct list hai
        else if (data is List) {
          return data;
        }
      }
    } catch (e) {
      print("Holiday Fetch Error: $e");
    }
    return [];
  }



  // 🔴 FORCE CHECKOUT API
  Future<Map<String, dynamic>> forceCheckOut({
    required List<double> faceEmbedding,
    required double latitude,
    required double longitude,
    required bool isFromAdminPhone,
    required String deviceDate,
  }) async {
    try {
      // 🔴 Endpoint changed to /forceCheckOut
      var url = Uri.parse("$baseUrl/employee/attendance/create");

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('saved_token');

      var response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "$token",
        },
        body: jsonEncode({

          "faceEmbedding": faceEmbedding,
          "latitude": latitude,
          "longitude": longitude,
          "isFromAdminPhone": isFromAdminPhone,
          "forceCheckOut": true,
          "deviceDate": deviceDate
        }),
      );
      debugPrint("-----------------------------------------Force checkout Done: ${response.statusCode}");
      debugPrint("-----------------------------------------Force checkout Done: ${response.body}");
      var data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201 && data['success'] == true) {
        return {
          "success": data['success'] ?? false,
          "message": data['message'] ?? "Unknown",
          "data": data['data'] // User details (Name, Photo etc.)
        };
      } else {
        return {"success": false, "message": "Server Error: ${response.statusCode}"};
      }
    } catch (e) {
      print("🔥-------------------------------------- Mark Attendance Error: $e");
      return {"success": false, "message": "Connection Error"};
    }
  }


  Future<Map<String, dynamic>?> fetchUserProfile(String empId) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token') ?? prefs.getString('saved_token');

      if (token == null) return null;

      var url = Uri.parse("$baseUrl/employee/get/$empId");

      var response = await http.get(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": token,
        },
      );
      debugPrint("-----------------------------------------fetchUserProfile  Done: ${response.statusCode}");
      debugPrint("-----------------------------------------fetchUserProfile Done: ${response.body}");
      if (response.statusCode == 200) {
        var json = jsonDecode(response.body);
        if (json['success'] == true) {
          // Pura data object return kar rahe hain (isme location aur department dono hote hain)
          return json['data'];
        }
      }
    } catch (e) {
      print("Profile Fetch Error: $e");
    }
    return null;
  }




  Future<bool> checkAdminDevice(String deviceId) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/admin/checkAdminDevice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"deviceId": deviceId}),
      );
      debugPrint("-----------------------------------------My  id: ${deviceId}");
      debugPrint("-----------------------------------------Admin id is   Done: ${response.statusCode}");
      debugPrint("-----------------------------------------Admin id is Done: ${response.body}");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['isAdmin'] ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }



}






