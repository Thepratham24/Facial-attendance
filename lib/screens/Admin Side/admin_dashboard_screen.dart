import 'dart:io';
import 'package:face_attendance/screens/Admin%20Side/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../Result_StartLogin Side/login_screen.dart';
import 'all_employee_list_screen.dart';
import 'all_employees_attendace_list.dart';
import 'admin_attendance_screen.dart';
import 'attendance_history_screen.dart';
import 'register_employee_screen.dart';
import 'holiday_calendar_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  final Color darkBlue = const Color(0xFF2E3192);
  final Color skyBlue = const Color(0xFF00D2FF);
  final Color bgColor = const Color(0xFFF2F5F9);

  final List<Widget> _pages = [
    const DashboardHomeFragment(),        // Index 0: Home
    const EmployeeListScreen(),           // Index 1: Staff
    const AllEmployeesAttendanceList(),   // Index 2: Reports
    const SettingsScreen(),               // Index 3: Settings
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // 🔴 BACK BUTTON LOGIC
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          _selectedIndex = 0;
        });
      },
      child: Scaffold(
        backgroundColor: bgColor,

        // Body
        body: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),

        // Bottom Navigation
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.grey.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, -5))
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildNavItem(Icons.dashboard_rounded, "Home", 0),
                  _buildNavItem(Icons.people_alt_rounded, "Staff", 1),
                  _buildNavItem(Icons.bar_chart_rounded, "Reports", 2),
                  _buildNavItem(Icons.settings_rounded, "Settings", 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = _selectedIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onItemTapped(index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: isSelected
              ? BoxDecoration(color: skyBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12))
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? darkBlue : Colors.grey.shade400, size: 26),
              const SizedBox(height: 4),
              Text(
                  label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? darkBlue : Colors.grey.shade500
                  )
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 🔴 FRAGMENT 1: HOME (SORTED NEWEST FIRST + TIME DISPLAY FIXED)
// ---------------------------------------------------------------------------
class DashboardHomeFragment extends StatefulWidget {
  const DashboardHomeFragment({super.key});

  @override
  State<DashboardHomeFragment> createState() => _DashboardHomeFragmentState();
}

class _DashboardHomeFragmentState extends State<DashboardHomeFragment> {
  final ApiService _apiService = ApiService();

  int total = 0, present = 0, absent = 0;
  List<Map<String, dynamic>> _presentList = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // Helper to safely parse time strings
  DateTime _parseDateTime(String timeStr) {
    try {
      // 1. If ISO format (contains T or Z)
      if (timeStr.contains('T') || timeStr.contains('Z')) {
        return DateTime.parse(timeStr).toLocal();
      }
      // 2. If simple HH:mm:ss format
      final now = DateTime.now();
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        return DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
      }
      return now; // Fallback
    } catch (e) {
      return DateTime.now(); // Error Fallback
    }
  }

  Future<void> _loadAllData() async {
    setState(() => loading = true);
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {

        var statsFuture = _apiService.getDashboardStats();
        var locFuture = _apiService.getLocations();
        var allEmpFuture = _apiService.getAllEmployees();

        var results = await Future.wait([statsFuture, locFuture, allEmpFuture]);

        var statsData = results[0] as Map<String, dynamic>;
        var locations = results[1] as List<dynamic>;
        var allEmployees = results[2] as List<dynamic>;

        Map<String, String> photoMap = {};
        for(var e in allEmployees) {
          String img = e['trim_faceImage'] ?? e['faceImage'] ?? "";
          if(img.isNotEmpty) photoMap[e['_id']] = img;
        }

        List<Map<String, dynamic>> finalPresentList = [];

        if (locations.isNotEmpty) {
          String locId = locations[0]['_id'];
          String date = DateFormat('yyyy-MM-dd').format(DateTime.now());

          var rawData = await _apiService.getAttendanceByDateAndLocation(date, locId);

          for (var emp in rawData) {
            var att = emp['attendance'];
            if (att is List && att.isNotEmpty) att = att[0];

            if (att != null && att is Map) {
              String? timeStr = att['checkInTime'] ?? att['punchIn'] ?? att['createdAt'];

              if (timeStr != null) {
                String empId = emp['employeeId'] ?? "";
                String photo = photoMap[empId] ?? "";

                finalPresentList.add({
                  "name": emp['name'] ?? "Employee",
                  "id": empId,
                  "time": timeStr, // Raw String store kar rahe hain
                  "image": photo,
                  "designation": emp['designation'] ?? "Staff"
                });
              }
            }
          }
        }

        // 🔴 SORTING LOGIC: Newest Time First (Descending)
        if (finalPresentList.isNotEmpty) {
          finalPresentList.sort((a, b) {
            DateTime tA = _parseDateTime(a['time']);
            DateTime tB = _parseDateTime(b['time']);
            return tB.compareTo(tA); // Newest First (B - A)
          });

          // 🔴 LIMIT: Only Top 6
          if (finalPresentList.length > 5) {
            finalPresentList = finalPresentList.sublist(0, 5);
          }
        }

        if (mounted) {
          setState(() {
            total = statsData['total'] ?? 0;
            present = statsData['present'] ?? 0;
            absent = statsData['absent'] ?? 0;
            _presentList = finalPresentList;
            loading = false;
          });
        }
      }
    } catch (e) {
      print("Dashboard Error: $e");
      if (mounted) setState(() { loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: const Color(0xFF2E3192),
      child: Column(
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF00D2FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
              boxShadow: [BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Admin Dashboard", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text("Overview & Management", style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildGlassStatCard("Total Staff", total.toString(), Icons.people),
                    _buildGlassStatCard("Present", present.toString(), Icons.check_circle, isGreen: true),
                    _buildGlassStatCard("Absent", absent.toString(), Icons.cancel, isRed: true),
                  ],
                ),
              ],
            ),
          ),

          // CONTENT
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(child: _buildActionCard("Take\nAttendance", Icons.qr_code_scanner_rounded, const Color(0xFF6366F1), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminAttendanceScreen())))),
                    const SizedBox(width: 15),
                    Expanded(child: _buildActionCard("Register\nEmployee", Icons.person_add_alt_1_rounded, const Color(0xFFF59E0B), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceRegisterScreen())))),
                  ],
                ),
                const SizedBox(height: 25),

                // HEADER
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Recently Present", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AllEmployeesAttendanceList()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2E3192).withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              )
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                "View All",
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // LIST
                loading
                    ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                    : _presentList.isEmpty
                    ? _buildEmptyState()
                    : Column(children: _presentList.map((emp) => _buildPresentCard(emp)).toList()),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassStatCard(String label, String value, IconData icon, {bool isGreen = false, bool isRed = false}) {
    Color iconColor = isGreen ? Colors.greenAccent : (isRed ? Colors.redAccent : Colors.white);
    return Container(
      width: 100, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white.withOpacity(0.2))),
      child: Column(children: [Icon(icon, color: iconColor, size: 22), const SizedBox(height: 8), Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))]),
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 8))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 26)), Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey[800], height: 1.2))]),
      ),
    );
  }

  // 🔴 PRESENT CARD - UPDATED WITH TIME LOGIC
  Widget _buildPresentCard(Map<String, dynamic> emp) {
    // Parsing Time with Robust Logic
    String displayTime = "--:--";
    try {
      DateTime dt = _parseDateTime(emp['time']);
      displayTime = DateFormat('hh:mm a').format(dt);
    } catch (_) {}

    String fullImageUrl = emp['image'].isNotEmpty ? "${_apiService.baseUrl}/${emp['image']}" : "";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2), // Optional: Border looks good
              ),
              child: ClipOval(
                child: fullImageUrl.isNotEmpty
                    ? Image.network(
                  fullImageUrl,
                  fit: BoxFit.cover,
                  // 🔴 MAGIC FIX: Agar 403/404 error aaya to ye chalega
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset('assets/img.png', fit: BoxFit.cover);
                  },
                  // Loading jab tak image download ho rahi ho
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                        child: SizedBox(
                            width: 15, height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2)
                        )
                    );
                  },
                )
                    : Image.asset('assets/img.png', fit: BoxFit.cover), // Agar URL hi khali ho
              ),
            ),
            Positioned(bottom: 0, right: 0, child: Container(height: 12, width: 12, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))
          ],
        ),
        title: Text(emp['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),

        // 🔴 TIME VISIBLE HERE
        subtitle: Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text("In: $displayTime", style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600))
            ]
        ),

        trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Text("Present", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold))),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(children: [const SizedBox(height: 20), Icon(Icons.person_off_rounded, size: 40, color: Colors.grey.shade300), const SizedBox(height: 10), Text("No one present yet", style: TextStyle(color: Colors.grey.shade400, fontSize: 14))]));
  }
}











// import 'dart:io';
// import 'package:face_attendance/screens/Admin%20Side/settings_screen.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:intl/intl.dart';
//
// import '../../services/api_service.dart';
// import '../Result_StartLogin Side/login_screen.dart';
// import 'all_employee_list_screen.dart';
// import 'all_employees_attendace_list.dart';
// import 'admin_attendance_screen.dart';
// import 'attendance_history_screen.dart';
// import 'register_employee_screen.dart';
// import 'holiday_calendar_screen.dart';
//
// class AdminDashboard extends StatefulWidget {
//   const AdminDashboard({super.key});
//
//   @override
//   State<AdminDashboard> createState() => _AdminDashboardState();
// }
//
// class _AdminDashboardState extends State<AdminDashboard> {
//   int _selectedIndex = 0;
//
//   final Color darkBlue = const Color(0xFF2E3192);
//   final Color skyBlue = const Color(0xFF00D2FF);
//   final Color bgColor = const Color(0xFFF2F5F9);
//
//   final List<Widget> _pages = [
//     const DashboardHomeFragment(),
//     const EmployeeListScreen(),
//     const AllEmployeesAttendanceList(),
//     const SettingsScreen(),
//   ];
//
//   void _onItemTapped(int index) {
//     setState(() => _selectedIndex = index);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return PopScope(
//       canPop: false,
//       onPopInvokedWithResult: (didPop, result) => SystemNavigator.pop(),
//       child: Scaffold(
//         backgroundColor: bgColor,
//         body: IndexedStack(
//           index: _selectedIndex,
//           children: _pages,
//         ),
//         bottomNavigationBar: Container(
//           decoration: BoxDecoration(
//             color: Colors.white,
//             boxShadow: [
//               BoxShadow(color: Colors.grey.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, -5))
//             ],
//           ),
//           child: SafeArea(
//             child: Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   _buildNavItem(Icons.dashboard_rounded, "Home", 0),
//                   _buildNavItem(Icons.people_alt_rounded, "Staff", 1),
//                   _buildNavItem(Icons.bar_chart_rounded, "Reports", 2),
//                   _buildNavItem(Icons.settings_rounded, "Settings", 3),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildNavItem(IconData icon, String label, int index) {
//     bool isSelected = _selectedIndex == index;
//     return Expanded(
//       child: InkWell(
//         onTap: () => _onItemTapped(index),
//         borderRadius: BorderRadius.circular(12),
//         child: Container(
//           padding: const EdgeInsets.symmetric(vertical: 8),
//           decoration: isSelected
//               ? BoxDecoration(color: skyBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12))
//               : null,
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Icon(icon, color: isSelected ? darkBlue : Colors.grey.shade400, size: 26),
//               const SizedBox(height: 4),
//               Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? darkBlue : Colors.grey.shade500))
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// // ---------------------------------------------------------------------------
// // 🔴 FRAGMENT 1: HOME (FIXED LOGIC FOR PHOTO & TIME)
// // ---------------------------------------------------------------------------
// class DashboardHomeFragment extends StatefulWidget {
//   const DashboardHomeFragment({super.key});
//
//   @override
//   State<DashboardHomeFragment> createState() => _DashboardHomeFragmentState();
// }
//
// class _DashboardHomeFragmentState extends State<DashboardHomeFragment> {
//   final ApiService _apiService = ApiService();
//
//   int total = 0, present = 0, absent = 0;
//   List<Map<String, dynamic>> _presentList = []; // Fixed Type
//   bool loading = true;
//
//   @override
//   void initState() {
//     super.initState();
//     _loadAllData();
//   }
//
//   Future<void> _loadAllData() async {
//     setState(() => loading = true);
//     try {
//       final result = await InternetAddress.lookup('google.com');
//       if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
//
//         // 1. Fetch Stats & Locations & All Employees (For Photos)
//         var statsFuture = _apiService.getDashboardStats();
//         var locFuture = _apiService.getLocations();
//         var allEmpFuture = _apiService.getAllEmployees();
//
//         var results = await Future.wait([statsFuture, locFuture, allEmpFuture]);
//
//         var statsData = results[0] as Map<String, dynamic>;
//         var locations = results[1] as List<dynamic>;
//         var allEmployees = results[2] as List<dynamic>;
//
//         // 🔴 IMAGE MAP (ID -> Image URL)
//         Map<String, String> photoMap = {};
//         for(var e in allEmployees) {
//           String img = e['trim_faceImage'] ?? e['faceImage'] ?? "";
//           if(img.isNotEmpty) photoMap[e['_id']] = img;
//         }
//
//         List<Map<String, dynamic>> finalPresentList = [];
//
//         if (locations.isNotEmpty) {
//           String locId = locations[0]['_id'];
//           String date = DateFormat('yyyy-MM-dd').format(DateTime.now());
//
//           // 2. Fetch Attendance
//           var rawData = await _apiService.getAttendanceByDateAndLocation(date, locId);
//
//           for (var emp in rawData) {
//             var att = emp['attendance'];
//
//             // Handle List vs Object mismatch from Backend
//             if (att is List && att.isNotEmpty) att = att[0];
//
//             if (att != null && att is Map) {
//               // 🔴 Check Time (CheckIn OR PunchIn OR CreatedAt)
//               String? timeStr = att['checkInTime'] ?? att['punchIn'] ?? att['createdAt'];
//
//               if (timeStr != null) {
//                 // 🔴 Merge Photo from Map
//                 String empId = emp['employeeId'] ?? "";
//                 String photo = photoMap[empId] ?? ""; // Get photo from All Employees List
//
//                 finalPresentList.add({
//                   "name": emp['name'] ?? "Employee",
//                   "id": empId,
//                   "time": timeStr,
//                   "image": photo,
//                   "designation": emp['designation'] ?? "Staff"
//                 });
//               }
//             }
//           }
//         }
//
//         if (mounted) {
//           setState(() {
//             total = statsData['total'] ?? 0;
//             present = statsData['present'] ?? 0;
//             absent = statsData['absent'] ?? 0;
//             _presentList = finalPresentList;
//             loading = false;
//           });
//         }
//       }
//     } catch (e) {
//       print("Dashboard Error: $e");
//       if (mounted) setState(() { loading = false; });
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return RefreshIndicator(
//       onRefresh: _loadAllData,
//       color: const Color(0xFF2E3192),
//       child: Column(
//         children: [
//           // HEADER
//           Container(
//             padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
//             decoration: const BoxDecoration(
//               gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF00D2FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
//               borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
//               boxShadow: [BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10))],
//             ),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 const Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text("Admin Dashboard", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
//                         SizedBox(height: 4),
//                         Text("Overview & Management", style: TextStyle(color: Colors.white70, fontSize: 13)),
//                       ],
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 25),
//                 loading
//                     ? const Center(child: CircularProgressIndicator(color: Colors.white))
//                     : Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     _buildGlassStatCard("Total Staff", total.toString(), Icons.people),
//                     _buildGlassStatCard("Present", present.toString(), Icons.check_circle, isGreen: true),
//                     _buildGlassStatCard("Absent", absent.toString(), Icons.cancel, isRed: true),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//
//           // CONTENT
//           Expanded(
//             child: ListView(
//               padding: const EdgeInsets.all(20),
//               children: [
//                 Row(
//                   children: [
//                     Expanded(child: _buildActionCard("Take\nAttendance", Icons.qr_code_scanner_rounded, const Color(0xFF6366F1), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminAttendanceScreen())))),
//                     const SizedBox(width: 15),
//                     Expanded(child: _buildActionCard("Register\nEmployee", Icons.person_add_alt_1_rounded, const Color(0xFFF59E0B), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceRegisterScreen())))),
//                   ],
//                 ),
//                 const SizedBox(height: 25),
//
//                 // HEADER
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     const Text("Present Today", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//                       decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
//                       child: GestureDetector(
//                         onTap: () {
//                           Navigator.push(
//                             context,
//                             MaterialPageRoute(builder: (context) => const AllEmployeesAttendanceList()),
//                           );
//                         },
//                         child: Container(
//                           padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                           decoration: BoxDecoration(
//                             gradient: const LinearGradient(
//                               colors: [Color(0xFF2E3192), Color(0xFF00D2FF)], // Premium Gradient
//                               begin: Alignment.topLeft,
//                               end: Alignment.bottomRight,
//                             ),
//                             borderRadius: BorderRadius.circular(20), // Pill Shape
//                             boxShadow: [
//                               BoxShadow(
//                                 color: const Color(0xFF2E3192).withOpacity(0.3),
//                                 blurRadius: 6,
//                                 offset: const Offset(0, 3),
//                               )
//                             ],
//                           ),
//                           child: Row(
//                             mainAxisSize: MainAxisSize.min, // Button utna hi bada hoga jitna text hai
//                             children: const [
//                               Text(
//                                 "View All",
//                                 style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
//                               ),
//                               SizedBox(width: 4),
//                               Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 12),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 15),
//
//                 // LIST
//                 loading
//                     ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
//                     : _presentList.isEmpty
//                     ? _buildEmptyState()
//                     : Column(children: _presentList.map((emp) => _buildPresentCard(emp)).toList()),
//
//                 const SizedBox(height: 20),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildGlassStatCard(String label, String value, IconData icon, {bool isGreen = false, bool isRed = false}) {
//     Color iconColor = isGreen ? Colors.greenAccent : (isRed ? Colors.redAccent : Colors.white);
//     return Container(
//       width: 100, padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white.withOpacity(0.2))),
//       child: Column(children: [Icon(icon, color: iconColor, size: 22), const SizedBox(height: 8), Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))]),
//     );
//   }
//
//   Widget _buildActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         height: 130, padding: const EdgeInsets.all(16),
//         decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 8))]),
//         child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 26)), Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey[800], height: 1.2))]),
//       ),
//     );
//   }
//
//   // 🔴 PRESENT CARD with PHOTO & TIME
//   Widget _buildPresentCard(Map<String, dynamic> emp) {
//     String time = "--:--";
//     try { time = DateFormat('hh:mm a').format(DateTime.parse(emp['time']).toLocal()); } catch(_) {}
//
//     String fullImageUrl = emp['image'].isNotEmpty ? "${_apiService.baseUrl}/${emp['image']}" : "";
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]),
//       child: ListTile(
//         // onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(employeeName: emp['name'], employeeId: emp['id'], locationId: ""))),
//         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//         leading: Stack(
//           children: [
//             Container(
//               width: 48, height: 48,
//               decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle, image: fullImageUrl.isNotEmpty ? DecorationImage(image: NetworkImage(fullImageUrl), fit: BoxFit.cover) : null),
//               child: fullImageUrl.isEmpty ? Center(child: Text(emp['name'][0], style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E3192)))) : null,
//             ),
//             Positioned(bottom: 0, right: 0, child: Container(height: 12, width: 12, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))
//           ],
//         ),
//         title: Text(emp['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
//         // subtitle: Row(children: [Icon(Icons.access_time_rounded, size: 12, color: Colors.grey), const SizedBox(width: 4), Text("In: $time", style: const TextStyle(fontSize: 12, color: Colors.grey))]),
//         trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Text("Present", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold))),
//       ),
//     );
//   }
//
//   Widget _buildEmptyState() {
//     return Center(child: Column(children: [const SizedBox(height: 20), Icon(Icons.person_off_rounded, size: 40, color: Colors.grey.shade300), const SizedBox(height: 10), Text("No one present yet", style: TextStyle(color: Colors.grey.shade400, fontSize: 14))]));
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
//
//
//
//
//
//
//
// // import 'dart:io';
// // import 'package:face_attendance/screens/Admin%20Side/settings_screen.dart';
// // import 'package:flutter/material.dart';
// // import 'package:flutter/services.dart';
// //
// // // Aapke Project Imports
// // import '../../services/api_service.dart';
// // import '../Result_StartLogin Side/login_screen.dart';
// // import 'all_employee_list_screen.dart';
// // import 'all_employees_attendace_list.dart';
// // import 'admin_attendance_screen.dart';
// // import 'attendance_history_screen.dart';
// // import 'register_employee_screen.dart';
// //
// // class AdminDashboard extends StatefulWidget {
// //   const AdminDashboard({super.key});
// //
// //   @override
// //   State<AdminDashboard> createState() => _AdminDashboardState();
// // }
// //
// // class _AdminDashboardState extends State<AdminDashboard> {
// //   int _selectedIndex = 0;
// //
// //   // 🔴 SKY BLUE THEME COLORS
// //   final Color darkBlue = const Color(0xFF2E3192);
// //   final Color skyBlue = const Color(0xFF00D2FF);
// //   final Color bgColor = const Color(0xFFF2F5F9);
// //
// //   // 🔴 PAGES
// //   final List<Widget> _pages = [
// //     const DashboardHomeFragment(), // Home
// //     const EmployeeListScreen(),    // Staff List
// //     const AllEmployeesAttendanceList(), // Reports
// //     const SettingsScreen(), // 🔴 NEW SETTINGS PAGE
// //   ];
// //
// //   void _onItemTapped(int index) {
// //     setState(() {
// //       _selectedIndex = index;
// //     });
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return PopScope(
// //       canPop: false,
// //       onPopInvokedWithResult: (didPop, result) => SystemNavigator.pop(),
// //       child: Scaffold(
// //         backgroundColor: bgColor,
// //
// //         // 🔴 BODY
// //         body: IndexedStack(
// //           index: _selectedIndex,
// //           children: _pages,
// //         ),
// //
// //         // 🔴 CENTER FLOATING SCAN BUTTON
// //
// //         // 🔴 BOTTOM NAVIGATION BAR
// //         bottomNavigationBar: BottomAppBar(
// //           shape: const CircularNotchedRectangle(),
// //           notchMargin: 8.0,
// //           color: Colors.white,
// //           elevation: 20,
// //           surfaceTintColor: Colors.white,
// //           height: 70,
// //           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
// //           child: Row(
// //             mainAxisAlignment: MainAxisAlignment.spaceAround,
// //             children: [
// //               _buildNavItem(Icons.dashboard_rounded, "Home", 0),
// //               _buildNavItem(Icons.people_alt_rounded, "Staff", 1),
// //               const SizedBox(width: 40), // Space for FAB
// //               _buildNavItem(Icons.bar_chart_rounded, "Reports", 2),
// //               _buildNavItem(Icons.settings_rounded, "Settings", 3), // 🔴 Changed to Settings
// //             ],
// //           ),
// //         ),
// //       ),
// //     );
// //   }
// //
// //   Widget _buildNavItem(IconData icon, String label, int index) {
// //     bool isSelected = _selectedIndex == index;
// //     return InkWell(
// //       onTap: () => _onItemTapped(index),
// //       borderRadius: BorderRadius.circular(50),
// //       child: Container(
// //         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
// //         child: Column(
// //           mainAxisSize: MainAxisSize.min,
// //           children: [
// //             Icon(
// //               icon,
// //               color: isSelected ? darkBlue : Colors.grey.shade400,
// //               size: 24,
// //             ),
// //             if (isSelected)
// //               Container(
// //                 margin: const EdgeInsets.only(top: 4),
// //                 height: 4, width: 4,
// //                 decoration: BoxDecoration(color: skyBlue, shape: BoxShape.circle),
// //               )
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// // }
// //
// // // ---------------------------------------------------------------------------
// // // 🔴 FRAGMENT 1: HOME (STATS + 2 ACTION CARDS + RECENT LIST)
// // // ---------------------------------------------------------------------------
// // class DashboardHomeFragment extends StatefulWidget {
// //   const DashboardHomeFragment({super.key});
// //
// //   @override
// //   State<DashboardHomeFragment> createState() => _DashboardHomeFragmentState();
// // }
// //
// // class _DashboardHomeFragmentState extends State<DashboardHomeFragment> {
// //   final ApiService _apiService = ApiService();
// //
// //   int total = 0, present = 0, absent = 0;
// //   List<dynamic> _recentLogs = []; // Only recent logs
// //   bool loading = true;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _loadAllData();
// //   }
// //
// //   Future<void> _loadAllData() async {
// //     setState(() => loading = true);
// //     try {
// //       final result = await InternetAddress.lookup('google.com');
// //       if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
// //
// //         var statsFuture = _apiService.getDashboardStats();
// //         var empFuture = _apiService.getAllEmployees();
// //
// //         var results = await Future.wait([statsFuture, empFuture]);
// //         var stats = results[0] as Map<String, dynamic>;
// //         var empList = results[1] as List<dynamic>;
// //
// //         if (mounted) {
// //           setState(() {
// //             total = stats['total'] ?? 0;
// //             present = stats['present'] ?? 0;
// //             absent = stats['absent'] ?? 0;
// //             _recentLogs = empList; // For now showing all, you can filter if API supports recent
// //             loading = false;
// //           });
// //         }
// //       }
// //     } catch (e) {
// //       if (mounted) setState(() { loading = false; });
// //     }
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return RefreshIndicator(
// //       onRefresh: _loadAllData,
// //       color: const Color(0xFF2E3192),
// //       child: Column(
// //         children: [
// //           // 🔴 HEADER (STATS)
// //           Container(
// //             padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
// //             decoration: const BoxDecoration(
// //               gradient: LinearGradient(
// //                 colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
// //                 begin: Alignment.topLeft,
// //                 end: Alignment.bottomRight,
// //               ),
// //               borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
// //               boxShadow: [BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10))],
// //             ),
// //             child: Column(
// //               crossAxisAlignment: CrossAxisAlignment.start,
// //               children: [
// //                 const Row(
// //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                   children: [
// //                     Column(
// //                       crossAxisAlignment: CrossAxisAlignment.start,
// //                       children: [
// //                         Text("Admin Dashboard", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
// //                         SizedBox(height: 4),
// //                         Text("Overview & Management", style: TextStyle(color: Colors.white70, fontSize: 13)),
// //                       ],
// //                     ),
// //                     // CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.notifications_none, color: Colors.white))
// //                   ],
// //                 ),
// //                 const SizedBox(height: 25),
// //                 loading
// //                     ? const Center(child: CircularProgressIndicator(color: Colors.white))
// //                     : Row(
// //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                   children: [
// //                     _buildGlassStatCard("Total Staff", total.toString(), Icons.people),
// //                     _buildGlassStatCard("Present", present.toString(), Icons.check_circle, isGreen: true),
// //                     _buildGlassStatCard("Absent", absent.toString(), Icons.cancel, isRed: true),
// //                   ],
// //                 ),
// //               ],
// //             ),
// //           ),
// //
// //           // SCROLLABLE CONTENT
// //           Expanded(
// //             child: ListView(
// //               padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 100),
// //               children: [
// //
// //                 // 🔴 2 ACTION CARDS (Beautiful Grid)
// //                 Row(
// //                   children: [
// //                     Expanded(
// //                       child: _buildActionCard(
// //                           "Take\nAttendance",
// //                           Icons.qr_code_scanner_rounded,
// //                           const Color(0xFF6366F1),
// //                               () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminAttendanceScreen()))
// //                       ),
// //                     ),
// //                     const SizedBox(width: 15),
// //                     Expanded(
// //                       child: _buildActionCard(
// //                           "Register\nEmployee",
// //                           Icons.person_add_alt_1_rounded,
// //                           const Color(0xFFF59E0B),
// //                               () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceRegisterScreen()))
// //                       ),
// //                     ),
// //                   ],
// //                 ),
// //
// //                 const SizedBox(height: 25),
// //
// //                 // 🔴 RECENT ACTIVITY TITLE
// //                 const Text("Recently Active", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
// //                 const SizedBox(height: 15),
// //
// //                 // 🔴 LIST
// //                 loading
// //                     ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
// //                     : _recentLogs.isEmpty
// //                     ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No data found")))
// //                     : Column(
// //                   children: _recentLogs.take(5).map((emp) => _buildEmployeeCard(emp)).toList(),
// //                 ),
// //               ],
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   Widget _buildGlassStatCard(String label, String value, IconData icon, {bool isGreen = false, bool isRed = false}) {
// //     Color iconColor = isGreen ? Colors.greenAccent : (isRed ? Colors.redAccent : Colors.white);
// //     return Container(
// //       width: 100,
// //       padding: const EdgeInsets.all(12),
// //       decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white.withOpacity(0.2))),
// //       child: Column(
// //         children: [
// //           Icon(icon, color: iconColor, size: 22),
// //           const SizedBox(height: 8),
// //           Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
// //           const SizedBox(height: 4),
// //           Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   // 🔴 BEAUTIFUL ACTION CARD DESIGN
// //   Widget _buildActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
// //     return GestureDetector(
// //       onTap: onTap,
// //       child: Container(
// //         height: 140,
// //         padding: const EdgeInsets.all(20),
// //         decoration: BoxDecoration(
// //           color: Colors.white,
// //           borderRadius: BorderRadius.circular(24),
// //           boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 8))],
// //         ),
// //         child: Column(
// //           crossAxisAlignment: CrossAxisAlignment.start,
// //           mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //           children: [
// //             Container(
// //               padding: const EdgeInsets.all(10),
// //               decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
// //               child: Icon(icon, color: color, size: 28),
// //             ),
// //             Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey[800], height: 1.2)),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// //
// //   Widget _buildEmployeeCard(dynamic emp) {
// //     String name = emp['name'] ?? "Unknown";
// //     String designation = emp['designation'] is String ? emp['designation'] : (emp['designation']?['name'] ?? "Staff");
// //     String imagePath = emp['trim_faceImage'] ?? emp['faceImage'] ?? "";
// //     String fullImageUrl = imagePath.isNotEmpty ? "${_apiService.baseUrl}/$imagePath" : "";
// //
// //     return Container(
// //       margin: const EdgeInsets.only(bottom: 12),
// //       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]),
// //       child: ListTile(
// //         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
// //         leading: CircleAvatar(
// //           radius: 24,
// //           backgroundColor: Colors.blue.withOpacity(0.1),
// //           backgroundImage: fullImageUrl.isNotEmpty ? NetworkImage(fullImageUrl) : null,
// //           child: fullImageUrl.isEmpty ? Text(name[0], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)) : null,
// //         ),
// //         title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
// //         subtitle: Text(designation, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
// //         trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
// //       ),
// //     );
// //   }
// // }
