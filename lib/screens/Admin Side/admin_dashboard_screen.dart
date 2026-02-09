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
    const DashboardHomeFragment(),
    const EmployeeListScreen(),
    const AllEmployeesAttendanceList(),
    const SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => SystemNavigator.pop(),
      child: Scaffold(
        backgroundColor: bgColor,
        body: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),
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
              Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? darkBlue : Colors.grey.shade500))
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 🔴 FRAGMENT 1: HOME (FIXED LOGIC FOR PHOTO & TIME)
// ---------------------------------------------------------------------------
class DashboardHomeFragment extends StatefulWidget {
  const DashboardHomeFragment({super.key});

  @override
  State<DashboardHomeFragment> createState() => _DashboardHomeFragmentState();
}

class _DashboardHomeFragmentState extends State<DashboardHomeFragment> {
  final ApiService _apiService = ApiService();

  int total = 0, present = 0, absent = 0;
  List<Map<String, dynamic>> _presentList = []; // Fixed Type
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => loading = true);
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {

        // 1. Fetch Stats & Locations & All Employees (For Photos)
        var statsFuture = _apiService.getDashboardStats();
        var locFuture = _apiService.getLocations();
        var allEmpFuture = _apiService.getAllEmployees();

        var results = await Future.wait([statsFuture, locFuture, allEmpFuture]);

        var statsData = results[0] as Map<String, dynamic>;
        var locations = results[1] as List<dynamic>;
        var allEmployees = results[2] as List<dynamic>;

        // 🔴 IMAGE MAP (ID -> Image URL)
        Map<String, String> photoMap = {};
        for(var e in allEmployees) {
          String img = e['trim_faceImage'] ?? e['faceImage'] ?? "";
          if(img.isNotEmpty) photoMap[e['_id']] = img;
        }

        List<Map<String, dynamic>> finalPresentList = [];

        if (locations.isNotEmpty) {
          String locId = locations[0]['_id'];
          String date = DateFormat('yyyy-MM-dd').format(DateTime.now());

          // 2. Fetch Attendance
          var rawData = await _apiService.getAttendanceByDateAndLocation(date, locId);

          for (var emp in rawData) {
            var att = emp['attendance'];

            // Handle List vs Object mismatch from Backend
            if (att is List && att.isNotEmpty) att = att[0];

            if (att != null && att is Map) {
              // 🔴 Check Time (CheckIn OR PunchIn OR CreatedAt)
              String? timeStr = att['checkInTime'] ?? att['punchIn'] ?? att['createdAt'];

              if (timeStr != null) {
                // 🔴 Merge Photo from Map
                String empId = emp['employeeId'] ?? "";
                String photo = photoMap[empId] ?? ""; // Get photo from All Employees List

                finalPresentList.add({
                  "name": emp['name'] ?? "Employee",
                  "id": empId,
                  "time": timeStr,
                  "image": photo,
                  "designation": emp['designation'] ?? "Staff"
                });
              }
            }
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
                    const Text("Present Today", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
                      child: Text("Live Feed", style: TextStyle(color: Colors.green.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
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

  // 🔴 PRESENT CARD with PHOTO & TIME
  Widget _buildPresentCard(Map<String, dynamic> emp) {
    String time = "--:--";
    try { time = DateFormat('hh:mm a').format(DateTime.parse(emp['time']).toLocal()); } catch(_) {}

    String fullImageUrl = emp['image'].isNotEmpty ? "${_apiService.baseUrl}/${emp['image']}" : "";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]),
      child: ListTile(
        // onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(employeeName: emp['name'], employeeId: emp['id'], locationId: ""))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle, image: fullImageUrl.isNotEmpty ? DecorationImage(image: NetworkImage(fullImageUrl), fit: BoxFit.cover) : null),
              child: fullImageUrl.isEmpty ? Center(child: Text(emp['name'][0], style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E3192)))) : null,
            ),
            Positioned(bottom: 0, right: 0, child: Container(height: 12, width: 12, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))
          ],
        ),
        title: Text(emp['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
        // subtitle: Row(children: [Icon(Icons.access_time_rounded, size: 12, color: Colors.grey), const SizedBox(width: 4), Text("In: $time", style: const TextStyle(fontSize: 12, color: Colors.grey))]),
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
//
// // Aapke Project Imports
// import '../../services/api_service.dart';
// import '../Result_StartLogin Side/login_screen.dart';
// import 'all_employee_list_screen.dart';
// import 'all_employees_attendace_list.dart';
// import 'admin_attendance_screen.dart';
// import 'attendance_history_screen.dart';
// import 'register_employee_screen.dart';
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
//   // 🔴 SKY BLUE THEME COLORS
//   final Color darkBlue = const Color(0xFF2E3192);
//   final Color skyBlue = const Color(0xFF00D2FF);
//   final Color bgColor = const Color(0xFFF2F5F9);
//
//   // 🔴 PAGES
//   final List<Widget> _pages = [
//     const DashboardHomeFragment(), // Home
//     const EmployeeListScreen(),    // Staff List
//     const AllEmployeesAttendanceList(), // Reports
//     const SettingsScreen(), // 🔴 NEW SETTINGS PAGE
//   ];
//
//   void _onItemTapped(int index) {
//     setState(() {
//       _selectedIndex = index;
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return PopScope(
//       canPop: false,
//       onPopInvokedWithResult: (didPop, result) => SystemNavigator.pop(),
//       child: Scaffold(
//         backgroundColor: bgColor,
//
//         // 🔴 BODY
//         body: IndexedStack(
//           index: _selectedIndex,
//           children: _pages,
//         ),
//
//         // 🔴 CENTER FLOATING SCAN BUTTON
//
//         // 🔴 BOTTOM NAVIGATION BAR
//         bottomNavigationBar: BottomAppBar(
//           shape: const CircularNotchedRectangle(),
//           notchMargin: 8.0,
//           color: Colors.white,
//           elevation: 20,
//           surfaceTintColor: Colors.white,
//           height: 70,
//           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceAround,
//             children: [
//               _buildNavItem(Icons.dashboard_rounded, "Home", 0),
//               _buildNavItem(Icons.people_alt_rounded, "Staff", 1),
//               const SizedBox(width: 40), // Space for FAB
//               _buildNavItem(Icons.bar_chart_rounded, "Reports", 2),
//               _buildNavItem(Icons.settings_rounded, "Settings", 3), // 🔴 Changed to Settings
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildNavItem(IconData icon, String label, int index) {
//     bool isSelected = _selectedIndex == index;
//     return InkWell(
//       onTap: () => _onItemTapped(index),
//       borderRadius: BorderRadius.circular(50),
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(
//               icon,
//               color: isSelected ? darkBlue : Colors.grey.shade400,
//               size: 24,
//             ),
//             if (isSelected)
//               Container(
//                 margin: const EdgeInsets.only(top: 4),
//                 height: 4, width: 4,
//                 decoration: BoxDecoration(color: skyBlue, shape: BoxShape.circle),
//               )
//           ],
//         ),
//       ),
//     );
//   }
// }
//
// // ---------------------------------------------------------------------------
// // 🔴 FRAGMENT 1: HOME (STATS + 2 ACTION CARDS + RECENT LIST)
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
//   List<dynamic> _recentLogs = []; // Only recent logs
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
//         var statsFuture = _apiService.getDashboardStats();
//         var empFuture = _apiService.getAllEmployees();
//
//         var results = await Future.wait([statsFuture, empFuture]);
//         var stats = results[0] as Map<String, dynamic>;
//         var empList = results[1] as List<dynamic>;
//
//         if (mounted) {
//           setState(() {
//             total = stats['total'] ?? 0;
//             present = stats['present'] ?? 0;
//             absent = stats['absent'] ?? 0;
//             _recentLogs = empList; // For now showing all, you can filter if API supports recent
//             loading = false;
//           });
//         }
//       }
//     } catch (e) {
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
//           // 🔴 HEADER (STATS)
//           Container(
//             padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
//             decoration: const BoxDecoration(
//               gradient: LinearGradient(
//                 colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
//                 begin: Alignment.topLeft,
//                 end: Alignment.bottomRight,
//               ),
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
//                     // CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.notifications_none, color: Colors.white))
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
//           // SCROLLABLE CONTENT
//           Expanded(
//             child: ListView(
//               padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 100),
//               children: [
//
//                 // 🔴 2 ACTION CARDS (Beautiful Grid)
//                 Row(
//                   children: [
//                     Expanded(
//                       child: _buildActionCard(
//                           "Take\nAttendance",
//                           Icons.qr_code_scanner_rounded,
//                           const Color(0xFF6366F1),
//                               () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminAttendanceScreen()))
//                       ),
//                     ),
//                     const SizedBox(width: 15),
//                     Expanded(
//                       child: _buildActionCard(
//                           "Register\nEmployee",
//                           Icons.person_add_alt_1_rounded,
//                           const Color(0xFFF59E0B),
//                               () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceRegisterScreen()))
//                       ),
//                     ),
//                   ],
//                 ),
//
//                 const SizedBox(height: 25),
//
//                 // 🔴 RECENT ACTIVITY TITLE
//                 const Text("Recently Active", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
//                 const SizedBox(height: 15),
//
//                 // 🔴 LIST
//                 loading
//                     ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
//                     : _recentLogs.isEmpty
//                     ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No data found")))
//                     : Column(
//                   children: _recentLogs.take(5).map((emp) => _buildEmployeeCard(emp)).toList(),
//                 ),
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
//       width: 100,
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white.withOpacity(0.2))),
//       child: Column(
//         children: [
//           Icon(icon, color: iconColor, size: 22),
//           const SizedBox(height: 8),
//           Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
//           const SizedBox(height: 4),
//           Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
//         ],
//       ),
//     );
//   }
//
//   // 🔴 BEAUTIFUL ACTION CARD DESIGN
//   Widget _buildActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         height: 140,
//         padding: const EdgeInsets.all(20),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(24),
//           boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 8))],
//         ),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Container(
//               padding: const EdgeInsets.all(10),
//               decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
//               child: Icon(icon, color: color, size: 28),
//             ),
//             Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey[800], height: 1.2)),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildEmployeeCard(dynamic emp) {
//     String name = emp['name'] ?? "Unknown";
//     String designation = emp['designation'] is String ? emp['designation'] : (emp['designation']?['name'] ?? "Staff");
//     String imagePath = emp['trim_faceImage'] ?? emp['faceImage'] ?? "";
//     String fullImageUrl = imagePath.isNotEmpty ? "${_apiService.baseUrl}/$imagePath" : "";
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]),
//       child: ListTile(
//         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//         leading: CircleAvatar(
//           radius: 24,
//           backgroundColor: Colors.blue.withOpacity(0.1),
//           backgroundImage: fullImageUrl.isNotEmpty ? NetworkImage(fullImageUrl) : null,
//           child: fullImageUrl.isEmpty ? Text(name[0], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)) : null,
//         ),
//         title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
//         subtitle: Text(designation, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
//         trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
//       ),
//     );
//   }
// }
//
// // ---------------------------------------------------------------------------
// // 🔴 FRAGMENT 4: SETTINGS PAGE
// // ---------------------------------------------------------------------------
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
// //     const DashboardHomeFragment(), // Updated Home
// //     const EmployeeListScreen(),
// //     const AllEmployeesAttendanceList(),
// //     const Center(child: Text("Settings")), // Placeholder
// //   ];
// //
// //   void _onItemTapped(int index) {
// //     if (index == 3) {
// //       _showLogoutDialog();
// //     } else {
// //       setState(() {
// //         _selectedIndex = index;
// //       });
// //     }
// //   }
// //
// //   void _handleLogout() async {
// //     await ApiService.logoutAdmin();
// //     if (mounted) {
// //       Navigator.pushAndRemoveUntil(
// //           context,
// //           MaterialPageRoute(builder: (context) => const LoginScreen(autoLogin: false)),
// //               (route) => false);
// //     }
// //   }
// //
// //   void _showLogoutDialog() {
// //     showDialog(
// //       context: context,
// //       builder: (c) => AlertDialog(
// //         title: const Text("Logout"),
// //         content: const Text("Are you sure you want to exit?"),
// //         actions: [
// //           TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
// //           TextButton(onPressed: _handleLogout, child: const Text("Logout", style: TextStyle(color: Colors.red))),
// //         ],
// //       ),
// //     );
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
// //         floatingActionButton: Container(
// //           height: 70, width: 70,
// //           decoration: BoxDecoration(
// //               shape: BoxShape.circle,
// //               gradient: LinearGradient(
// //                 colors: [darkBlue, skyBlue],
// //                 begin: Alignment.topLeft,
// //                 end: Alignment.bottomRight,
// //               ),
// //               boxShadow: [
// //                 BoxShadow(color: skyBlue.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))
// //               ]
// //           ),
// //           child: FloatingActionButton(
// //             onPressed: () {
// //               Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminAttendanceScreen()));
// //             },
// //             backgroundColor: Colors.transparent,
// //             elevation: 0,
// //             shape: const CircleBorder(),
// //             child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 32),
// //           ),
// //         ),
// //         floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
// //
// //         // 🔴 BOTTOM NAVIGATION BAR
// //         bottomNavigationBar: BottomAppBar(
// //           shape: const CircularNotchedRectangle(),
// //           notchMargin: 10.0,
// //           color: Colors.white,
// //           elevation: 20,
// //           surfaceTintColor: Colors.white,
// //           height: 70,
// //           padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
// //           child: Row(
// //             mainAxisAlignment: MainAxisAlignment.spaceAround,
// //             children: [
// //               _buildNavItem(Icons.dashboard_rounded, "Home", 0),
// //               _buildNavItem(Icons.people_alt_rounded, "Staff", 1),
// //               const SizedBox(width: 40), // Space for FAB
// //               _buildNavItem(Icons.bar_chart_rounded, "Reports", 2),
// //               _buildNavItem(Icons.logout_rounded, "Logout", 3),
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
// //         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
// //         child: Column(
// //           mainAxisSize: MainAxisSize.min,
// //           children: [
// //             Icon(
// //               icon,
// //               color: isSelected ? darkBlue : Colors.grey.shade400,
// //               size: 26,
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
// // // 🔴 FRAGMENT 1: HOME (STATS + REGISTER CARD + LIST)
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
// //   List<dynamic> _employees = [];
// //   bool loading = true;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _loadAllData();
// //   }
// //
// //   // 🔴 DATA LOADER
// //   Future<void> _loadAllData() async {
// //     setState(() => loading = true);
// //     try {
// //       final result = await InternetAddress.lookup('google.com');
// //       if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
// //
// //         // Parallel API Calls for speed
// //         var statsFuture = _apiService.getDashboardStats();
// //         var empFuture = _apiService.getAllEmployees();
// //
// //         var results = await Future.wait([statsFuture, empFuture]);
// //
// //         var stats = results[0] as Map<String, dynamic>;
// //         var empList = results[1] as List<dynamic>;
// //
// //         if (mounted) {
// //           setState(() {
// //             total = stats['total'] ?? 0;
// //             present = stats['present'] ?? 0;
// //             absent = stats['absent'] ?? 0;
// //             _employees = empList;
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
// //     // 🔴 REFRESH INDICATOR ADDED
// //     return RefreshIndicator(
// //       onRefresh: _loadAllData,
// //       color: const Color(0xFF2E3192),
// //       child: Column(
// //         children: [
// //           // 🔴 1. BIG HEADER WITH GLASS CARDS
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
// //
// //                   ],
// //                 ),
// //                 const SizedBox(height: 25),
// //
// //                 // 🔴 STATS CARDS (Glassmorphism)
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
// //           // SCROLLABLE CONTENT START
// //           Expanded(
// //             child: ListView(
// //               padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 100),
// //               physics: const AlwaysScrollableScrollPhysics(), // Ensures Refresh works
// //               children: [
// //
// //                 // 🔴 2. BIG REGISTER CARD (Highlight)
// //                 GestureDetector(
// //                   onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceRegisterScreen())),
// //                   child: Container(
// //                     padding: const EdgeInsets.all(20),
// //                     decoration: BoxDecoration(
// //                         gradient: LinearGradient(
// //                           colors: [Colors.indigo.shade600, Colors.indigo.shade400],
// //                           begin: Alignment.centerLeft,
// //                           end: Alignment.centerRight,
// //                         ),
// //                         borderRadius: BorderRadius.circular(20),
// //                         boxShadow: [
// //                           BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))
// //                         ]
// //                     ),
// //                     child: Row(
// //                       children: [
// //                         Container(
// //                           padding: const EdgeInsets.all(12),
// //                           decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
// //                           child: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 30),
// //                         ),
// //                         const SizedBox(width: 15),
// //                         const Column(
// //                           crossAxisAlignment: CrossAxisAlignment.start,
// //                           children: [
// //                             Text("Register New Employee", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
// //                             SizedBox(height: 4),
// //                             Text("Add new staff to database", style: TextStyle(color: Colors.white70, fontSize: 12)),
// //                           ],
// //                         ),
// //                         const Spacer(),
// //                         const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 18)
// //                       ],
// //                     ),
// //                   ),
// //                 ),
// //
// //                 const SizedBox(height: 25),
// //
// //                 // 🔴 3. STAFF DIRECTORY HEADER
// //                 Row(
// //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                   children: [
// //                     const Text("Staff Directory", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
// //                     Text("View All", style: TextStyle(color: Colors.indigo.shade400, fontWeight: FontWeight.bold, fontSize: 13)),
// //                   ],
// //                 ),
// //
// //                 const SizedBox(height: 15),
// //
// //                 // 🔴 4. EMPLOYEE LIST (Inside ListView now to avoid scroll conflict)
// //                 loading
// //                     ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
// //                     : _employees.isEmpty
// //                     ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No employees found")))
// //                     : Column(
// //                   children: _employees.take(10).map((emp) => _buildEmployeeCard(emp)).toList(),
// //                 ),
// //               ],
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   // 🔴 BEAUTIFUL GLASS STAT CARD
// //   Widget _buildGlassStatCard(String label, String value, IconData icon, {bool isGreen = false, bool isRed = false}) {
// //     Color iconColor = isGreen ? Colors.greenAccent : (isRed ? Colors.redAccent : Colors.white);
// //
// //     return Container(
// //       width: 100,
// //       padding: const EdgeInsets.all(12),
// //       decoration: BoxDecoration(
// //         color: Colors.white.withOpacity(0.15),
// //         borderRadius: BorderRadius.circular(15),
// //         border: Border.all(color: Colors.white.withOpacity(0.2)),
// //       ),
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
// //   // 🔴 EMPLOYEE CARD
// //   Widget _buildEmployeeCard(dynamic emp) {
// //     String name = emp['name'] ?? "Unknown";
// //     String empId = emp['_id'] ?? "";
// //     String designation = "Staff";
// //
// //     var rawDesig = emp['designation'];
// //     if (rawDesig is String) designation = rawDesig;
// //     else if (rawDesig is Map) designation = rawDesig['name'] ?? "Staff";
// //
// //     String locationId = "";
// //     var rawLoc = emp['locationId'];
// //     if (rawLoc is String) locationId = rawLoc;
// //     else if (rawLoc is Map) locationId = rawLoc['_id'] ?? "";
// //
// //     String imagePath = emp['trim_faceImage'] ?? emp['faceImage'] ?? "";
// //     String fullImageUrl = imagePath.isNotEmpty ? "${_apiService.baseUrl}/$imagePath" : "";
// //
// //     return Container(
// //       margin: const EdgeInsets.only(bottom: 12),
// //       decoration: BoxDecoration(
// //         color: Colors.white,
// //         borderRadius: BorderRadius.circular(16),
// //         boxShadow: [
// //           BoxShadow(color: Colors.blueGrey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))
// //         ],
// //       ),
// //       child: Material(
// //         color: Colors.transparent,
// //         child: InkWell(
// //           borderRadius: BorderRadius.circular(16),
// //           onTap: () {
// //             Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(
// //                 employeeName: name,
// //                 employeeId: empId,
// //                 locationId: locationId
// //             )));
// //           },
// //           child: Padding(
// //             padding: const EdgeInsets.all(12),
// //             child: Row(
// //               children: [
// //                 Container(
// //                   height: 50, width: 50,
// //                   decoration: BoxDecoration(
// //                       shape: BoxShape.circle,
// //                       border: Border.all(color: const Color(0xFF2E3192).withOpacity(0.1), width: 1.5),
// //                       image: fullImageUrl.isNotEmpty
// //                           ? DecorationImage(image: NetworkImage(fullImageUrl), fit: BoxFit.cover)
// //                           : null
// //                   ),
// //                   child: fullImageUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
// //                 ),
// //                 const SizedBox(width: 15),
// //                 Expanded(
// //                   child: Column(
// //                     crossAxisAlignment: CrossAxisAlignment.start,
// //                     children: [
// //                       Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
// //                       Text(designation, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
// //                     ],
// //                   ),
// //                 ),
// //                 Container(
// //                   padding: const EdgeInsets.all(8),
// //                   decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
// //                   child: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
// //                 )
// //               ],
// //             ),
// //           ),
// //         ),
// //       ),
// //     );
// //   }
// // }
// //
// //
// //
// //
// //
// //
// // // import 'dart:io';
// // //
// // // import 'package:face_attendance/screens/Admin%20Side/register_employee_screen.dart';
// // // import 'package:flutter/material.dart';
// // // import 'package:flutter/services.dart'; // 👈 IMPORT THIS (For App Exit)
// // // import '../../services/api_service.dart';
// // // import '../Result_StartLogin Side/login_screen.dart';
// // // import 'all_employee_list_screen.dart';
// // // import 'all_employees_attendace_list.dart';
// // // import 'admin_attendance_screen.dart';
// // //
// // // class AdminDashboard extends StatefulWidget {
// // //   const AdminDashboard({super.key});
// // //
// // //   @override
// // //   State<AdminDashboard> createState() => _AdminDashboardState();
// // // }
// // //
// // // class _AdminDashboardState extends State<AdminDashboard> {
// // //   final ApiService _apiService = ApiService();
// // //   int totalStaff = 0;
// // //   int presentToday = 0;
// // //   int absentToday = 0;
// // //   bool isLoading = true;
// // //   bool _isOffline = true;
// // //
// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     _loadStats();
// // //   }
// // //
// // //   // Future<void> _loadStats() async {
// // //   //   setState(() => isLoading = true);
// // //   //   final stats = await _apiService.getDashboardStats();
// // //   //   try{
// // //   //     // print(stats);
// // //   //     if (mounted) {
// // //   //       setState(() {
// // //   //         totalStaff = stats['total'] ?? 0;
// // //   //         presentToday = stats['present'] ?? 0;
// // //   //         absentToday = stats['absent'] ?? 0;
// // //   //         isLoading = false;
// // //   //         _isOffline = false;
// // //   //       });
// // //   //     }
// // //   //   }catch(e){
// // //   //     debugPrint("error in admin dashboard: $e");
// // //   //     if (mounted) {
// // //   //       setState(() {
// // //   //         // Data ko 0 kar do
// // //   //         totalStaff = 0;
// // //   //         presentToday = 0;
// // //   //         absentToday = 0;
// // //   //
// // //   //         isLoading = false;
// // //   //         _isOffline = true; // 🔴 ERROR AAYA = INTERNET NAHI HAI (Message dikhao)
// // //   //       });
// // //   //     }
// // //   //   }
// // //   // }
// // //   Future<void> _loadStats() async {
// // //     setState(() => isLoading = true); // Loading shuru
// // //
// // //     try {
// // //       // 🔴 STEP 1: Check Internet Connection (Ping Google)
// // //       final result = await InternetAddress.lookup('google.com');
// // //
// // //       if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
// // //         // ✅ INTERNET CHAL RAHA HAI
// // //
// // //         // Ab API call karo
// // //         final stats = await _apiService.getDashboardStats();
// // //
// // //         if (mounted) {
// // //           setState(() {
// // //             _isOffline = false; // Internet hai, Patti hatao
// // //
// // //             // Data update karo
// // //             totalStaff = stats['total'] ?? 0;
// // //             presentToday = stats['present'] ?? 0;
// // //             absentToday = stats['absent'] ?? 0;
// // //
// // //             isLoading = false;
// // //           });
// // //         }
// // //       }
// // //     } on SocketException catch (_) {
// // //       // ❌ STEP 2: INTERNET BAND HAI (Ye block pakka chalega)
// // //       if (mounted) {
// // //         setState(() {
// // //           _isOffline = true; // 🔴 Red Patti ON karo
// // //
// // //           // Data 0 hi rakho
// // //           totalStaff = 0;
// // //           presentToday = 0;
// // //           absentToday = 0;
// // //
// // //           isLoading = false; // Loading band
// // //         });
// // //       }
// // //     } catch (e) {
// // //       // Koi aur error aaya
// // //       if (mounted) {
// // //         setState(() {
// // //           _isOffline = true; // Error maano
// // //           isLoading = false;
// // //         });
// // //       }
// // //     }
// // //   }
// // //   // 🔴 EXIT APP FUNCTION (Back dabane par App Band)
// // //   void _exitApp() {
// // //     SystemNavigator.pop();
// // //   }
// // //
// // //   // 🔴 LOGOUT HANDLER (Ye Login Page par le jayega aur sab clear karega)
// // //   void _handleLogout() async {
// // //     await ApiService.logoutAdmin();
// // //
// // //     if (mounted) {
// // //       Navigator.pushAndRemoveUntil(
// // //           context,
// // //           MaterialPageRoute(builder: (context) => const LoginScreen(autoLogin: false)),
// // //               (route) => false // 👈 Sab uda do
// // //       );
// // //     }
// // //   }
// // //
// // //   @override
// // //   Widget build(BuildContext context) {
// // //     return PopScope(
// // //       canPop: false, // 🔴 System Back Button disable
// // //       onPopInvokedWithResult: (bool didPop, dynamic result) async {
// // //         if (didPop) return;
// // //         _exitApp(); // 🔴 Ab App Exit hogi
// // //       },
// // //       child: Scaffold(
// // //         backgroundColor: const Color(0xFFF1F5F9),
// // //         body: RefreshIndicator(
// // //           onRefresh: _loadStats,
// // //           color: const Color(0xFF0F172A),
// // //           child: SingleChildScrollView(
// // //             physics: const AlwaysScrollableScrollPhysics(),
// // //             child: Column(
// // //               crossAxisAlignment: CrossAxisAlignment.start,
// // //               children: [
// // //
// // //                 // HEADER
// // //                 Container(
// // //                   width: double.infinity,
// // //                   padding: const EdgeInsets.fromLTRB(25, 60, 25, 40),
// // //                   decoration: const BoxDecoration(
// // //                     color: Color(0xFF0F172A),
// // //                     borderRadius: BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35)),
// // //                   ),
// // //                   child: Column(
// // //                     children: [
// // //                       Row(
// // //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // //                         children: [
// // //                           Column(
// // //                             crossAxisAlignment: CrossAxisAlignment.start,
// // //                             children: [
// // //                               Text("Dashboard", style: TextStyle(color: Colors.blueGrey[300], fontSize: 14, fontWeight: FontWeight.w500)),
// // //                               const SizedBox(height: 6),
// // //                               const Text("Admin Overview", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
// // //                             ],
// // //                           ),
// // //                           InkWell(
// // //                             onTap: _handleLogout, // Logout Button
// // //                             borderRadius: BorderRadius.circular(12),
// // //                             child: Container(
// // //                               padding: const EdgeInsets.all(10),
// // //                               decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
// // //                               child: const Icon(Icons.power_settings_new_rounded, color: Colors.white70, size: 20),
// // //                             ),
// // //                           ),
// // //                         ],
// // //                       ),
// // //
// // //                       const SizedBox(height: 35),
// // //                       Row(
// // //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // //                         children: [
// // //                           _buildStatCard("Total Staff", totalStaff.toString(), Icons.people_alt_rounded, Colors.white),
// // //                           Container(height: 40, width: 1, color: Colors.white.withOpacity(0.1)),
// // //                           _buildStatCard("Present", presentToday.toString(), Icons.check_circle_rounded, const Color(0xFF4ADE80)),
// // //                           Container(height: 40, width: 1, color: Colors.white.withOpacity(0.1)),
// // //                           _buildStatCard("Absent", absentToday.toString(), Icons.cancel_rounded, const Color(0xFFF87171)),
// // //                         ],
// // //                       ),
// // //                     ],
// // //                   ),
// // //                 ),
// // //                 const SizedBox(height: 25),
// // //                 Padding(
// // //                   padding: const EdgeInsets.symmetric(horizontal: 25),
// // //                   child: Column(
// // //                     crossAxisAlignment: CrossAxisAlignment.start,
// // //                     children: [
// // //                       Text("Manage System", style: TextStyle(color: Colors.blueGrey[800], fontSize: 18, fontWeight: FontWeight.bold)),
// // //                       const SizedBox(height: 15),
// // //                       GridView.count(
// // //                         shrinkWrap: true,
// // //                         physics: const NeverScrollableScrollPhysics(),
// // //                         crossAxisCount: 2,
// // //                         crossAxisSpacing: 15,
// // //                         mainAxisSpacing: 15,
// // //                         childAspectRatio: 0.9,
// // //                         children: [
// // //                           _buildAttractiveCard(
// // //                               title: "Take\nAttendance",
// // //                               subtitle: "Start Camera",
// // //                               icon: Icons.qr_code_scanner_rounded,
// // //                               color: const Color(0xFF3B82F6),
// // //                               onTap: () => _navigate(context, const AdminAttendanceScreen())
// // //                           ),
// // //                           _buildAttractiveCard(
// // //                               title: "Employee\nDirectory",
// // //                               subtitle: "Staff List",
// // //                               icon: Icons.people_outline_rounded,
// // //                               color: const Color(0xFFF59E0B),
// // //                               onTap: () => _navigate(context, const EmployeeListScreen())
// // //                           ),
// // //                           _buildAttractiveCard(
// // //                               title: "Daily\nReports",
// // //                               subtitle: "View Logs",
// // //                               icon: Icons.bar_chart_rounded,
// // //                               color: const Color(0xFF10B981),
// // //                               onTap: () => _navigate(context, const AllEmployeesAttendanceList())
// // //                           ),
// // //                           _buildAttractiveCard(
// // //                               title: "Register\nNew User",
// // //                               subtitle: "Add Employee",
// // //                               icon: Icons.person_add_rounded,
// // //                               color: const Color(0xFF6366F1),
// // //                               onTap: () => _navigate(context, const AttendanceRegisterScreen())
// // //                           ),
// // //                         ],
// // //                       ),
// // //                     ],
// // //                   ),
// // //                 ),
// // //                 const SizedBox(height: 30),
// // //                 if (_isOffline)
// // //                   Container(
// // //                     width: double.infinity,
// // //                     color: Colors.redAccent, // Lal rang ka background
// // //                     padding: const EdgeInsets.all(10),
// // //                     child: Row(
// // //                       mainAxisAlignment: MainAxisAlignment.center,
// // //                       children: const [
// // //                         Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
// // //                         SizedBox(width: 10),
// // //                         Text(
// // //                           "No Internet Connection. Pull to Retry.",
// // //                           style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
// // //                         ),
// // //                       ],
// // //                     ),
// // //                   ),
// // //               ],
// // //             ),
// // //           ),
// // //         ),
// // //       ),
// // //     );
// // //   }
// // //
// // //   // ... (Baaki ke Helper Widgets same rahenge) ...
// // //   Widget _buildStatCard(String label, String value, IconData icon, Color color) {
// // //     return Column(
// // //       children: [
// // //         Icon(icon, color: color, size: 24),
// // //         const SizedBox(height: 8),
// // //         Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
// // //         const SizedBox(height: 4),
// // //         Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
// // //       ],
// // //     );
// // //   }
// // //
// // //   Widget _buildAttractiveCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
// // //     return GestureDetector(
// // //       onTap: onTap,
// // //       child: Container(
// // //         decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: const Color(0xFF64748B).withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))]),
// // //         child: Stack(
// // //           children: [
// // //             Positioned(right: -10, bottom: -10, child: Icon(icon, size: 80, color: color.withOpacity(0.05))),
// // //             Padding(
// // //               padding: const EdgeInsets.all(18),
// // //               child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
// // //                 Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(height: 45, width: 45, decoration: BoxDecoration(gradient: LinearGradient(colors: [color, color.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]), child: Icon(icon, color: Colors.white, size: 22)), Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.grey[300])]),
// // //                 Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 15, fontWeight: FontWeight.bold, height: 1.2)), const SizedBox(height: 4), Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 11, fontWeight: FontWeight.w500))]),
// // //               ]),
// // //             ),
// // //           ],
// // //         ),
// // //       ),
// // //     );
// // //   }
// // //
// // //   // 🔴 Simple Push Navigation (Back button will work)
// // //   void _navigate(BuildContext context, Widget page) {
// // //     Navigator.push(context, MaterialPageRoute(builder: (context) => page)).then((_) => _loadStats());
// // //   }
// // // }
// // //
// // //
// // //
// // //
// // //
// // //
// // // // import 'package:face_attendance/screens/Admin%20Side/register_employee_screen.dart';
// // // // import 'package:flutter/material.dart';
// // // // import '../../services/api_service.dart';
// // // // import '../Result_StartLogin Side/login_screen.dart';
// // // // import 'all_employee_list_screen.dart';
// // // // import 'all_employees_attendace_list.dart';
// // // // import 'admin_attendance_screen.dart';
// // // //
// // // // class AdminDashboard extends StatefulWidget {
// // // //   const AdminDashboard({super.key});
// // // //
// // // //   @override
// // // //   State<AdminDashboard> createState() => _AdminDashboardState();
// // // // }
// // // //
// // // // class _AdminDashboardState extends State<AdminDashboard> {
// // // //   final ApiService _apiService = ApiService();
// // // //   int totalStaff = 0;
// // // //   int presentToday = 0;
// // // //   int absentToday = 0;
// // // //   bool isLoading = true;
// // // //
// // // //   @override
// // // //   void initState() {
// // // //     super.initState();
// // // //     _loadStats();
// // // //   }
// // // //
// // // //   Future<void> _loadStats() async {
// // // //     setState(() => isLoading = true);
// // // //     final stats = await _apiService.getDashboardStats();
// // // //     if (mounted) {
// // // //       setState(() {
// // // //         totalStaff = stats['total'];
// // // //         presentToday = stats['present'];
// // // //         absentToday = stats['absent'];
// // // //         isLoading = false;
// // // //       });
// // // //     }
// // // //   }
// // // //
// // // //   // 🔴 BACK HANDLER: GO TO LOGIN SCREEN (AUTO LOGIN FALSE)
// // // //   void _goBackToSelection() {
// // // //     Navigator.pushReplacement(
// // // //       context,
// // // //       MaterialPageRoute(builder: (context) => const LoginScreen(autoLogin: false)),
// // // //     );
// // // //   }
// // // //
// // // //   // 🔴 LOGOUT HANDLER (Ye data clear karega)
// // // //   void _handleLogout() async {
// // // //
// // // //     // ✅ Change Here: Call Specific Admin Logout
// // // //     await ApiService.logoutAdmin();
// // // //
// // // //     if (mounted) {
// // // //       Navigator.pushAndRemoveUntil(
// // // //           context,
// // // //           MaterialPageRoute(builder: (context) => const LoginScreen(autoLogin: false)),
// // // //               (route) => false
// // // //       );
// // // //     }
// // // //   }
// // // //
// // // //   @override
// // // //   Widget build(BuildContext context) {
// // // //     return PopScope(
// // // //       canPop: false,
// // // //       onPopInvokedWithResult: (bool didPop, dynamic result) async {
// // // //         if (didPop) return;
// // // //         _goBackToSelection();
// // // //       },
// // // //       child: Scaffold(
// // // //         backgroundColor: const Color(0xFFF1F5F9),
// // // //         body: RefreshIndicator(
// // // //           onRefresh: _loadStats,
// // // //           color: const Color(0xFF0F172A),
// // // //           child: SingleChildScrollView(
// // // //             physics: const AlwaysScrollableScrollPhysics(),
// // // //             child: Column(
// // // //               crossAxisAlignment: CrossAxisAlignment.start,
// // // //               children: [
// // // //                 Container(
// // // //                   width: double.infinity,
// // // //                   padding: const EdgeInsets.fromLTRB(25, 60, 25, 40),
// // // //                   decoration: const BoxDecoration(
// // // //                     color: Color(0xFF0F172A),
// // // //                     borderRadius: BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35)),
// // // //                   ),
// // // //                   child: Column(
// // // //                     children: [
// // // //                       Row(
// // // //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // // //                         children: [
// // // //                           Column(
// // // //                             crossAxisAlignment: CrossAxisAlignment.start,
// // // //                             children: [
// // // //                               Text("Dashboard", style: TextStyle(color: Colors.blueGrey[300], fontSize: 14, fontWeight: FontWeight.w500)),
// // // //                               const SizedBox(height: 6),
// // // //                               const Text("Admin Overview", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
// // // //                             ],
// // // //                           ),
// // // //                           InkWell(
// // // //                             onTap: _handleLogout, // Logout Button
// // // //                             borderRadius: BorderRadius.circular(12),
// // // //                             child: Container(
// // // //                               padding: const EdgeInsets.all(10),
// // // //                               decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
// // // //                               child: const Icon(Icons.power_settings_new_rounded, color: Colors.white70, size: 20),
// // // //                             ),
// // // //                           ),
// // // //                         ],
// // // //                       ),
// // // //                       const SizedBox(height: 35),
// // // //                       Row(
// // // //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // // //                         children: [
// // // //                           _buildStatCard("Total Staff", totalStaff.toString(), Icons.people_alt_rounded, Colors.white),
// // // //                           Container(height: 40, width: 1, color: Colors.white.withOpacity(0.1)),
// // // //                           _buildStatCard("Present", presentToday.toString(), Icons.check_circle_rounded, const Color(0xFF4ADE80)),
// // // //                           Container(height: 40, width: 1, color: Colors.white.withOpacity(0.1)),
// // // //                           _buildStatCard("Absent", absentToday.toString(), Icons.cancel_rounded, const Color(0xFFF87171)),
// // // //                         ],
// // // //                       ),
// // // //                     ],
// // // //                   ),
// // // //                 ),
// // // //                 const SizedBox(height: 25),
// // // //                 Padding(
// // // //                   padding: const EdgeInsets.symmetric(horizontal: 25),
// // // //                   child: Column(
// // // //                     crossAxisAlignment: CrossAxisAlignment.start,
// // // //                     children: [
// // // //                       Text("Manage System", style: TextStyle(color: Colors.blueGrey[800], fontSize: 18, fontWeight: FontWeight.bold)),
// // // //                       const SizedBox(height: 15),
// // // //                       GridView.count(
// // // //                         shrinkWrap: true,
// // // //                         physics: const NeverScrollableScrollPhysics(),
// // // //                         crossAxisCount: 2,
// // // //                         crossAxisSpacing: 15,
// // // //                         mainAxisSpacing: 15,
// // // //                         childAspectRatio: 0.9,
// // // //                         children: [
// // // //                           _buildAttractiveCard(title: "Take\nAttendance", subtitle: "Start Camera", icon: Icons.qr_code_scanner_rounded, color: const Color(0xFF3B82F6), onTap: () => _navigate(context, const AdminAttendanceScreen())),
// // // //                           _buildAttractiveCard(title: "Employee\nDirectory", subtitle: "Staff List", icon: Icons.people_outline_rounded, color: const Color(0xFFF59E0B), onTap: () => _navigate(context, const EmployeeListScreen())),
// // // //                           _buildAttractiveCard(title: "Daily\nReports", subtitle: "View Logs", icon: Icons.bar_chart_rounded, color: const Color(0xFF10B981), onTap: () => _navigate(context, const AllEmployeesAttendanceList())),
// // // //                           _buildAttractiveCard(title: "Register\nNew User", subtitle: "Add Employee", icon: Icons.person_add_rounded, color: const Color(0xFF6366F1), onTap: () => _navigate(context, const AttendanceRegisterScreen())),
// // // //                         ],
// // // //                       ),
// // // //                     ],
// // // //                   ),
// // // //                 ),
// // // //                 const SizedBox(height: 30),
// // // //               ],
// // // //             ),
// // // //           ),
// // // //         ),
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildStatCard(String label, String value, IconData icon, Color color) {
// // // //     return Column(
// // // //       children: [
// // // //         Icon(icon, color: color, size: 24),
// // // //         const SizedBox(height: 8),
// // // //         Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
// // // //         const SizedBox(height: 4),
// // // //         Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
// // // //       ],
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildAttractiveCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
// // // //     return GestureDetector(
// // // //       onTap: onTap,
// // // //       child: Container(
// // // //         decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: const Color(0xFF64748B).withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))]),
// // // //         child: Stack(
// // // //           children: [
// // // //             Positioned(right: -10, bottom: -10, child: Icon(icon, size: 80, color: color.withOpacity(0.05))),
// // // //             Padding(
// // // //               padding: const EdgeInsets.all(18),
// // // //               child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
// // // //                 Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(height: 45, width: 45, decoration: BoxDecoration(gradient: LinearGradient(colors: [color, color.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]), child: Icon(icon, color: Colors.white, size: 22)), Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.grey[300])]),
// // // //                 Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 15, fontWeight: FontWeight.bold, height: 1.2)), const SizedBox(height: 4), Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 11, fontWeight: FontWeight.w500))]),
// // // //               ]),
// // // //             ),
// // // //           ],
// // // //         ),
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   void _navigate(BuildContext context, Widget page) {
// // // //     Navigator.push(context, MaterialPageRoute(builder: (context) => page)).then((_) => _loadStats());
// // // //   }
// // // // }
// // // //
// // // //
// // // //
// // // //
// // // //
