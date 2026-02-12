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

  // Summary Counters
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

      if (response != null) {
        List<dynamic> attendanceList = [];
        Map<String, dynamic> backTotals = {};
        Map<String, dynamic> monthSumm = response['monthSummary'] ?? {};
        print("---------------------------monthly summary: $response['totals']");
        if (response['data'] != null && response['data'] is List && response['data'].isNotEmpty) {
          print("---------------------------monthly summary: $monthSumm");
          var empData = response['data'][0];
          attendanceList = empData['attendance'] ?? [];
          backTotals = empData['totals'] ?? {};
        } else if (response['attendance'] != null) {
          attendanceList = response['attendance'];
          backTotals = response['totals'] ?? {};
        }

        List<Map<String, dynamic>> tempList = [];
        DateTime now = DateTime.now();
        DateTime todayMidnight = DateTime(now.year, now.month, now.day);

        for (var dayRecord in attendanceList) {
          int day = dayRecord['day'] ?? 1;
          Map<String, dynamic> innerData = dayRecord['data'] ?? {};

          int status = innerData['status'] ?? 2;
          String? inTime = innerData['checkInTime'] ?? innerData['punchIn'];
          String? outTime = innerData['checkOutTime'] ?? innerData['punchOut'];
          String note = dayRecord['note'] ?? "";
          var holidayName = dayRecord['holiday'];

          // 🔴 LATE LOGIC
          bool isLate = innerData['isLate'] == true;

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
            "isLate": isLate, // 🔴 Saved in list
          });
        }

        if (mounted) {
          setState(() {
            _presentCount = (backTotals['present'] ?? 0).toInt();
            _absentCount = (backTotals['absent'] ?? 0).toInt();
            _lateCount = (backTotals['late'] ?? 0).toInt();
            _halfdayCount = (backTotals['halfDays'] ?? 0).toInt();
            _holidayCount = (monthSumm['totalHolidays'] ?? 0).toInt();
            _sundayCount = (monthSumm['totalSundays'] ?? 0).toInt();
            _dailyRecords = tempList;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
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
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 25),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)]),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
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
                    Expanded(child: Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCol("Present", _presentCount),
                    _buildStatCol("Late", _lateCount),
                    _buildStatCol("Half Day", _halfdayCount),
                    _buildStatCol("Absent", _absentCount),
                    _buildStatCol("Sundays", _sundayCount),
                    _buildStatCol("Holidays", _holidayCount),
                  ],
                )
              ],
            ),
          ),

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

  Widget _buildStatCol(String label, int val) => Column(children: [
    Text(val.toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10))
  ]);

  Widget _buildRecordCard(Map<String, dynamic> item) {
    String statusKey = item['uiStatus'];
    bool isLate = item['isLate'] ?? false; // 🔴 Fetch Late status
    Color statusColor;
    IconData statusIcon;

    switch (statusKey) {
      case "P": statusColor = Colors.green; statusIcon = Icons.check_circle; break;
      case "L": statusColor = Colors.orange; statusIcon = Icons.access_time_filled; break;
      case "HD": statusColor = Colors.purple; statusIcon = Icons.star_half; break;
      case "S": statusColor = Colors.blueGrey; statusIcon = Icons.wb_sunny; break;
      case "H": statusColor = Colors.amber; statusIcon = Icons.star; break;
      case "NJ": statusColor = Colors.grey; statusIcon = Icons.person_add_disabled; break;
      case "A": statusColor = Colors.redAccent; statusIcon = Icons.cancel; break;
      default: statusColor = Colors.grey.shade300; statusIcon = Icons.hourglass_empty;
    }

    String inT = item['inTime'];
    String outT = item['outTime'];
    bool hasTime = inT.isNotEmpty && inT != "--:--";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 6, decoration: BoxDecoration(color: statusColor, borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Column(children: [
                      Text(item['dayNum'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(item['dayName'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                    const SizedBox(width: 20),
                    Container(width: 1, height: 30, color: Colors.grey.shade200),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(children: [
                            Icon(statusIcon, size: 16, color: statusColor),
                            const SizedBox(width: 5),
                            Text(item['uiText'], style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(width: 8),

                            // 🔴 LATE TAG
                            if (isLate)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade200)),
                                child: const Text("LATE", style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                          ]),
                          if (hasTime)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text("${_formatTime(inT)} - ${outT.isEmpty ? 'Active' : _formatTime(outT)}", style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
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
//     required this.departmentId
//   });
//
//   @override
//   State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
// }
//
// class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
//   final ApiService _apiService = ApiService();
//
//   bool _isLoading = true;
//   DateTime _selectedDate = DateTime.now();
//
//   // Summary Counters
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
//     _fetchReport();
//   }
//
//   void _fetchReport() async {
//     setState(() => _isLoading = true);
//
//     String monthStr = DateFormat('yyyy-MM').format(_selectedDate);
//
//     try {
//       var response = await _apiService.getMonthlyReport(
//           widget.employeeId,
//           monthStr,
//           widget.locationId,
//           widget.departmentId
//       );
//
//       List<dynamic> attendanceList = [];
//
//       if (response != null) {
//         if (response['data'] is List && response['data'].isNotEmpty) {
//           attendanceList = response['data'][0]['attendance'] ?? [];
//         } else if (response['attendance'] != null) {
//           attendanceList = response['attendance'];
//         }
//       }
//
//       if (attendanceList.isNotEmpty) {
//         List<Map<String, dynamic>> tempList = [];
//         int p = 0, a = 0, h = 0, s = 0;
//         DateTime now = DateTime.now();
//         DateTime todayMidnight = DateTime(now.year, now.month, now.day);
//
//         for (var dayRecord in attendanceList) {
//           int day = dayRecord['day'] ?? 1;
//           Map<String, dynamic> innerData = dayRecord['data'] ?? {};
//
//           String? note = dayRecord['note'];
//           String? holidayName = dayRecord['holiday'];
//
//           DateTime recordDate = DateTime(_selectedDate.year, _selectedDate.month, day);
//           String dateString = DateFormat('yyyy-MM-dd').format(recordDate);
//
//           String? inTimeRaw = innerData['checkInTime'] ?? innerData['punchIn'];
//           String? outTimeRaw = innerData['checkOutTime'] ?? innerData['punchOut'];
//           bool isLate = innerData['isLate'] == true;
//
//           String statusType = "A";
//           String displayStatus = "Absent";
//           bool isFuture = recordDate.isAfter(todayMidnight);
//
//           // 🧠 STATUS LOGIC
//           if (inTimeRaw != null && inTimeRaw.isNotEmpty) {
//             statusType = "P";
//             displayStatus = "Present";
//             p++;
//           }
//           else if (holidayName != null && holidayName.isNotEmpty) {
//             statusType = "H";
//             displayStatus = holidayName;
//             h++;
//           }
//           else if (note == "Sunday") {
//             statusType = "S";
//             displayStatus = "Sunday";
//             s++;
//           }
//           else if (note == "NotJoined") {
//             statusType = "NJ";
//             displayStatus = "Not Joined";
//           }
//           else if (isFuture) {
//             statusType = "NA";
//             displayStatus = "-";
//           }
//           else {
//             statusType = "A";
//             displayStatus = "Absent";
//             a++;
//           }
//
//           // 🔴 DIRECT BACKEND FETCH (No Manual Calculation)
//           // Backend keys check kar rahe hain: workingHours, duration, ya workTime
//           String workDuration = innerData['workingHours'] ?? innerData['duration'] ?? innerData['workTime'] ?? "";
//
//           tempList.add({
//             "date": dateString,
//             "dayNum": day.toString(),
//             "dayName": DateFormat('EEE').format(recordDate),
//             "statusType": statusType,
//             "displayStatus": displayStatus,
//             "inTime": inTimeRaw ?? "",
//             "outTime": outTimeRaw ?? "",
//             "workDuration": workDuration, // ✅ Seedha Backend se
//             "isToday": day == now.day && _selectedDate.month == now.month && _selectedDate.year == now.year,
//             "isLate": isLate,
//           });
//         }
//
//         if (mounted) {
//           setState(() {
//             _dailyRecords = tempList;
//             _presentCount = p;
//             _absentCount = a;
//             _holidayCount = h;
//             _sundayCount = s;
//             _isLoading = false;
//           });
//         }
//       } else {
//         if (mounted) setState(() { _dailyRecords = []; _isLoading = false; });
//       }
//     } catch (e) {
//       debugPrint("Report Error: $e");
//       if (mounted) setState(() { _dailyRecords = []; _isLoading = false; });
//     }
//   }
//
//   void _changeMonth(int monthsToAdd) {
//     setState(() {
//       _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + monthsToAdd);
//     });
//     _fetchReport();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF5F7FA),
//       body: Column(
//         children: [
//           // HEADER
//           Container(
//             padding: const EdgeInsets.only(top: 50, bottom: 25, left: 20, right: 20),
//             decoration: const BoxDecoration(
//                 gradient: LinearGradient(
//                   colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
//                   begin: Alignment.topLeft,
//                   end: Alignment.bottomRight,
//                 ),
//                 borderRadius: BorderRadius.only(
//                   bottomLeft: Radius.circular(30),
//                   bottomRight: Radius.circular(30),
//                 ),
//                 boxShadow: [
//                   BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
//                 ]
//             ),
//             child: Column(
//               children: [
//                 Row(
//                   children: [
//                     InkWell(
//                       onTap: () => Navigator.pop(context),
//                       child: Container(
//                         padding: const EdgeInsets.all(8),
//                         decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
//                         child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
//                       ),
//                     ),
//                     const SizedBox(width: 15),
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
//                         const Text("Monthly Report", style: TextStyle(color: Colors.white70, fontSize: 12)),
//                       ],
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 20),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30)),
//                     Text(DateFormat('MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
//                     IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right, color: Colors.white, size: 30)),
//                   ],
//                 ),
//                 const SizedBox(height: 10),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                   children: [
//                     _buildHeaderStat("Present", _presentCount.toString()),
//                     Container(height: 25, width: 1, color: Colors.white24),
//                     _buildHeaderStat("Absent", _absentCount.toString()),
//                     Container(height: 25, width: 1, color: Colors.white24),
//                     _buildHeaderStat("Holidays", _holidayCount.toString()),
//                     Container(height: 25, width: 1, color: Colors.white24),
//                     _buildHeaderStat("Sunday", _sundayCount.toString()),
//                   ],
//                 )
//               ],
//             ),
//           ),
//
//           // LIST
//           Expanded(
//             child: _isLoading
//                 ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
//                 : _dailyRecords.isEmpty
//                 ? _buildEmptyState()
//                 : ListView.builder(
//               padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
//               itemCount: _dailyRecords.length,
//               itemBuilder: (context, index) => _buildModernCard(_dailyRecords[index]),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildHeaderStat(String label, String count) {
//     return Column(
//       children: [
//         Text(count, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
//         Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
//       ],
//     );
//   }
//
//   Widget _buildModernCard(Map<String, dynamic> item) {
//     String type = item['statusType']; // P, A, H, S, NJ, NA
//     bool isToday = item['isToday'];
//
//     Color statusColor = _getStatusColor(type);
//     IconData statusIcon = _getStatusIcon(type);
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: isToday ? Border.all(color: Colors.blueAccent, width: 1.5) : null,
//         boxShadow: [
//           BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))
//         ],
//       ),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(12),
//         child: IntrinsicHeight(
//           child: Row(
//             children: [
//               // Left Strip
//               Container(width: 5, color: statusColor),
//
//               Expanded(
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
//                   child: Row(
//                     children: [
//                       // Date Box
//                       Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           Text(item['dayNum'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF2E3192))),
//                           Text(item['dayName'].toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
//                         ],
//                       ),
//
//                       const SizedBox(width: 20),
//                       Container(width: 1, height: 35, color: Colors.grey.shade200),
//                       const SizedBox(width: 20),
//
//                       // Content Area
//                       Expanded(
//                         child: type == "P"
//                             ? _buildPresentDetails(item)
//                             : _buildStatusDetails(item['displayStatus'], statusColor, statusIcon),
//                       ),
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
//   Color _getStatusColor(String type) {
//     switch (type) {
//       case "P": return const Color(0xFF00C853);
//       case "A": return const Color(0xFFE53935);
//       case "H": return const Color(0xFF9C27B0);
//       case "S": return const Color(0xFFFF9800);
//       case "NJ": return Colors.grey;
//       default: return Colors.grey.shade300;
//     }
//   }
//
//   IconData _getStatusIcon(String type) {
//     switch (type) {
//       case "P": return Icons.check_circle_outline;
//       case "A": return Icons.cancel_outlined;
//       case "H": return Icons.celebration;
//       case "S": return Icons.weekend;
//       case "NJ": return Icons.person_off_outlined;
//       default: return Icons.hourglass_empty_rounded;
//     }
//   }
//
//   Widget _buildPresentDetails(Map<String, dynamic> item) {
//     bool isLate = item['isLate'];
//     String workTime = item['workDuration'];
//
//     return Row(
//       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//       children: [
//         Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             _buildTimeRow("In", item['inTime']),
//             const SizedBox(height: 4),
//             _buildTimeRow("Out", item['outTime']),
//           ],
//         ),
//         Column(
//           crossAxisAlignment: CrossAxisAlignment.end,
//           children: [
//             const Text("Present", style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold)),
//
//             if(isLate)
//               Container(
//                 margin: const EdgeInsets.only(top: 4, bottom: 2),
//                 padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                 decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4)),
//                 child: const Text("LATE", style: TextStyle(color: Color(0xFFD32F2F), fontSize: 9, fontWeight: FontWeight.bold)),
//               ),
//
//             // 🔴 WORK TIME (Below Late Tag)
//             if(workTime.isNotEmpty && workTime != "0")
//               Padding(
//                 padding: const EdgeInsets.only(top: 4),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     const Icon(Icons.timer_outlined, size: 12, color: Colors.blueGrey),
//                     const SizedBox(width: 3),
//                     Text(workTime, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.blueGrey)),
//                   ],
//                 ),
//               )
//           ],
//         )
//       ],
//     );
//   }
//
//   Widget _buildStatusDetails(String text, Color color, IconData icon) {
//     return Row(
//       children: [
//         Icon(icon, color: color, size: 22),
//         const SizedBox(width: 12),
//         Flexible(
//           child: Text(
//             text,
//             style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
//             overflow: TextOverflow.ellipsis,
//           ),
//         ),
//       ],
//     );
//   }
//
//   Widget _buildTimeRow(String label, String time) {
//     String displayTime = time;
//     if(time != "--:--") {
//       try { displayTime = DateFormat("hh:mm a").format(DateFormat("HH:mm").parse(time)); } catch(_) {}
//     }
//     return Row(
//       children: [
//         SizedBox(width: 25, child: Text("$label:", style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
//         Text(displayTime, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF263238))),
//       ],
//     );
//   }
//
//   Widget _buildEmptyState() {
//     return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_view_day_rounded, size: 50, color: Colors.grey.shade300), const SizedBox(height: 10), Text("No records found", style: TextStyle(color: Colors.grey.shade500))]));
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
// // import '../../services/api_service.dart';
// //
// // class AttendanceHistoryScreen extends StatefulWidget {
// //   final String employeeName;
// //   final String employeeId;
// //   final String locationId;
// //   final String departmentId;
// //
// //   const AttendanceHistoryScreen({
// //     super.key,
// //     required this.employeeName,
// //     required this.employeeId,
// //     required this.locationId,
// //     required this.departmentId
// //   });
// //
// //   @override
// //   State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
// // }
// //
// // class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
// //   final ApiService _apiService = ApiService();
// //
// //   bool _isLoading = true;
// //   DateTime _selectedDate = DateTime.now();
// //
// //   // Summary Counters
// //   int _presentCount = 0;
// //   int _absentCount = 0;
// //   int _holidayCount = 0; // Includes Sundays + Specific Holidays
// //   int _sundayCount = 0; // Includes Sundays + Specific Holidays
// //
// //   List<Map<String, dynamic>> _dailyRecords = [];
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _fetchReport();
// //   }
// //
// //   void _fetchReport() async {
// //     setState(() => _isLoading = true);
// //
// //     String monthStr = DateFormat('yyyy-MM').format(_selectedDate);
// //
// //     var response = await _apiService.getMonthlyReport(
// //         widget.employeeId,
// //         monthStr,
// //         widget.locationId,
// //         widget.departmentId
// //     );
// //
// //     List<dynamic> attendanceList = [];
// //
// //     // Data Extraction Logic
// //     if (response != null) {
// //       if (response['data'] is List && response['data'].isNotEmpty) {
// //         attendanceList = response['data'][0]['attendance'] ?? [];
// //       } else if (response['attendance'] != null) {
// //         attendanceList = response['attendance'];
// //       }
// //     }
// //
// //     if (attendanceList.isNotEmpty) {
// //       List<Map<String, dynamic>> tempList = [];
// //       int p = 0, a = 0, h = 0, s=0;
// //       DateTime now = DateTime.now();
// //       DateTime todayMidnight = DateTime(now.year, now.month, now.day);
// //
// //       for (var dayRecord in attendanceList) {
// //         int day = dayRecord['day'] ?? 1;
// //         Map<String, dynamic> innerData = dayRecord['data'] ?? {};
// //
// //         // 🔴 BACKEND FIELDS (As it is extraction)
// //         String? note = dayRecord['note'];       // "Sunday", "NotJoined"
// //         String? holidayName = dayRecord['holiday']; // "Diwali", "Holi", "h2"
// //
// //         DateTime recordDate = DateTime(_selectedDate.year, _selectedDate.month, day);
// //         String dateString = DateFormat('yyyy-MM-dd').format(recordDate);
// //
// //         String? inTimeRaw = innerData['checkInTime'] ?? innerData['punchIn'];
// //         String? outTimeRaw = innerData['checkOutTime'] ?? innerData['punchOut'];
// //         bool isLate = innerData['isLate'] == true;
// //
// //         String statusType = "A"; // Default Absent
// //         String displayStatus = "Absent";
// //         bool isFuture = recordDate.isAfter(todayMidnight);
// //
// //         // 🔥 MAIN LOGIC: Priority-wise checking
// //         if (inTimeRaw != null && inTimeRaw.isNotEmpty) {
// //           // 1. Agar Punch In hai = PRESENT
// //           statusType = "P";
// //           displayStatus = "Present";
// //           p++;
// //         }
// //         else if (holidayName != null && holidayName.isNotEmpty) {
// //           // 2. Agar Holiday field hai = HOLIDAY
// //           statusType = "H";
// //           displayStatus = holidayName; // Backend ka naam (e.g., Diwali)
// //           h++;
// //         }
// //         else if (note == "Sunday") {
// //           // 3. Agar Note Sunday hai = SUNDAY
// //           statusType = "S";
// //           displayStatus = "Sunday";
// //           s++; // Sunday ko bhi holiday count me jod rahe hain header ke liye
// //         }
// //         else if (note == "NotJoined") {
// //           // 4. Not Joined
// //           statusType = "NJ";
// //           displayStatus = "Not Joined";
// //         }
// //         else if (isFuture) {
// //           // 5. Future Date
// //           statusType = "NA";
// //           displayStatus = "-";
// //         }
// //         else {
// //           // 6. Kuch nahi mila = ABSENT
// //           statusType = "A";
// //           displayStatus = "Absent";
// //           a++;
// //         }
// //
// //         // Work Duration Calculation
// //         String workDuration = "";
// //         if (inTimeRaw != null && outTimeRaw != null) {
// //           try {
// //             DateTime inT = DateFormat("HH:mm").parse(inTimeRaw);
// //             DateTime outT = DateFormat("HH:mm").parse(outTimeRaw);
// //             Duration diff = outT.difference(inT);
// //             if (diff.isNegative) diff = diff + const Duration(hours: 24);
// //             int hrs = diff.inHours;
// //             int mins = diff.inMinutes % 60;
// //             workDuration = "${hrs}h ${mins}m";
// //           } catch (_) {}
// //         }
// //
// //         tempList.add({
// //           "date": dateString,
// //           "dayNum": day.toString(),
// //           "dayName": DateFormat('EEE').format(recordDate),
// //           "statusType": statusType,
// //           "displayStatus": displayStatus,
// //           "inTime": inTimeRaw ?? "",
// //           "outTime": outTimeRaw ?? "",
// //           "workDuration": workDuration,
// //           "isToday": day == now.day && _selectedDate.month == now.month && _selectedDate.year == now.year,
// //           "isLate": isLate,
// //         });
// //       }
// //
// //       if (mounted) {
// //         setState(() {
// //           _dailyRecords = tempList;
// //           _presentCount = p;
// //           _absentCount = a;
// //           _holidayCount = h;
// //           _sundayCount= s;
// //           _isLoading = false;
// //         });
// //       }
// //     } else {
// //       if (mounted) {
// //         setState(() {
// //           _dailyRecords = [];
// //           _isLoading = false;
// //         });
// //       }
// //     }
// //   }
// //
// //   void _changeMonth(int monthsToAdd) {
// //     setState(() {
// //       _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + monthsToAdd);
// //     });
// //     _fetchReport();
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
// //                 borderRadius: BorderRadius.only(
// //                   bottomLeft: Radius.circular(30),
// //                   bottomRight: Radius.circular(30),
// //                 ),
// //                 boxShadow: [
// //                   BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
// //                 ]
// //             ),
// //             child: Column(
// //               children: [
// //                 Row(
// //                   children: [
// //                     InkWell(
// //                       onTap: () => Navigator.pop(context),
// //                       child: Container(
// //                         padding: const EdgeInsets.all(8),
// //                         decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
// //                         child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
// //                       ),
// //                     ),
// //                     const SizedBox(width: 15),
// //                     Column(
// //                       crossAxisAlignment: CrossAxisAlignment.start,
// //                       children: [
// //                         Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
// //                         const Text("Monthly Report", style: TextStyle(color: Colors.white70, fontSize: 12)),
// //                       ],
// //                     ),
// //                   ],
// //                 ),
// //                 const SizedBox(height: 20),
// //                 Row(
// //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                   children: [
// //                     IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30)),
// //                     Text(DateFormat('MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
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
// //                     Container(height: 25, width: 1, color: Colors.white24),
// //                     _buildHeaderStat("Sunday", _sundayCount.toString()),
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
// //               padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
// //               itemCount: _dailyRecords.length,
// //               itemBuilder: (context, index) => _buildModernCard(_dailyRecords[index]),
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   Widget _buildHeaderStat(String label, String count) {
// //     return Column(
// //       children: [
// //         Text(count, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
// //         Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
// //       ],
// //     );
// //   }
// //
// //   Widget _buildModernCard(Map<String, dynamic> item) {
// //     String type = item['statusType']; // P, A, H, S, NJ, NA
// //     bool isToday = item['isToday'];
// //
// //     // 🔴 DYNAMIC COLOR & ICON FETCHING
// //     Color statusColor = _getStatusColor(type);
// //     IconData statusIcon = _getStatusIcon(type);
// //
// //     return Container(
// //       margin: const EdgeInsets.only(bottom: 12),
// //       decoration: BoxDecoration(
// //         color: Colors.white,
// //         borderRadius: BorderRadius.circular(12),
// //         border: isToday ? Border.all(color: Colors.blueAccent, width: 1.5) : null,
// //         boxShadow: [
// //           BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))
// //         ],
// //       ),
// //       child: ClipRRect(
// //         borderRadius: BorderRadius.circular(12),
// //         child: IntrinsicHeight(
// //           child: Row(
// //             children: [
// //               // Left Strip (Color Identifier)
// //               Container(width: 5, color: statusColor),
// //
// //               Expanded(
// //                 child: Padding(
// //                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
// //                   child: Row(
// //                     children: [
// //                       // Date Box
// //                       Column(
// //                         crossAxisAlignment: CrossAxisAlignment.start,
// //                         mainAxisAlignment: MainAxisAlignment.center,
// //                         children: [
// //                           Text(item['dayNum'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF2E3192))),
// //                           Text(item['dayName'].toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
// //                         ],
// //                       ),
// //
// //                       const SizedBox(width: 20),
// //                       Container(width: 1, height: 35, color: Colors.grey.shade200),
// //                       const SizedBox(width: 20),
// //
// //                       // Content Area
// //                       Expanded(
// //                         child: type == "P"
// //                             ? _buildPresentDetails(item)
// //                             : _buildStatusDetails(item['displayStatus'], statusColor, statusIcon),
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
// //   // 🔴 COLORS (Distinct for Sunday & Holiday)
// //   Color _getStatusColor(String type) {
// //     switch (type) {
// //       case "P": return const Color(0xFF00C853); // Green (Present)
// //       case "A": return const Color(0xFFE53935); // Red (Absent)
// //       case "H": return const Color(0xFF9C27B0); // Purple (Holiday - Diwali etc)
// //       case "S": return const Color(0xFFFF9800); // Orange (Sunday)
// //       case "NJ": return Colors.grey;            // Grey
// //       default: return Colors.grey.shade300;     // Future
// //     }
// //   }
// //
// //   // 🔴 ICONS (Distinct for Sunday & Holiday)
// //   IconData _getStatusIcon(String type) {
// //     switch (type) {
// //       case "P": return Icons.check_circle_outline;
// //       case "A": return Icons.cancel_outlined;
// //       case "H": return Icons.celebration; // Party Icon for Holiday
// //       case "S": return Icons.weekend;     // Sofa Icon for Sunday
// //       case "NJ": return Icons.person_off_outlined;
// //       default: return Icons.hourglass_empty_rounded;
// //     }
// //   }
// //
// //   Widget _buildPresentDetails(Map<String, dynamic> item) {
// //     bool isLate = item['isLate'];
// //     return Row(
// //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //       children: [
// //         Column(
// //           crossAxisAlignment: CrossAxisAlignment.start,
// //           mainAxisAlignment: MainAxisAlignment.center,
// //           children: [
// //             _buildTimeRow("In", item['inTime']),
// //             const SizedBox(height: 4),
// //             _buildTimeRow("Out", item['outTime']),
// //           ],
// //         ),
// //         Column(
// //           crossAxisAlignment: CrossAxisAlignment.end,
// //           children: [
// //             const Text("Present", style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold)),
// //             if(isLate)
// //               Container(
// //                 margin: const EdgeInsets.only(top: 4),
// //                 padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
// //                 decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4)),
// //                 child: const Text("LATE", style: TextStyle(color: Color(0xFFD32F2F), fontSize: 9, fontWeight: FontWeight.bold)),
// //               ),
// //           ],
// //         )
// //       ],
// //     );
// //   }
// //
// //   Widget _buildStatusDetails(String text, Color color, IconData icon) {
// //     return Row(
// //       children: [
// //         Icon(icon, color: color, size: 22),
// //         const SizedBox(width: 12),
// //         Flexible(
// //           child: Text(
// //             text,
// //             style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
// //             overflow: TextOverflow.ellipsis,
// //           ),
// //         ),
// //       ],
// //     );
// //   }
// //
// //   Widget _buildTimeRow(String label, String time) {
// //     String displayTime = time;
// //     if(time != "--:--") {
// //       try { displayTime = DateFormat("hh:mm a").format(DateFormat("HH:mm").parse(time)); } catch(_) {}
// //     }
// //     return Row(
// //       children: [
// //         SizedBox(width: 25, child: Text("$label:", style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
// //         Text(displayTime, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF263238))),
// //       ],
// //     );
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
// //
// //
// //
// //
// // // import 'package:flutter/material.dart';
// // // import 'package:intl/intl.dart';
// // // import '../../services/api_service.dart';
// // //
// // // class AttendanceHistoryScreen extends StatefulWidget {
// // //   final String employeeName;
// // //   final String employeeId;
// // //   final String locationId;
// // //   final String departmentId;
// // //
// // //   const AttendanceHistoryScreen({
// // //     super.key,
// // //     required this.employeeName,
// // //     required this.employeeId,
// // //     required this.locationId,
// // //     required this.departmentId
// // //   });
// // //
// // //   @override
// // //   State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
// // // }
// // //
// // // class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
// // //   final ApiService _apiService = ApiService();
// // //
// // //   bool _isLoading = true;
// // //   DateTime _selectedDate = DateTime.now();
// // //
// // //   // Summary Counters
// // //   int _presentCount = 0;
// // //   int _absentCount = 0;
// // //   int _holidayCount = 0;
// // //
// // //   List<Map<String, dynamic>> _dailyRecords = [];
// // //
// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     _fetchReport();
// // //   }
// // //
// // //   void _fetchReport() async {
// // //     setState(() => _isLoading = true);
// // //
// // //     String monthStr = DateFormat('yyyy-MM').format(_selectedDate);
// // //
// // //     var response = await _apiService.getMonthlyReport(
// // //         widget.employeeId,
// // //         monthStr,
// // //         widget.locationId,
// // //         widget.departmentId
// // //     );
// // //
// // //     // 🔴 DATA PARSING LOGIC BASED ON YOUR LOGS
// // //     List<dynamic> attendanceList = [];
// // //
// // //     // Check structure based on logs: data -> [0] -> attendance
// // //     if (response != null) {
// // //       if (response['data'] is List && response['data'].isNotEmpty) {
// // //         attendanceList = response['data'][0]['attendance'] ?? [];
// // //       } else if (response['attendance'] != null) {
// // //         attendanceList = response['attendance'];
// // //       }
// // //     }
// // //
// // //     if (attendanceList.isNotEmpty) {
// // //       List<Map<String, dynamic>> tempList = [];
// // //       int p = 0, a = 0, h = 0;
// // //       DateTime now = DateTime.now();
// // //       DateTime todayMidnight = DateTime(now.year, now.month, now.day);
// // //
// // //       for (var dayRecord in attendanceList) {
// // //         int day = dayRecord['day'] ?? 1;
// // //         Map<String, dynamic> innerData = dayRecord['data'] ?? {};
// // //
// // //         // 🔴 BACKEND FIELDS
// // //         String? note = dayRecord['note'];     // e.g. "Sunday", "NotJoined"
// // //         String? holiday = dayRecord['holiday']; // e.g. "h2", "Diwali"
// // //
// // //         DateTime recordDate = DateTime(_selectedDate.year, _selectedDate.month, day);
// // //         String dateString = DateFormat('yyyy-MM-dd').format(recordDate);
// // //
// // //         String? inTimeRaw = innerData['checkInTime'] ?? innerData['punchIn'];
// // //         String? outTimeRaw = innerData['checkOutTime'] ?? innerData['punchOut'];
// // //         bool isLate = innerData['isLate'] == true;
// // //
// // //         String statusType = "A"; // P, A, H, S, NJ (Not Joined), NA (Future)
// // //         String displayStatus = "Absent";
// // //         bool isFuture = recordDate.isAfter(todayMidnight);
// // //
// // //         // 🧠 LOGIC TO DETERMINE STATUS
// // //         if (inTimeRaw != null && inTimeRaw.isNotEmpty) {
// // //           statusType = "P";
// // //           displayStatus = "Present";
// // //           p++;
// // //         } else if (holiday != null && holiday.isNotEmpty) {
// // //           statusType = "H";
// // //           displayStatus = holiday; // Show Backend Holiday Name
// // //           h++;
// // //         } else if (note == "Sunday") {
// // //           statusType = "S";
// // //           displayStatus = "Sunday";
// // //           h++; // Counting Sunday as holiday type for stats
// // //         } else if (note == "NotJoined") {
// // //           statusType = "NJ";
// // //           displayStatus = "Not Joined";
// // //         } else if (isFuture) {
// // //           statusType = "NA";
// // //           displayStatus = "-";
// // //         } else {
// // //           statusType = "A";
// // //           displayStatus = "Absent";
// // //           a++;
// // //         }
// // //
// // //         // Duration Calculation
// // //         String workDuration = "";
// // //         if (inTimeRaw != null && outTimeRaw != null) {
// // //           try {
// // //             DateTime inT = DateFormat("HH:mm").parse(inTimeRaw);
// // //             DateTime outT = DateFormat("HH:mm").parse(outTimeRaw);
// // //             Duration diff = outT.difference(inT);
// // //             if (diff.isNegative) diff = diff + const Duration(hours: 24);
// // //             int hrs = diff.inHours;
// // //             int mins = diff.inMinutes % 60;
// // //             workDuration = "${hrs}h ${mins}m";
// // //           } catch (_) {}
// // //         }
// // //
// // //         tempList.add({
// // //           "date": dateString,
// // //           "dayNum": day.toString(),
// // //           "dayName": DateFormat('EEE').format(recordDate),
// // //
// // //           "statusType": statusType,   // Internal Logic Key
// // //           "displayStatus": displayStatus, // Text to show on UI
// // //
// // //           "inTime": inTimeRaw ?? "",
// // //           "outTime": outTimeRaw ?? "",
// // //           "workDuration": workDuration,
// // //           "isToday": day == now.day && _selectedDate.month == now.month && _selectedDate.year == now.year,
// // //           "isLate": isLate,
// // //           "isFuture": isFuture
// // //         });
// // //       }
// // //
// // //       if (mounted) {
// // //         setState(() {
// // //           _dailyRecords = tempList;
// // //           _presentCount = p;
// // //           _absentCount = a;
// // //           _holidayCount = h;
// // //           _isLoading = false;
// // //         });
// // //       }
// // //     } else {
// // //       if (mounted) {
// // //         setState(() {
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
// // //       backgroundColor: const Color(0xFFF5F7FA),
// // //       body: Column(
// // //         children: [
// // //           // 🔴 HEADER
// // //           Container(
// // //             padding: const EdgeInsets.only(top: 50, bottom: 25, left: 20, right: 20),
// // //             decoration: const BoxDecoration(
// // //                 gradient: LinearGradient(
// // //                   colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
// // //                   begin: Alignment.topLeft,
// // //                   end: Alignment.bottomRight,
// // //                 ),
// // //                 borderRadius: BorderRadius.only(
// // //                   bottomLeft: Radius.circular(30),
// // //                   bottomRight: Radius.circular(30),
// // //                 ),
// // //                 boxShadow: [
// // //                   BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
// // //                 ]
// // //             ),
// // //             child: Column(
// // //               children: [
// // //                 Row(
// // //                   children: [
// // //                     InkWell(
// // //                       onTap: () => Navigator.pop(context),
// // //                       child: Container(
// // //                         padding: const EdgeInsets.all(8),
// // //                         decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
// // //                         child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
// // //                       ),
// // //                     ),
// // //                     const SizedBox(width: 15),
// // //                     Column(
// // //                       crossAxisAlignment: CrossAxisAlignment.start,
// // //                       children: [
// // //                         Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
// // //                         const Text("Monthly Report", style: TextStyle(color: Colors.white70, fontSize: 12)),
// // //                       ],
// // //                     ),
// // //                   ],
// // //                 ),
// // //                 const SizedBox(height: 20),
// // //                 Row(
// // //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // //                   children: [
// // //                     IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30)),
// // //                     Text(DateFormat('MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
// // //                     IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right, color: Colors.white, size: 30)),
// // //                   ],
// // //                 ),
// // //                 const SizedBox(height: 10),
// // //                 Row(
// // //                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
// // //                   children: [
// // //                     _buildHeaderStat("Present", _presentCount.toString()),
// // //                     Container(height: 25, width: 1, color: Colors.white24),
// // //                     _buildHeaderStat("Absent", _absentCount.toString()),
// // //                     Container(height: 25, width: 1, color: Colors.white24),
// // //                     _buildHeaderStat("Holidays", _holidayCount.toString()),
// // //                   ],
// // //                 )
// // //               ],
// // //             ),
// // //           ),
// // //
// // //           // 🔴 LIST
// // //           Expanded(
// // //             child: _isLoading
// // //                 ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// // //                 : _dailyRecords.isEmpty
// // //                 ? _buildEmptyState()
// // //                 : ListView.builder(
// // //               padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
// // //               itemCount: _dailyRecords.length,
// // //               itemBuilder: (context, index) => _buildModernCard(_dailyRecords[index]),
// // //             ),
// // //           ),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   Widget _buildHeaderStat(String label, String count) {
// // //     return Column(
// // //       children: [
// // //         Text(count, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
// // //         Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
// // //       ],
// // //     );
// // //   }
// // //
// // //   // 🔴 CARD UI WITH DYNAMIC ICONS & COLORS
// // //   Widget _buildModernCard(Map<String, dynamic> item) {
// // //     String type = item['statusType']; // P, A, H, S, NJ, NA
// // //     bool isToday = item['isToday'];
// // //
// // //     Color statusColor = _getStatusColor(type);
// // //     IconData statusIcon = _getStatusIcon(type);
// // //
// // //     return Container(
// // //       margin: const EdgeInsets.only(bottom: 12),
// // //       decoration: BoxDecoration(
// // //         color: Colors.white,
// // //         borderRadius: BorderRadius.circular(12),
// // //         border: isToday ? Border.all(color: Colors.blueAccent, width: 1.5) : null,
// // //         boxShadow: [
// // //           BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))
// // //         ],
// // //       ),
// // //       child: ClipRRect(
// // //         borderRadius: BorderRadius.circular(12),
// // //         child: IntrinsicHeight(
// // //           child: Row(
// // //             children: [
// // //               // Left Strip
// // //               Container(width: 5, color: statusColor),
// // //
// // //               Expanded(
// // //                 child: Padding(
// // //                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
// // //                   child: Row(
// // //                     children: [
// // //                       // Date Box
// // //                       Column(
// // //                         crossAxisAlignment: CrossAxisAlignment.start,
// // //                         mainAxisAlignment: MainAxisAlignment.center,
// // //                         children: [
// // //                           Text(item['dayNum'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF2E3192))),
// // //                           Text(item['dayName'].toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
// // //                         ],
// // //                       ),
// // //
// // //                       const SizedBox(width: 20),
// // //                       Container(width: 1, height: 35, color: Colors.grey.shade200),
// // //                       const SizedBox(width: 20),
// // //
// // //                       // Content
// // //                       Expanded(
// // //                         child: type == "P"
// // //                             ? _buildPresentDetails(item)
// // //                             : _buildStatusDetails(item['displayStatus'], statusColor, statusIcon),
// // //                       ),
// // //                     ],
// // //                   ),
// // //                 ),
// // //               ),
// // //             ],
// // //           ),
// // //         ),
// // //       ),
// // //     );
// // //   }
// // //
// // //   // 🔴 Helper: Get Color based on Status Type
// // //   Color _getStatusColor(String type) {
// // //     switch (type) {
// // //       case "P": return const Color(0xFF00C853); // Green (Present)
// // //       case "A": return const Color(0xFFE53935); // Red (Absent)
// // //       case "H": return const Color(0xFF2E3192); // Pink (Holiday)
// // //       case "S": return const Color(0xFFFF9800); // Orange (Sunday)
// // //       case "NJ": return Colors.grey;            // Grey (Not Joined)
// // //       default: return Colors.grey.shade300;     // Future/Unknown
// // //     }
// // //   }
// // //
// // //   // 🔴 Helper: Get Icon based on Status Type
// // //   IconData _getStatusIcon(String type) {
// // //     switch (type) {
// // //       case "P": return Icons.check_circle_outline;
// // //       case "A": return Icons.cancel_outlined;
// // //       case "H": return Icons.celebration_rounded; // Party for Holiday
// // //       case "S": return Icons.weekend_rounded;     // Sofa for Sunday
// // //       case "NJ": return Icons.person_off_outlined;
// // //       default: return Icons.hourglass_empty_rounded;
// // //     }
// // //   }
// // //
// // //   Widget _buildPresentDetails(Map<String, dynamic> item) {
// // //     bool isLate = item['isLate'];
// // //     return Row(
// // //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // //       children: [
// // //         Column(
// // //           crossAxisAlignment: CrossAxisAlignment.start,
// // //           mainAxisAlignment: MainAxisAlignment.center,
// // //           children: [
// // //             _buildTimeRow("In", item['inTime']),
// // //             const SizedBox(height: 4),
// // //             _buildTimeRow("Out", item['outTime']),
// // //           ],
// // //         ),
// // //         Column(
// // //           crossAxisAlignment: CrossAxisAlignment.end,
// // //           children: [
// // //             const Text("Present", style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold)),
// // //             if(isLate)
// // //               Container(
// // //                 margin: const EdgeInsets.only(top: 4),
// // //                 padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
// // //                 decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4)),
// // //                 child: const Text("LATE", style: TextStyle(color: Color(0xFFD32F2F), fontSize: 9, fontWeight: FontWeight.bold)),
// // //               ),
// // //           ],
// // //         )
// // //       ],
// // //     );
// // //   }
// // //
// // //   Widget _buildStatusDetails(String text, Color color, IconData icon) {
// // //     return Row(
// // //       children: [
// // //         Icon(icon, color: color, size: 22),
// // //         const SizedBox(width: 12),
// // //         Flexible(
// // //           child: Text(
// // //             text,
// // //             style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
// // //             overflow: TextOverflow.ellipsis,
// // //           ),
// // //         ),
// // //       ],
// // //     );
// // //   }
// // //
// // //   Widget _buildTimeRow(String label, String time) {
// // //     String displayTime = time;
// // //     if(time != "--:--") {
// // //       try { displayTime = DateFormat("hh:mm a").format(DateFormat("HH:mm").parse(time)); } catch(_) {}
// // //     }
// // //     return Row(
// // //       children: [
// // //         SizedBox(width: 25, child: Text("$label:", style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
// // //         Text(displayTime, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF263238))),
// // //       ],
// // //     );
// // //   }
// // //
// // //   Widget _buildEmptyState() {
// // //     return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_view_day_rounded, size: 50, color: Colors.grey.shade300), const SizedBox(height: 10), Text("No records found", style: TextStyle(color: Colors.grey.shade500))]));
// // //   }
// // // }
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // //
// // // // import 'package:flutter/material.dart';
// // // // import 'package:intl/intl.dart';
// // // // import '../../services/api_service.dart';
// // // //
// // // // class AttendanceHistoryScreen extends StatefulWidget {
// // // //   final String employeeName;
// // // //   final String employeeId;
// // // //   final String locationId;
// // // //   final String departmentId;
// // // //
// // // //   const AttendanceHistoryScreen({
// // // //     super.key,
// // // //     required this.employeeName,
// // // //     required this.employeeId,
// // // //     required this.locationId,
// // // //     required this.departmentId
// // // //   });
// // // //
// // // //   @override
// // // //   State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
// // // // }
// // // //
// // // // class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
// // // //   final ApiService _apiService = ApiService();
// // // //
// // // //   bool _isLoading = true;
// // // //   DateTime _selectedDate = DateTime.now();
// // // //
// // // //   // Summary Counters
// // // //   int _presentCount = 0;
// // // //   int _absentCount = 0;
// // // //   int _holidayCount = 0;
// // // //
// // // //   List<Map<String, dynamic>> _dailyRecords = [];
// // // //
// // // //   @override
// // // //   void initState() {
// // // //     super.initState();
// // // //     _fetchReport();
// // // //   }
// // // //
// // // //   void _fetchReport() async {
// // // //     setState(() => _isLoading = true);
// // // //
// // // //     String monthStr = DateFormat('yyyy-MM').format(_selectedDate);
// // // //
// // // //     var data = await _apiService.getMonthlyReport(
// // // //         widget.employeeId,
// // // //         monthStr,
// // // //         widget.locationId,
// // // //         widget.departmentId
// // // //     );
// // // //
// // // //     if (data != null && data['attendance'] != null) {
// // // //       List<dynamic> attendanceList = data['attendance'];
// // // //       List<Map<String, dynamic>> tempList = [];
// // // //       int p = 0, a = 0, h = 0;
// // // //       DateTime now = DateTime.now();
// // // //       DateTime todayMidnight = DateTime(now.year, now.month, now.day);
// // // //
// // // //       for (var dayRecord in attendanceList) {
// // // //         int day = dayRecord['day'] ?? 1;
// // // //         Map<String, dynamic> innerData = dayRecord['data'] ?? {};
// // // //         String note = dayRecord['note'] ?? "";
// // // //
// // // //         // 🔴 DEBUG PRINT (Backend Data Check)
// // // //         if (innerData.isNotEmpty) {
// // // //           print("📅 Date: $day | Data: $innerData");
// // // //         }
// // // //
// // // //         DateTime recordDate = DateTime(_selectedDate.year, _selectedDate.month, day);
// // // //         String dateString = DateFormat('yyyy-MM-dd').format(recordDate);
// // // //
// // // //         String? inTimeRaw = innerData['checkInTime'] ?? innerData['punchIn'];
// // // //         String? outTimeRaw = innerData['checkOutTime'] ?? innerData['punchOut'];
// // // //
// // // //         // 🔴 LATE CHECK
// // // //         bool isLate = innerData['isLate'] == true;
// // // //
// // // //         String status = "A";
// // // //         String statusText = "Absent";
// // // //         bool isFuture = recordDate.isAfter(todayMidnight);
// // // //
// // // //         if (inTimeRaw != null && inTimeRaw.isNotEmpty) {
// // // //           status = "P";
// // // //           statusText = "Present";
// // // //           p++;
// // // //         } else if (note.isNotEmpty) {
// // // //           status = "H";
// // // //           statusText = note;
// // // //           h++;
// // // //         } else if (isFuture) {
// // // //           status = "NA";
// // // //           statusText = "-";
// // // //         } else {
// // // //           status = "A";
// // // //           a++;
// // // //         }
// // // //
// // // //         String workDuration = "";
// // // //         if (inTimeRaw != null && outTimeRaw != null) {
// // // //           try {
// // // //             DateTime inT = DateFormat("HH:mm").parse(inTimeRaw);
// // // //             DateTime outT = DateFormat("HH:mm").parse(outTimeRaw);
// // // //             Duration diff = outT.difference(inT);
// // // //             if (diff.isNegative) diff = diff + const Duration(hours: 24);
// // // //             int hrs = diff.inHours;
// // // //             int mins = diff.inMinutes % 60;
// // // //             workDuration = "${hrs}h ${mins}m";
// // // //           } catch (_) {}
// // // //         }
// // // //
// // // //         tempList.add({
// // // //           "date": dateString,
// // // //           "dayNum": day.toString(),
// // // //           "dayName": DateFormat('EEE').format(recordDate),
// // // //           "status": status,
// // // //           "statusText": statusText,
// // // //           "inTime": inTimeRaw ?? "",
// // // //           "outTime": outTimeRaw ?? "",
// // // //           "workDuration": workDuration,
// // // //           "isToday": day == now.day && _selectedDate.month == now.month && _selectedDate.year == now.year,
// // // //           "isLate": isLate,
// // // //           "isFuture": isFuture
// // // //         });
// // // //       }
// // // //
// // // //       if (mounted) {
// // // //         setState(() {
// // // //           _dailyRecords = tempList;
// // // //           _presentCount = p;
// // // //           _absentCount = a;
// // // //           _holidayCount = h;
// // // //           _isLoading = false;
// // // //         });
// // // //       }
// // // //     } else {
// // // //       if (mounted) {
// // // //         setState(() {
// // // //           _dailyRecords = [];
// // // //           _presentCount = 0;
// // // //           _absentCount = 0;
// // // //           _holidayCount = 0;
// // // //           _isLoading = false;
// // // //         });
// // // //       }
// // // //     }
// // // //   }
// // // //
// // // //   void _changeMonth(int monthsToAdd) {
// // // //     setState(() {
// // // //       _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + monthsToAdd);
// // // //     });
// // // //     _fetchReport();
// // // //   }
// // // //
// // // //   @override
// // // //   Widget build(BuildContext context) {
// // // //     return Scaffold(
// // // //       backgroundColor: const Color(0xFFF5F7FA), // Clean Light Grey Background
// // // //       body: Column(
// // // //         children: [
// // // //           // 🔴 1. HEADER (Gradient Sky Blue - Same as before)
// // // //           Container(
// // // //             padding: const EdgeInsets.only(top: 50, bottom: 25, left: 20, right: 20),
// // // //             decoration: const BoxDecoration(
// // // //                 gradient: LinearGradient(
// // // //                   colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
// // // //                   begin: Alignment.topLeft,
// // // //                   end: Alignment.bottomRight,
// // // //                 ),
// // // //                 borderRadius: BorderRadius.only(
// // // //                   bottomLeft: Radius.circular(30),
// // // //                   bottomRight: Radius.circular(30),
// // // //                 ),
// // // //                 boxShadow: [
// // // //                   BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
// // // //                 ]
// // // //             ),
// // // //             child: Column(
// // // //               children: [
// // // //                 // Nav & Title
// // // //                 Row(
// // // //                   children: [
// // // //                     InkWell(
// // // //                       onTap: () => Navigator.pop(context),
// // // //                       child: Container(
// // // //                         padding: const EdgeInsets.all(8),
// // // //                         decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
// // // //                         child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
// // // //                       ),
// // // //                     ),
// // // //                     const SizedBox(width: 15),
// // // //                     Column(
// // // //                       crossAxisAlignment: CrossAxisAlignment.start,
// // // //                       children: [
// // // //                         Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
// // // //                         const Text("Attendance Report", style: TextStyle(color: Colors.white70, fontSize: 12)),
// // // //                       ],
// // // //                     ),
// // // //                   ],
// // // //                 ),
// // // //
// // // //                 const SizedBox(height: 20),
// // // //
// // // //                 // Month Selector
// // // //                 Row(
// // // //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // // //                   children: [
// // // //                     IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30)),
// // // //                     Text(DateFormat('MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
// // // //                     IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right, color: Colors.white, size: 30)),
// // // //                   ],
// // // //                 ),
// // // //
// // // //                 const SizedBox(height: 10),
// // // //
// // // //                 // Stats Row
// // // //                 Row(
// // // //                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
// // // //                   children: [
// // // //                     _buildHeaderStat("Present", _presentCount.toString()),
// // // //                     Container(height: 25, width: 1, color: Colors.white24),
// // // //                     _buildHeaderStat("Absent", _absentCount.toString()),
// // // //                     Container(height: 25, width: 1, color: Colors.white24),
// // // //                     _buildHeaderStat("Holidays", _holidayCount.toString()),
// // // //                   ],
// // // //                 )
// // // //               ],
// // // //             ),
// // // //           ),
// // // //
// // // //           // 🔴 2. LIST CONTENT
// // // //           Expanded(
// // // //             child: _isLoading
// // // //                 ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// // // //                 : _dailyRecords.isEmpty
// // // //                 ? _buildEmptyState()
// // // //                 : ListView.builder(
// // // //               padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
// // // //               itemCount: _dailyRecords.length,
// // // //               itemBuilder: (context, index) => _buildModernCard(_dailyRecords[index]),
// // // //             ),
// // // //           ),
// // // //         ],
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildHeaderStat(String label, String count) {
// // // //     return Column(
// // // //       children: [
// // // //         Text(count, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
// // // //         Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
// // // //       ],
// // // //     );
// // // //   }
// // // //
// // // //   // 🔴 3. CLEAN & ATTRACTIVE CARD
// // // //   Widget _buildModernCard(Map<String, dynamic> item) {
// // // //     bool isFuture = item['isFuture'];
// // // //     String status = item['status'];
// // // //     bool isPresent = status == "P";
// // // //     bool isAbsent = status == "A";
// // // //     bool isHoliday = status == "H";
// // // //     bool isToday = item['isToday'];
// // // //
// // // //     // Status Colors
// // // //     Color statusColor = Colors.grey.shade300;
// // // //     if(isPresent) statusColor = const Color(0xFF00C853); // Bright Green
// // // //     if(isAbsent) statusColor = const Color(0xFFE53935); // Bright Red
// // // //     if(isHoliday) statusColor = const Color(0xFFFF9800); // Orange
// // // //
// // // //     return Container(
// // // //       margin: const EdgeInsets.only(bottom: 12),
// // // //       decoration: BoxDecoration(
// // // //         color: isFuture ? const Color(0xFFF9FAFB) : Colors.white,
// // // //         borderRadius: BorderRadius.circular(12),
// // // //         border: isToday ? Border.all(color: Colors.green, width: 1.5) : Border.all(color: Colors.transparent),
// // // //         boxShadow: isFuture ? [] : [
// // // //           BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))
// // // //         ],
// // // //       ),
// // // //       child: ClipRRect(
// // // //         borderRadius: BorderRadius.circular(12),
// // // //         child: IntrinsicHeight(
// // // //           child: Row(
// // // //             children: [
// // // //               // Left Color Strip
// // // //               Container(width: 5, color: statusColor),
// // // //
// // // //               Expanded(
// // // //                 child: Padding(
// // // //                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
// // // //                   child: Row(
// // // //                     children: [
// // // //                       // DATE BOX (Simple & Clean)
// // // //                       Column(
// // // //                         crossAxisAlignment: CrossAxisAlignment.start,
// // // //                         mainAxisAlignment: MainAxisAlignment.center,
// // // //                         children: [
// // // //                           Text(item['dayNum'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isFuture ? Colors.grey : const Color(0xFF2E3192))),
// // // //                           Text(item['dayName'].toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
// // // //                         ],
// // // //                       ),
// // // //
// // // //                       const SizedBox(width: 20),
// // // //
// // // //                       // Vertical Line Separator
// // // //                       Container(width: 1, height: 35, color: Colors.grey.shade200),
// // // //
// // // //                       const SizedBox(width: 20),
// // // //
// // // //                       // INFO AREA
// // // //                       Expanded(
// // // //                         child: isPresent
// // // //                             ? _buildPresentDetails(item)
// // // //                             : _buildStatusDetails(item, statusColor),
// // // //                       ),
// // // //                     ],
// // // //                   ),
// // // //                 ),
// // // //               ),
// // // //             ],
// // // //           ),
// // // //         ),
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildPresentDetails(Map<String, dynamic> item) {
// // // //     bool isLate = item['isLate'];
// // // //
// // // //     return Row(
// // // //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // // //       children: [
// // // //         // Times
// // // //         Column(
// // // //           crossAxisAlignment: CrossAxisAlignment.start,
// // // //           mainAxisAlignment: MainAxisAlignment.center,
// // // //           children: [
// // // //             _buildTimeRow("In", item['inTime']),
// // // //             const SizedBox(height: 4),
// // // //             _buildTimeRow("Out", item['outTime']),
// // // //           ],
// // // //         ),
// // // //
// // // //         // Right Side: Badges
// // // //         Column(
// // // //           crossAxisAlignment: CrossAxisAlignment.end,
// // // //           mainAxisAlignment: MainAxisAlignment.center,
// // // //           children: [
// // // //             // Present Text
// // // //             const Text("Present", style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold)),
// // // //
// // // //             const SizedBox(height: 4),
// // // //
// // // //             // 🔴 LATE BADGE
// // // //             if(isLate)
// // // //               Container(
// // // //                 margin: const EdgeInsets.only(bottom: 4),
// // // //                 padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
// // // //                 decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4)),
// // // //                 child: const Text("LATE", style: TextStyle(color: Color(0xFFD32F2F), fontSize: 9, fontWeight: FontWeight.bold)),
// // // //               ),
// // // //
// // // //             // Work Hrs
// // // //             if(item['workDuration'].isNotEmpty)
// // // //               Row(
// // // //                 children: [
// // // //                   const Icon(Icons.access_time, size: 11, color: Colors.grey),
// // // //                   const SizedBox(width: 3),
// // // //                   Text(item['workDuration'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF455A64))),
// // // //                 ],
// // // //               )
// // // //           ],
// // // //         )
// // // //       ],
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildStatusDetails(Map<String, dynamic> item, Color color) {
// // // //     return Row(
// // // //       children: [
// // // //         Icon(
// // // //             item['status'] == "H" ? Icons.star_rounded : (item['isFuture'] ? Icons.hourglass_empty_rounded : Icons.cancel),
// // // //             color: color,
// // // //             size: 20
// // // //         ),
// // // //         const SizedBox(width: 10),
// // // //         Text(
// // // //           item['statusText'],
// // // //           style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
// // // //         ),
// // // //       ],
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildTimeRow(String label, String time) {
// // // //     String displayTime = time;
// // // //     if(time != "--:--") {
// // // //       try { displayTime = DateFormat("hh:mm a").format(DateFormat("HH:mm").parse(time)); } catch (_) {}
// // // //     }
// // // //
// // // //     return Row(
// // // //       children: [
// // // //         SizedBox(width: 25, child: Text("$label:", style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
// // // //         Text(displayTime, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF263238))),
// // // //       ],
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildEmptyState() {
// // // //     return Center(
// // // //       child: Column(
// // // //         mainAxisAlignment: MainAxisAlignment.center,
// // // //         children: [
// // // //           Icon(Icons.calendar_view_day_rounded, size: 50, color: Colors.grey.shade300),
// // // //           const SizedBox(height: 10),
// // // //           Text("No records found", style: TextStyle(color: Colors.grey.shade500)),
// // // //         ],
// // // //       ),
// // // //     );
// // // //   }
// // // // }
// // // //
// // // //
// // // //
// // // //
// // // //
// // // //
// // // //
// // // //
// // // //
// // // // // import 'package:flutter/material.dart';
// // // // // import 'package:intl/intl.dart';
// // // // // import '../../services/api_service.dart';
// // // // //
// // // // // class AttendanceHistoryScreen extends StatefulWidget {
// // // // //   final String employeeName;
// // // // //   final String employeeId;
// // // // //   final String locationId; // 🔴 NEW: Location ID Added
// // // // //
// // // // //   const AttendanceHistoryScreen({
// // // // //     super.key,
// // // // //     required this.employeeName,
// // // // //     required this.employeeId,
// // // // //     required this.locationId // 🔴 Required
// // // // //   });
// // // // //
// // // // //   @override
// // // // //   State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
// // // // // }
// // // // //
// // // // // class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
// // // // //   final ApiService _apiService = ApiService();
// // // // //
// // // // //   bool _isLoading = true;
// // // // //   DateTime _selectedDate = DateTime.now();
// // // // //
// // // // //   Map<String, dynamic>? _reportData;
// // // // //   List<Map<String, dynamic>> _dailyRecords = [];
// // // // //
// // // // //   @override
// // // // //   void initState() {
// // // // //     super.initState();
// // // // //     _fetchReport();
// // // // //   }
// // // // //
// // // // //   // lib/screens/Admin Side/attendance_history_screen.dart
// // // // //
// // // // //   void _fetchReport() async {
// // // // //     setState(() => _isLoading = true);
// // // // //
// // // // //     String monthStr = DateFormat('yyyy-MM').format(_selectedDate);
// // // // //
// // // // //     var data = await _apiService.getMonthlyReport(
// // // // //         widget.employeeId,
// // // // //         monthStr,
// // // // //         widget.locationId
// // // // //     );
// // // // //
// // // // //     if (data != null) {
// // // // //       // 🔴 Check karo ki 'days' exist karta hai ya nahi
// // // // //       Map<String, dynamic> daysMap = {};
// // // // //
// // // // //       if (data['days'] != null && data['days'] is Map) {
// // // // //         daysMap = data['days'];
// // // // //       } else if (data['attendance'] != null && data['attendance']['days'] != null) {
// // // // //         // Kabhi kabhi data nested hota hai
// // // // //         daysMap = data['attendance']['days'];
// // // // //       }
// // // // //
// // // // //       List<Map<String, dynamic>> tempList = [];
// // // // //
// // // // //       daysMap.forEach((dateKey, value) {
// // // // //         tempList.add({
// // // // //           "date": dateKey,
// // // // //           "status": value['status'] ?? "",
// // // // //           "arr": value['arr'] ?? "",
// // // // //           "dep": value['dep'] ?? "",
// // // // //           "work": value['work'] ?? "0"
// // // // //         });
// // // // //       });
// // // // //
// // // // //       // Sort Latest First
// // // // //       tempList.sort((a, b) => b['date'].compareTo(a['date']));
// // // // //
// // // // //       if (mounted) {
// // // // //         setState(() {
// // // // //           _reportData = data;
// // // // //           _dailyRecords = tempList;
// // // // //           _isLoading = false;
// // // // //         });
// // // // //       }
// // // // //     } else {
// // // // //       if (mounted) {
// // // // //         setState(() {
// // // // //           _reportData = null;
// // // // //           _dailyRecords = [];
// // // // //           _isLoading = false;
// // // // //         });
// // // // //       }
// // // // //     }
// // // // //   }
// // // // //
// // // // //   void _changeMonth(int monthsToAdd) {
// // // // //     setState(() {
// // // // //       _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + monthsToAdd);
// // // // //     });
// // // // //     _fetchReport();
// // // // //   }
// // // // //
// // // // //   @override
// // // // //   Widget build(BuildContext context) {
// // // // //     return Scaffold(
// // // // //       backgroundColor: const Color(0xFFF2F5F9),
// // // // //       body: Stack(
// // // // //         children: [
// // // // //           Container(
// // // // //             height: 240,
// // // // //             decoration: const BoxDecoration(
// // // // //               gradient: LinearGradient(
// // // // //                 colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
// // // // //                 begin: Alignment.topLeft,
// // // // //                 end: Alignment.bottomRight,
// // // // //               ),
// // // // //               borderRadius: BorderRadius.only(
// // // // //                 bottomLeft: Radius.circular(30),
// // // // //                 bottomRight: Radius.circular(30),
// // // // //               ),
// // // // //             ),
// // // // //           ),
// // // // //
// // // // //           SafeArea(
// // // // //             child: Column(
// // // // //               children: [
// // // // //                 Padding(
// // // // //                   padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
// // // // //                   child: Row(
// // // // //                     children: [
// // // // //                       IconButton(
// // // // //                         icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
// // // // //                         onPressed: () => Navigator.pop(context),
// // // // //                       ),
// // // // //                       const SizedBox(width: 10),
// // // // //                       Column(
// // // // //                         crossAxisAlignment: CrossAxisAlignment.start,
// // // // //                         children: [
// // // // //                           Text(
// // // // //                             widget.employeeName,
// // // // //                             style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
// // // // //                           ),
// // // // //                           Text(
// // // // //                             "Attendance History",
// // // // //                             style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
// // // // //                           ),
// // // // //                         ],
// // // // //                       )
// // // // //                     ],
// // // // //                   ),
// // // // //                 ),
// // // // //
// // // // //                 Container(
// // // // //                   margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
// // // // //                   padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
// // // // //                   decoration: BoxDecoration(
// // // // //                       color: Colors.white.withOpacity(0.2),
// // // // //                       borderRadius: BorderRadius.circular(15),
// // // // //                       border: Border.all(color: Colors.white.withOpacity(0.3))
// // // // //                   ),
// // // // //                   child: Row(
// // // // //                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // // // //                     children: [
// // // // //                       IconButton(
// // // // //                         icon: const Icon(Icons.chevron_left, color: Colors.white),
// // // // //                         onPressed: () => _changeMonth(-1),
// // // // //                       ),
// // // // //                       Text(
// // // // //                         DateFormat('MMMM yyyy').format(_selectedDate),
// // // // //                         style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
// // // // //                       ),
// // // // //                       IconButton(
// // // // //                         icon: const Icon(Icons.chevron_right, color: Colors.white),
// // // // //                         onPressed: () => _changeMonth(1),
// // // // //                       ),
// // // // //                     ],
// // // // //                   ),
// // // // //                 ),
// // // // //
// // // // //                 const SizedBox(height: 15),
// // // // //
// // // // //                 if (_reportData != null)
// // // // //                   Container(
// // // // //                     margin: const EdgeInsets.symmetric(horizontal: 20),
// // // // //                     padding: const EdgeInsets.all(15),
// // // // //                     decoration: BoxDecoration(
// // // // //                       color: Colors.white,
// // // // //                       borderRadius: BorderRadius.circular(20),
// // // // //                       boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
// // // // //                     ),
// // // // //                     child: Row(
// // // // //                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // // // //                       children: [
// // // // //                         _buildSummaryItem("Present", _reportData!['present'].toString(), Colors.green),
// // // // //                         _buildSummaryItem("Absent", _reportData!['absent'].toString(), Colors.red),
// // // // //                         _buildSummaryItem("Half Day", _reportData!['halfDay'].toString(), Colors.orange),
// // // // //                       ],
// // // // //                     ),
// // // // //                   ),
// // // // //
// // // // //                 const SizedBox(height: 15),
// // // // //
// // // // //                 Expanded(
// // // // //                   child: _isLoading
// // // // //                       ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// // // // //                       : _dailyRecords.isEmpty
// // // // //                       ? _buildEmptyState()
// // // // //                       : ListView.builder(
// // // // //                     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
// // // // //                     itemCount: _dailyRecords.length,
// // // // //                     itemBuilder: (context, index) {
// // // // //                       return _buildDailyCard(_dailyRecords[index]);
// // // // //                     },
// // // // //                   ),
// // // // //                 ),
// // // // //               ],
// // // // //             ),
// // // // //           ),
// // // // //         ],
// // // // //       ),
// // // // //     );
// // // // //   }
// // // // //
// // // // //   Widget _buildSummaryItem(String label, String value, Color color) {
// // // // //     return Column(
// // // // //       children: [
// // // // //         Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
// // // // //         const SizedBox(height: 4),
// // // // //         Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
// // // // //       ],
// // // // //     );
// // // // //   }
// // // // //
// // // // //   Widget _buildDailyCard(Map<String, dynamic> item) {
// // // // //     DateTime dt = DateTime.parse(item['date']);
// // // // //     String dayNum = DateFormat('dd').format(dt);
// // // // //     String dayName = DateFormat('EEE').format(dt);
// // // // //
// // // // //     String status = item['status'];
// // // // //     String arr = item['arr'];
// // // // //     String dep = item['dep'];
// // // // //     String work = item['work'];
// // // // //
// // // // //     Color statusColor = Colors.grey;
// // // // //     String statusText = "Off";
// // // // //
// // // // //     if (status == "A") {
// // // // //       statusColor = Colors.red;
// // // // //       statusText = "Absent";
// // // // //     } else if (status == "H") {
// // // // //       statusColor = Colors.orange;
// // // // //       statusText = "Half Day";
// // // // //     } else if (status == "P" || (arr.isNotEmpty && status != "A")) {
// // // // //       statusColor = Colors.green;
// // // // //       statusText = "Present";
// // // // //     }
// // // // //
// // // // //     if (arr.isNotEmpty && dep.isEmpty) {
// // // // //       statusColor = Colors.blue;
// // // // //       statusText = "Active";
// // // // //     }
// // // // //
// // // // //     return Container(
// // // // //       margin: const EdgeInsets.only(bottom: 12),
// // // // //       decoration: BoxDecoration(
// // // // //         color: Colors.white,
// // // // //         borderRadius: BorderRadius.circular(15),
// // // // //         boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3))],
// // // // //       ),
// // // // //       child: IntrinsicHeight(
// // // // //         child: Row(
// // // // //           children: [
// // // // //             Container(
// // // // //               width: 5,
// // // // //               decoration: BoxDecoration(
// // // // //                 color: statusColor,
// // // // //                 borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15)),
// // // // //               ),
// // // // //             ),
// // // // //             Expanded(
// // // // //               child: Padding(
// // // // //                 padding: const EdgeInsets.all(12),
// // // // //                 child: Row(
// // // // //                   children: [
// // // // //                     Container(
// // // // //                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
// // // // //                       decoration: BoxDecoration(
// // // // //                         color: Colors.grey.shade50,
// // // // //                         borderRadius: BorderRadius.circular(10),
// // // // //                       ),
// // // // //                       child: Column(
// // // // //                         children: [
// // // // //                           Text(dayNum, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
// // // // //                           Text(dayName.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
// // // // //                         ],
// // // // //                       ),
// // // // //                     ),
// // // // //                     const SizedBox(width: 15),
// // // // //                     Expanded(
// // // // //                       child: Column(
// // // // //                         crossAxisAlignment: CrossAxisAlignment.start,
// // // // //                         children: [
// // // // //                           if (status == "A" || (arr.isEmpty && dep.isEmpty))
// // // // //                             Text("No Punch Record", style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontStyle: FontStyle.italic))
// // // // //                           else ...[
// // // // //                             _buildTimeRow("In", arr, Colors.black87),
// // // // //                             const SizedBox(height: 4),
// // // // //                             _buildTimeRow("Out", dep.isEmpty ? "--:--" : dep, Colors.grey.shade600),
// // // // //                           ]
// // // // //                         ],
// // // // //                       ),
// // // // //                     ),
// // // // //                     Column(
// // // // //                       crossAxisAlignment: CrossAxisAlignment.end,
// // // // //                       children: [
// // // // //                         Container(
// // // // //                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
// // // // //                           decoration: BoxDecoration(
// // // // //                             color: statusColor.withOpacity(0.1),
// // // // //                             borderRadius: BorderRadius.circular(6),
// // // // //                           ),
// // // // //                           child: Text(
// // // // //                             statusText.toUpperCase(),
// // // // //                             style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
// // // // //                           ),
// // // // //                         ),
// // // // //                         const SizedBox(height: 6),
// // // // //                         if (work != "0" && work.isNotEmpty)
// // // // //                           Text(
// // // // //                             (double.tryParse(work) ?? 0) < 1.0
// // // // //                                 ? "${((double.tryParse(work) ?? 0) * 60).toStringAsFixed(0)} min"
// // // // //                                 : "${double.tryParse(work)?.toStringAsFixed(1) ?? 0} hrs",
// // // // //                             style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
// // // // //                           ),
// // // // //                       ],
// // // // //                     )
// // // // //                   ],
// // // // //                 ),
// // // // //               ),
// // // // //             )
// // // // //           ],
// // // // //         ),
// // // // //       ),
// // // // //     );
// // // // //   }
// // // // //
// // // // //   Widget _buildTimeRow(String label, String time, Color color) {
// // // // //     return Row(
// // // // //       children: [
// // // // //         Text("$label: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
// // // // //         Text(time.isEmpty ? "--:--" : time, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
// // // // //       ],
// // // // //     );
// // // // //   }
// // // // //
// // // // //   Widget _buildEmptyState() {
// // // // //     return Center(
// // // // //       child: Column(
// // // // //         mainAxisAlignment: MainAxisAlignment.center,
// // // // //         children: [
// // // // //           Icon(Icons.calendar_today_outlined, size: 50, color: Colors.grey.shade300),
// // // // //           const SizedBox(height: 10),
// // // // //           Text("No records found", style: TextStyle(color: Colors.grey.shade500)),
// // // // //         ],
// // // // //       ),
// // // // //     );
// // // // //   }
// // // // // }
// // // // //