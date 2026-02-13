import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final String employeeName;
  final String employeeId;
  final String locationId;
  final String departmentId;

  const AttendanceHistoryScreen({
    super.key,
    required this.employeeName,
    required this.employeeId,
    required this.locationId,
    required this.departmentId,
  });

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  // 🔴 Summary Counters (Ab ye API se direct bharne hain)
  int _totalDays = 0; // New
  int _presentCount = 0;
  int _absentCount = 0;
  int _lateCount = 0;
  int _holidayCount = 0;
  int _halfdayCount = 0;
  int _sundayCount = 0;

  List<Map<String, dynamic>> _dailyRecords = [];

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  void _fetchReport() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    String monthStr = DateFormat('yyyy-MM').format(_selectedDate);

    try {
      var response = await _apiService.getMonthlyReport(
          widget.employeeId, monthStr, widget.locationId, widget.departmentId);

      if (response != null && response['success'] == true) {

        // 1️⃣ DATA EXTRACTION FROM RESPONSE STRUCTURE
        // Data array me se first object nikalna hai (User Specific)
        var empData = (response['data'] as List).isNotEmpty ? response['data'][0] : {};
        var totals = empData['totals'] ?? {};

        // Month Summary root level pe hai
        var summary = response['monthSummary'] ?? {};

        // 2️⃣ SET SUMMARY COUNTERS DIRECTLY (No manual calculation)
        if (mounted) {
          setState(() {
            // Employee Specific Totals
            _presentCount = (totals['present'] ?? 0).toInt();
            _absentCount = (totals['absent'] ?? 0).toInt();
            _lateCount = (totals['late'] ?? 0).toInt();
            _halfdayCount = (totals['halfDays'] ?? 0).toInt();

            // Month Summary Totals
            _totalDays = (summary['totalDays'] ?? 0).toInt();
            _holidayCount = (summary['totalHolidays'] ?? 0).toInt();
            _sundayCount = (summary['totalSundays'] ?? 0).toInt();
          });

          print("total  $_totalDays");
          print("present  $_presentCount");
          print("late  $_lateCount");
          print("absent  $_absentCount");
          print("Half day $_halfdayCount");
          print("sunday $_sundayCount");
        }

        // 3️⃣ PROCESS DAILY LIST (Sirf UI List banane ke liye)
        List<dynamic> attendanceList = empData['attendance'] ?? [];
        List<Map<String, dynamic>> tempList = [];

        DateTime now = DateTime.now();
        DateTime todayMidnight = DateTime(now.year, now.month, now.day);

        for (var dayRecord in attendanceList) {
          int day = dayRecord['day'] ?? 1;
          Map<String, dynamic> innerData = dayRecord['data'] ?? {};

          // Backend Values
          int status = innerData['status'] ?? 2;
          String? inTime = innerData['checkInTime'] ?? innerData['punchIn'];
          String? outTime = innerData['checkOutTime'] ?? innerData['punchOut'];
          String note = dayRecord['note'] ?? "";
          var holidayName = dayRecord['holiday'];
          String workDuration = innerData['workingHours'] ?? innerData['duration'] ?? "";
          bool isLate = innerData['isLate'] == true;

          // UI Status Logic (Sirf Display Text ke liye)
          DateTime recordDate = DateTime(_selectedDate.year, _selectedDate.month, day);
          String uiStatus = "A";
          String uiText = "Absent";

          if (holidayName != null) {
            uiStatus = "H"; uiText = holidayName.toString();
          } else if (note == "Sunday") {
            uiStatus = "S"; uiText = "Sunday";
          } else if (note == "NotJoined") {
            uiStatus = "NJ"; uiText = "Not Joined";
          } else if (note == "Future" || recordDate.isAfter(todayMidnight)) {
            uiStatus = "F"; uiText = "-";
          } else {
            if (status == 1) { uiStatus = "P"; uiText = "Present"; }
            else if (status == 3) { uiStatus = "L"; uiText = "Late"; }
            else if (status == 4) { uiStatus = "HD"; uiText = "Half Day"; }
            else if (status == 5) { uiStatus = "E"; uiText = "Excused"; }
            else { uiStatus = "A"; uiText = "Absent"; }
          }

          tempList.add({
            "dayNum": day.toString(),
            "dayName": DateFormat('EEE').format(recordDate),
            "uiStatus": uiStatus,
            "uiText": uiText,
            "inTime": inTime ?? "",
            "outTime": outTime ?? "",
            "isLate": isLate,
            "status": status,
            "workDuration": workDuration
          });
        }

        if (mounted) {
          setState(() {
            _dailyRecords = tempList;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("History Error: $e");
      if (mounted) setState(() => _isLoading = false);
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
          // 🔴 HEADER SECTION
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 25),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)]),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: Column(
              children: [
                // Top Bar
                Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18)
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(child: Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  ],
                ),

                const SizedBox(height: 20),

                // Month Selector
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30)),
                    Text(DateFormat('MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right, color: Colors.white, size: 30)),
                  ],
                ),

                const SizedBox(height: 20),

                // 🔴 STATS ROW (Horizontal Scrollable for better fit)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Total Days (New)
                      _buildStatCol("Days", _totalDays, Colors.white),
                      _buildDivider(),
                      _buildStatCol("Present", _presentCount, Colors.white),
                      _buildDivider(),
                      _buildStatCol("Late", _lateCount, Colors.white),
                      _buildDivider(),
                      _buildStatCol("Half Day", _halfdayCount, Colors.white),
                      _buildDivider(),
                      _buildStatCol("Absent", _absentCount, Colors.white),
                      _buildDivider(),
                      _buildStatCol("Sundays", _sundayCount, Colors.white),
                      _buildDivider(),
                      _buildStatCol("Holidays", _holidayCount, Colors.white),
                    ],
                  ),
                )
              ],
            ),
          ),

          // 🔴 LIST SECTION
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
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

  // 🔴 STATS WIDGETS
  Widget _buildStatCol(String label, int val, Color color) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Column(children: [
      Text(val.toString(), style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500))
    ]),
  );

  Widget _buildDivider() => Container(height: 25, width: 1, color: Colors.white24);

  // 🔴 MODERN CARD (Same as your approved design)
  Widget _buildRecordCard(Map<String, dynamic> item) {
    String statusKey = item['uiStatus'];
    bool isLate = item['isLate'] ?? false;
    int status = item['status'] ?? 2;
    String workTime = item['workDuration'] ?? "";

    Color statusColor;
    Color bgColor;
    IconData statusIcon;

    switch (statusKey) {
      case "P": statusColor = const Color(0xFF00C853); bgColor = const Color(0xFFE8F5E9); statusIcon = Icons.check_circle_outline; break;
      case "L": statusColor = const Color(0xFFFF9800); bgColor = const Color(0xFFFFF3E0); statusIcon = Icons.access_time; break;
      case "HD": statusColor = const Color(0xFF673AB7); bgColor = const Color(0xFFEDE7F6); statusIcon = Icons.star_half; break;
      case "S": statusColor = const Color(0xFF607D8B); bgColor = const Color(0xFFECEFF1); statusIcon = Icons.weekend; break;
      case "H": statusColor = const Color(0xFFFFD600); bgColor = const Color(0xFFFFFDE7); statusIcon = Icons.celebration; break;
      case "NJ": statusColor = Colors.grey; bgColor = const Color(0xFFFAFAFA); statusIcon = Icons.person_off; break;
      case "A": statusColor = const Color(0xFFD32F2F); bgColor = const Color(0xFFFFEBEE); statusIcon = Icons.cancel_outlined; break;
      default: statusColor = Colors.grey.shade400; bgColor = const Color(0xFFF5F5F5); statusIcon = Icons.hourglass_empty;
    }

    String inT = item['inTime'];
    String outT = item['outTime'];
    bool hasTime = inT.isNotEmpty && inT != "--:--";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 70,
                decoration: BoxDecoration(color: bgColor, border: Border(right: BorderSide(color: statusColor.withOpacity(0.3), width: 1))),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item['dayNum'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: statusColor)),
                    Text(item['dayName'].toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor.withOpacity(0.8))),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [Icon(statusIcon, size: 14, color: statusColor), const SizedBox(width: 4), Text(item['uiText'], style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold))]),
                          ),
                          if (isLate && status != 3)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade100)),
                              child: const Text("LATE", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (hasTime) ...[
                        Row(children: [
                          _buildTimeInfo(Icons.login_rounded, "In", _formatTime(inT), Colors.green),
                          Container(height: 25, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 15)),
                          _buildTimeInfo(Icons.logout_rounded, "Out", outT.isEmpty ? "Active" : _formatTime(outT), outT.isEmpty ? Colors.blue : Colors.redAccent),
                        ]),
                      ] else ...[
                        Text(statusKey == "S" || statusKey == "H" ? "Enjoy your holiday!" : "No punch records.", style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic))
                      ],
                      if (workTime.isNotEmpty && workTime != "0") ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6)),
                          child: Row(children: [const Icon(Icons.timer_outlined, size: 14, color: Colors.blueGrey), const SizedBox(width: 6), Text("Total Work: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)), Text("$workTime Hrs", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87))]),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeInfo(IconData icon, String label, String time, Color color) {
    return Row(children: [Icon(icon, size: 16, color: color.withOpacity(0.7)), const SizedBox(width: 6), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)), Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87))])]);
  }

  String _formatTime(String t) {
    if (t.isEmpty || t == "--:--") return "--:--";
    try {
      DateTime dt = t.contains("T") ? DateTime.parse(t).toLocal() : DateFormat("HH:mm").parse(t);
      return DateFormat("hh:mm a").format(dt);
    } catch (_) { return t; }
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.event_busy, size: 60, color: Colors.grey.shade300), const SizedBox(height: 10), Text("No records found", style: TextStyle(color: Colors.grey.shade500))]));
  }
}
















// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import '../../services/api_service.dart';
//
// class AttendanceHistoryScreen extends StatefulWidget {
//   final String employeeName;
//   final String employeeId;
//   final String locationId;
//   final String departmentId;
//
//   const AttendanceHistoryScreen({
//     super.key,
//     required this.employeeName,
//     required this.employeeId,
//     required this.locationId,
//     required this.departmentId,
//   });
//
//   @override
//   State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
// }
//
// class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
//   final ApiService _apiService = ApiService();
//   bool _isLoading = true;
//   DateTime _selectedDate = DateTime.now();
//
//   // Summary Counters
//   int _presentCount = 0;
//   int _absentCount = 0;
//   int _lateCount = 0;
//   int _holidayCount = 0;
//   int _halfdayCount = 0;
//   int _sundayCount = 0;
//
//   List<Map<String, dynamic>> _dailyRecords = [];
//
//   @override
//   void initState() {
//     super.initState();
//     _fetchReport();
//   }
//
//   void _fetchReport() async {
//     if (!mounted) return;
//     setState(() => _isLoading = true);
//     String monthStr = DateFormat('yyyy-MM').format(_selectedDate);
//
//     try {
//       var response = await _apiService.getMonthlyReport(
//           widget.employeeId, monthStr, widget.locationId, widget.departmentId);
//
//       if (response != null) {
//         List<dynamic> attendanceList = [];
//         Map<String, dynamic> backTotals = {};
//         Map<String, dynamic> monthSumm = response['monthSummary'] ?? {};
//         print("---------------------------monthly summary: $response['totals']");
//         if (response['data'] != null && response['data'] is List && response['data'].isNotEmpty) {
//           print("---------------------------monthly summary: $monthSumm");
//           var empData = response['data'][0];
//           attendanceList = empData['attendance'] ?? [];
//           backTotals = empData['totals'] ?? {};
//         } else if (response['attendance'] != null) {
//           attendanceList = response['attendance'];
//           backTotals = response['totals'] ?? {};
//         }
//
//         List<Map<String, dynamic>> tempList = [];
//         DateTime now = DateTime.now();
//         DateTime todayMidnight = DateTime(now.year, now.month, now.day);
//
//         for (var dayRecord in attendanceList) {
//           int day = dayRecord['day'] ?? 1;
//           Map<String, dynamic> innerData = dayRecord['data'] ?? {};
//
//           int status = innerData['status'] ?? 2;
//           String? inTime = innerData['checkInTime'] ?? innerData['punchIn'];
//           String? outTime = innerData['checkOutTime'] ?? innerData['punchOut'];
//           String note = dayRecord['note'] ?? "";
//           var holidayName = dayRecord['holiday'];
//           String workDuration = innerData['workingHours'] ?? innerData['duration'] ?? innerData['workTime'] ?? "";
//           // 🔴 LATE LOGIC
//           bool isLate = innerData['isLate'] == true;
//
//           DateTime recordDate = DateTime(_selectedDate.year, _selectedDate.month, day);
//           String uiStatus = "A";
//           String uiText = "Absent";
//
//           if (holidayName != null) {
//             uiStatus = "H"; uiText = holidayName.toString();
//           } else if (note == "Sunday") {
//             uiStatus = "S"; uiText = "Sunday";
//           } else if (note == "NotJoined") {
//             uiStatus = "NJ"; uiText = "Not Joined";
//           } else if (note == "Future" || recordDate.isAfter(todayMidnight)) {
//             uiStatus = "F"; uiText = "-";
//           } else {
//             if (status == 1) { uiStatus = "P"; uiText = "Present"; }
//             else if (status == 2) { uiStatus = "A"; uiText = "Absent"; }
//             else if (status == 3) { uiStatus = "L"; uiText = "Late"; }
//             else if (status == 4) { uiStatus = "HD"; uiText = "Half Day"; }
//             else if (status == 5) { uiStatus = "E"; uiText = "Excused"; }
//             else { uiStatus = "A"; uiText = "Absent"; }
//           }
//
//           tempList.add({
//             "dayNum": day.toString(),
//             "dayName": DateFormat('EEE').format(recordDate),
//             "uiStatus": uiStatus,
//             "uiText": uiText,
//             "inTime": inTime ?? "",
//             "outTime": outTime ?? "",
//             "isLate": isLate, // 🔴 Saved in list
//             "status": status,
//             "workDuration": workDuration
//           });
//         }
//
//         if (mounted) {
//           setState(() {
//             _presentCount = (backTotals['present'] ?? 0).toInt();
//             _absentCount = (backTotals['absent'] ?? 0).toInt();
//             _lateCount = (backTotals['late'] ?? 0).toInt();
//             _halfdayCount = (backTotals['halfDays'] ?? 0).toInt();
//             _holidayCount = (monthSumm['totalHolidays'] ?? 0).toInt();
//             _sundayCount = (monthSumm['totalSundays'] ?? 0).toInt();
//             _dailyRecords = tempList;
//             _isLoading = false;
//           });
//         }
//       }
//     } catch (e) {
//       if (mounted) setState(() => _isLoading = false);
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
//           Container(
//             padding: const EdgeInsets.fromLTRB(20, 50, 20, 25),
//             decoration: const BoxDecoration(
//               gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)]),
//               borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
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
//                     Expanded(child: Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
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
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceAround,
//                   children: [
//                     _buildStatCol("Present", _presentCount),
//                     _buildStatCol("Late", _lateCount),
//                     _buildStatCol("Half Day", _halfdayCount),
//                     _buildStatCol("Absent", _absentCount),
//                     _buildStatCol("Sundays", _sundayCount),
//                     _buildStatCol("Holidays", _holidayCount),
//                   ],
//                 )
//               ],
//             ),
//           ),
//
//           Expanded(
//             child: _isLoading
//                 ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
//                 : _dailyRecords.isEmpty
//                 ? _buildEmptyState()
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
//   Widget _buildStatCol(String label, int val) => Column(children: [
//     Text(val.toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
//     Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10))
//   ]);
//
//   Widget _buildRecordCard(Map<String, dynamic> item) {
//     String statusKey = item['uiStatus'];
//     bool isLate = item['isLate'] ?? false;
//     int status = item['status'] ?? 2;
//     String workTime = item['workDuration'] ?? "";
//
//     // 🎨 Color & Icon Logic
//     Color statusColor;
//     Color bgColor;
//     IconData statusIcon;
//
//     switch (statusKey) {
//       case "P":
//         statusColor = const Color(0xFF00C853); // Green
//         bgColor = const Color(0xFFE8F5E9);
//         statusIcon = Icons.check_circle_outline;
//         break;
//       case "L":
//         statusColor = const Color(0xFFFF9800); // Orange
//         bgColor = const Color(0xFFFFF3E0);
//         statusIcon = Icons.access_time;
//         break;
//       case "HD":
//         statusColor = const Color(0xFF673AB7); // Purple
//         bgColor = const Color(0xFFEDE7F6);
//         statusIcon = Icons.star_half;
//         break;
//       case "S":
//         statusColor = const Color(0xFF607D8B); // Blue Grey
//         bgColor = const Color(0xFFECEFF1);
//         statusIcon = Icons.weekend;
//         break;
//       case "H":
//         statusColor = const Color(0xFFFFD600); // Amber
//         bgColor = const Color(0xFFFFFDE7);
//         statusIcon = Icons.celebration;
//         break;
//       case "NJ":
//         statusColor = Colors.grey;
//         bgColor = const Color(0xFFFAFAFA);
//         statusIcon = Icons.person_off;
//         break;
//       case "A":
//         statusColor = const Color(0xFFD32F2F); // Red
//         bgColor = const Color(0xFFFFEBEE);
//         statusIcon = Icons.cancel_outlined;
//         break;
//       default:
//         statusColor = Colors.grey.shade400;
//         bgColor = const Color(0xFFF5F5F5);
//         statusIcon = Icons.hourglass_empty;
//     }
//
//     String inT = item['inTime'];
//     String outT = item['outTime'];
//     bool hasTime = inT.isNotEmpty && inT != "--:--";
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.06),
//             blurRadius: 10,
//             offset: const Offset(0, 4),
//           )
//         ],
//       ),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(16),
//         child: IntrinsicHeight(
//           child: Row(
//             children: [
//               // 🔴 1. LEFT SIDE: DATE BOX (Colored)
//               Container(
//                 width: 70,
//                 decoration: BoxDecoration(
//                     color: bgColor,
//                     border: Border(right: BorderSide(color: statusColor.withOpacity(0.3), width: 1))
//                 ),
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Text(
//                       item['dayNum'],
//                       style: TextStyle(
//                         fontSize: 22,
//                         fontWeight: FontWeight.bold,
//                         color: statusColor,
//                       ),
//                     ),
//                     Text(
//                       item['dayName'].toUpperCase(),
//                       style: TextStyle(
//                         fontSize: 12,
//                         fontWeight: FontWeight.bold,
//                         color: statusColor.withOpacity(0.8),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//
//               // 🔴 2. RIGHT SIDE: DETAILS
//               Expanded(
//                 child: Padding(
//                   padding: const EdgeInsets.all(12),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       // --- Top Row: Status Badge & Late Tag ---
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Container(
//                             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                             decoration: BoxDecoration(
//                               color: statusColor.withOpacity(0.1),
//                               borderRadius: BorderRadius.circular(8),
//                             ),
//                             child: Row(
//                               children: [
//                                 Icon(statusIcon, size: 14, color: statusColor),
//                                 const SizedBox(width: 4),
//                                 Text(
//                                   item['uiText'],
//                                   style: TextStyle(
//                                     color: statusColor,
//                                     fontSize: 12,
//                                     fontWeight: FontWeight.bold,
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),
//
//                           // LATE BADGE
//                           if (isLate && status != 3)
//                             Container(
//                               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                               decoration: BoxDecoration(
//                                 color: Colors.red.shade50,
//                                 borderRadius: BorderRadius.circular(8),
//                                 border: Border.all(color: Colors.red.shade100),
//                               ),
//                               child: const Text(
//                                 "LATE",
//                                 style: TextStyle(
//                                   color: Colors.red,
//                                   fontSize: 10,
//                                   fontWeight: FontWeight.bold,
//                                 ),
//                               ),
//                             ),
//                         ],
//                       ),
//
//                       const SizedBox(height: 10),
//
//                       // --- Middle: Timings (Only if Present) ---
//                       if (hasTime) ...[
//                         Row(
//                           children: [
//                             // IN TIME
//                             _buildTimeInfo(Icons.login_rounded, "In", _formatTime(inT), Colors.green),
//
//                             // Vertical Divider
//                             Container(height: 25, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 15)),
//
//                             // OUT TIME
//                             _buildTimeInfo(Icons.logout_rounded, "Out", outT.isEmpty ? "Active" : _formatTime(outT), outT.isEmpty ? Colors.blue : Colors.redAccent),
//                           ],
//                         ),
//                       ] else ...[
//                         // Agar absent hai to message
//                         Text(
//                           statusKey == "S" || statusKey == "H" ? "Enjoy your holiday!" : "No punch records found.",
//                           style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
//                         )
//                       ],
//
//                       // --- Bottom: Work Duration ---
//                       if (workTime.isNotEmpty && workTime != "0") ...[
//                         const SizedBox(height: 10),
//                         Container(
//                           width: double.infinity,
//                           padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
//                           decoration: BoxDecoration(
//                             color: Colors.grey.shade50,
//                             borderRadius: BorderRadius.circular(6),
//                           ),
//                           child: Row(
//                             children: [
//                               const Icon(Icons.timer_outlined, size: 14, color: Colors.blueGrey),
//                               const SizedBox(width: 6),
//                               Text(
//                                 "Total Work: ",
//                                 style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
//                               ),
//                               Text(
//                                 "$workTime Hrs",
//                                 style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ]
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   // Helper Widget for Time Row
//   Widget _buildTimeInfo(IconData icon, String label, String time, Color color) {
//     return Row(
//       children: [
//         Icon(icon, size: 16, color: color.withOpacity(0.7)),
//         const SizedBox(width: 6),
//         Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
//             Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
//           ],
//         ),
//       ],
//     );
//   }
//
//   String _formatTime(String t) {
//     if (t.isEmpty || t == "--:--") return "--:--";
//     try {
//       DateTime dt = t.contains("T") ? DateTime.parse(t).toLocal() : DateFormat("HH:mm").parse(t);
//       return DateFormat("hh:mm a").format(dt);
//     } catch (_) { return t; }
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
