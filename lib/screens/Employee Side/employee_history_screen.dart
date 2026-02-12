import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

class EmployeeHistoryScreen extends StatefulWidget {
  final String employeeName;
  final String employeeId;

  const EmployeeHistoryScreen({
    super.key,
    required this.employeeName,
    required this.employeeId
  });

  @override
  State<EmployeeHistoryScreen> createState() => _EmployeeHistoryScreenState();
}

class _EmployeeHistoryScreenState extends State<EmployeeHistoryScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  String? _storedLocationId;
  String? _autoDepartmentId;

  // Stats Counters
  int _presentCount = 0;
  int _absentCount = 0;
  int _holidayCount = 0;
  int _sundayCount = 0;
  int _lateCount = 0;
  int _halfDayCount = 0;

  List<Map<String, dynamic>> _dailyRecords = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _storedLocationId = prefs.getString('locationId');

    var depts = await _apiService.getDepartmentForEmployee();

    if (mounted) {
      setState(() {
        if (depts.isNotEmpty) {
          _autoDepartmentId = depts[0]['_id'];
        }
      });

      if (_storedLocationId != null && _autoDepartmentId != null) {
        _fetchReport();
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🔴 🔴 FIXED DATA PARSING & COUNTING LOGIC 🔴 🔴
  void _fetchReport() async {
    if (_storedLocationId == null || _autoDepartmentId == null) return;

    setState(() => _isLoading = true);
    String monthStr = DateFormat('yyyy-MM').format(_selectedDate);

    try {
      var response = await _apiService.getEmployeeOwnHistory(
          widget.employeeId,
          monthStr,
          _storedLocationId!,
          _autoDepartmentId!
      );

      // 🔴 DEBUG PRINT
      print("DEBUG: History Response received");

      List<dynamic> attendanceList = [];

      // 🔴 PARSING FIX: Check Nested 'data' -> [0] -> 'attendance'
      if (response != null && response['data'] is List && response['data'].isNotEmpty) {
        attendanceList = response['data'][0]['attendance'] ?? [];
      }
      // Fallback: Check Direct 'attendance'
      else if (response != null && response['attendance'] is List) {
        attendanceList = response['attendance'];
      }

      if (attendanceList.isNotEmpty) {
        List<Map<String, dynamic>> tempList = [];

        // Counters
        int p = 0; // Present
        int a = 0; // Absent
        int l = 0; // Late
        int hd = 0; // Half Day
        int h = 0; // Holiday
        int s = 0; // Sunday

        DateTime today = DateTime.now();
        DateTime todayMidnight = DateTime(today.year, today.month, today.day);

        for (var dayRecord in attendanceList) {
          int day = dayRecord['day'] ?? 1;

          // Data Extraction
          Map<String, dynamic> innerData = dayRecord['data'] ?? {};
          int status = innerData['status'] ?? 2; // Default 2 (Absent)
          String? inTimeRaw = innerData['checkInTime'] ?? innerData['punchIn'];
          String? outTimeRaw = innerData['checkOutTime'] ?? innerData['punchOut'];

          // Notes/Holidays
          String note = dayRecord['note'] ?? "";
          var holidayObj = dayRecord['holiday'];

          DateTime recordDate = DateTime(_selectedDate.year, _selectedDate.month, day);
          bool isFuture = recordDate.isAfter(todayMidnight);

          // 🔴 UI STATUS & COUNTING LOGIC
          String uiStatus = "A";
          String uiText = "Absent";

          // 1. PRIORITY: Check Explicit Notes/Holidays first
          if (holidayObj != null) {
            uiStatus = "H";
            uiText = "Holiday";
            h++;
          }
          else if (note == "Sunday") {
            uiStatus = "S";
            uiText = "Sunday";
            s++;
          }
          else if (note == "NotJoined") {
            uiStatus = "NJ";
            uiText = "Not Joined";
            // ⚠️ Count NOTHING (Na Present, Na Absent)
          }
          else if (note == "Future" || isFuture) {
            uiStatus = "F";
            uiText = "-";
            // Count NOTHING
          }
          // 2. CHECK ATTENDANCE DATA (Status 1,3,4)
          else if (innerData.isNotEmpty) {
            if (status == 1) {
              uiStatus = "P";
              uiText = "Present";
              p++;
            } else if (status == 3) {
              uiStatus = "L";
              uiText = "Late";
              l++;
            } else if (status == 4) {
              uiStatus = "HD";
              uiText = "Half Day";
              hd++;
            } else {
              // Status 2 (Absent)
              uiStatus = "A";
              uiText = "Absent";
              a++;
            }
          }
          // 3. FALLBACK: Pure Absent
          else {
            uiStatus = "A";
            uiText = "Absent";
            a++;
          }

          tempList.add({
            "dayNum": day.toString(),
            "dayName": DateFormat('EEE').format(recordDate),
            "uiStatus": uiStatus,
            "uiText": uiText,
            "inTime": inTimeRaw ?? "",
            "outTime": outTimeRaw ?? "",
            "isToday": day == today.day && _selectedDate.month == today.month && _selectedDate.year == today.year,
            "isFuture": isFuture
          });
        }

        if (mounted) {
          setState(() {
            _dailyRecords = tempList;
            _presentCount = p;
            _absentCount = a;
            _lateCount = l;
            _halfDayCount = hd;
            _holidayCount = h;
            _sundayCount = s;
            _isLoading = false;
          });
        }
      } else {
        print("⚠️ Attendance List is empty after parsing");
        if (mounted) setState(() { _dailyRecords = []; _isLoading = false; });
      }
    } catch (e) {
      print("Error Parsing History: $e");
      if (mounted) setState(() { _dailyRecords = []; _isLoading = false; });
    }
  }

  void _changeMonth(int val) {
    setState(() => _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + val));
    _fetchReport();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 25),
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF29B6F6), Color(0xFF0288D1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18)),
                    ),
                    const SizedBox(width: 15),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const Text("My Attendance Logs", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30)),
                    Text(DateFormat('MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right, color: Colors.white, size: 30)),
                  ],
                ),
                const SizedBox(height: 15),

                // 🔴 UPDATED STATS ROW
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildHeaderStat("Present", _presentCount + _halfDayCount), // Half Day is mostly present
                    _buildHeaderStat("Late", _lateCount),
                    _buildHeaderStat("Half days", _halfDayCount),
                    _buildHeaderStat("Absent", _absentCount),
                    _buildHeaderStat("Sundays", _sundayCount),
                    _buildHeaderStat("Holidays", _holidayCount),

                  ],
                )
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0288D1)))
                : _dailyRecords.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _dailyRecords.length,
              itemBuilder: (context, index) => _buildRecordCard(_dailyRecords[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, int count) {
    return Column(children: [
      Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10))
    ]);
  }

  // 🔴 CARD UI LOGIC
  Widget _buildRecordCard(Map<String, dynamic> item) {
    String statusKey = item['uiStatus'];
    String statusText = item['uiText'];
    bool isToday = item['isToday'];
    bool isFuture = item['isFuture'];
    String inTime = item['inTime'];
    String outTime = item['outTime'];

    Color statusColor;
    IconData statusIcon;

    switch (statusKey) {
      case "P":
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case "L":
        statusColor = Colors.orange;
        statusIcon = Icons.access_time_filled;
        break;
      case "HD":
        statusColor = Colors.purpleAccent;
        statusIcon = Icons.star_half;
        break;
      case "S":
        statusColor = Colors.blueGrey;
        statusIcon = Icons.wb_sunny;
        break;
      case "H":
        statusColor = Colors.amber;
        statusIcon = Icons.star;
        break;
      case "NJ": // Not Joined
        statusColor = Colors.grey;
        statusIcon = Icons.person_add_disabled;
        break;
      case "A":
        statusColor = Colors.redAccent;
        statusIcon = Icons.cancel;
        break;
      default: // Future
        statusColor = Colors.grey.shade300;
        statusIcon = Icons.hourglass_empty;
    }

    // 🔴 TIME DISPLAY: Valid if present in raw data
    bool showTime = inTime.isNotEmpty && inTime != "--:--";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isFuture ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: isToday ? Border.all(color: const Color(0xFF0288D1), width: 1.5) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 6, decoration: BoxDecoration(color: statusColor, borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15)))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Column(
                      children: [
                        Text(item['dayNum'], style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: statusKey == "F" ? Colors.grey : Colors.black87)),
                        Text(item['dayName'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Container(width: 1, height: 30, color: Colors.grey.shade200),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Icon(statusIcon, size: 16, color: statusColor),
                              const SizedBox(width: 5),
                              Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          // 🔴 SHOW TIME IF AVAILABLE (Irrespective of status)
                          if (showTime)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text("${_formatTime(inTime)} - ${_formatTime(outTime)}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String time) {
    if (time.isEmpty || time == "--:--") return "--:--";
    try {
      return DateFormat("hh:mm a").format(DateFormat("HH:mm").parse(time));
    } catch (_) { return time; }
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.event_busy, size: 60, color: Colors.grey.shade300), const SizedBox(height: 10), Text("No records found", style: TextStyle(color: Colors.grey.shade500))]));
  }
}

















// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import '../../services/api_service.dart';
//
// class EmployeeHistoryScreen extends StatefulWidget {
//   final String employeeName;
//   final String employeeId;
//
//   const EmployeeHistoryScreen({
//     super.key,
//     required this.employeeName,
//     required this.employeeId
//   });
//
//   @override
//   State<EmployeeHistoryScreen> createState() => _EmployeeHistoryScreenState();
// }
//
// class _EmployeeHistoryScreenState extends State<EmployeeHistoryScreen> {
//   final ApiService _apiService = ApiService();
//
//   bool _isLoading = true;
//   DateTime _selectedDate = DateTime.now();
//   String? _storedLocationId;
//   String? _autoDepartmentId;
//
//   // Stats Counters
//   int _presentCount = 0;
//   int _absentCount = 0;
//   int _holidayCount = 0;
//   int _sundayCount = 0;
//
//   List<Map<String, dynamic>> _dailyRecords = [];
//
//   @override
//   void initState() {
//     super.initState();
//     _initData();
//   }
//
//   void _initData() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     _storedLocationId = prefs.getString('locationId');
//
//     // Fetch Departments to pick the first one automatically (as requested)
//     var depts = await _apiService.getDepartmentForEmployee();
//
//     if (mounted) {
//       setState(() {
//         if (depts.isNotEmpty) {
//           _autoDepartmentId = depts[0]['_id'];
//         }
//       });
//
//       if (_storedLocationId != null && _autoDepartmentId != null) {
//         _fetchReport();
//       } else {
//         setState(() => _isLoading = false);
//       }
//     }
//   }
//
//   void _fetchReport() async {
//     if (_storedLocationId == null || _autoDepartmentId == null) return;
//
//     setState(() => _isLoading = true);
//     String monthStr = DateFormat('yyyy-MM').format(_selectedDate);
//
//     var data = await _apiService.getEmployeeOwnHistory(
//         widget.employeeId,
//         monthStr,
//         _storedLocationId!,
//         _autoDepartmentId!
//     );
//
//     if (data != null && data['attendance'] != null) {
//       List<dynamic> attendanceList = data['attendance'];
//       List<Map<String, dynamic>> tempList = [];
//
//       int p = 0, a = 0, h = 0, s = 0;
//       DateTime today = DateTime.now();
//       DateTime todayMidnight = DateTime(today.year, today.month, today.day);
//
//       for (var dayRecord in attendanceList) {
//         int day = dayRecord['day'] ?? 1;
//         Map<String, dynamic> innerData = dayRecord['data'] ?? {};
//         String note = dayRecord['note'] ?? "";
//         String? holiday = dayRecord['holiday'];
//
//         DateTime recordDate = DateTime(_selectedDate.year, _selectedDate.month, day);
//         String dateString = DateFormat('yyyy-MM-dd').format(recordDate);
//
//         String? inTimeRaw = innerData['checkInTime'] ?? innerData['punchIn'];
//         String? outTimeRaw = innerData['checkOutTime'] ?? innerData['punchOut'];
//         bool isFuture = recordDate.isAfter(todayMidnight);
//
//         String statusKey = "A";
//         String statusText = "Absent";
//
//         // Logic based on Backend Response
//         if (inTimeRaw != null && inTimeRaw.isNotEmpty) {
//           statusKey = "P";
//           statusText = "Present";
//           p++;
//         } else if (note == "Sunday") {
//           statusKey = "S";
//           statusText = "Sunday";
//           s++;
//         } else if (holiday != null) {
//           statusKey = "H";
//           statusText = "Holiday";
//           h++;
//         } else if (note == "NotJoined") {
//           statusKey = "NJ";
//           statusText = "Not Joined";
//         } else if (isFuture) {
//           statusKey = "NA";
//           statusText = "-";
//         } else {
//           statusKey = "A";
//           statusText = "Absent";
//           a++;
//         }
//
//         tempList.add({
//           "dayNum": day.toString(),
//           "dayName": DateFormat('EEE').format(recordDate),
//           "status": statusKey,
//           "statusText": statusText,
//           "inTime": inTimeRaw ?? "",
//           "outTime": outTimeRaw ?? "",
//           "isToday": day == today.day && _selectedDate.month == today.month && _selectedDate.year == today.year,
//           "isFuture": isFuture
//         });
//       }
//
//       if (mounted) {
//         setState(() {
//           _dailyRecords = tempList;
//           _presentCount = p;
//           _absentCount = a;
//           _holidayCount = h;
//           _sundayCount = s;
//           _isLoading = false;
//         });
//       }
//     } else {
//       if (mounted) setState(() { _dailyRecords = []; _isLoading = false; });
//     }
//   }
//
//   void _changeMonth(int val) {
//     setState(() => _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + val));
//     _fetchReport();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF0F4F8),
//       body: Column(
//         children: [
//           // HEADER (Sky Blue Theme)
//           Container(
//             padding: const EdgeInsets.fromLTRB(20, 50, 20, 25),
//             decoration: const BoxDecoration(
//                 gradient: LinearGradient(
//                   colors: [Color(0xFF29B6F6), Color(0xFF0288D1)],
//                   begin: Alignment.topLeft,
//                   end: Alignment.bottomRight,
//                 ),
//                 borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
//                 boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]
//             ),
//             child: Column(
//               children: [
//                 Row(
//                   children: [
//                     InkWell(
//                       onTap: () => Navigator.pop(context),
//                       child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18)),
//                     ),
//                     const SizedBox(width: 15),
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
//                         const Text("My Attendance Logs", style: TextStyle(color: Colors.white70, fontSize: 12)),
//                       ],
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 15),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30)),
//                     Text(DateFormat('MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
//                     IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right, color: Colors.white, size: 30)),
//                   ],
//                 ),
//                 const SizedBox(height: 15),
//                 // Stats Row with Sunday
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                   children: [
//                     _buildHeaderStat("Present", _presentCount),
//                     _buildHeaderStat("Absent", _absentCount),
//                     _buildHeaderStat("Holidays", _holidayCount),
//                     _buildHeaderStat("Sundays", _sundayCount),
//                   ],
//                 )
//               ],
//             ),
//           ),
//
//           Expanded(
//             child: _isLoading
//                 ? const Center(child: CircularProgressIndicator(color: Color(0xFF0288D1)))
//                 : ListView.builder(
//               padding: const EdgeInsets.all(20),
//               itemCount: _dailyRecords.length,
//               itemBuilder: (context, index) => _buildRecordCard(_dailyRecords[index]),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildHeaderStat(String label, int count) {
//     return Column(children: [
//       Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
//       Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10))
//     ]);
//   }
//
//   Widget _buildRecordCard(Map<String, dynamic> item) {
//     String status = item['status'];
//     bool isToday = item['isToday'];
//     bool isFuture = item['isFuture'];
//
//     Color statusColor;
//     IconData statusIcon;
//
//     switch (status) {
//       case "P":
//         statusColor = Colors.green;
//         statusIcon = Icons.check_circle;
//         break;
//       case "S":
//         statusColor = Colors.blueGrey;
//         statusIcon = Icons.wb_sunny;
//         break;
//       case "H":
//         statusColor = Colors.orange;
//         statusIcon = Icons.star;
//         break;
//       case "NJ":
//         statusColor = Colors.blue;
//         statusIcon = Icons.info_outline;
//         break;
//       case "A":
//         statusColor = Colors.redAccent;
//         statusIcon = Icons.cancel;
//         break;
//       default:
//         statusColor = Colors.grey.shade400;
//         statusIcon = Icons.remove_circle_outline;
//     }
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//         color: isFuture ? Colors.grey.shade50 : Colors.white,
//         borderRadius: BorderRadius.circular(15),
//         border: isToday ? Border.all(color: const Color(0xFF0288D1), width: 1.5) : null,
//         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
//       ),
//       child: IntrinsicHeight(
//         child: Row(
//           children: [
//             Container(width: 6, decoration: BoxDecoration(color: statusColor, borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15)))),
//             Expanded(
//               child: Padding(
//                 padding: const EdgeInsets.all(15),
//                 child: Row(
//                   children: [
//                     Column(
//                       children: [
//                         Text(item['dayNum'], style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isFuture ? Colors.grey : Colors.black87)),
//                         Text(item['dayName'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
//                       ],
//                     ),
//                     const SizedBox(width: 20),
//                     Container(width: 1, height: 30, color: Colors.grey.shade200),
//                     const SizedBox(width: 20),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           Row(
//                             children: [
//                               Icon(statusIcon, size: 16, color: statusColor),
//                               const SizedBox(width: 5),
//                               Text(item['statusText'], style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 16)),
//                             ],
//                           ),
//                           if (status == "P")
//                             Text("${_formatTime(item['inTime'])} - ${_formatTime(item['outTime'])}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
//                         ],
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   String _formatTime(String time) {
//     if (time.isEmpty || time == "--:--") return "--:--";
//     try {
//       return DateFormat("hh:mm a").format(DateFormat("HH:mm").parse(time));
//     } catch (_) { return time; }
//   }
//
//   Widget _buildEmptyState() {
//     return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.event_busy, size: 60, color: Colors.grey.shade300), const SizedBox(height: 10), Text("No records found", style: TextStyle(color: Colors.grey.shade500))]));
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
// // import 'package:flutter/material.dart';
// // import 'package:intl/intl.dart';
// // import 'package:shared_preferences/shared_preferences.dart';
// // import '../../services/api_service.dart';
// //
// // class EmployeeHistoryScreen extends StatefulWidget {
// //   final String employeeName;
// //   final String employeeId;
// //
// //   const EmployeeHistoryScreen({
// //     super.key,
// //     required this.employeeName,
// //     required this.employeeId
// //   });
// //
// //   @override
// //   State<EmployeeHistoryScreen> createState() => _EmployeeHistoryScreenState();
// // }
// //
// // class _EmployeeHistoryScreenState extends State<EmployeeHistoryScreen> {
// //   final ApiService _apiService = ApiService();
// //
// //   bool _isLoading = true;
// //   DateTime _selectedDate = DateTime.now();
// //   String? _storedLocationId;
// //
// //   int _presentCount = 0;
// //   int _absentCount = 0;
// //   int _holidayCount = 0;
// //
// //   List<Map<String, dynamic>> _dailyRecords = [];
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _fetchLocationAndReport();
// //   }
// //
// //   // 🔥 SMART FETCH: Pehle Storage check karo, nahi mila to API se mangwao
// //   void _fetchLocationAndReport() async {
// //     SharedPreferences prefs = await SharedPreferences.getInstance();
// //     String? locId = prefs.getString('locationId');
// //
// //     if (locId != null && locId.isNotEmpty) {
// //       // ✅ Case 1: Storage mein mil gayi
// //       print("✅ Location ID found in Storage: $locId");
// //       if(mounted) {
// //         setState(() { _storedLocationId = locId; });
// //         _fetchReport();
// //       }
// //     } else {
// //       // ⚠️ Case 2: Storage mein nahi hai (Shayad purana login hai)
// //       print("⚠️ Location ID missing. Auto-fetching from Profile...");
// //
// //       String? fetchedId = await _apiService.fetchUserLocationId(widget.employeeId);
// //
// //       if (fetchedId != null && mounted) {
// //         print("✅ Auto-fetched Location ID: $fetchedId");
// //         await prefs.setString('locationId', fetchedId); // Future ke liye save karo
// //
// //         setState(() { _storedLocationId = fetchedId; });
// //         _fetchReport();
// //       } else {
// //         print("❌ Failed to fetch Location ID.");
// //         if(mounted) setState(() => _isLoading = false);
// //       }
// //     }
// //   }
// //
// //   void _fetchReport() async {
// //     if (_storedLocationId == null) return;
// //
// //     setState(() => _isLoading = true);
// //     String monthStr = DateFormat('yyyy-MM').format(_selectedDate);
// //
// //     var data = await _apiService.getEmployeeOwnHistory(
// //         widget.employeeId,
// //         monthStr,
// //         _storedLocationId!
// //
// //     );
// //
// //     if (data != null && data['attendance'] != null) {
// //       List<dynamic> attendanceList = data['attendance'];
// //       List<Map<String, dynamic>> tempList = [];
// //
// //       int p = 0, a = 0, h = 0;
// //       DateTime now = DateTime.now();
// //       DateTime todayMidnight = DateTime(now.year, now.month, now.day);
// //
// //       for (var dayRecord in attendanceList) {
// //         int day = dayRecord['day'] ?? 1;
// //         Map<String, dynamic> innerData = dayRecord['data'] ?? {};
// //         String note = dayRecord['note'] ?? "";
// //
// //         DateTime recordDate = DateTime(_selectedDate.year, _selectedDate.month, day);
// //         String dateString = DateFormat('yyyy-MM-dd').format(recordDate);
// //
// //         String? inTimeRaw = innerData['checkInTime'] ?? innerData['punchIn'];
// //         String? outTimeRaw = innerData['checkOutTime'] ?? innerData['punchOut'];
// //         bool isLate = innerData['isLate'] == true;
// //
// //         String status = "A";
// //         String statusText = "Absent";
// //         bool isFuture = recordDate.isAfter(todayMidnight);
// //
// //         if (inTimeRaw != null && inTimeRaw.isNotEmpty) {
// //           status = "P";
// //           statusText = "Present";
// //           p++;
// //         } else if (note.isNotEmpty) {
// //           status = "H";
// //           statusText = note;
// //           h++;
// //         } else if (isFuture) {
// //           status = "NA";
// //           statusText = "-";
// //         } else {
// //           status = "A";
// //           a++;
// //         }
// //
// //         String workDuration = "";
// //         if (inTimeRaw != null && outTimeRaw != null) {
// //           try {
// //             DateTime inT = DateFormat("HH:mm").parse(inTimeRaw);
// //             DateTime outT = DateFormat("HH:mm").parse(outTimeRaw);
// //             Duration diff = outT.difference(inT);
// //             if (diff.isNegative) diff = diff + const Duration(hours: 24);
// //             workDuration = "${diff.inHours}h ${diff.inMinutes % 60}m";
// //           } catch (_) {}
// //         }
// //
// //         tempList.add({
// //           "date": dateString,
// //           "dayNum": day.toString(),
// //           "dayName": DateFormat('EEE').format(recordDate),
// //           "status": status,
// //           "statusText": statusText,
// //           "inTime": inTimeRaw ?? "",
// //           "outTime": outTimeRaw ?? "",
// //           "workDuration": workDuration,
// //           "isToday": day == now.day && _selectedDate.month == now.month && _selectedDate.year == now.year,
// //           "isLate": isLate,
// //           "isFuture": isFuture
// //         });
// //       }
// //
// //       if (mounted) {
// //         setState(() {
// //           _dailyRecords = tempList;
// //           _presentCount = p;
// //           _absentCount = a;
// //           _holidayCount = h;
// //           _isLoading = false;
// //         });
// //       }
// //     } else {
// //       if (mounted) setState(() { _dailyRecords = []; _isLoading = false; });
// //     }
// //   }
// //
// //   void _changeMonth(int monthsToAdd) {
// //     setState(() {
// //       _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + monthsToAdd);
// //     });
// //     // Month change hone par dubara ID check karne ki zarurat nahi, bas report fetch karo
// //     if(_storedLocationId != null) _fetchReport();
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       backgroundColor: const Color(0xFFF5F7FA),
// //       body: Column(
// //         children: [
// //           // 🔴 HEADER
// //           Container(
// //             padding: const EdgeInsets.only(top: 50, bottom: 25, left: 20, right: 20),
// //             decoration: const BoxDecoration(
// //                 gradient: LinearGradient(
// //                   colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
// //                   begin: Alignment.topLeft,
// //                   end: Alignment.bottomRight,
// //                 ),
// //                 borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
// //                 boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]
// //             ),
// //             child: Column(
// //               children: [
// //                 Row(
// //                   children: [
// //                     InkWell(
// //                       onTap: () => Navigator.pop(context),
// //                       child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18)),
// //                     ),
// //                     const SizedBox(width: 15),
// //                     Column(
// //                       crossAxisAlignment: CrossAxisAlignment.start,
// //                       children: [
// //                         Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
// //                         const Text("My Attendance Logs", style: TextStyle(color: Colors.white70, fontSize: 12)),
// //                       ],
// //                     ),
// //                   ],
// //                 ),
// //                 const SizedBox(height: 20),
// //                 Row(
// //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                   children: [
// //                     IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30)),
// //                     Text(DateFormat('MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
// //                     IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right, color: Colors.white, size: 30)),
// //                   ],
// //                 ),
// //                 const SizedBox(height: 10),
// //                 Row(
// //                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
// //                   children: [
// //                     _buildHeaderStat("Present", _presentCount.toString()),
// //                     Container(height: 25, width: 1, color: Colors.white24),
// //                     _buildHeaderStat("Absent", _absentCount.toString()),
// //                     Container(height: 25, width: 1, color: Colors.white24),
// //                     _buildHeaderStat("Holidays", _holidayCount.toString()),
// //                   ],
// //                 )
// //               ],
// //             ),
// //           ),
// //
// //           // 🔴 LIST
// //           Expanded(
// //             child: _isLoading
// //                 ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// //                 : _dailyRecords.isEmpty
// //                 ? _buildEmptyState()
// //                 : ListView.builder(
// //               padding: const EdgeInsets.all(20),
// //               itemCount: _dailyRecords.length,
// //               itemBuilder: (context, index) => _buildCleanCard(_dailyRecords[index]),
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   Widget _buildHeaderStat(String label, String count) {
// //     return Column(children: [Text(count, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))]);
// //   }
// //
// //   Widget _buildCleanCard(Map<String, dynamic> item) {
// //     bool isFuture = item['isFuture'];
// //     String status = item['status'];
// //     bool isPresent = status == "P";
// //     bool isAbsent = status == "A";
// //     bool isHoliday = status == "H";
// //     bool isToday = item['isToday'];
// //     bool isLate = item['isLate'];
// //
// //     Color statusColor = Colors.grey.shade300;
// //     if(isPresent) statusColor = const Color(0xFF00C853);
// //     if(isAbsent) statusColor = const Color(0xFFE53935);
// //     if(isHoliday) statusColor = const Color(0xFFFB8C00);
// //
// //     return Container(
// //       margin: const EdgeInsets.only(bottom: 12),
// //       decoration: BoxDecoration(
// //         color: isFuture ? const Color(0xFFF9FAFB) : Colors.white,
// //         borderRadius: BorderRadius.circular(12),
// //         border: isToday ? Border.all(color: const Color(0xFF2E3192), width: 1.5) : null,
// //         boxShadow: isFuture ? [] : [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
// //       ),
// //       child: ClipRRect(
// //         borderRadius: BorderRadius.circular(12),
// //         child: IntrinsicHeight(
// //           child: Row(
// //             children: [
// //               Container(width: 5, color: statusColor),
// //               Expanded(
// //                 child: Padding(
// //                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
// //                   child: Row(
// //                     children: [
// //                       Column(
// //                         crossAxisAlignment: CrossAxisAlignment.start,
// //                         children: [
// //                           Text(item['dayNum'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isFuture ? Colors.grey : const Color(0xFF2E3192))),
// //                           Text(item['dayName'].toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
// //                         ],
// //                       ),
// //                       const SizedBox(width: 20),
// //                       Container(width: 1, height: 35, color: Colors.grey.shade200),
// //                       const SizedBox(width: 20),
// //                       Expanded(
// //                         child: isPresent
// //                             ? _buildPresentDetails(item, isLate)
// //                             : _buildStatusDetails(item, statusColor),
// //                       ),
// //                     ],
// //                   ),
// //                 ),
// //               ),
// //             ],
// //           ),
// //         ),
// //       ),
// //     );
// //   }
// //
// //   Widget _buildPresentDetails(Map<String, dynamic> item, bool isLate) {
// //     return Row(
// //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //       children: [
// //         Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
// //           _buildTimeRow("In", item['inTime']), const SizedBox(height: 4), _buildTimeRow("Out", item['outTime']),
// //         ]),
// //         Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
// //           const Text("Present", style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold)),
// //           const SizedBox(height: 4),
// //           if(isLate) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4)), child: const Text("LATE", style: TextStyle(color: Color(0xFFD32F2F), fontSize: 9, fontWeight: FontWeight.bold))),
// //           if(item['workDuration'].isNotEmpty) Text(item['workDuration'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF455A64))),
// //         ])
// //       ],
// //     );
// //   }
// //
// //   Widget _buildStatusDetails(Map<String, dynamic> item, Color color) {
// //     return Row(children: [Icon(item['status'] == "H" ? Icons.star_rounded : (item['isFuture'] ? Icons.hourglass_empty_rounded : Icons.cancel), color: color, size: 20), const SizedBox(width: 10), Text(item['statusText'], style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold))]);
// //   }
// //
// //   Widget _buildTimeRow(String label, String time) {
// //     String displayTime = "--:--";
// //     if(time != "" && time != "--:--") {
// //       try { displayTime = DateFormat("hh:mm a").format(DateFormat("HH:mm").parse(time)); } catch (_) {}
// //     }
// //     return Row(children: [SizedBox(width: 25, child: Text("$label:", style: TextStyle(fontSize: 11, color: Colors.grey.shade500))), Text(displayTime, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF263238)))]);
// //   }
// //
// //   Widget _buildEmptyState() {
// //     return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_view_day_rounded, size: 50, color: Colors.grey.shade300), const SizedBox(height: 10), Text("No records found", style: TextStyle(color: Colors.grey.shade500))]));
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
// // // import 'package:flutter/material.dart';
// // // import 'package:intl/intl.dart';
// // // import '../../services/api_service.dart';
// // //
// // // class EmployeeHistoryScreen extends StatefulWidget {
// // //   final String employeeName;
// // //   final String employeeId;
// // //
// // //   const EmployeeHistoryScreen({
// // //     super.key,
// // //     required this.employeeName,
// // //     required this.employeeId
// // //   });
// // //
// // //   @override
// // //   State<EmployeeHistoryScreen> createState() => _EmployeeHistoryScreenState();
// // // }
// // //
// // // class _EmployeeHistoryScreenState extends State<EmployeeHistoryScreen> {
// // //   final ApiService _apiService = ApiService();
// // //
// // //   bool _isLoading = true;
// // //   DateTime _selectedDate = DateTime.now();
// // //
// // //   // Data Holders
// // //   Map<String, dynamic>? _reportData;
// // //   List<Map<String, dynamic>> _dailyRecords = [];
// // //
// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     _fetchReport();
// // //   }
// // //
// // //   // 🔴 API CALL LOGIC (Using Specialized Function)
// // //   void _fetchReport() async {
// // //     setState(() => _isLoading = true);
// // //
// // //     String monthStr = DateFormat('yyyy-MM').format(_selectedDate).toString();
// // //
// // //     // 🔥 CALLING THE NEW EMPLOYEE-SPECIFIC FUNCTION
// // //     var data = await _apiService.getEmployeeOwnHistory(widget.employeeId, monthStr);
// // //
// // //     if (data != null) {
// // //       // 1. Parse Data
// // //       Map<String, dynamic> daysMap = data['days'] ?? {};
// // //       List<Map<String, dynamic>> tempList = [];
// // //
// // //       daysMap.forEach((dateKey, value) {
// // //         tempList.add({
// // //           "date": dateKey,
// // //           "status": value['status'] ?? "",
// // //           "arr": value['arr'] ?? "",
// // //           "dep": value['dep'] ?? "",
// // //           "work": value['work'] ?? "0"
// // //         });
// // //       });
// // //
// // //       // 2. Sort List
// // //       tempList.sort((a, b) => b['date'].compareTo(b['date']));
// // //
// // //       if (mounted) {
// // //         setState(() {
// // //           _reportData = data;
// // //           _dailyRecords = tempList;
// // //           _isLoading = false;
// // //         });
// // //       }
// // //     } else {
// // //       if (mounted) {
// // //         setState(() {
// // //           _reportData = null;
// // //           _dailyRecords = [];
// // //           _isLoading = false;
// // //         });
// // //       }
// // //     }
// // //   }
// // //
// // //   void _changeMonth(int monthsToAdd) {
// // //     setState(() {
// // //       _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + monthsToAdd);
// // //     });
// // //     _fetchReport();
// // //   }
// // //
// // //   @override
// // //   Widget build(BuildContext context) {
// // //     return Scaffold(
// // //       backgroundColor: const Color(0xFFF2F5F9),
// // //       body: Stack(
// // //         children: [
// // //           // --- HEADER BACKGROUND (Blue-Cyan Gradient) ---
// // //           Container(
// // //             height: 240,
// // //             decoration: const BoxDecoration(
// // //               gradient: LinearGradient(
// // //                 colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
// // //                 begin: Alignment.topLeft,
// // //                 end: Alignment.bottomRight,
// // //               ),
// // //               borderRadius: BorderRadius.only(
// // //                 bottomLeft: Radius.circular(30),
// // //                 bottomRight: Radius.circular(30),
// // //               ),
// // //             ),
// // //           ),
// // //
// // //           SafeArea(
// // //             child: Column(
// // //               children: [
// // //                 // --- TOP BAR ---
// // //                 Padding(
// // //                   padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
// // //                   child: Row(
// // //                     children: [
// // //                       IconButton(
// // //                         icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
// // //                         onPressed: () => Navigator.pop(context),
// // //                       ),
// // //                       const SizedBox(width: 10),
// // //                       Column(
// // //                         crossAxisAlignment: CrossAxisAlignment.start,
// // //                         children: [
// // //                           Text(
// // //                             widget.employeeName,
// // //                             style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
// // //                           ),
// // //                           Text(
// // //                             "My Attendance Logs",
// // //                             style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
// // //                           ),
// // //                         ],
// // //                       )
// // //                     ],
// // //                   ),
// // //                 ),
// // //
// // //                 // --- MONTH SELECTOR ---
// // //                 Container(
// // //                   margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
// // //                   padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
// // //                   decoration: BoxDecoration(
// // //                       color: Colors.white.withOpacity(0.2),
// // //                       borderRadius: BorderRadius.circular(15),
// // //                       border: Border.all(color: Colors.white.withOpacity(0.3))
// // //                   ),
// // //                   child: Row(
// // //                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // //                     children: [
// // //                       IconButton(
// // //                         icon: const Icon(Icons.chevron_left, color: Colors.white),
// // //                         onPressed: () => _changeMonth(-1),
// // //                       ),
// // //                       Text(
// // //                         DateFormat('MMMM yyyy').format(_selectedDate),
// // //                         style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
// // //                       ),
// // //                       IconButton(
// // //                         icon: const Icon(Icons.chevron_right, color: Colors.white),
// // //                         onPressed: () => _changeMonth(1),
// // //                       ),
// // //                     ],
// // //                   ),
// // //                 ),
// // //
// // //                 const SizedBox(height: 15),
// // //
// // //                 // --- SUMMARY STATS GRID ---
// // //                 if (_reportData != null)
// // //                   Container(
// // //                     margin: const EdgeInsets.symmetric(horizontal: 20),
// // //                     padding: const EdgeInsets.all(15),
// // //                     decoration: BoxDecoration(
// // //                       color: Colors.white,
// // //                       borderRadius: BorderRadius.circular(20),
// // //                       boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
// // //                     ),
// // //                     child: Row(
// // //                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // //                       children: [
// // //                         _buildSummaryItem("Present", _reportData!['present'].toString(), Colors.green),
// // //                         _buildSummaryItem("Absent", _reportData!['absent'].toString(), Colors.red),
// // //                         _buildSummaryItem("Half Day", _reportData!['halfDay'].toString(), Colors.orange),
// // //                       ],
// // //                     ),
// // //                   ),
// // //
// // //                 const SizedBox(height: 15),
// // //
// // //                 // --- LIST OF DAILY RECORDS ---
// // //                 Expanded(
// // //                   child: _isLoading
// // //                       ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// // //                       : _dailyRecords.isEmpty
// // //                       ? _buildEmptyState()
// // //                       : ListView.builder(
// // //                     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
// // //                     itemCount: _dailyRecords.length,
// // //                     itemBuilder: (context, index) {
// // //                       return _buildDailyCard(_dailyRecords[index]);
// // //                     },
// // //                   ),
// // //                 ),
// // //               ],
// // //             ),
// // //           ),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   // --- WIDGETS (Same as Admin) ---
// // //
// // //   Widget _buildSummaryItem(String label, String value, Color color) {
// // //     return Column(
// // //       children: [
// // //         Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
// // //         const SizedBox(height: 4),
// // //         Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
// // //       ],
// // //     );
// // //   }
// // //
// // //   Widget _buildDailyCard(Map<String, dynamic> item) {
// // //     DateTime dt = DateTime.parse(item['date']);
// // //     String dayNum = DateFormat('dd').format(dt);
// // //     String dayName = DateFormat('EEE').format(dt);
// // //     String status = item['status'];
// // //     String arr = item['arr'];
// // //     String dep = item['dep'];
// // //     String work = item['work'];
// // //
// // //     Color statusColor = Colors.grey;
// // //     String statusText = "Off";
// // //
// // //     if (status == "A") {
// // //       statusColor = Colors.red;
// // //       statusText = "Absent";
// // //     } else if (status == "H") {
// // //       statusColor = Colors.orange;
// // //       statusText = "Half Day";
// // //     } else if (status == "P" || (arr.isNotEmpty && status != "A")) {
// // //       statusColor = Colors.green;
// // //       statusText = "Present";
// // //     }
// // //
// // //     if (arr.isNotEmpty && dep.isEmpty) {
// // //       statusColor = Colors.blue;
// // //       statusText = "Active";
// // //     }
// // //
// // //     return Container(
// // //       margin: const EdgeInsets.only(bottom: 12),
// // //       decoration: BoxDecoration(
// // //         color: Colors.white,
// // //         borderRadius: BorderRadius.circular(15),
// // //         boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3))],
// // //       ),
// // //       child: IntrinsicHeight(
// // //         child: Row(
// // //           children: [
// // //             Container(
// // //               width: 5,
// // //               decoration: BoxDecoration(
// // //                 color: statusColor,
// // //                 borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15)),
// // //               ),
// // //             ),
// // //             Expanded(
// // //               child: Padding(
// // //                 padding: const EdgeInsets.all(12),
// // //                 child: Row(
// // //                   children: [
// // //                     Container(
// // //                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
// // //                       decoration: BoxDecoration(
// // //                         color: Colors.grey.shade50,
// // //                         borderRadius: BorderRadius.circular(10),
// // //                       ),
// // //                       child: Column(
// // //                         children: [
// // //                           Text(dayNum, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
// // //                           Text(dayName.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
// // //                         ],
// // //                       ),
// // //                     ),
// // //                     const SizedBox(width: 15),
// // //                     Expanded(
// // //                       child: Column(
// // //                         crossAxisAlignment: CrossAxisAlignment.start,
// // //                         children: [
// // //                           if (status == "A" || (arr.isEmpty && dep.isEmpty))
// // //                             Text("No Punch Record", style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontStyle: FontStyle.italic))
// // //                           else ...[
// // //                             _buildTimeRow("In", arr, Colors.black87),
// // //                             const SizedBox(height: 4),
// // //                             _buildTimeRow("Out", dep.isEmpty ? "--:--" : dep, Colors.grey.shade600),
// // //                           ]
// // //                         ],
// // //                       ),
// // //                     ),
// // //                     Column(
// // //                       crossAxisAlignment: CrossAxisAlignment.end,
// // //                       children: [
// // //                         Container(
// // //                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
// // //                           decoration: BoxDecoration(
// // //                             color: statusColor.withOpacity(0.1),
// // //                             borderRadius: BorderRadius.circular(6),
// // //                           ),
// // //                           child: Text(
// // //                             statusText.toUpperCase(),
// // //                             style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
// // //                           ),
// // //                         ),
// // //                         const SizedBox(height: 6),
// // //                         if (work != "0" && work.isNotEmpty)
// // //                         Text(
// // //                           (double.parse(work) * 60) < 60
// // //                               ? "${(double.parse(work) * 60).toStringAsFixed(0)} min"  // If less than 60 mins (e.g., "45 min")
// // //                               : "${double.parse(work).toStringAsFixed(1)} hrs",        // If 60+ mins (e.g., "1.5 hrs")
// // //                           // 👆 LOGIC END
// // //                         ),
// // //                           ],
// // //                     )
// // //                   ],
// // //                 ),
// // //               ),
// // //             )
// // //           ],
// // //         ),
// // //       ),
// // //     );
// // //   }
// // //
// // //   Widget _buildTimeRow(String label, String time, Color color) {
// // //     return Row(
// // //       children: [
// // //         Text("$label: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
// // //         Text(time.isEmpty ? "--:--" : time, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
// // //       ],
// // //     );
// // //   }
// // //
// // //   Widget _buildEmptyState() {
// // //     return Center(
// // //       child: Column(
// // //         mainAxisAlignment: MainAxisAlignment.center,
// // //         children: [
// // //           Icon(Icons.calendar_today_outlined, size: 50, color: Colors.grey.shade300),
// // //           const SizedBox(height: 10),
// // //           Text("No records found", style: TextStyle(color: Colors.grey.shade500)),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // // }