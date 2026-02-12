import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../Employee Side/employee_history_screen.dart';
import 'employee_attendace_screen.dart';
import '../Result_StartLogin Side/login_screen.dart';

class EmployeeDashboard extends StatefulWidget {
  final String employeeName;
  final String employeeId;

  const EmployeeDashboard({super.key, required this.employeeName, required this.employeeId});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  bool _isLoadingLocations = true;

  List<dynamic> _locations = [];
  String? _selectedLocationId;

  String _statusText = "Absent";
  Color _statusColor = Colors.redAccent;
  String _workingHours = "0h 0m";
  String _punchInDisplay = "--:--";
  String _punchOutDisplay = "--:--";

  DateTime? _inDateTime;
  DateTime? _outDateTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchLocations();
  }

  // 🔴 1. FETCH LOCATIONS & SET DEFAULT
  void _fetchLocations() async {
    setState(() => _isLoadingLocations = true);
    List<dynamic> locs = await _apiService.getLocationsForEmployee();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedId = prefs.getString('locationId');

    if (mounted) {
      setState(() {
        _locations = locs;
        if (locs.isNotEmpty) {
          // Check if previously saved ID exists in the current list
          if (savedId != null && locs.any((l) => l['_id'] == savedId)) {
            _selectedLocationId = savedId;
          } else {
            _selectedLocationId = locs[0]['_id'];
            prefs.setString('locationId', _selectedLocationId!);
          }
        }
        _isLoadingLocations = false;
      });

      // 🔴 Pass selected ID directly to avoid race conditions
      if (_selectedLocationId != null) {
        _fetchTodayStatus(explicitId: _selectedLocationId);
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🔴 2. FETCH DATA (Added explicitId parameter to ensure fresh ID usage)
  void _fetchTodayStatus({String? explicitId}) async {
    final targetId = explicitId ?? _selectedLocationId;
    if (targetId == null) return;

    if (mounted) setState(() => _isLoading = true);
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      print("📡 Fetching Attendance for Location ID: $targetId");
      var data = await _apiService.getDailyAttendance(
          widget.employeeId,
          targetId, // ✅ Fresh ID being used
          todayDate
      );

      if (data != null && data['attendance'] != null) {
        var att = data['attendance'];
        if (att is Map && att.isNotEmpty) {
          _parseAttendanceData(att);
          return;
        }
      }
      _setAbsent();
    } catch (e) {
      debugPrint("Fetch Error: $e");
      _setAbsent();
    }
  }

  void _parseAttendanceData(Map<dynamic, dynamic> att) {
    String? inTimeRaw = att['checkInTime'] ?? att['punchIn'] ?? att['createdAt'];
    String? outTimeRaw = att['checkOutTime'] ?? att['punchOut'];

    DateTime? parsedIn = _parseDateTime(inTimeRaw);
    DateTime? parsedOut = _parseDateTime(outTimeRaw);

    if (parsedIn != null) {
      if (mounted) {
        setState(() {
          _inDateTime = parsedIn;
          _outDateTime = parsedOut;
          _punchInDisplay = DateFormat('hh:mm a').format(parsedIn);

          if (parsedOut != null) {
            _punchOutDisplay = DateFormat('hh:mm a').format(parsedOut);
            _statusText = "Duty Off";
            _statusColor = Colors.orange;
            _timer?.cancel();
          } else {
            _punchOutDisplay = "--:--";
            _statusText = "On Duty";
            _statusColor = Colors.green;
            _startLiveTimer();
          }
          _calculateWorkingHours();
          _isLoading = false;
        });
      }
    } else {
      _setAbsent();
    }
  }

  DateTime? _parseDateTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      return DateTime.parse(timeStr).toLocal();
    } catch (_) {
      try {
        final now = DateTime.now();
        DateTime timePart = timeStr.split(':').length == 3
            ? DateFormat("HH:mm:ss").parse(timeStr)
            : DateFormat("HH:mm").parse(timeStr);
        return DateTime(now.year, now.month, now.day, timePart.hour, timePart.minute, timePart.second);
      } catch (_) {}
    }
    return null;
  }

  void _setAbsent() {
    if (mounted) {
      setState(() {
        _statusText = "Absent";
        _statusColor = Colors.redAccent;
        _workingHours = "0h 0m";
        _punchInDisplay = "--:--";
        _punchOutDisplay = "--:--";
        _inDateTime = null;
        _outDateTime = null;
        _isLoading = false;
      });
      _timer?.cancel();
    }
  }

  void _startLiveTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted && _statusText == "On Duty") _calculateWorkingHours();
      else timer.cancel();
    });
  }

  void _calculateWorkingHours() {
    if (_inDateTime == null) return;
    DateTime end = _outDateTime ?? DateTime.now();
    Duration diff = end.difference(_inDateTime!);
    if (diff.isNegative) diff = Duration.zero;
    if (mounted) setState(() => _workingHours = "${diff.inHours}h ${diff.inMinutes % 60}m");
  }

  void _logout(BuildContext context) async {
    _timer?.cancel();
    await ApiService.logoutEmployee();
    if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const LoginScreen(autoLogin: false)), (r) => false);
  }



  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        elevation: 10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔴 Icon
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 35),
              ),
              const SizedBox(height: 20),

              // 🔴 Title & Subtitle
              const Text(
                "Log Out?",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 10),
              const Text(
                "Are you sure you want to leave?\nYou will need to login again.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 30),

              // 🔴 Buttons Row
              Row(
                children: [
                  // CANCEL BUTTON
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Cancel", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 15),

                  // LOGOUT BUTTON
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx); // Dialog band karo
                        _logout(context);   // 🔴 Asli Logout Call karo
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: const Text("Log Out", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async { if (didPop) return; SystemNavigator.pop(); },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        body: RefreshIndicator(
          onRefresh: () async { _fetchTodayStatus(); },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                // HEADER
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF29B6F6), Color(0xFF0288D1)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            CircleAvatar(radius: 22, backgroundColor: Colors.white, child: Text(widget.employeeName.isNotEmpty ? widget.employeeName[0] : "E", style: const TextStyle(color: Color(0xFF0288D1), fontWeight: FontWeight.bold))),
                            const SizedBox(width: 12),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Welcome,", style: TextStyle(color: Colors.white70, fontSize: 12)), Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                          ]),
                          IconButton(onPressed:_showLogoutDialog, icon: const Icon(Icons.logout, color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 25),
                      // 🔴 DROPDOWN FIXED
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
                        child: _isLoadingLocations
                            ? const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()))
                            : DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedLocationId,
                            isExpanded: true,
                            hint: const Text("Select Location"),
                            icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0288D1)),
                            items: _locations.map<DropdownMenuItem<String>>((loc) {
                              return DropdownMenuItem(value: loc['_id'], child: Text(loc['name'], style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)));
                            }).toList(),
                            onChanged: (val) async {
                              if (val != null) {
                                print("📍 Selected Location Changed to: $val");
                                setState(() => _selectedLocationId = val);

                                // Save selection
                                SharedPreferences prefs = await SharedPreferences.getInstance();
                                await prefs.setString('locationId', val);

                                // 🔴 Call API directly with the 'val' to ensure correct request
                                _fetchTodayStatus(explicitId: val);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatCard("Status", _statusText, _statusColor, Icons.how_to_reg),
                      _buildStatCard("Hours", _workingHours, Colors.blue, Icons.access_time_filled),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10)]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildTimeCol("Punch In", _punchInDisplay, Colors.green),
                      Container(height: 40, width: 1, color: Colors.grey.shade300),
                      _buildTimeCol("Punch Out", _punchOutDisplay, Colors.red),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildBtn("Mark Attendance", Icons.face_retouching_natural, const Color(0xFF0288D1), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const EmployeeAttendanceScreen())).then((_) => _fetchTodayStatus())),
                      const SizedBox(height: 15),
                      _buildBtn("View History", Icons.calendar_month, Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (c) => EmployeeHistoryScreen(employeeName: widget.employeeName, employeeId: widget.employeeId)))),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String val, Color color, IconData icon) {
    return Container(
      width: 150, padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10)]),
      child: Column(children: [CircleAvatar(radius: 20, backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 22)), const SizedBox(height: 10), Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)), Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))]),
    );
  }

  Widget _buildTimeCol(String label, String time, Color color) {
    return Column(children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text(time, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color))]);
  }

  Widget _buildBtn(String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(15), child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 5)]), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color)), const SizedBox(width: 20), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)), const Spacer(), const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey)])));
  }
}












// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:intl/intl.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import '../../services/api_service.dart';
// import '../Employee Side/employee_history_screen.dart';
// import 'employee_attendace_screen.dart';
// import '../Result_StartLogin Side/login_screen.dart';
//
// class EmployeeDashboard extends StatefulWidget {
//   final String employeeName;
//   final String employeeId;
//
//   const EmployeeDashboard({super.key, required this.employeeName, required this.employeeId});
//
//   @override
//   State<EmployeeDashboard> createState() => _EmployeeDashboardState();
// }
//
// class _EmployeeDashboardState extends State<EmployeeDashboard> {
//   final ApiService _apiService = ApiService();
//
//   bool _isLoading = true;
//   bool _isLoadingLocations = true;
//
//   // 🔴 DROPDOWN DATA
//   List<dynamic> _locations = [];
//   String? _selectedLocationId;
//
//   String _statusText = "Absent";
//   Color _statusColor = Colors.redAccent;
//   String _workingHours = "0h 0m";
//   String _punchInDisplay = "--:--";
//   String _punchOutDisplay = "--:--";
//
//   DateTime? _inDateTime;
//   DateTime? _outDateTime;
//   Timer? _timer;
//
//   @override
//   void initState() {
//     super.initState();
//     _fetchLocations();
//   }
//
//   // 🔴 1. FETCH LOCATIONS & SET DEFAULT
//   void _fetchLocations() async {
//     List<dynamic> locs = await _apiService.getLocationsForEmployee();
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     String? savedId = prefs.getString('locationId');
//
//     if (mounted) {
//       setState(() {
//         _locations = locs;
//         if (locs.isNotEmpty) {
//           // Agar purana saved hai to wo select karo, warna pehla wala
//           if (savedId != null && locs.any((l) => l['_id'] == savedId)) {
//             _selectedLocationId = savedId;
//           } else {
//             _selectedLocationId = locs[0]['_id'];
//             prefs.setString('locationId', _selectedLocationId!); // Save default
//           }
//         }
//         _isLoadingLocations = false;
//       });
//
//       if (_selectedLocationId != null) _fetchTodayStatus();
//       else setState(() => _isLoading = false);
//     }
//   }
//
//   // 🔴 2. FETCH DATA USING SELECTED LOCATION ID
//   void _fetchTodayStatus() async {
//     if (_selectedLocationId == null) return;
//     if(mounted) setState(() => _isLoading = true);
//
//     String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
//
//     try {
//       var data = await _apiService.getDailyAttendance(
//           widget.employeeId,
//           _selectedLocationId!, // Passing String ID
//           todayDate
//       );
//
//       if (data != null && data['attendance'] != null) {
//         var att = data['attendance'];
//         if (att is Map && att.isNotEmpty) {
//           _parseAttendance(att);
//           return;
//         }
//       }
//       _setAbsent();
//     } catch (e) {
//       _setAbsent();
//     }
//   }
//
//   void _parseAttendance(Map<dynamic, dynamic> att) {
//     String? inTimeRaw = att['checkInTime'] ?? att['punchIn'] ?? att['createdAt'];
//     String? outTimeRaw = att['checkOutTime'] ?? att['punchOut'];
//
//     DateTime? parsedIn = _parseDateTime(inTimeRaw);
//     DateTime? parsedOut = _parseDateTime(outTimeRaw);
//
//     if (parsedIn != null) {
//       if (mounted) {
//         setState(() {
//           _inDateTime = parsedIn;
//           _outDateTime = parsedOut;
//           _punchInDisplay = DateFormat('hh:mm a').format(parsedIn);
//
//           if (parsedOut != null) {
//             _punchOutDisplay = DateFormat('hh:mm a').format(parsedOut);
//             _statusText = "Duty Off";
//             _statusColor = Colors.orange;
//             _timer?.cancel();
//           } else {
//             _punchOutDisplay = "--:--";
//             _statusText = "On Duty";
//             _statusColor = Colors.green;
//             _startLiveTimer();
//           }
//           _calculateWorkingHours();
//           _isLoading = false;
//         });
//       }
//     } else {
//       _setAbsent();
//     }
//   }
//
//   DateTime? _parseDateTime(String? timeStr) {
//     if (timeStr == null || timeStr.isEmpty) return null;
//     try {
//       return DateTime.parse(timeStr).toLocal();
//     } catch (_) {
//       try {
//         final now = DateTime.now();
//         DateTime timePart = timeStr.split(':').length == 3
//             ? DateFormat("HH:mm:ss").parse(timeStr)
//             : DateFormat("HH:mm").parse(timeStr);
//         return DateTime(now.year, now.month, now.day, timePart.hour, timePart.minute, timePart.second);
//       } catch (_) {}
//     }
//     return null;
//   }
//
//   void _setAbsent() {
//     if (mounted) setState(() { _statusText = "Absent"; _statusColor = Colors.redAccent; _workingHours = "0h 0m"; _punchInDisplay = "--:--"; _punchOutDisplay = "--:--"; _isLoading = false; });
//     _timer?.cancel();
//   }
//
//   void _startLiveTimer() {
//     _timer?.cancel();
//     _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
//       if (mounted && _statusText == "On Duty") _calculateWorkingHours(); else timer.cancel();
//     });
//   }
//
//   void _calculateWorkingHours() {
//     if (_inDateTime == null) return;
//     DateTime end = _outDateTime ?? DateTime.now();
//     Duration diff = end.difference(_inDateTime!);
//     if (diff.isNegative) diff = Duration.zero;
//     if (mounted) setState(() => _workingHours = "${diff.inHours}h ${diff.inMinutes % 60}m");
//   }
//
//   void _logout(BuildContext context) async {
//     _timer?.cancel();
//     await ApiService.logoutEmployee();
//     if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const LoginScreen(autoLogin: false)), (r) => false);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return PopScope(
//       canPop: false,
//       onPopInvokedWithResult: (didPop, result) async { if (didPop) return; SystemNavigator.pop(); },
//       child: Scaffold(
//         backgroundColor: const Color(0xFFF0F4F8),
//         body: RefreshIndicator(
//           onRefresh: () async { _fetchTodayStatus(); },
//           child: SingleChildScrollView(
//             physics: const AlwaysScrollableScrollPhysics(),
//             child: Column(
//               children: [
//                 // 🔴 HEADER (Sky Blue + Dropdown)
//                 Container(
//                   padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
//                   decoration: const BoxDecoration(
//                     gradient: LinearGradient(colors: [Color(0xFF29B6F6), Color(0xFF0288D1)], begin: Alignment.topLeft, end: Alignment.bottomRight),
//                     borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
//                     boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
//                   ),
//                   child: Column(
//                     children: [
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Row(children: [
//                             CircleAvatar(radius: 22, backgroundColor: Colors.white, child: Text(widget.employeeName.isNotEmpty ? widget.employeeName[0] : "E", style: const TextStyle(color: Color(0xFF0288D1), fontWeight: FontWeight.bold))),
//                             const SizedBox(width: 12),
//                             Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Welcome Back,", style: TextStyle(color: Colors.white70, fontSize: 12)), Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
//                           ]),
//                           IconButton(onPressed: () => _logout(context), icon: const Icon(Icons.logout, color: Colors.white)),
//                         ],
//                       ),
//                       const SizedBox(height: 25),
//                       // 🔴 DROPDOWN
//                       Container(
//                         padding: const EdgeInsets.symmetric(horizontal: 15),
//                         decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
//                         child: _isLoadingLocations
//                             ? const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()))
//                             : DropdownButtonHideUnderline(
//                           child: DropdownButton<String>(
//                             value: _selectedLocationId,
//                             isExpanded: true,
//                             hint: const Text("Select Location"),
//                             icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0288D1)),
//                             items: _locations.map<DropdownMenuItem<String>>((loc) {
//                               return DropdownMenuItem(value: loc['_id'], child: Text(loc['name'], style: const TextStyle(fontWeight: FontWeight.w600)));
//                             }).toList(),
//                             onChanged: (val) async {
//                               if (val != null) {
//                                 setState(() => _selectedLocationId = val);
//                                 SharedPreferences prefs = await SharedPreferences.getInstance();
//                                 await prefs.setString('locationId', val); // Save
//                                 _fetchTodayStatus(); // Refresh Data
//                               }
//                             },
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 20),
//                 // 🔴 CIRCULAR STATS
//                 Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 20),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                     children: [
//                       _buildStatCard("Status", _statusText, _statusColor, Icons.how_to_reg),
//                       _buildStatCard("Hours", _workingHours, Colors.blue, Icons.access_time_filled),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 20),
//                 // 🔴 TIMES
//                 Container(
//                   margin: const EdgeInsets.symmetric(horizontal: 20),
//                   padding: const EdgeInsets.all(15),
//                   decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10)]),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceAround,
//                     children: [
//                       _buildTimeCol("Punch In", _punchInDisplay, Colors.green),
//                       Container(height: 40, width: 1, color: Colors.grey.shade300),
//                       _buildTimeCol("Punch Out", _punchOutDisplay, Colors.red),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 25),
//                 // 🔴 ACTIONS
//                 Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 20),
//                   child: Column(
//                     children: [
//                       _buildBtn("Mark Attendance", Icons.face_retouching_natural, const Color(0xFF0288D1), () => Navigator.push(context, MaterialPageRoute(builder: (c) => const EmployeeAttendanceScreen())).then((_) => _fetchTodayStatus())),
//                       const SizedBox(height: 15),
//                       _buildBtn("View History", Icons.calendar_month, Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (c) => EmployeeHistoryScreen(employeeName: widget.employeeName, employeeId: widget.employeeId)))),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 30),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildStatCard(String label, String val, Color color, IconData icon) {
//     return Container(
//       width: 150, padding: const EdgeInsets.all(15),
//       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10)]),
//       child: Column(children: [CircleAvatar(radius: 20, backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 22)), const SizedBox(height: 10), Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)), Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))]),
//     );
//   }
//
//   Widget _buildTimeCol(String label, String time, Color color) {
//     return Column(children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text(time, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color))]);
//   }
//
//   Widget _buildBtn(String title, IconData icon, Color color, VoidCallback onTap) {
//     return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(15), child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 5)]), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color)), const SizedBox(width: 20), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const Spacer(), const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey)])));
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
// // import 'dart:async';
// // import 'package:flutter/material.dart';
// // import 'package:flutter/services.dart';
// // import 'package:intl/intl.dart';
// // import 'package:shared_preferences/shared_preferences.dart';
// // import '../../services/api_service.dart';
// // import '../Employee Side/employee_history_screen.dart';
// // import 'employee_attendace_screen.dart';
// // import '../Result_StartLogin Side/login_screen.dart';
// //
// // class EmployeeDashboard extends StatefulWidget {
// //   final String employeeName;
// //   final String employeeId;
// //
// //   const EmployeeDashboard({
// //     super.key,
// //     required this.employeeName,
// //     required this.employeeId,
// //   });
// //
// //   @override
// //   State<EmployeeDashboard> createState() => _EmployeeDashboardState();
// // }
// //
// // class _EmployeeDashboardState extends State<EmployeeDashboard> {
// //   final ApiService _apiService = ApiService();
// //
// //   bool _isLoading = true;
// //   bool _isLoadingLocations = true;
// //
// //   // Data
// //   List<dynamic> _locations = [];
// //   String? _selectedLocationId; // 🔴 Single String ID for Dropdown
// //
// //   // Status Variables
// //   String _statusText = "Absent";
// //   Color _statusColor = Colors.redAccent;
// //   String _workingHours = "0h 0m";
// //   String _punchInDisplay = "--:--";
// //   String _punchOutDisplay = "--:--";
// //
// //   DateTime? _inDateTime;
// //   DateTime? _outDateTime;
// //   Timer? _timer;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _fetchLocations();
// //   }
// //
// //   // 🔴 1. FETCH LOCATIONS FOR DROPDOWN
// //   void _fetchLocations() async {
// //     setState(() => _isLoadingLocations = true);
// //
// //     // API se locations mangwao
// //     List<dynamic> locs = await _apiService.getLocationsForEmployee();
// //
// //     // Local Storage se saved ID check karo (Default selection ke liye)
// //     SharedPreferences prefs = await SharedPreferences.getInstance();
// //     String? savedLocId = prefs.getString('locationId'); // Last selected ID
// //
// //     if (mounted) {
// //       setState(() {
// //         _locations = locs;
// //
// //         // Logic: Agar saved ID list mein hai to wahi select karo, nahi to pehli wali
// //         if (locs.isNotEmpty) {
// //           if (savedLocId != null && locs.any((l) => l['_id'] == savedLocId)) {
// //             _selectedLocationId = savedLocId;
// //           } else {
// //             _selectedLocationId = locs[0]['_id'];
// //           }
// //         }
// //         _isLoadingLocations = false;
// //       });
// //
// //       // Location milne ke baad hi Data fetch karo
// //       if (_selectedLocationId != null) {
// //         _fetchTodayStatus();
// //       } else {
// //         setState(() => _isLoading = false);
// //       }
// //     }
// //   }
// //
// //   // 🔴 2. FETCH DATA (Uses selected Dropdown ID)
// //   void _fetchTodayStatus() async {
// //     if (_selectedLocationId == null) return;
// //
// //     if (mounted) setState(() => _isLoading = true);
// //     String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
// //
// //     try {
// //       // API call with Single String ID
// //       var data = await _apiService.getDailyAttendance(
// //           widget.employeeId,
// //           _selectedLocationId!,
// //           todayDate
// //       );
// //
// //       if (data != null && data['attendance'] != null) {
// //         var att = data['attendance'];
// //         if (att is Map && att.isNotEmpty) {
// //           _parseAttendanceData(att);
// //           return;
// //         }
// //       }
// //       _setAbsent(); // Agar data nahi mila
// //     } catch (e) {
// //       debugPrint("Fetch Error: $e");
// //       _setAbsent();
// //     }
// //   }
// //
// //   void _parseAttendanceData(Map<dynamic, dynamic> att) {
// //     String? inTimeRaw = att['checkInTime'] ?? att['punchIn'] ?? att['createdAt'];
// //     String? outTimeRaw = att['checkOutTime'] ?? att['punchOut'];
// //
// //     DateTime? parsedIn = _parseDateTime(inTimeRaw);
// //     DateTime? parsedOut = _parseDateTime(outTimeRaw);
// //
// //     if (parsedIn != null) {
// //       if (mounted) {
// //         setState(() {
// //           _inDateTime = parsedIn;
// //           _outDateTime = parsedOut;
// //           _punchInDisplay = DateFormat('hh:mm a').format(parsedIn);
// //
// //           if (parsedOut != null) {
// //             _punchOutDisplay = DateFormat('hh:mm a').format(parsedOut);
// //             _statusText = "Duty Off";
// //             _statusColor = Colors.orange;
// //             _timer?.cancel();
// //           } else {
// //             _punchOutDisplay = "--:--";
// //             _statusText = "On Duty";
// //             _statusColor = Colors.greenAccent;
// //             _startLiveTimer();
// //           }
// //           _calculateWorkingHours();
// //           _isLoading = false;
// //         });
// //       }
// //     } else {
// //       _setAbsent();
// //     }
// //   }
// //
// //   DateTime? _parseDateTime(String? timeStr) {
// //     if (timeStr == null || timeStr.isEmpty) return null;
// //     try {
// //       return DateTime.parse(timeStr).toLocal();
// //     } catch (_) {
// //       try {
// //         final now = DateTime.now();
// //         DateTime timePart = timeStr.split(':').length == 3
// //             ? DateFormat("HH:mm:ss").parse(timeStr)
// //             : DateFormat("HH:mm").parse(timeStr);
// //         return DateTime(now.year, now.month, now.day, timePart.hour, timePart.minute, timePart.second);
// //       } catch (_) {}
// //     }
// //     return null;
// //   }
// //
// //   void _setAbsent() {
// //     if (mounted) {
// //       setState(() {
// //         _statusText = "Absent";
// //         _statusColor = Colors.redAccent;
// //         _workingHours = "0h 0m";
// //         _punchInDisplay = "--:--";
// //         _punchOutDisplay = "--:--";
// //         _inDateTime = null;
// //         _outDateTime = null;
// //         _isLoading = false;
// //       });
// //       _timer?.cancel();
// //     }
// //   }
// //
// //   void _startLiveTimer() {
// //     _timer?.cancel();
// //     _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
// //       if (mounted && _statusText == "On Duty") _calculateWorkingHours();
// //       else timer.cancel();
// //     });
// //   }
// //
// //   void _calculateWorkingHours() {
// //     if (_inDateTime == null) return;
// //     DateTime end = _outDateTime ?? DateTime.now();
// //     Duration diff = end.difference(_inDateTime!);
// //     if (diff.isNegative) diff = Duration.zero;
// //     if (mounted) setState(() => _workingHours = "${diff.inHours}h ${diff.inMinutes % 60}m");
// //   }
// //
// //   void _logout(BuildContext context) async {
// //     _timer?.cancel();
// //     await ApiService.logoutEmployee();
// //     if (context.mounted) {
// //       Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const LoginScreen(autoLogin: false)), (r) => false);
// //     }
// //   }
// //
// //   // 🔴 UI BUILD START
// //   @override
// //   Widget build(BuildContext context) {
// //     return PopScope(
// //       canPop: false,
// //       onPopInvokedWithResult: (didPop, result) async { if (didPop) return; SystemNavigator.pop(); },
// //       child: Scaffold(
// //         backgroundColor: const Color(0xFFF0F4F8), // Light Sky-Grey
// //         body: RefreshIndicator(
// //           onRefresh: () async { _fetchTodayStatus(); },
// //           child: SingleChildScrollView(
// //             physics: const AlwaysScrollableScrollPhysics(),
// //             child: Column(
// //               children: [
// //                 // 🔴 HEADER (Sky Blue Theme + Dropdown)
// //                 Container(
// //                   padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
// //                   decoration: const BoxDecoration(
// //                     gradient: LinearGradient(
// //                       colors: [Color(0xFF29B6F6), Color(0xFF0288D1)], // Sky Blue Gradient
// //                       begin: Alignment.topLeft,
// //                       end: Alignment.bottomRight,
// //                     ),
// //                     borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
// //                     boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
// //                   ),
// //                   child: Column(
// //                     crossAxisAlignment: CrossAxisAlignment.start,
// //                     children: [
// //                       // Top Row: Name & Logout
// //                       Row(
// //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                         children: [
// //                           Row(
// //                             children: [
// //                               CircleAvatar(
// //                                 radius: 22,
// //                                 backgroundColor: Colors.white,
// //                                 child: Text(widget.employeeName.isNotEmpty ? widget.employeeName[0] : "E", style: const TextStyle(color: Color(0xFF0288D1), fontWeight: FontWeight.bold)),
// //                               ),
// //                               const SizedBox(width: 12),
// //                               Column(
// //                                 crossAxisAlignment: CrossAxisAlignment.start,
// //                                 children: [
// //                                   const Text("Welcome Back,", style: TextStyle(color: Colors.white70, fontSize: 12)),
// //                                   Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
// //                                 ],
// //                               ),
// //                             ],
// //                           ),
// //                           IconButton(onPressed: () => _logout(context), icon: const Icon(Icons.logout, color: Colors.white)),
// //                         ],
// //                       ),
// //
// //                       const SizedBox(height: 25),
// //
// //                       // 🔴 DROPDOWN (Pyara Sa)
// //                       Container(
// //                         padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
// //                         decoration: BoxDecoration(
// //                           color: Colors.white,
// //                           borderRadius: BorderRadius.circular(15),
// //                           boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
// //                         ),
// //                         child: _isLoadingLocations
// //                             ? const SizedBox(height: 50, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
// //                             : DropdownButtonHideUnderline(
// //                           child: DropdownButton<String>(
// //                             value: _selectedLocationId,
// //                             isExpanded: true,
// //                             icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF0288D1)),
// //                             hint: const Text("Select Location", style: TextStyle(color: Colors.grey)),
// //                             items: _locations.map<DropdownMenuItem<String>>((loc) {
// //                               return DropdownMenuItem(
// //                                 value: loc['_id'],
// //                                 child: Text(loc['name'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
// //                               );
// //                             }).toList(),
// //                             onChanged: (val) async {
// //                               if (val != null) {
// //                                 setState(() => _selectedLocationId = val);
// //
// //                                 // Save choice
// //                                 SharedPreferences prefs = await SharedPreferences.getInstance();
// //                                 await prefs.setString('locationId', val);
// //
// //                                 // Fetch Data for new location
// //                                 _fetchTodayStatus();
// //                               }
// //                             },
// //                           ),
// //                         ),
// //                       ),
// //                     ],
// //                   ),
// //                 ),
// //
// //                 const SizedBox(height: 20),
// //
// //                 // 🔴 CIRCULAR STATS (Admin Style)
// //                 Padding(
// //                   padding: const EdgeInsets.symmetric(horizontal: 20),
// //                   child: Row(
// //                     mainAxisAlignment: MainAxisAlignment.spaceEvenly,
// //                     children: [
// //                       _buildCircularStat("Status", _statusText, _statusColor, Icons.how_to_reg),
// //                       _buildCircularStat("Hours", _workingHours, Colors.blue, Icons.access_time_filled),
// //                     ],
// //                   ),
// //                 ),
// //
// //                 const SizedBox(height: 20),
// //
// //                 // 🔴 TIMING CARD
// //                 Container(
// //                   margin: const EdgeInsets.symmetric(horizontal: 20),
// //                   padding: const EdgeInsets.all(15),
// //                   decoration: BoxDecoration(
// //                     color: Colors.white,
// //                     borderRadius: BorderRadius.circular(20),
// //                     boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10, offset: const Offset(0, 5))],
// //                   ),
// //                   child: _isLoading
// //                       ? const Center(child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()))
// //                       : Row(
// //                     mainAxisAlignment: MainAxisAlignment.spaceAround,
// //                     children: [
// //                       _buildTimeColumn("Punch In", _punchInDisplay, Colors.green),
// //                       Container(height: 40, width: 1, color: Colors.grey.shade300),
// //                       _buildTimeColumn("Punch Out", _punchOutDisplay, Colors.red),
// //                     ],
// //                   ),
// //                 ),
// //
// //                 const SizedBox(height: 25),
// //
// //                 // 🔴 ACTIONS
// //                 Padding(
// //                   padding: const EdgeInsets.symmetric(horizontal: 20),
// //                   child: Column(
// //                     children: [
// //                       _buildActionCard(
// //                           "Mark Attendance",
// //                           Icons.face_retouching_natural,
// //                           const Color(0xFF0288D1),
// //                               () => Navigator.push(context, MaterialPageRoute(builder: (c) => const EmployeeAttendanceScreen())).then((_) => _fetchTodayStatus())
// //                       ),
// //                       const SizedBox(height: 15),
// //                       _buildActionCard(
// //                           "View History",
// //                           Icons.calendar_month,
// //                           Colors.orange,
// //                               () => Navigator.push(context, MaterialPageRoute(builder: (c) => EmployeeHistoryScreen(employeeName: widget.employeeName, employeeId: widget.employeeId)))
// //                       ),
// //                     ],
// //                   ),
// //                 ),
// //
// //                 const SizedBox(height: 30),
// //               ],
// //             ),
// //           ),
// //         ),
// //       ),
// //     );
// //   }
// //
// //   // --- WIDGET HELPERS ---
// //
// //   Widget _buildCircularStat(String label, String value, Color color, IconData icon) {
// //     return Container(
// //       width: 150,
// //       padding: const EdgeInsets.all(15),
// //       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10)]),
// //       child: Column(
// //         children: [
// //           CircleAvatar(radius: 20, backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 22)),
// //           const SizedBox(height: 10),
// //           Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
// //           Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   Widget _buildTimeColumn(String label, String time, Color color) {
// //     return Column(
// //       children: [
// //         Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
// //         const SizedBox(height: 5),
// //         Text(time, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
// //       ],
// //     );
// //   }
// //
// //   Widget _buildActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
// //     return InkWell(
// //       onTap: onTap,
// //       borderRadius: BorderRadius.circular(15),
// //       child: Container(
// //         padding: const EdgeInsets.all(20),
// //         decoration: BoxDecoration(
// //             color: Colors.white,
// //             borderRadius: BorderRadius.circular(15),
// //             boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 5, offset: const Offset(0, 3))]
// //         ),
// //         child: Row(
// //           children: [
// //             Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color)),
// //             const SizedBox(width: 20),
// //             Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
// //             const Spacer(),
// //             const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
// //           ],
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
// //
