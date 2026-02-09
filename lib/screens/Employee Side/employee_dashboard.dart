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

  const EmployeeDashboard({
    super.key,
    required this.employeeName,
    required this.employeeId,
  });

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;

  // Status Variables
  String _statusText = "Absent";
  Color _statusColor = Colors.redAccent;

  // Time Variables
  String _workingHours = "0h 0m";
  String _punchInDisplay = "--:--";
  String _punchOutDisplay = "--:--";

  DateTime? _inDateTime;
  DateTime? _outDateTime;

  Timer? _timer;
  String _localLocationId = "";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 🔴 FIX 1: Timer Life Cycle Management
  // Timer tabhi start karo jab zaroorat ho, aur purana cancel karo
  void _startLiveTimer() {
    _timer?.cancel(); // Purana timer band karo
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted && _statusText == "On Duty") {
        _calculateWorkingHours();
      } else {
        timer.cancel(); // Agar duty off ho gayi to timer rok do
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _loadData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _localLocationId = prefs.getString('locationId') ?? "";
    _fetchTodayStatus();
  }

  // 🔴 FIX 2: Robust Date Parser (Ye kabhi crash nahi hoga)
  DateTime? _parseDateTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      // 1. Try ISO Format (2024-02-06T09:00:00)
      return DateTime.parse(timeStr).toLocal();
    } catch (_) {
      // 2. Try Time Formats (HH:mm:ss or HH:mm)
      try {
        final now = DateTime.now();
        // DateFormat class ka use karke parse karo, manual split mat karo
        DateTime timePart;
        if (timeStr.split(':').length == 3) {
          timePart = DateFormat("HH:mm:ss").parse(timeStr);
        } else {
          timePart = DateFormat("HH:mm").parse(timeStr);
        }
        return DateTime(now.year, now.month, now.day, timePart.hour, timePart.minute, timePart.second);
      } catch (e) {
        debugPrint("Date Parsing Failed: $e");
      }
    }
    return null;
  }

  void _fetchTodayStatus() async {
    if (_localLocationId.isEmpty) return;

    if(mounted) setState(() => _isLoading = true);
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      var data = await _apiService.getDailyAttendance(
          widget.employeeId,
          _localLocationId,
          todayDate
      );

      if (data != null && data['attendance'] != null) {
        var att = data['attendance'];

        if (att is Map && att.isNotEmpty) {
          // Backend keys handling
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
                  // Duty Off
                  _punchOutDisplay = DateFormat('hh:mm a').format(parsedOut);
                  _statusText = "Duty Off";
                  _statusColor = Colors.red;
                  _timer?.cancel(); // Stop timer
                } else {
                  // On Duty
                  _punchOutDisplay = "--:--";
                  _statusText = "On Duty";
                  _statusColor = Colors.green;
                  _startLiveTimer(); // Start timer
                }

                _calculateWorkingHours();
                _isLoading = false;
              });
            }
            return; // Exit function successfully
          }
        }
      }
      // Agar yahan pahuche matlab data nahi mila
      _setAbsent();

    } catch (e) {
      debugPrint("Fetch Error: $e");
      _setAbsent();
    }
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

  void _calculateWorkingHours() {
    if (_inDateTime == null) return;

    try {
      DateTime end = _outDateTime ?? DateTime.now();
      Duration diff = end.difference(_inDateTime!);

      if (diff.isNegative) diff = Duration.zero;

      if (mounted) {
        setState(() {
          _workingHours = "${diff.inHours}h ${diff.inMinutes % 60}m";
        });
      }
    } catch (e) {
      debugPrint("Calc Error: $e");
    }
  }

  void _logout(BuildContext context) async {
    _timer?.cancel(); // Safe cleanup
    await ApiService.logoutEmployee();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen(autoLogin: false)),
              (route) => false
      );
    }
  }

  Future<void> _handleRefresh() async {
    _fetchTodayStatus();
  }

  @override
  Widget build(BuildContext context) {
    var hour = DateTime.now().hour;
    String greeting = (hour < 12) ? "Good Morning," : (hour < 17) ? "Good Afternoon," : "Good Evening,";

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async { if (didPop) return; SystemNavigator.pop(); },
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: const Color(0xFF0F172A),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                // HEADER
                Stack(
                  children: [
                    Container(
                      height: 250,
                      padding: const EdgeInsets.fromLTRB(25, 60, 25, 40),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F172A),
                        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35)),
                      ),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text("Employee Panel", style: TextStyle(color: Colors.blueGrey[200], fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            const Text("Dashboard", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                          ]),
                          InkWell(onTap: () => _logout(context), borderRadius: BorderRadius.circular(12), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 22))),
                        ]),
                        const Spacer(),
                        Row(children: [
                          CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Text(widget.employeeName.isNotEmpty ? widget.employeeName[0] : "E", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)))),
                          const SizedBox(width: 15),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(greeting, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)), Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))]),
                        ]),
                      ]),
                    ),
                  ],
                ),

                const SizedBox(height: 25),

                // STATUS CARD
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: const Color(0xFF64748B).withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))]),
                    child: _isLoading ? const Center(child: CircularProgressIndicator()) : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text("Today's Status", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 5),
                              Row(children: [
                                Icon(_statusText == "Absent" ? Icons.cancel : Icons.check_circle, color: _statusColor, size: 20),
                                const SizedBox(width: 6),
                                Text(_statusText, style: TextStyle(color: _statusColor, fontSize: 18, fontWeight: FontWeight.bold))
                              ]),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _buildSmallTime("In", _punchInDisplay),
                                  const SizedBox(width: 15),
                                  _buildSmallTime("Out", _punchOutDisplay),
                                ],
                              )
                            ]),
                          ),
                          Container(height: 50, width: 1, color: Colors.grey[200]),
                          const SizedBox(width: 15),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text("Work Hours", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Text(_workingHours, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.w900))
                          ])
                        ]),
                  ),
                ),

                const SizedBox(height: 25),

                // ACTION CARDS
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Column(children: [
                    _buildBigCard(
                        title: "Mark Attendance", subtitle: "Scan Face to Check-in/out", icon: Icons.face_retouching_natural_rounded, color: const Color(0xFF3B82F6),
                        onTap: () {
                          // 🔴 FIX 3: Wait for result and then refresh
                          Navigator.push(context, MaterialPageRoute(builder: (c) => const EmployeeAttendanceScreen()))
                              .then((_) {
                            // Jab wapis aaye, tab data update karo
                            _fetchTodayStatus();
                          });
                        }
                    ),
                    const SizedBox(height: 20),
                    _buildBigCard(
                        title: "My Logs", subtitle: "View Attendance History", icon: Icons.calendar_month_rounded, color: const Color(0xFF10B981),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => EmployeeHistoryScreen(employeeName: widget.employeeName, employeeId: widget.employeeId)))
                    ),
                  ]),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallTime(String label, String time) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold)),
        Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
      ],
    );
  }

  Widget _buildBigCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Container(
      height: 110,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: const Color(0xFF64748B).withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 8))]),
      child: Material(
          color: Colors.transparent,
          child: InkWell(
              onTap: onTap, borderRadius: BorderRadius.circular(24),
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Container(height: 60, width: 60, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: color, size: 30)),
                    const SizedBox(width: 20),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.blueGrey[400]))
                    ])),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey)
                  ])
              )
          )
      ),
    );
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
//   const EmployeeDashboard({
//     super.key,
//     required this.employeeName,
//     required this.employeeId,
//   });
//
//   @override
//   State<EmployeeDashboard> createState() => _EmployeeDashboardState();
// }
//
// class _EmployeeDashboardState extends State<EmployeeDashboard> {
//   final ApiService _apiService = ApiService();
//
//   bool _isLoading = true;
//
//   // Status Variables
//   String _statusText = "Absent";
//   Color _statusColor = Colors.redAccent;
//
//   // Time Variables
//   String _workingHours = "0h 0m";
//   String _punchInDisplay = "--:--";
//   String _punchOutDisplay = "--:--";
//
//   // DateTime objects for calculation
//   DateTime? _inDateTime;
//   DateTime? _outDateTime;
//
//   Timer? _timer;
//   String _localLocationId = "";
//
//   @override
//   void initState() {
//     super.initState();
//
//     _loadData();
//
//     // 🔴 LIVE TIMER
//     _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
//       if (_statusText == "On Duty") {
//         _calculateWorkingHours();
//       }
//     });
//   }
//
//   @override
//   void dispose() {
//     _timer?.cancel();
//     super.dispose();
//   }
//
//   void _loadData() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     _localLocationId = prefs.getString('locationId') ?? "";
//     _fetchTodayStatus();
//   }
//
//   // 🔥 SMART DATE PARSER (Ye Error Fix Karega)
//   DateTime? _parseDateTime(String? timeStr) {
//     if (timeStr == null || timeStr.isEmpty) return null;
//     try {
//       // 1. Try Full ISO format (e.g., 2024-02-06T09:15:00)
//       return DateTime.parse(timeStr).toLocal();
//     } catch (_) {
//       try {
//         // 2. Try Time only format (e.g., "09:15" or "9:15")
//         // Aaj ki date ke saath combine kar do
//         final now = DateTime.now();
//         final parts = timeStr.split(':');
//         if (parts.length >= 2) {
//           int h = int.parse(parts[0]);
//           int m = int.parse(parts[1]);
//           return DateTime(now.year, now.month, now.day, h, m);
//         }
//       } catch (e) {
//         print("Date Parse Error: $e");
//       }
//     }
//     return null;
//   }
//
//   void _fetchTodayStatus() async {
//     if (_localLocationId.isEmpty) return;
//
//     setState(() => _isLoading = true);
//     String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
//
//     var data = await _apiService.getDailyAttendance(
//         widget.employeeId,
//         _localLocationId,
//         todayDate
//     );
//
//     if (data != null) {
//       var att = data['attendance'];
// print("---------------------------$data");
//       // 🔴 LOGIC: Check if attendance exists
//       if (att != null && att is Map && att.isNotEmpty) {
//
//         // Backend keys
//         String? inTimeRaw = att['checkInTime'] ?? att['punchIn'] ?? att['createdAt'];
//         String? outTimeRaw = att['checkOutTime'] ?? att['punchOut'];
//
//         // 🔥 Parse Time safely using Helper
//         DateTime? parsedIn = _parseDateTime(inTimeRaw);
//         DateTime? parsedOut = _parseDateTime(outTimeRaw);
//
//         if (parsedIn != null) {
//           if (mounted) {
//             setState(() {
//               _inDateTime = parsedIn;
//               _outDateTime = parsedOut;
//
//               // Display Strings
//               _punchInDisplay = DateFormat('hh:mm a').format(parsedIn);
//
//               if (parsedOut != null) {
//                 // CASE: DUTY OFF (Present)
//                 _punchOutDisplay = DateFormat('hh:mm a').format(parsedOut);
//                 _statusText = "Duty Off";
//                 _statusColor = Colors.red;
//               } else {
//                 // CASE: ON DUTY (Working)
//                 _punchOutDisplay = "--:--";
//                 _statusText = "On Duty";
//                 _statusColor = Colors.green;
//               }
//
//               _calculateWorkingHours();
//               _isLoading = false;
//             });
//           }
//         } else {
//           // Time parse nahi hua to Absent mark karo safe side
//           _setAbsent();
//         }
//       } else {
//         _setAbsent();
//       }
//     } else {
//       _setAbsent();
//     }
//   }
//
//   void _setAbsent() {
//     if (mounted) {
//       setState(() {
//         _statusText = "Absent";
//         _statusColor = Colors.redAccent;
//         _workingHours = "0h 0m";
//         _punchInDisplay = "--:--";
//         _punchOutDisplay = "--:--";
//         _inDateTime = null;
//         _outDateTime = null;
//         _isLoading = false;
//       });
//     }
//   }
//
//   // 🔴 TIME CALCULATION LOGIC
//   void _calculateWorkingHours() {
//     if (_inDateTime == null) return;
//
//     try {
//       // Agar Out nahi hua, to Current Time lo
//       DateTime end = _outDateTime ?? DateTime.now();
//
//       Duration diff = end.difference(_inDateTime!);
//       if (diff.isNegative) diff = Duration.zero;
//
//       if (mounted) {
//         setState(() {
//           _workingHours = "${diff.inHours}h ${diff.inMinutes % 60}m";
//         });
//       }
//     } catch (e) {
//       print("Calc Logic Error: $e");
//     }
//   }
//
//   void _logout(BuildContext context) async {
//     await ApiService.logoutEmployee();
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.clear();
//     if (context.mounted) {
//       Navigator.pushAndRemoveUntil(
//           context,
//           MaterialPageRoute(builder: (context) => const LoginScreen(autoLogin: false)),
//               (route) => false
//       );
//     }
//   }
//
//   Future<void> _handleRefresh() async {
//     _fetchTodayStatus();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     var hour = DateTime.now().hour;
//     String greeting = (hour < 12) ? "Good Morning," : (hour < 17) ? "Good Afternoon," : "Good Evening,";
//
//     return PopScope(
//       canPop: false,
//       onPopInvokedWithResult: (didPop, result) async { if (didPop) return; SystemNavigator.pop(); },
//       child: Scaffold(
//         backgroundColor: const Color(0xFFF1F5F9),
//         body: RefreshIndicator(
//           onRefresh: _handleRefresh,
//           color: const Color(0xFF0F172A),
//           child: SingleChildScrollView(
//             physics: const AlwaysScrollableScrollPhysics(),
//             child: Column(
//               children: [
//                 // HEADER
//                 Stack(
//                   children: [
//                     Container(
//                       height: 250,
//                       padding: const EdgeInsets.fromLTRB(25, 60, 25, 40),
//                       decoration: const BoxDecoration(
//                         color: Color(0xFF0F172A),
//                         borderRadius: BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35)),
//                       ),
//                       child: Column(children: [
//                         Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
//                           Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//                             Text("Employee Panel", style: TextStyle(color: Colors.blueGrey[200], fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
//                             const SizedBox(height: 4),
//                             const Text("Dashboard", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
//                           ]),
//                           InkWell(onTap: () => _logout(context), borderRadius: BorderRadius.circular(12), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 22))),
//                         ]),
//                         const Spacer(),
//                         Row(children: [
//                           CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Text(widget.employeeName.isNotEmpty ? widget.employeeName[0] : "E", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)))),
//                           const SizedBox(width: 15),
//                           Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(greeting, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)), Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))]),
//                         ]),
//                       ]),
//                     ),
//                   ],
//                 ),
//
//                 const SizedBox(height: 25),
//
//                 // 🔴 STATUS CARD
//                 Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 25),
//                   child: Container(
//                     padding: const EdgeInsets.all(20),
//                     decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: const Color(0xFF64748B).withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))]),
//                     child: _isLoading ? const Center(child: CircularProgressIndicator()) : Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           // Left Side: Status & Times
//                           Expanded(
//                             child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//                               Text("Today's Status", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
//                               const SizedBox(height: 5),
//                               Row(children: [
//                                 Icon(
//                                     _statusText == "Absent" ? Icons.cancel : Icons.check_circle,
//                                     color: _statusColor,
//                                     size: 20
//                                 ),
//                                 const SizedBox(width: 6),
//                                 Text(
//                                     _statusText,
//                                     style: TextStyle(color: _statusColor, fontSize: 18, fontWeight: FontWeight.bold)
//                                 )
//                               ]),
//                               const SizedBox(height: 10),
//                               // Show In and Out Time
//                               Row(
//                                 children: [
//                                   _buildSmallTime("In", _punchInDisplay),
//                                   const SizedBox(width: 15),
//                                   _buildSmallTime("Out", _punchOutDisplay),
//                                 ],
//                               )
//                             ]),
//                           ),
//
//                           // Right Side: Work Hours
//                           Container(height: 50, width: 1, color: Colors.grey[200]),
//                           const SizedBox(width: 15),
//                           Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
//                             Text("Work Hours", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
//                             const SizedBox(height: 5),
//                             Text(_workingHours, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.w900))
//                           ])
//                         ]),
//                   ),
//                 ),
//
//                 const SizedBox(height: 25),
//
//                 // ACTION CARDS
//                 Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 25),
//                   child: Column(children: [
//                     _buildBigCard(
//                         title: "Mark Attendance", subtitle: "Scan Face to Check-in/out", icon: Icons.face_retouching_natural_rounded, color: const Color(0xFF3B82F6),
//                         onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const EmployeeAttendanceScreen())).then((_){
//                           _fetchTodayStatus();
//                         })
//                     ),
//                     const SizedBox(height: 20),
//                     _buildBigCard(
//                         title: "My Logs", subtitle: "View Attendance History", icon: Icons.calendar_month_rounded, color: const Color(0xFF10B981),
//                         onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => EmployeeHistoryScreen(employeeName: widget.employeeName, employeeId: widget.employeeId)))
//                     ),
//                   ]),
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
//   Widget _buildSmallTime(String label, String time) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold)),
//         Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
//       ],
//     );
//   }
//
//   Widget _buildBigCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
//     return Container(
//       height: 110,
//       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: const Color(0xFF64748B).withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 8))]),
//       child: Material(
//           color: Colors.transparent,
//           child: InkWell(
//               onTap: onTap, borderRadius: BorderRadius.circular(24),
//               child: Padding(
//                   padding: const EdgeInsets.all(20),
//                   child: Row(children: [
//                     Container(height: 60, width: 60, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: color, size: 30)),
//                     const SizedBox(width: 20),
//                     Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
//                       Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
//                       const SizedBox(height: 4),
//                       Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.blueGrey[400]))
//                     ])),
//                     const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey)
//                   ])
//               )
//           )
//       ),
//     );
//   }
// }
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
//
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
// //
// //   // Status Variables
// //   String _statusText = "Absent"; // Default
// //   Color _statusColor = Colors.redAccent;
// //
// //   // Time Variables
// //   String _workingHours = "--";
// //   String _punchInTime = "--:--";
// //   String? _checkInTimeStr;
// //   String? _checkOutTimeStr;
// //
// //   Timer? _timer;
// //   String _localLocationId = "";
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _loadData();
// //
// //     // Live Timer (Only runs if On Duty)
// //     _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
// //       if (_statusText == "On Duty" && _checkOutTimeStr == null) {
// //         _calculateWorkingHours();
// //       }
// //     });
// //   }
// //
// //   @override
// //   void dispose() {
// //     _timer?.cancel();
// //     super.dispose();
// //   }
// //
// //   void _loadData() async {
// //     SharedPreferences prefs = await SharedPreferences.getInstance();
// //     _localLocationId = prefs.getString('locationId') ?? "";
// //     _fetchTodayStatus();
// //   }
// //
// //   void _fetchTodayStatus() async {
// //     if (_localLocationId.isEmpty) return;
// //
// //     setState(() => _isLoading = true);
// //     String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
// //
// //     var data = await _apiService.getDailyAttendance(
// //         widget.employeeId,
// //         _localLocationId,
// //         todayDate
// //     );
// //
// //     if (data != null) {
// //       var att = data['attendance']; // Backend sends {} if absent
// //
// //       // 🔴 CHECK: Is Attendance Object Empty?
// //       if (att != null && att is Map && att.isNotEmpty) {
// //
// //         // --- PRESENT CASE ---
// //         // Backend keys: createdAt (auto), checkInTime, punchIn
// //         String? inTime = att['createdAt'] ?? att['checkInTime'] ?? att['punchIn'];
// //         String? outTime = att['checkOutTime'] ?? att['punchOut'];
// //
// //         if (inTime != null) {
// //           if (mounted) {
// //             setState(() {
// //               _checkInTimeStr = inTime;
// //               _checkOutTimeStr = outTime;
// //
// //               // Format Punch In Time
// //               try {
// //                 DateTime dt = DateTime.parse(inTime).toLocal();
// //                 _punchInTime = DateFormat('hh:mm a').format(dt);
// //               } catch (_) {
// //                 _punchInTime = "--:--";
// //               }
// //
// //               // Determine Status
// //               if (outTime != null) {
// //                 _statusText = "Present"; // Or "Duty Off"
// //                 _statusColor = Colors.green;
// //               } else {
// //                 _statusText = "On Duty";
// //                 _statusColor = Colors.blue;
// //               }
// //
// //               _calculateWorkingHours();
// //               _isLoading = false;
// //             });
// //           }
// //         } else {
// //           _setAbsent();
// //         }
// //       } else {
// //         // --- ABSENT CASE (Empty Object) ---
// //         _setAbsent();
// //       }
// //     } else {
// //       _setAbsent();
// //     }
// //   }
// //
// //   void _setAbsent() {
// //     if (mounted) {
// //       setState(() {
// //         _statusText = "Absent";
// //         _statusColor = Colors.redAccent;
// //         _workingHours = "0h 0m";
// //         _punchInTime = "--:--";
// //         _checkInTimeStr = null;
// //         _isLoading = false;
// //       });
// //     }
// //   }
// //
// //   void _calculateWorkingHours() {
// //     if (_checkInTimeStr == null) return;
// //
// //     try {
// //       DateTime start = DateTime.parse(_checkInTimeStr!).toLocal();
// //
// //       // Agar Out nahi hua, to Current Time lo (Live)
// //       DateTime end = _checkOutTimeStr != null
// //           ? DateTime.parse(_checkOutTimeStr!).toLocal()
// //           : DateTime.now();
// //
// //       Duration diff = end.difference(start);
// //       if (diff.isNegative) diff = Duration.zero;
// //
// //       if (mounted) {
// //         setState(() {
// //           _workingHours = "${diff.inHours}h ${diff.inMinutes % 60}m";
// //         });
// //       }
// //     } catch (_) {}
// //   }
// //
// //   void _logout(BuildContext context) async {
// //     await ApiService.logoutEmployee();
// //     SharedPreferences prefs = await SharedPreferences.getInstance();
// //     await prefs.clear();
// //     if (context.mounted) {
// //       Navigator.pushAndRemoveUntil(
// //           context,
// //           MaterialPageRoute(builder: (context) => const LoginScreen(autoLogin: false)),
// //               (route) => false
// //       );
// //     }
// //   }
// //
// //   Future<void> _handleRefresh() async {
// //     _fetchTodayStatus();
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     var hour = DateTime.now().hour;
// //     String greeting = (hour < 12) ? "Good Morning," : (hour < 17) ? "Good Afternoon," : "Good Evening,";
// //
// //     return PopScope(
// //       canPop: false,
// //       onPopInvokedWithResult: (didPop, result) async { if (didPop) return; SystemNavigator.pop(); },
// //       child: Scaffold(
// //         backgroundColor: const Color(0xFFF1F5F9),
// //         body: RefreshIndicator(
// //           onRefresh: _handleRefresh,
// //           color: const Color(0xFF0F172A),
// //           child: SingleChildScrollView(
// //             physics: const AlwaysScrollableScrollPhysics(),
// //             child: Column(
// //               children: [
// //                 // HEADER
// //                 Stack(
// //                   children: [
// //                     Container(
// //                       height: 250,
// //                       padding: const EdgeInsets.fromLTRB(25, 60, 25, 40),
// //                       decoration: const BoxDecoration(
// //                         color: Color(0xFF0F172A),
// //                         borderRadius: BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35)),
// //                       ),
// //                       child: Column(children: [
// //                         Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
// //                           Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
// //                             Text("Employee Panel", style: TextStyle(color: Colors.blueGrey[200], fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
// //                             const SizedBox(height: 4),
// //                             const Text("Dashboard", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
// //                           ]),
// //                           InkWell(onTap: () => _logout(context), borderRadius: BorderRadius.circular(12), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 22))),
// //                         ]),
// //                         const Spacer(),
// //                         Row(children: [
// //                           CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Text(widget.employeeName.isNotEmpty ? widget.employeeName[0] : "E", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)))),
// //                           const SizedBox(width: 15),
// //                           Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(greeting, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)), Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))]),
// //                         ]),
// //                       ]),
// //                     ),
// //                   ],
// //                 ),
// //
// //                 const SizedBox(height: 25),
// //
// //                 // 🔴 STATUS CARD (Updated Logic)
// //                 Padding(
// //                   padding: const EdgeInsets.symmetric(horizontal: 25),
// //                   child: Container(
// //                     padding: const EdgeInsets.all(20),
// //                     decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: const Color(0xFF64748B).withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))]),
// //                     child: _isLoading ? const Center(child: CircularProgressIndicator()) : Row(
// //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                         children: [
// //                           Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
// //                             Text("Today's Status", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
// //                             const SizedBox(height: 5),
// //                             Row(children: [
// //                               Icon(
// //                                   _statusText == "Absent" ? Icons.cancel : Icons.check_circle,
// //                                   color: _statusColor,
// //                                   size: 20
// //                               ),
// //                               const SizedBox(width: 6),
// //                               Text(
// //                                   _statusText,
// //                                   style: TextStyle(color: _statusColor, fontSize: 18, fontWeight: FontWeight.bold)
// //                               )
// //                             ]),
// //                             if(_statusText != "Absent")
// //                               Padding(padding: const EdgeInsets.only(top: 4), child: Text("In: $_punchInTime", style: const TextStyle(fontSize: 12, color: Colors.grey))),
// //                           ]),
// //                           Container(height: 40, width: 1, color: Colors.grey[200]),
// //                           Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
// //                             Text("Work Hours", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
// //                             const SizedBox(height: 5),
// //                             Text(_workingHours, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.w900))
// //                           ])
// //                         ]),
// //                   ),
// //                 ),
// //
// //                 const SizedBox(height: 25),
// //
// //                 // ACTION CARDS
// //                 Padding(
// //                   padding: const EdgeInsets.symmetric(horizontal: 25),
// //                   child: Column(children: [
// //                     _buildBigCard(
// //                         title: "Mark Attendance", subtitle: "Scan Face to Check-in/out", icon: Icons.face_retouching_natural_rounded, color: const Color(0xFF3B82F6),
// //                         onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const EmployeeAttendanceScreen()))
// //                     ),
// //                     const SizedBox(height: 20),
// //                     _buildBigCard(
// //                         title: "My Logs", subtitle: "View Attendance History", icon: Icons.calendar_month_rounded, color: const Color(0xFF10B981),
// //                         onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => EmployeeHistoryScreen(employeeName: widget.employeeName, employeeId: widget.employeeId)))
// //                     ),
// //                   ]),
// //                 ),
// //                 const SizedBox(height: 30),
// //               ],
// //             ),
// //           ),
// //         ),
// //       ),
// //     );
// //   }
// //
// //   Widget _buildBigCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
// //     return Container(
// //       height: 110,
// //       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: const Color(0xFF64748B).withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 8))]),
// //       child: Material(
// //           color: Colors.transparent,
// //           child: InkWell(
// //               onTap: onTap, borderRadius: BorderRadius.circular(24),
// //               child: Padding(
// //                   padding: const EdgeInsets.all(20),
// //                   child: Row(children: [
// //                     Container(height: 60, width: 60, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: color, size: 30)),
// //                     const SizedBox(width: 20),
// //                     Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
// //                       Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
// //                       const SizedBox(height: 4),
// //                       Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.blueGrey[400]))
// //                     ])),
// //                     const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey)
// //                   ])
// //               )
// //           )
// //       ),
// //     );
// //   }
// // }
// //
