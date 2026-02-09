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

  int _presentCount = 0;
  int _absentCount = 0;
  int _holidayCount = 0;

  List<Map<String, dynamic>> _dailyRecords = [];

  @override
  void initState() {
    super.initState();
    _fetchLocationAndReport();
  }

  // 🔥 SMART FETCH: Pehle Storage check karo, nahi mila to API se mangwao
  void _fetchLocationAndReport() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? locId = prefs.getString('locationId');

    if (locId != null && locId.isNotEmpty) {
      // ✅ Case 1: Storage mein mil gayi
      print("✅ Location ID found in Storage: $locId");
      if(mounted) {
        setState(() { _storedLocationId = locId; });
        _fetchReport();
      }
    } else {
      // ⚠️ Case 2: Storage mein nahi hai (Shayad purana login hai)
      print("⚠️ Location ID missing. Auto-fetching from Profile...");

      String? fetchedId = await _apiService.fetchUserLocationId(widget.employeeId);

      if (fetchedId != null && mounted) {
        print("✅ Auto-fetched Location ID: $fetchedId");
        await prefs.setString('locationId', fetchedId); // Future ke liye save karo

        setState(() { _storedLocationId = fetchedId; });
        _fetchReport();
      } else {
        print("❌ Failed to fetch Location ID.");
        if(mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _fetchReport() async {
    if (_storedLocationId == null) return;

    setState(() => _isLoading = true);
    String monthStr = DateFormat('yyyy-MM').format(_selectedDate);

    var data = await _apiService.getEmployeeOwnHistory(
        widget.employeeId,
        monthStr,
        _storedLocationId!

    );

    if (data != null && data['attendance'] != null) {
      List<dynamic> attendanceList = data['attendance'];
      List<Map<String, dynamic>> tempList = [];

      int p = 0, a = 0, h = 0;
      DateTime now = DateTime.now();
      DateTime todayMidnight = DateTime(now.year, now.month, now.day);

      for (var dayRecord in attendanceList) {
        int day = dayRecord['day'] ?? 1;
        Map<String, dynamic> innerData = dayRecord['data'] ?? {};
        String note = dayRecord['note'] ?? "";

        DateTime recordDate = DateTime(_selectedDate.year, _selectedDate.month, day);
        String dateString = DateFormat('yyyy-MM-dd').format(recordDate);

        String? inTimeRaw = innerData['checkInTime'] ?? innerData['punchIn'];
        String? outTimeRaw = innerData['checkOutTime'] ?? innerData['punchOut'];
        bool isLate = innerData['isLate'] == true;

        String status = "A";
        String statusText = "Absent";
        bool isFuture = recordDate.isAfter(todayMidnight);

        if (inTimeRaw != null && inTimeRaw.isNotEmpty) {
          status = "P";
          statusText = "Present";
          p++;
        } else if (note.isNotEmpty) {
          status = "H";
          statusText = note;
          h++;
        } else if (isFuture) {
          status = "NA";
          statusText = "-";
        } else {
          status = "A";
          a++;
        }

        String workDuration = "";
        if (inTimeRaw != null && outTimeRaw != null) {
          try {
            DateTime inT = DateFormat("HH:mm").parse(inTimeRaw);
            DateTime outT = DateFormat("HH:mm").parse(outTimeRaw);
            Duration diff = outT.difference(inT);
            if (diff.isNegative) diff = diff + const Duration(hours: 24);
            workDuration = "${diff.inHours}h ${diff.inMinutes % 60}m";
          } catch (_) {}
        }

        tempList.add({
          "date": dateString,
          "dayNum": day.toString(),
          "dayName": DateFormat('EEE').format(recordDate),
          "status": status,
          "statusText": statusText,
          "inTime": inTimeRaw ?? "",
          "outTime": outTimeRaw ?? "",
          "workDuration": workDuration,
          "isToday": day == now.day && _selectedDate.month == now.month && _selectedDate.year == now.year,
          "isLate": isLate,
          "isFuture": isFuture
        });
      }

      if (mounted) {
        setState(() {
          _dailyRecords = tempList;
          _presentCount = p;
          _absentCount = a;
          _holidayCount = h;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() { _dailyRecords = []; _isLoading = false; });
    }
  }

  void _changeMonth(int monthsToAdd) {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + monthsToAdd);
    });
    // Month change hone par dubara ID check karne ki zarurat nahi, bas report fetch karo
    if(_storedLocationId != null) _fetchReport();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // 🔴 HEADER
          Container(
            padding: const EdgeInsets.only(top: 50, bottom: 25, left: 20, right: 20),
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
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
                      child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18)),
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
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30)),
                    Text(DateFormat('MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                    IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right, color: Colors.white, size: 30)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildHeaderStat("Present", _presentCount.toString()),
                    Container(height: 25, width: 1, color: Colors.white24),
                    _buildHeaderStat("Absent", _absentCount.toString()),
                    Container(height: 25, width: 1, color: Colors.white24),
                    _buildHeaderStat("Holidays", _holidayCount.toString()),
                  ],
                )
              ],
            ),
          ),

          // 🔴 LIST
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
                : _dailyRecords.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _dailyRecords.length,
              itemBuilder: (context, index) => _buildCleanCard(_dailyRecords[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, String count) {
    return Column(children: [Text(count, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))]);
  }

  Widget _buildCleanCard(Map<String, dynamic> item) {
    bool isFuture = item['isFuture'];
    String status = item['status'];
    bool isPresent = status == "P";
    bool isAbsent = status == "A";
    bool isHoliday = status == "H";
    bool isToday = item['isToday'];
    bool isLate = item['isLate'];

    Color statusColor = Colors.grey.shade300;
    if(isPresent) statusColor = const Color(0xFF00C853);
    if(isAbsent) statusColor = const Color(0xFFE53935);
    if(isHoliday) statusColor = const Color(0xFFFB8C00);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isFuture ? const Color(0xFFF9FAFB) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isToday ? Border.all(color: const Color(0xFF2E3192), width: 1.5) : null,
        boxShadow: isFuture ? [] : [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['dayNum'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isFuture ? Colors.grey : const Color(0xFF2E3192))),
                          Text(item['dayName'].toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                        ],
                      ),
                      const SizedBox(width: 20),
                      Container(width: 1, height: 35, color: Colors.grey.shade200),
                      const SizedBox(width: 20),
                      Expanded(
                        child: isPresent
                            ? _buildPresentDetails(item, isLate)
                            : _buildStatusDetails(item, statusColor),
                      ),
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

  Widget _buildPresentDetails(Map<String, dynamic> item, bool isLate) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildTimeRow("In", item['inTime']), const SizedBox(height: 4), _buildTimeRow("Out", item['outTime']),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text("Present", style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if(isLate) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4)), child: const Text("LATE", style: TextStyle(color: Color(0xFFD32F2F), fontSize: 9, fontWeight: FontWeight.bold))),
          if(item['workDuration'].isNotEmpty) Text(item['workDuration'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF455A64))),
        ])
      ],
    );
  }

  Widget _buildStatusDetails(Map<String, dynamic> item, Color color) {
    return Row(children: [Icon(item['status'] == "H" ? Icons.star_rounded : (item['isFuture'] ? Icons.hourglass_empty_rounded : Icons.cancel), color: color, size: 20), const SizedBox(width: 10), Text(item['statusText'], style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold))]);
  }

  Widget _buildTimeRow(String label, String time) {
    String displayTime = "--:--";
    if(time != "" && time != "--:--") {
      try { displayTime = DateFormat("hh:mm a").format(DateFormat("HH:mm").parse(time)); } catch (_) {}
    }
    return Row(children: [SizedBox(width: 25, child: Text("$label:", style: TextStyle(fontSize: 11, color: Colors.grey.shade500))), Text(displayTime, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF263238)))]);
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_view_day_rounded, size: 50, color: Colors.grey.shade300), const SizedBox(height: 10), Text("No records found", style: TextStyle(color: Colors.grey.shade500))]));
  }
}









// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
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
//
//   // Data Holders
//   Map<String, dynamic>? _reportData;
//   List<Map<String, dynamic>> _dailyRecords = [];
//
//   @override
//   void initState() {
//     super.initState();
//     _fetchReport();
//   }
//
//   // 🔴 API CALL LOGIC (Using Specialized Function)
//   void _fetchReport() async {
//     setState(() => _isLoading = true);
//
//     String monthStr = DateFormat('yyyy-MM').format(_selectedDate).toString();
//
//     // 🔥 CALLING THE NEW EMPLOYEE-SPECIFIC FUNCTION
//     var data = await _apiService.getEmployeeOwnHistory(widget.employeeId, monthStr);
//
//     if (data != null) {
//       // 1. Parse Data
//       Map<String, dynamic> daysMap = data['days'] ?? {};
//       List<Map<String, dynamic>> tempList = [];
//
//       daysMap.forEach((dateKey, value) {
//         tempList.add({
//           "date": dateKey,
//           "status": value['status'] ?? "",
//           "arr": value['arr'] ?? "",
//           "dep": value['dep'] ?? "",
//           "work": value['work'] ?? "0"
//         });
//       });
//
//       // 2. Sort List
//       tempList.sort((a, b) => b['date'].compareTo(b['date']));
//
//       if (mounted) {
//         setState(() {
//           _reportData = data;
//           _dailyRecords = tempList;
//           _isLoading = false;
//         });
//       }
//     } else {
//       if (mounted) {
//         setState(() {
//           _reportData = null;
//           _dailyRecords = [];
//           _isLoading = false;
//         });
//       }
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
//       backgroundColor: const Color(0xFFF2F5F9),
//       body: Stack(
//         children: [
//           // --- HEADER BACKGROUND (Blue-Cyan Gradient) ---
//           Container(
//             height: 240,
//             decoration: const BoxDecoration(
//               gradient: LinearGradient(
//                 colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
//                 begin: Alignment.topLeft,
//                 end: Alignment.bottomRight,
//               ),
//               borderRadius: BorderRadius.only(
//                 bottomLeft: Radius.circular(30),
//                 bottomRight: Radius.circular(30),
//               ),
//             ),
//           ),
//
//           SafeArea(
//             child: Column(
//               children: [
//                 // --- TOP BAR ---
//                 Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
//                   child: Row(
//                     children: [
//                       IconButton(
//                         icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
//                         onPressed: () => Navigator.pop(context),
//                       ),
//                       const SizedBox(width: 10),
//                       Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             widget.employeeName,
//                             style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
//                           ),
//                           Text(
//                             "My Attendance Logs",
//                             style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
//                           ),
//                         ],
//                       )
//                     ],
//                   ),
//                 ),
//
//                 // --- MONTH SELECTOR ---
//                 Container(
//                   margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
//                   padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
//                   decoration: BoxDecoration(
//                       color: Colors.white.withOpacity(0.2),
//                       borderRadius: BorderRadius.circular(15),
//                       border: Border.all(color: Colors.white.withOpacity(0.3))
//                   ),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       IconButton(
//                         icon: const Icon(Icons.chevron_left, color: Colors.white),
//                         onPressed: () => _changeMonth(-1),
//                       ),
//                       Text(
//                         DateFormat('MMMM yyyy').format(_selectedDate),
//                         style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
//                       ),
//                       IconButton(
//                         icon: const Icon(Icons.chevron_right, color: Colors.white),
//                         onPressed: () => _changeMonth(1),
//                       ),
//                     ],
//                   ),
//                 ),
//
//                 const SizedBox(height: 15),
//
//                 // --- SUMMARY STATS GRID ---
//                 if (_reportData != null)
//                   Container(
//                     margin: const EdgeInsets.symmetric(horizontal: 20),
//                     padding: const EdgeInsets.all(15),
//                     decoration: BoxDecoration(
//                       color: Colors.white,
//                       borderRadius: BorderRadius.circular(20),
//                       boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
//                     ),
//                     child: Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                       children: [
//                         _buildSummaryItem("Present", _reportData!['present'].toString(), Colors.green),
//                         _buildSummaryItem("Absent", _reportData!['absent'].toString(), Colors.red),
//                         _buildSummaryItem("Half Day", _reportData!['halfDay'].toString(), Colors.orange),
//                       ],
//                     ),
//                   ),
//
//                 const SizedBox(height: 15),
//
//                 // --- LIST OF DAILY RECORDS ---
//                 Expanded(
//                   child: _isLoading
//                       ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
//                       : _dailyRecords.isEmpty
//                       ? _buildEmptyState()
//                       : ListView.builder(
//                     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
//                     itemCount: _dailyRecords.length,
//                     itemBuilder: (context, index) {
//                       return _buildDailyCard(_dailyRecords[index]);
//                     },
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   // --- WIDGETS (Same as Admin) ---
//
//   Widget _buildSummaryItem(String label, String value, Color color) {
//     return Column(
//       children: [
//         Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
//         const SizedBox(height: 4),
//         Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
//       ],
//     );
//   }
//
//   Widget _buildDailyCard(Map<String, dynamic> item) {
//     DateTime dt = DateTime.parse(item['date']);
//     String dayNum = DateFormat('dd').format(dt);
//     String dayName = DateFormat('EEE').format(dt);
//     String status = item['status'];
//     String arr = item['arr'];
//     String dep = item['dep'];
//     String work = item['work'];
//
//     Color statusColor = Colors.grey;
//     String statusText = "Off";
//
//     if (status == "A") {
//       statusColor = Colors.red;
//       statusText = "Absent";
//     } else if (status == "H") {
//       statusColor = Colors.orange;
//       statusText = "Half Day";
//     } else if (status == "P" || (arr.isNotEmpty && status != "A")) {
//       statusColor = Colors.green;
//       statusText = "Present";
//     }
//
//     if (arr.isNotEmpty && dep.isEmpty) {
//       statusColor = Colors.blue;
//       statusText = "Active";
//     }
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(15),
//         boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3))],
//       ),
//       child: IntrinsicHeight(
//         child: Row(
//           children: [
//             Container(
//               width: 5,
//               decoration: BoxDecoration(
//                 color: statusColor,
//                 borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15)),
//               ),
//             ),
//             Expanded(
//               child: Padding(
//                 padding: const EdgeInsets.all(12),
//                 child: Row(
//                   children: [
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//                       decoration: BoxDecoration(
//                         color: Colors.grey.shade50,
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       child: Column(
//                         children: [
//                           Text(dayNum, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
//                           Text(dayName.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
//                         ],
//                       ),
//                     ),
//                     const SizedBox(width: 15),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           if (status == "A" || (arr.isEmpty && dep.isEmpty))
//                             Text("No Punch Record", style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontStyle: FontStyle.italic))
//                           else ...[
//                             _buildTimeRow("In", arr, Colors.black87),
//                             const SizedBox(height: 4),
//                             _buildTimeRow("Out", dep.isEmpty ? "--:--" : dep, Colors.grey.shade600),
//                           ]
//                         ],
//                       ),
//                     ),
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.end,
//                       children: [
//                         Container(
//                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
//                           decoration: BoxDecoration(
//                             color: statusColor.withOpacity(0.1),
//                             borderRadius: BorderRadius.circular(6),
//                           ),
//                           child: Text(
//                             statusText.toUpperCase(),
//                             style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
//                           ),
//                         ),
//                         const SizedBox(height: 6),
//                         if (work != "0" && work.isNotEmpty)
//                         Text(
//                           (double.parse(work) * 60) < 60
//                               ? "${(double.parse(work) * 60).toStringAsFixed(0)} min"  // If less than 60 mins (e.g., "45 min")
//                               : "${double.parse(work).toStringAsFixed(1)} hrs",        // If 60+ mins (e.g., "1.5 hrs")
//                           // 👆 LOGIC END
//                         ),
//                           ],
//                     )
//                   ],
//                 ),
//               ),
//             )
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildTimeRow(String label, String time, Color color) {
//     return Row(
//       children: [
//         Text("$label: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
//         Text(time.isEmpty ? "--:--" : time, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
//       ],
//     );
//   }
//
//   Widget _buildEmptyState() {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(Icons.calendar_today_outlined, size: 50, color: Colors.grey.shade300),
//           const SizedBox(height: 10),
//           Text("No records found", style: TextStyle(color: Colors.grey.shade500)),
//         ],
//       ),
//     );
//   }
// }