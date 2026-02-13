import 'dart:io';
import 'package:face_attendance/screens/Admin%20Side/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import 'all_employee_list_screen.dart';
import 'all_employees_attendace_list.dart';
import 'admin_attendance_screen.dart';
import 'register_employee_screen.dart' hide AdminAttendanceScreen;

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
    const DashboardHomeFragment(), // Index 0: Home
    const EmployeeListScreen(), // Index 1: Staff
    const AllEmployeesAttendanceList(), // Index 2: Reports
    const SettingsScreen(), // Index 3: Settings
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
        } else {
          SystemNavigator.pop(); // App Close
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
        // 🔴 IndexedStack Hataya: Ab har tab par fresh API call hogi
        body: _pages[_selectedIndex],
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.grey.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, -5))
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
              ? BoxDecoration(
              color: skyBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12))
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: isSelected ? darkBlue : Colors.grey.shade400,
                  size: 26),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? darkBlue : Colors.grey.shade500))
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 🔴 DASHBOARD FRAGMENT (OPTIMIZED & CORRECTED)
// ---------------------------------------------------------------------------
class DashboardHomeFragment extends StatefulWidget {
  const DashboardHomeFragment({super.key});

  @override
  State<DashboardHomeFragment> createState() => _DashboardHomeFragmentState();
}

class _DashboardHomeFragmentState extends State<DashboardHomeFragment> {
  final ApiService _apiService = ApiService();

  // Counters
  int total = 0, present = 0, absent = 0, late = 0, halfDay = 0;
  List<Map<String, dynamic>> _recentActivityList = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // 🔴 STATUS HELPER
  String _getStatusText(int status) {
    switch (status) {
      case 1: return "Present";
      case 2: return "Absent";
      case 3: return "Late";
      case 4: return "Half Day";
      case 5: return "Excused";
      default: return "Absent";
    }
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1: return Colors.green;
      case 2: return Colors.red;
      case 3: return Colors.orange;
      case 4: return Colors.purple;
      case 5: return Colors.blueGrey;
      default: return Colors.red;
    }
  }

  // 🔴 OPTIMIZED LOAD DATA FUNCTION
  Future<void> _loadAllData() async {
    setState(() => loading = true);
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {

        // 1. Sirf Locations mangwao (Fast)
        var locFuture = _apiService.getLocations();
        var results = await Future.wait([locFuture]);
        var locations = results[0] as List<dynamic>;

        List<Map<String, dynamic>> tempList = [];

        // Local Counters
        int localTotal = 0;
        int localPresent = 0;
        int localAbsent = 0;
        int localLate = 0;
        int localHalfday = 0;

        if (locations.isNotEmpty) {
          String locId = locations[0]['_id']; // Default first location
          String date = DateFormat('yyyy-MM-dd').format(DateTime.now());

          // 2. Fetch Attendance (Yehi Data + Stats dega)
          var rawData = await _apiService.getAttendanceByDateAndLocation(date, locId);
          localTotal = rawData.length;

          for (var emp in rawData) {
            var att = emp['attendance'];

            // 🔴 LOGIC: Agar attendance null hai ya empty hai -> ABSENT
            if (att == null || att is! Map || att.isEmpty) {
              localAbsent++;
              continue; // Aage badho, list me add nahi karna
            }

            int status = att['status'] ?? 2;
            String checkIn = att['checkInTime'] ?? att['punchIn'] ?? "";
            String checkOut = att['checkOutTime'] ?? att['punchOut'] ?? "";
            String sortTime = checkIn.isNotEmpty ? checkIn : (att['createdAt'] ?? "");

            // 🔴 CORRECT COUNTING LOGIC
            if (status == 1) {
              localPresent++;
            }
            else if (status == 3) {
              localLate++; // Late Box me
            }
            else if (status == 4) {
              localHalfday++; // Half Day Box me
            }
            else {
              localAbsent++; // Status 2 or 5
            }

            // List me sirf wo ayenge jo Present/Late/HalfDay hain
            if (checkIn.isNotEmpty) {
              String empId = emp['employeeId'] ?? "";

              // Note: Backend se 'faceImage' aane lage to yahan map kar dena
              String imagePath = emp['trim_faceImage'] ?? emp['faceImage'] ?? "";

              tempList.add({
                "name": emp['name'] ?? "Unknown",
                "designation": emp['designation'] ?? "Staff",
                "id": empId,
                "image": imagePath,
                "checkIn": checkIn,
                "checkOut": checkOut,
                "sortTime": sortTime,
                "status": status
              });
            }
          }
        }

        // Sort List (Latest first)
        tempList.sort((a, b) => b['sortTime'].compareTo(a['sortTime']));

        // Limit
        if (tempList.length > 6) {
          tempList = tempList.sublist(0, 6);
        }

        if (mounted) {
          setState(() {
            total = localTotal;
            present = localPresent;
            absent = localAbsent;
            late = localLate;
            halfDay = localHalfday;

            _recentActivityList = tempList;
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
          // HEADER (Stats)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40)),
              boxShadow: [
                BoxShadow(
                    color: Color(0x402E3192),
                    blurRadius: 20,
                    offset: Offset(0, 10))
              ],
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Admin Dashboard",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text("Overview & Management",
                            style:
                            TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                loading
                    ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildGlassStatCard("Total", total.toString(), Icons.people),
                    const SizedBox(width: 5),
                    _buildGlassStatCard("Present", present.toString(), Icons.check_circle, color: Colors.greenAccent),
                    const SizedBox(width: 5),
                    _buildGlassStatCard("Late", late.toString(), Icons.access_time_filled, color: Colors.orangeAccent),
                    const SizedBox(width: 5),
                    _buildGlassStatCard("Absent", absent.toString(), Icons.cancel, color: Colors.redAccent),
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
                // Actions
                Row(
                  children: [
                    Expanded(
                        child: _buildActionCard(
                            "Take\nAttendance",
                            Icons.qr_code_scanner_rounded,
                            const Color(0xFF6366F1), () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (c) =>
                                  const AdminAttendanceScreen())).then((v) {
                            _loadAllData();
                          });
                        })),
                    const SizedBox(width: 15),
                    Expanded(
                        child: _buildActionCard(
                            "Register\nEmployee",
                            Icons.person_add_alt_1_rounded,
                            const Color(0xFFF59E0B), () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (c) =>
                                  const AttendanceRegisterScreen())).then((v) {
                            _loadAllData();
                          });
                        })),
                  ],
                ),
                const SizedBox(height: 25),

                // Recent Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Recently Active",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B))),
                    GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (c) =>
                              const AllEmployeesAttendanceList())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20)),
                        child: const Text("View All",
                            style: TextStyle(
                                color: Colors.blue,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // 🔴 LIST (Shows Present & Late Employees)
                loading
                    ? const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator()))
                    : _recentActivityList.isEmpty
                    ? _buildEmptyState()
                    : Column(
                    children: _recentActivityList
                        .map((emp) => _buildEmployeeCard(emp))
                        .toList()),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String timeStr) {
    if (timeStr.isEmpty) return "--:--";
    try {
      if (timeStr.contains(':') && !timeStr.contains('T')) {
        final parts = timeStr.split(':');
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]),
            int.parse(parts[1]));
        return DateFormat('hh:mm a').format(dt);
      }
      DateTime dt = DateTime.parse(timeStr).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (e) {
      return timeStr;
    }
  }

  Widget _buildEmployeeCard(Map<String, dynamic> emp) {
    String inTime = _formatTime(emp['checkIn']);
    String outTime = _formatTime(emp['checkOut']);

    // API se image nahi aa rahi to filhal placeholder dikha rahe hain
    // Jab backend fix ho jaye to: "${_apiService.baseUrl}/${emp['image']}" use karna
    String fullImageUrl = emp['image'].isNotEmpty ? "${_apiService.baseUrl}/${emp['image']}" : "";

    int status = emp['status'];
    Color statusColor = _getStatusColor(status);
    String statusText = _getStatusText(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.blueGrey.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ]),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: statusColor.withOpacity(0.5),
                        width: 2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: fullImageUrl.isNotEmpty
                          ? Image.network(fullImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) =>
                              Image.asset('assets/img.png'))
                          : Image.asset('assets/img.png', fit: BoxFit.cover),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)),
                    child: const SizedBox(width: 6, height: 6),
                  ),
                )
              ],
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    emp['name'],
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF1E293B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(emp['designation'],
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 4),
                  Text(statusText,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold))
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      const Text("In: ",
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(inTime,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text("Out: ",
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(outTime,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: emp['checkOut'].isEmpty
                                  ? Colors.grey
                                  : Colors.redAccent)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassStatCard(String label, String value, IconData icon,
      {Color color = Colors.white}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withOpacity(0.2))),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              textAlign: TextAlign.center)
        ]),
      ),
    );
  }

  Widget _buildActionCard(
      String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.15),
                  blurRadius: 15,
                  offset: const Offset(0, 8))
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 26)),
              Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                      height: 1.2))
            ]),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
        child: Column(children: [
          const SizedBox(height: 20),
          Icon(Icons.history_toggle_off_rounded,
              size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text("No activity today yet",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14))
        ]));
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
// import 'register_employee_screen.dart' hide AdminAttendanceScreen;
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
//     const DashboardHomeFragment(), // Index 0: Home
//     const EmployeeListScreen(), // Index 1: Staff
//     const AllEmployeesAttendanceList(), // Index 2: Reports
//     const SettingsScreen(), // Index 3: Settings
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
//       onPopInvokedWithResult: (didPop, result) {
//         if (_selectedIndex != 0) {
//           setState(() {
//             _selectedIndex = 0;
//           });
//         } else {
//           SystemNavigator.pop();
//         }
//       },
//       child: Scaffold(
//         backgroundColor: bgColor,
//         body: _pages[_selectedIndex],
//         bottomNavigationBar: Container(
//           decoration: BoxDecoration(
//             color: Colors.white,
//             boxShadow: [
//               BoxShadow(
//                   color: Colors.grey.withOpacity(0.15),
//                   blurRadius: 10,
//                   offset: const Offset(0, -5))
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
//               ? BoxDecoration(
//                   color: skyBlue.withOpacity(0.1),
//                   borderRadius: BorderRadius.circular(12))
//               : null,
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Icon(icon,
//                   color: isSelected ? darkBlue : Colors.grey.shade400,
//                   size: 26),
//               const SizedBox(height: 4),
//               Text(label,
//                   style: TextStyle(
//                       fontSize: 11,
//                       fontWeight:
//                           isSelected ? FontWeight.bold : FontWeight.w500,
//                       color: isSelected ? darkBlue : Colors.grey.shade500))
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// // ---------------------------------------------------------------------------
// // 🔴 FRAGMENT 1: HOME (UPDATED LOGIC: LATE SEPARATE COUNT)
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
//   // 🔴 Added 'late' variable
//   int total = 0, present = 0, absent = 0, late = 0, halfDay = 0;
//   List<Map<String, dynamic>> _recentActivityList = [];
//   bool loading = true;
//
//   @override
//   void initState() {
//     super.initState();
//     _loadAllData();
//   }
//
//   // 🔴 STATUS TEXT HELPER
//   String _getStatusText(int status) {
//     switch (status) {
//       case 1:
//         return "Present";
//       case 2:
//         return "Absent";
//       case 3:
//         return "Late"; // 🔴 New
//       case 4:
//         return "Half Day";
//       case 5:
//         return "Excused";
//       default:
//         return "Present";
//     }
//   }
//
//   // 🔴 STATUS COLOR HELPER
//   Color _getStatusColor(int status) {
//     switch (status) {
//       case 1:
//         return Colors.green;
//       case 2:
//         return Colors.red;
//       case 3:
//         return Colors.orange; // 🔴 Orange for Late
//       case 4:
//         return Colors.amber;
//       case 5:
//         return Colors.blueGrey;
//       default:
//         return Colors.green;
//     }
//   }
//
//   // Future<void> _loadAllData() async {
//   //   setState(() => loading = true);
//   //   try {
//   //     final result = await InternetAddress.lookup('google.com');
//   //     if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
//   //
//   //       var statsFuture = _apiService.getDashboardStats();
//   //       var locFuture = _apiService.getLocations();
//   //       var empFuture = _apiService.getAllEmployees();
//   //
//   //       var results = await Future.wait([statsFuture, locFuture, empFuture]);
//   //
//   //       var statsData = results[0] as Map<String, dynamic>;
//   //       var locations = results[1] as List<dynamic>;
//   //       var allEmployees = results[2] as List<dynamic>;
//   //
//   //       // Image Map
//   //       Map<String, String> photoMap = {};
//   //       for (var e in allEmployees) {
//   //         String img = e['trim_faceImage'] ?? e['faceImage'] ?? "";
//   //         if (img.isNotEmpty) photoMap[e['_id']] = img;
//   //       }
//   //
//   //       List<Map<String, dynamic>> tempList = [];
//   //
//   //       // 🔴 Local Counters Calculation
//   //       int localTotal = 0; // Stats API wala total use karenge ya length se
//   //       int localPresent = 0;
//   //       int localAbsent = 0;
//   //       int localLate = 0;  // 🔴 New Counter
//   //
//   //       if (locations.isNotEmpty) {
//   //         String locId = locations[0]['_id'];
//   //         String date = DateFormat('yyyy-MM-dd').format(DateTime.now());
//   //
//   //         var rawData = await _apiService.getAttendanceByDateAndLocation(date, locId);
//   //         localTotal = rawData.length;
//   //
//   //         for (var emp in rawData) {
//   //           var att = emp['attendance'];
//   //
//   //           // Default Status if attendance object is missing = Absent (2)
//   //           int status = 2;
//   //           String timeStr = "";
//   //
//   //           if (att != null && att is Map && att.isNotEmpty) {
//   //             status = att['status'] ?? 2;
//   //             timeStr = att['checkInTime'] ?? att['punchIn'] ?? att['createdAt'] ?? "";
//   //           }
//   //
//   //           // 🔴 🔴 🔴 NEW COUNTING LOGIC 🔴 🔴 🔴
//   //           // 1=Present, 2=Absent, 3=Late, 4=HalfDay, 5=Excused
//   //
//   //           if (status == 1 || status == 4) {
//   //             // Present or Half Day -> Count as Present
//   //             localPresent++;
//   //           }
//   //           else if (status == 3) {
//   //             // 🔴 Late -> Count ONLY as Late (Not Present)
//   //             localLate++;
//   //           }
//   //           else {
//   //             // Absent or Excused -> Count as Absent
//   //             localAbsent++;
//   //           }
//   //
//   //           // Only add to list if they have check-in time (Present/Late/HalfDay)
//   //           if (timeStr.isNotEmpty) {
//   //             String empId = emp['employeeId'] ?? "";
//   //             String imagePath = photoMap[empId] ?? "";
//   //
//   //             tempList.add({
//   //               "name": emp['name'] ?? "Unknown",
//   //               "designation": emp['designation'] ?? "Staff",
//   //               "id": empId,
//   //               "image": imagePath,
//   //               "time": timeStr,
//   //               "status": status // Pass original status for UI color
//   //             });
//   //           }
//   //         }
//   //       }
//   //
//   //       // Sorting
//   //       tempList.sort((a, b) => b['time'].compareTo(a['time']));
//   //
//   //       // Limit
//   //       if (tempList.length > 6) {
//   //         tempList = tempList.sublist(0, 6);
//   //       }
//   //
//   //       if (mounted) {
//   //         setState(() {
//   //           // Total hum API wala le sakte hain ya list length.
//   //           // Better to use total employees count from Stats API for consistency.
//   //           total = statsData['total'] ?? localTotal;
//   //
//   //           // 🔴 Assign Calculated Values
//   //           present = localPresent;
//   //           absent = localAbsent;
//   //           late = localLate;
//   //
//   //           _recentActivityList = tempList;
//   //           loading = false;
//   //         });
//   //       }
//   //     }
//   //   } catch (e) {
//   //     print("Dashboard Error: $e");
//   //     if (mounted) setState(() { loading = false; });
//   //   }
//   // }
//   Future<void> _loadAllData() async {
//     setState(() => loading = true);
//     try {
//       final result = await InternetAddress.lookup('google.com');
//       if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
//         var statsFuture = _apiService.getDashboardStats();
//         var locFuture = _apiService.getLocations();
//         var empFuture = _apiService.getAllEmployees();
//
//         var results = await Future.wait([statsFuture, locFuture, empFuture]);
//
//         var statsData = results[0] as Map<String, dynamic>;
//         var locations = results[1] as List<dynamic>;
//         var allEmployees = results[2] as List<dynamic>;
//
//         // Image Map
//         Map<String, String> photoMap = {};
//         for (var e in allEmployees) {
//           String img = e['trim_faceImage'] ?? e['faceImage'] ?? "";
//           if (img.isNotEmpty) photoMap[e['_id']] = img;
//         }
//
//         List<Map<String, dynamic>> tempList = [];
//
//         // Counters
//         int localTotal = 0;
//         int localPresent = 0;
//         int localAbsent = 0;
//         int localLate = 0;
//         int localHalfday = 0;
//
//         if (locations.isNotEmpty) {
//           String locId = locations[0]['_id'];
//           String date = DateFormat('yyyy-MM-dd').format(DateTime.now());
//
//           var rawData =
//               await _apiService.getAttendanceByDateAndLocation(date, locId);
//           localTotal = rawData.length;
//
//           for (var emp in rawData) {
//             var att = emp['attendance'];
//
//             int status = 2;
//
//             // 🔴 CHANGE 1: CheckIn aur CheckOut alag-alag nikalo
//             String checkIn = "";
//             String checkOut = "";
//             String sortTime = ""; // Sorting ke liye
//
//             if (att != null && att is Map && att.isNotEmpty) {
//               status = att['status'] ?? 2;
//               checkIn = att['checkInTime'] ?? att['punchIn'] ?? "";
//               checkOut = att['checkOutTime'] ?? att['punchOut'] ?? "";
//
//               // Sorting ke liye CheckIn use karo, agar wo nahi hai to CreatedAt
//               sortTime =
//                   checkIn.isNotEmpty ? checkIn : (att['createdAt'] ?? "");
//             }
//
//             // --- COUNTING LOGIC (Same as before) ---
//             if (status == 1) {
//               localPresent++;
//             } else if (status == 3) {
//               localLate++;
//             } else if (status == 4) {
//               localHalfday++;
//             } else {
//               localAbsent++;
//             }
//
//             // 🔴 CHANGE 2: List me 'checkIn' aur 'checkOut' add karo
//             // Sirf tab add karo agar CheckIn time exist karta hai
//             if (checkIn.isNotEmpty) {
//               String empId = emp['employeeId'] ?? "";
//               String imagePath = photoMap[empId] ?? "";
//
//               tempList.add({
//                 "name": emp['name'] ?? "Unknown",
//                 "designation": emp['designation'] ?? "Staff",
//                 "id": empId,
//                 "image": imagePath,
//                 "checkIn": checkIn, // ✅ New Field
//                 "checkOut": checkOut, // ✅ New Field
//                 "sortTime": sortTime, // ✅ For Sorting
//                 "status": status
//               });
//             }
//           }
//         }
//
//         // 🔴 CHANGE 3: Sorting 'sortTime' ke base par karo
//         tempList.sort((a, b) => b['sortTime'].compareTo(a['sortTime']));
//
//         // Limit
//         if (tempList.length > 6) {
//           tempList = tempList.sublist(0, 6);
//         }
//
//         if (mounted) {
//           setState(() {
//             total = statsData['total'] ?? localTotal;
//             present = localPresent;
//             absent = localAbsent;
//             late = localLate;
//             halfDay = localHalfday;
//             _recentActivityList = tempList;
//             loading = false;
//           });
//         }
//       }
//     } catch (e) {
//       print("Dashboard Error: $e");
//       if (mounted)
//         setState(() {
//           loading = false;
//         });
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
//           // HEADER (Stats)
//           Container(
//             padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
//             decoration: const BoxDecoration(
//               gradient: LinearGradient(
//                   colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
//                   begin: Alignment.topLeft,
//                   end: Alignment.bottomRight),
//               borderRadius: BorderRadius.only(
//                   bottomLeft: Radius.circular(40),
//                   bottomRight: Radius.circular(40)),
//               boxShadow: [
//                 BoxShadow(
//                     color: Color(0x402E3192),
//                     blurRadius: 20,
//                     offset: Offset(0, 10))
//               ],
//             ),
//             child: Column(
//               children: [
//                 const Row(
//                   children: [
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text("Admin Dashboard",
//                             style: TextStyle(
//                                 color: Colors.white,
//                                 fontSize: 24,
//                                 fontWeight: FontWeight.bold)),
//                         SizedBox(height: 4),
//                         Text("Overview & Management",
//                             style:
//                                 TextStyle(color: Colors.white70, fontSize: 13)),
//                       ],
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 25),
//                 loading
//                     ? const Center(
//                         child: CircularProgressIndicator(color: Colors.white))
//                     : Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           // 🔴 4 CARDS NOW (Using Expanded to fit nicely)
//                           _buildGlassStatCard(
//                               "Total", total.toString(), Icons.people),
//                           const SizedBox(width: 8),
//                           _buildGlassStatCard(
//                               "Present", present.toString(), Icons.check_circle,
//                               color: Colors.greenAccent),
//                           const SizedBox(width: 8),
//                           _buildGlassStatCard(
//                               "Late", late.toString(), Icons.access_time_filled,
//                               color: Colors.orangeAccent), // 🔴 Late Card
//                           const SizedBox(width: 8),
//                           _buildGlassStatCard("Half Day", halfDay.toString(),
//                               Icons.access_time_filled,
//                               color: Colors.purple), // 🔴 Late Card
//                           const SizedBox(width: 8),
//                           _buildGlassStatCard(
//                               "Absent", absent.toString(), Icons.cancel,
//                               color: Colors.redAccent),
//                         ],
//                       ),
//               ],
//             ),
//           ),
//
//           // CONTENT
//           Expanded(
//             child: ListView(
//               padding: const EdgeInsets.all(20),
//               children: [
//                 // Actions
//                 Row(
//                   children: [
//                     Expanded(
//                         child: _buildActionCard(
//                             "Take\nAttendance",
//                             Icons.qr_code_scanner_rounded,
//                             const Color(0xFF6366F1), () {
//                       Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                               builder: (c) =>
//                                   const AdminAttendanceScreen())).then((v) {
//                         _loadAllData();
//                       });
//                     })),
//                     const SizedBox(width: 15),
//                     Expanded(
//                         child: _buildActionCard(
//                             "Register\nEmployee",
//                             Icons.person_add_alt_1_rounded,
//                             const Color(0xFFF59E0B), () {
//                       Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                               builder: (c) =>
//                                   const AttendanceRegisterScreen())).then((v) {
//                         _loadAllData();
//                       });
//                     })),
//                   ],
//                 ),
//                 const SizedBox(height: 25),
//
//                 // Recent Title
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     const Text("Recently Present/Late",
//                         style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                             color: Color(0xFF1E293B))),
//                     GestureDetector(
//                       onTap: () => Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                               builder: (c) =>
//                                   const AllEmployeesAttendanceList())),
//                       child: Container(
//                         padding: const EdgeInsets.symmetric(
//                             horizontal: 12, vertical: 6),
//                         decoration: BoxDecoration(
//                             color: Colors.blue.withOpacity(0.1),
//                             borderRadius: BorderRadius.circular(20)),
//                         child: const Text("View All",
//                             style: TextStyle(
//                                 color: Colors.blue,
//                                 fontSize: 12,
//                                 fontWeight: FontWeight.bold)),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 15),
//
//                 // 🔴 LIST (Shows Present & Late Employees)
//                 loading
//                     ? const Center(
//                         child: Padding(
//                             padding: EdgeInsets.all(20),
//                             child: CircularProgressIndicator()))
//                     : _recentActivityList.isEmpty
//                         ? _buildEmptyState()
//                         : Column(
//                             children: _recentActivityList
//                                 .map((emp) => _buildEmployeeCard(emp))
//                                 .toList()),
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
// // 🔴 TIME FORMATTER FIX
//   String _formatTime(String timeStr) {
//     if (timeStr.isEmpty) return "--:--";
//     try {
//       // Agar format "HH:mm" hai (e.g., "11:26")
//       if (timeStr.contains(':') && !timeStr.contains('T')) {
//         final parts = timeStr.split(':');
//         final now = DateTime.now();
//         // Aaj ki date ke sath time combine karo
//         final dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]),
//             int.parse(parts[1]));
//         return DateFormat('hh:mm a').format(dt);
//       }
//
//       // Agar format ISO hai (e.g., "2026-02-12T11:26:00...")
//       DateTime dt = DateTime.parse(timeStr).toLocal();
//       return DateFormat('hh:mm a').format(dt);
//     } catch (e) {
//       return timeStr; // Error aaye to original string dikha do
//     }
//   }
//
//   // 🔴 EMPLOYEE CARD (Status Logic for Badge)
//   // 🔴 UPDATED CARD
//   // 🔴 UPDATED PREMIUM CARD (With In & Out Time)
//   Widget _buildEmployeeCard(Map<String, dynamic> emp) {
//     // Times Format karo
//     String inTime = _formatTime(emp['checkIn']);
//     String outTime =
//         _formatTime(emp['checkOut']); // Agar empty hoga to --:-- ban jayega
//
//     String fullImageUrl =
//         emp['image'].isNotEmpty ? "${_apiService.baseUrl}/${emp['image']}" : "";
//     int status = emp['status'];
//
//     Color statusColor = _getStatusColor(status);
//     String statusText = _getStatusText(status);
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(16),
//           boxShadow: [
//             BoxShadow(
//                 color: Colors.blueGrey.withOpacity(0.08),
//                 blurRadius: 12,
//                 offset: const Offset(0, 4))
//           ]),
//       child: Padding(
//         padding: const EdgeInsets.all(12),
//         child: Row(
//           children: [
//             // 1. IMAGE with Status Border
//             Stack(
//               children: [
//                 Container(
//                   width: 55,
//                   height: 55,
//                   decoration: BoxDecoration(
//                     shape: BoxShape.circle,
//                     border: Border.all(
//                         color: statusColor.withOpacity(0.5),
//                         width: 2), // Status color border
//                   ),
//                   child: Padding(
//                     padding:
//                         const EdgeInsets.all(2), // Gap between border and image
//                     child: ClipOval(
//                       child: fullImageUrl.isNotEmpty
//                           ? Image.network(fullImageUrl,
//                               fit: BoxFit.cover,
//                               errorBuilder: (c, e, s) =>
//                                   Image.asset('assets/img.png'))
//                           : Image.asset('assets/img.png', fit: BoxFit.cover),
//                     ),
//                   ),
//                 ),
//                 // Small Status Icon
//                 Positioned(
//                   bottom: 0,
//                   right: 0,
//                   child: Container(
//                     padding: const EdgeInsets.all(4),
//                     decoration: BoxDecoration(
//                         color: statusColor,
//                         shape: BoxShape.circle,
//                         border: Border.all(color: Colors.white, width: 2)),
//                     child: const SizedBox(width: 6, height: 6), // Just a dot
//                   ),
//                 )
//               ],
//             ),
//
//             const SizedBox(width: 15),
//
//             // 2. NAME & DESIGNATION
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     emp['name'],
//                     style: const TextStyle(
//                         fontWeight: FontWeight.bold,
//                         fontSize: 16,
//                         color: Color(0xFF1E293B)),
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                   const SizedBox(height: 2),
//                   Container(
//                     padding:
//                         const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                     decoration: BoxDecoration(
//                         color: Colors.grey.shade100,
//                         borderRadius: BorderRadius.circular(4)),
//                     child: Text(emp['designation'],
//                         style: TextStyle(
//                             fontSize: 10,
//                             color: Colors.grey.shade600,
//                             fontWeight: FontWeight.w600)),
//                   ),
//                   const SizedBox(height: 4),
//                   Text(statusText,
//                       style: TextStyle(
//                           color: statusColor,
//                           fontSize: 11,
//                           fontWeight: FontWeight.bold))
//                 ],
//               ),
//             ),
//
//             // 3. TIME BOX (IN & OUT)
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//               decoration: BoxDecoration(
//                   color: const Color(0xFFF8FAFC), // Very light grey bg
//                   borderRadius: BorderRadius.circular(12),
//                   border: Border.all(color: Colors.grey.shade200)),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.end,
//                 children: [
//                   // IN TIME
//                   Row(
//                     children: [
//                       const Text("In: ",
//                           style: TextStyle(fontSize: 11, color: Colors.grey)),
//                       Text(inTime,
//                           style: const TextStyle(
//                               fontSize: 13,
//                               fontWeight: FontWeight.bold,
//                               color: Colors.green)),
//                     ],
//                   ),
//                   const SizedBox(height: 4),
//                   // OUT TIME
//                   Row(
//                     children: [
//                       const Text("Out: ",
//                           style: TextStyle(fontSize: 11, color: Colors.grey)),
//                       Text(outTime,
//                           style: TextStyle(
//                               fontSize: 13,
//                               fontWeight: FontWeight.bold,
//                               color: emp['checkOut'].isEmpty
//                                   ? Colors.grey
//                                   : Colors.redAccent)),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   // 🔴 UPDATED: Flexible Stats Card
//   Widget _buildGlassStatCard(String label, String value, IconData icon,
//       {Color color = Colors.white}) {
//     return Expanded(
//       // Using Expanded to fit 4 cards
//       child: Container(
//         padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
//         decoration: BoxDecoration(
//             color: Colors.white.withOpacity(0.15),
//             borderRadius: BorderRadius.circular(15),
//             border: Border.all(color: Colors.white.withOpacity(0.2))),
//         child: Column(children: [
//           Icon(icon, color: color, size: 20),
//           const SizedBox(height: 6),
//           Text(value,
//               style: const TextStyle(
//                   color: Colors.white,
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold)),
//           const SizedBox(height: 2),
//           Text(label,
//               style: const TextStyle(color: Colors.white70, fontSize: 10),
//               textAlign: TextAlign.center)
//         ]),
//       ),
//     );
//   }
//
//   Widget _buildActionCard(
//       String title, IconData icon, Color color, VoidCallback onTap) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         height: 130,
//         padding: const EdgeInsets.all(16),
//         decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(24),
//             boxShadow: [
//               BoxShadow(
//                   color: color.withOpacity(0.15),
//                   blurRadius: 15,
//                   offset: const Offset(0, 8))
//             ]),
//         child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Container(
//                   padding: const EdgeInsets.all(10),
//                   decoration: BoxDecoration(
//                       color: color.withOpacity(0.1), shape: BoxShape.circle),
//                   child: Icon(icon, color: color, size: 26)),
//               Text(title,
//                   style: TextStyle(
//                       fontSize: 15,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.blueGrey[800],
//                       height: 1.2))
//             ]),
//       ),
//     );
//   }
//
//   Widget _buildEmptyState() {
//     return Center(
//         child: Column(children: [
//       const SizedBox(height: 20),
//       Icon(Icons.history_toggle_off_rounded,
//           size: 40, color: Colors.grey.shade300),
//       const SizedBox(height: 10),
//       Text("No activity today yet",
//           style: TextStyle(color: Colors.grey.shade400, fontSize: 14))
//     ]));
//   }
// }
//
// // import 'dart:io';
// // import 'package:face_attendance/screens/Admin%20Side/settings_screen.dart';
// // import 'package:flutter/material.dart';
// // import 'package:flutter/services.dart';
// // import 'package:intl/intl.dart';
// //
// // import '../../services/api_service.dart';
// // import '../Result_StartLogin Side/login_screen.dart';
// // import 'all_employee_list_screen.dart';
// // import 'all_employees_attendace_list.dart';
// // import 'admin_attendance_screen.dart';
// // import 'attendance_history_screen.dart';
// // import 'register_employee_screen.dart' hide AdminAttendanceScreen;
// // import 'holiday_calendar_screen.dart';
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
// //   final Color darkBlue = const Color(0xFF2E3192);
// //   final Color skyBlue = const Color(0xFF00D2FF);
// //   final Color bgColor = const Color(0xFFF2F5F9);
// //
// //   final List<Widget> _pages = [
// //     const DashboardHomeScreen(),        // Index 0: Home
// //     const EmployeeListScreen(),           // Index 1: Staff
// //     const AllEmployeesAttendanceList(),   // Index 2: Reports
// //     const SettingsScreen(),               // Index 3: Settings
// //   ];
// //
// //   void _onItemTapped(int index) {
// //     setState(() => _selectedIndex = index);
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     // 🔴 BACK BUTTON LOGIC
// //     return PopScope(
// //       canPop: false,
// //       onPopInvokedWithResult: (didPop, result) {
// //         if (_selectedIndex != 0) {
// //           // Agar kisi aur tab (Staff/Reports/Settings) par hain, to Home (0) par lao
// //           setState(() {
// //             _selectedIndex = 0;
// //           });
// //         } else {
// //           // 🔴 AGAR HOME TAB PAR HAIN: To Login par nahi jana, seedha App band karni hai
// //           SystemNavigator.pop();
// //         }
// //       },
// //       child: Scaffold(
// //         backgroundColor: bgColor,
// //
// //         // Body
// //         body: IndexedStack(
// //           index: _selectedIndex,
// //           children: _pages,
// //         ),
// //
// //         // Bottom Navigation
// //         bottomNavigationBar: Container(
// //           decoration: BoxDecoration(
// //             color: Colors.white,
// //             boxShadow: [
// //               BoxShadow(color: Colors.grey.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, -5))
// //             ],
// //           ),
// //           child: SafeArea(
// //             child: Padding(
// //               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
// //               child: Row(
// //                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                 children: [
// //                   _buildNavItem(Icons.dashboard_rounded, "Home", 0),
// //                   _buildNavItem(Icons.people_alt_rounded, "Staff", 1),
// //                   _buildNavItem(Icons.bar_chart_rounded, "Reports", 2),
// //                   _buildNavItem(Icons.settings_rounded, "Settings", 3),
// //                 ],
// //               ),
// //             ),
// //           ),
// //         ),
// //       ),
// //     );
// //   }
// //
// //   Widget _buildNavItem(IconData icon, String label, int index) {
// //     bool isSelected = _selectedIndex == index;
// //     return Expanded(
// //       child: InkWell(
// //         onTap: () => _onItemTapped(index),
// //         borderRadius: BorderRadius.circular(12),
// //         child: Container(
// //           padding: const EdgeInsets.symmetric(vertical: 8),
// //           decoration: isSelected
// //               ? BoxDecoration(color: skyBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12))
// //               : null,
// //           child: Column(
// //             mainAxisSize: MainAxisSize.min,
// //             children: [
// //               Icon(icon, color: isSelected ? darkBlue : Colors.grey.shade400, size: 26),
// //               const SizedBox(height: 4),
// //               Text(
// //                   label,
// //                   style: TextStyle(
// //                       fontSize: 11,
// //                       fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
// //                       color: isSelected ? darkBlue : Colors.grey.shade500
// //                   )
// //               )
// //             ],
// //           ),
// //         ),
// //       ),
// //     );
// //   }
// // }
// //
// // // ---------------------------------------------------------------------------
// // // 🔴 FRAGMENT 1: HOME (LATEST 6 PRESENT ONLY + IMAGES)
// // // ---------------------------------------------------------------------------
// // class DashboardHomeScreen extends StatefulWidget {
// //   const DashboardHomeScreen({super.key});
// //
// //   @override
// //   State<DashboardHomeScreen> createState() => _DashboardHomeScreenState();
// // }
// //
// // class _DashboardHomeScreenState extends State<DashboardHomeScreen> {
// //   final ApiService _apiService = ApiService();
// //
// //   int total = 0, present = 0, absent = 0;
// //   List<Map<String, dynamic>> _recentActivityList = [];
// //   bool loading = true;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _loadAllData();
// //   }
// //
// //   // 🔴 STATUS HELPER
// //   String _getStatusText(int status) {
// //     switch (status) {
// //       case 1: return "Present";
// //       case 3: return "Late";
// //       case 4: return "Half Day";
// //       case 5: return "Excused";
// //       default: return "Present";
// //     }
// //   }
// //
// //   Color _getStatusColor(int status) {
// //     switch (status) {
// //       case 1: return Colors.green;
// //       case 3: return Colors.orange;
// //       case 4: return Colors.amber;
// //       case 5: return Colors.blueGrey;
// //       default: return Colors.green;
// //     }
// //   }
// //
// //   Future<void> _loadAllData() async {
// //     setState(() => loading = true);
// //     try {
// //       final result = await InternetAddress.lookup('google.com');
// //       if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
// //
// //         // 1. Fetch Stats, Locations & All Employees (For Images)
// //         var statsFuture = _apiService.getDashboardStats();
// //         var locFuture = _apiService.getLocations();
// //         var empFuture = _apiService.getAllEmployees(); // Image ke liye zaroori hai
// //
// //         var results = await Future.wait([statsFuture, locFuture, empFuture]);
// //
// //         var statsData = results[0] as Map<String, dynamic>;
// //         var locations = results[1] as List<dynamic>;
// //         var allEmployees = results[2] as List<dynamic>;
// //
// //         // 2. Create Photo Map (ID -> Image URL)
// //         Map<String, String> photoMap = {};
// //         for (var e in allEmployees) {
// //           String img = e['trim_faceImage'] ?? e['faceImage'] ?? "";
// //           if (img.isNotEmpty) photoMap[e['_id']] = img;
// //         }
// //
// //         List<Map<String, dynamic>> tempList = [];
// //
// //         if (locations.isNotEmpty) {
// //           String locId = locations[0]['_id'];
// //           String date = DateFormat('yyyy-MM-dd').format(DateTime.now());
// //
// //           // 3. Get Today's Attendance
// //           var rawData = await _apiService.getAttendanceByDateAndLocation(date, locId);
// //
// //           for (var emp in rawData) {
// //             var att = emp['attendance'];
// //
// //             // 🔴 FILTER: Agar attendance nahi hai, to skip karo (Absent nahi dikhana)
// //             if (att == null || att is! Map || att.isEmpty) continue;
// //
// //             String timeStr = att['checkInTime'] ?? att['punchIn'] ?? att['createdAt'] ?? "";
// //
// //             // 🔴 FILTER: Agar time nahi hai, to skip
// //             if (timeStr.isEmpty) continue;
// //
// //             int status = att['status'] ?? 1;
// //             String empId = emp['employeeId'] ?? "";
// //             String imagePath = photoMap[empId] ?? ""; // Map se photo nikalo
// //
// //             tempList.add({
// //               "name": emp['name'] ?? "Unknown",
// //               "designation": emp['designation'] ?? "Staff",
// //               "id": empId,
// //               "image": imagePath,
// //               "time": timeStr,
// //               "status": status
// //             });
// //           }
// //         }
// //
// //         // 4. SORT: Newest Time First
// //         tempList.sort((a, b) => b['time'].compareTo(a['time']));
// //
// //         // 5. LIMIT: Only Top 6
// //         if (tempList.length > 6) {
// //           tempList = tempList.sublist(0, 6);
// //         }
// //
// //         if (mounted) {
// //           setState(() {
// //             total = statsData['total'] ?? 0;
// //             present = statsData['present'] ?? 0;
// //             absent = statsData['absent'] ?? 0;
// //             _recentActivityList = tempList;
// //             loading = false;
// //           });
// //         }
// //       }
// //     } catch (e) {
// //       print("Dashboard Error: $e");
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
// //           // HEADER (Stats)
// //           Container(
// //             padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
// //             decoration: const BoxDecoration(
// //               gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF00D2FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
// //               borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
// //               boxShadow: [BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10))],
// //             ),
// //             child: Column(
// //               children: [
// //                 const Row(
// //                   children: [
// //                     Column(
// //                       crossAxisAlignment: CrossAxisAlignment.start,
// //                       children: [
// //                         Text("Admin Dashboard", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
// //                         SizedBox(height: 4),
// //                         Text("Overview & Management", style: TextStyle(color: Colors.white70, fontSize: 13)),
// //                       ],
// //                     ),
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
// //           // CONTENT
// //           Expanded(
// //             child: ListView(
// //               padding: const EdgeInsets.all(20),
// //               children: [
// //                 // Actions
// //                 Row(
// //                   children: [
// //                     Expanded(child: _buildActionCard("Take\nAttendance", Icons.qr_code_scanner_rounded, const Color(0xFF6366F1), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminAttendanceScreen())))),
// //                     const SizedBox(width: 15),
// //                     Expanded(child: _buildActionCard("Register\nEmployee", Icons.person_add_alt_1_rounded, const Color(0xFFF59E0B), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AttendanceRegisterScreen())))),
// //                   ],
// //                 ),
// //                 const SizedBox(height: 25),
// //
// //                 // Recent Title
// //                 Row(
// //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                   children: [
// //                     const Text("Recently Present", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
// //                     GestureDetector(
// //                       onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AllEmployeesAttendanceList())),
// //                       child: Container(
// //                         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
// //                         decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
// //                         child: const Text("View All", style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
// //                       ),
// //                     ),
// //                   ],
// //                 ),
// //                 const SizedBox(height: 15),
// //
// //                 // 🔴 LIST (Only Present Employees)
// //                 loading
// //                     ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
// //                     : _recentActivityList.isEmpty
// //                     ? _buildEmptyState()
// //                     : Column(children: _recentActivityList.map((emp) => _buildEmployeeCard(emp)).toList()),
// //
// //                 const SizedBox(height: 20),
// //               ],
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   // 🔴 EMPLOYEE CARD (With Image & Status)
// //   Widget _buildEmployeeCard(Map<String, dynamic> emp) {
// //     String time = "--:--";
// //     try {
// //       time = DateFormat('hh:mm a').format(DateTime.parse(emp['time']).toLocal());
// //     } catch (_) {}
// //
// //     String fullImageUrl = emp['image'].isNotEmpty ? "${_apiService.baseUrl}/${emp['image']}" : "";
// //     int status = emp['status'];
// //     Color statusColor = _getStatusColor(status);
// //     String statusText = _getStatusText(status);
// //
// //     return Container(
// //       margin: const EdgeInsets.only(bottom: 12),
// //       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]),
// //       child: ListTile(
// //         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
// //         leading: Stack(
// //           children: [
// //             Container(
// //               width: 48, height: 48,
// //               decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
// //               child: ClipOval(
// //                 child: fullImageUrl.isNotEmpty
// //                     ? Image.network(fullImageUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => Image.asset('assets/img.png', fit: BoxFit.cover))
// //                     : Image.asset('assets/img.png', fit: BoxFit.cover),
// //               ),
// //             ),
// //             Positioned(bottom: 0, right: 0, child: Container(height: 12, width: 12, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))
// //           ],
// //         ),
// //         title: Text(emp['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
// //         subtitle: Row(
// //           children: [
// //             Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade500),
// //             const SizedBox(width: 4),
// //             Text("In: $time", style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
// //           ],
// //         ),
// //         trailing: Container(
// //           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
// //           decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
// //           child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
// //         ),
// //       ),
// //     );
// //   }
// //
// //   Widget _buildGlassStatCard(String label, String value, IconData icon, {bool isGreen = false, bool isRed = false}) {
// //     Color iconColor = isGreen ? Colors.greenAccent : (isRed ? Colors.redAccent : Colors.white);
// //     return Container(
// //       width: 100, padding: const EdgeInsets.all(12),
// //       decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white.withOpacity(0.2))),
// //       child: Column(children: [Icon(icon, color: iconColor, size: 22), const SizedBox(height: 8), Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))]),
// //     );
// //   }
// //
// //   Widget _buildActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
// //     return GestureDetector(
// //       onTap: onTap,
// //       child: Container(
// //         height: 130, padding: const EdgeInsets.all(16),
// //         decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 8))]),
// //         child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 26)), Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey[800], height: 1.2))]),
// //       ),
// //     );
// //   }
// //
// //   Widget _buildEmptyState() {
// //     return Center(child: Column(children: [const SizedBox(height: 20), Icon(Icons.history_toggle_off_rounded, size: 40, color: Colors.grey.shade300), const SizedBox(height: 10), Text("No activity today yet", style: TextStyle(color: Colors.grey.shade400, fontSize: 14))]));
// //   }
// // }
