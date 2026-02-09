import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import 'attendance_history_screen.dart';

class AllEmployeesAttendanceList extends StatefulWidget {
  const AllEmployeesAttendanceList({super.key});

  @override
  State<AllEmployeesAttendanceList> createState() => _AllEmployeesAttendanceListState();
}

class _AllEmployeesAttendanceListState extends State<AllEmployeesAttendanceList> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _finalList = [];
  bool _isLoading = true;

  DateTime _selectedDate = DateTime.now();
  List<dynamic> _locations = [];
  String? _selectedLocationId;
  String _currentFilter = 'Total';

  // 🔴 MASTER MAP FOR DEPARTMENT IDs
  // Key: EmployeeID, Value: DepartmentID
  Map<String, String> _employeeDepartmentMap = {};

  // Stats
  int _totalStaff = 0;
  int _totalPresent = 0;
  int _totalLate = 0;
  int _totalAbsent = 0;

  final double _headerHeight = 330.0;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // 🔴 INITIALIZE ALL DATA
  void _initData() async {
    setState(() => _isLoading = true);

    // 1. Fetch Locations
    // 2. Fetch All Employees (To get Department IDs)
    try {
      await Future.wait([
        _fetchLocations(),
        _fetchEmployeeMap(),
      ]);

      // Data aane ke baad attendance fetch karo
      if (_selectedLocationId != null) {
        _fetchData(isBackground: false);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchLocations() async {
    try {
      var locs = await _apiService.getLocations();
      if (mounted) {
        setState(() {
          _locations = locs;
          if (_locations.isNotEmpty) {
            _selectedLocationId = _locations[0]['_id'];
          }
        });
      }
    } catch (e) {
      debugPrint("Loc Error: $e");
    }
  }

  // 🔴 FETCH ALL EMPLOYEES TO MAP DEPARTMENTS
  Future<void> _fetchEmployeeMap() async {
    try {
      var list = await _apiService.getAllEmployees();
      Map<String, String> tempMap = {};

      for (var emp in list) {
        String empId = emp['_id'] ?? emp['id'];
        String deptId = "";

        // Department Extract Logic
        if (emp['departmentId'] != null) {
          if (emp['departmentId'] is Map) {
            deptId = emp['departmentId']['_id'] ?? "";
          } else if (emp['departmentId'] is String) {
            deptId = emp['departmentId'];
          }
        }

        if (empId.isNotEmpty) {
          tempMap[empId] = deptId;
        }
      }

      if (mounted) {
        setState(() {
          _employeeDepartmentMap = tempMap;
        });
        print("✅ Employee Dept Map Loaded: ${tempMap.length} entries");
      }
    } catch (e) {
      debugPrint("Employee Map Error: $e");
    }
  }

  Future<void> _fetchData({bool isBackground = false}) async {
    if (_selectedLocationId == null) return;

    if (!isBackground) {
      setState(() => _isLoading = true);
    }

    try {
      String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      List<dynamic> apiData = await _apiService.getAttendanceByDateAndLocation(dateStr, _selectedLocationId!);

      List<Map<String, dynamic>> temp = [];
      int totalCount = 0, presentCount = 0, lateCount = 0, absentCount = 0;

      for (var item in apiData) {
        totalCount++;
        String name = item['name'] ?? "Unknown";
        String designation = item['designation'] ?? "Staff";
        String empId = item['employeeId'] ?? item['_id'] ?? "";

        // 🔴 1. TRY TO GET DEPT ID FROM API RESPONSE
        String deptId = "";
        if (item['departmentId'] != null) {
          if (item['departmentId'] is Map) {
            deptId = item['departmentId']['_id'] ?? "";
          } else if (item['departmentId'] is String) {
            deptId = item['departmentId'];
          }
        }

        // 🔴 2. FALLBACK: IF EMPTY, GET FROM MASTER MAP
        if (deptId.isEmpty && _employeeDepartmentMap.containsKey(empId)) {
          deptId = _employeeDepartmentMap[empId] ?? "";
        }

        var attendance = item['attendance'];
        String status = "Absent";
        String? checkIn;
        String? checkOut;
        bool isLate = false;

        if (attendance != null && attendance is Map) {
          checkIn = attendance['checkInTime'] ?? attendance['punchIn'];
          checkOut = attendance['checkOutTime'] ?? attendance['punchOut'];
          isLate = attendance['isLate'] == true;

          if (checkIn != null || attendance['faceEmbedding'] != null) {
            status = "Present";
            presentCount++;
            if (isLate) lateCount++;
          } else {
            status = "Absent";
            absentCount++;
          }
        } else {
          status = "Absent";
          absentCount++;
        }

        temp.add({
          '_id': empId,
          'name': name,
          'designation': designation,
          'departmentId': deptId, // 🔴 Passed Successfully
          'status': status,
          'checkIn': checkIn,
          'checkOut': checkOut,
          'isLate': isLate,
          'email': item['email'] ?? "",
        });
      }

      if (mounted) {
        setState(() {
          _finalList = temp;
          _totalStaff = totalCount;
          _totalPresent = presentCount;
          _totalLate = lateCount;
          _totalAbsent = absentCount;

          if (!isBackground) _isLoading = false;
          _currentFilter = 'Total';
        });
      }
    } catch (e) {
      if (mounted && !isBackground) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchData();
    }
  }

  String _formatSafeTime(String? val) {
    if (val == null || val.toString().isEmpty) return "--:--";
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(val).toLocal());
    } catch (_) { return val; }
  }

  List<Map<String, dynamic>> _getFilteredList() {
    if (_currentFilter == 'Present') return _finalList.where((e) => e['status'] == 'Present').toList();
    if (_currentFilter == 'Late') return _finalList.where((e) => e['isLate'] == true).toList();
    if (_currentFilter == 'Absent') return _finalList.where((e) => e['status'] == 'Absent').toList();
    return _finalList;
  }

  @override
  Widget build(BuildContext context) {
    String day = DateFormat('d').format(_selectedDate);
    String month = DateFormat('MMMM').format(_selectedDate);
    String year = DateFormat('yyyy').format(_selectedDate);
    String weekDay = DateFormat('EEEE').format(_selectedDate);

    // Filtered List
    List<Map<String, dynamic>> displayList = _getFilteredList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Stack(
        children: [
          // LAYER 1: LIST WITH PULL TO REFRESH
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
              : RefreshIndicator(
            onRefresh: () => _fetchData(isBackground: false),
            color: const Color(0xFF2E3192),
            edgeOffset: 340, // 🔴 Loader Header ke neeche aayega

            // 🔴 FIX: Empty Check
            child: displayList.isEmpty
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(top: _headerHeight + 50),
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off_rounded, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 15),
                      Text("No Attendance Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600))
                    ],
                  ),
                ),
              ],
            )
                : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, _headerHeight + 20, 16, 30),
              itemCount: displayList.length,
              itemBuilder: (context, index) {
                return _buildUltraModernCard(displayList[index]);
              },
            ),
          ),

          // LAYER 2: HEADER (Unchanged)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: _headerHeight,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF00D2FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(36), bottomRight: Radius.circular(36)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10), spreadRadius: -5)],
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 42, height: 42,
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              height: 42,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.2)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedLocationId,
                                  dropdownColor: const Color(0xFF2E3192),
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                                  hint: const Text("Select Location", style: TextStyle(color: Colors.white70)),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  items: _locations.map<DropdownMenuItem<String>>((dynamic loc) {
                                    return DropdownMenuItem<String>(value: loc['_id'], child: Text(loc['name'], overflow: TextOverflow.ellipsis));
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() => _selectedLocationId = val);
                                    _fetchData();
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // Date Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: _pickDate,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(day, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1)),
                                    const SizedBox(width: 8),
                                    Text(weekDay.substring(0,3).toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                Text("$month $year", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          // Export removed as per previous code
                        ],
                      ),

                      const SizedBox(height: 25),

                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildCompactStat("Total", _totalStaff.toString(), Colors.blue.shade800, 'Total'),
                            Container(width: 1, height: 25, color: Colors.grey.shade200),
                            _buildCompactStat("Present", _totalPresent.toString(), Colors.green.shade600, 'Present'),
                            Container(width: 1, height: 25, color: Colors.grey.shade200),
                            _buildCompactStat("Late", _totalLate.toString(), Colors.orange.shade700, 'Late'),
                            Container(width: 1, height: 25, color: Colors.grey.shade200),
                            _buildCompactStat("Absent", _totalAbsent.toString(), Colors.red.shade600, 'Absent'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(String label, String value, Color color, String filterKey) {
    bool isSelected = _currentFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _currentFilter = filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.08) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [Text(value, style: TextStyle(color: isSelected ? color : Colors.black87, fontSize: 19, fontWeight: FontWeight.w800)), Text(label, style: TextStyle(color: isSelected ? color : Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600))]),
      ),
    );
  }

  Widget _buildUltraModernCard(Map<String, dynamic> item) {
    String name = item['name'] ?? "Unknown";
    String designation = item['designation'] ?? "Staff";
    bool isPresent = item['status'] == 'Present';
    bool isLate = item['isLate'] ?? false;
    String inTime = isPresent && item['checkIn'] != null ? _formatSafeTime(item['checkIn']) : "--:--";
    String outTime = isPresent && item['checkOut'] != null ? _formatSafeTime(item['checkOut']) : "Working";
    Color statusColor = !isPresent ? const Color(0xFFFF4B4B) : (isLate ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6));

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10)]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(
                employeeName: name,
                employeeId: item['_id'],
                locationId: _selectedLocationId!,
                departmentId: item['departmentId'] ?? "", // 🔴 USING FETCHED/MAPPED DEPT ID
              )))
                  .then((_) => _fetchData(isBackground: false));
            },
            child: Row(
              children: [
                Container(width: 6, height: 90, color: statusColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      CircleAvatar(radius: 24, backgroundColor: const Color(0xFFF0F2F5), child: Text(name.isNotEmpty ? name[0] : "?", style: const TextStyle(fontWeight: FontWeight.bold))),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(designation, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (!isPresent)
                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text("ABSENT", style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)))
                        else ...[Text("In: $inTime", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)), Text(outTime == "Working" ? "Active" : outTime, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: outTime == "Working" ? Colors.green : Colors.black87))]
                      ])
                    ]),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}












// import 'dart:async';
// import 'dart:io';
// import 'dart:typed_data';
// import 'package:excel/excel.dart' hide Border;
// import 'package:file_saver/file_saver.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_file_dialog/flutter_file_dialog.dart';
// import 'package:intl/intl.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:share_plus/share_plus.dart';
// import '../../services/api_service.dart';
// import 'attendance_history_screen.dart';
//
// class AllEmployeesAttendanceList extends StatefulWidget {
//   const AllEmployeesAttendanceList({super.key});
//
//   @override
//   State<AllEmployeesAttendanceList> createState() => _AllEmployeesAttendanceListState();
// }
//
// class _AllEmployeesAttendanceListState extends State<AllEmployeesAttendanceList> {
//   final ApiService _apiService = ApiService();
//   List<Map<String, dynamic>> _finalList = [];
//   bool _isLoading = true;
//
//   bool _isExporting = false;
//   String _exportStatus = "";
//   double _exportProgress = 0.0;
//
//   DateTime _selectedDate = DateTime.now();
//   List<dynamic> _locations = [];
//   String? _selectedLocationId;
//   String _currentFilter = 'Total';
//
//   // Stats
//   int _totalStaff = 0;
//   int _totalPresent = 0;
//   int _totalLate = 0;
//   int _totalAbsent = 0;
//
//   final double _headerHeight = 330.0;
//
//   @override
//   void initState() {
//     super.initState();
//     _fetchLocations();
//   }
//
//   void _fetchLocations() async {
//     try {
//       var locs = await _apiService.getLocations();
//       if (mounted) {
//         setState(() {
//           _locations = locs;
//           if (_locations.isNotEmpty) {
//             _selectedLocationId = _locations[0]['_id'];
//           }
//         });
//         if (_selectedLocationId != null) {
//           _fetchData();
//         } else {
//           setState(() => _isLoading = false);
//         }
//       }
//     } catch (e) {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }
//
//   Future<void> _fetchData({bool isBackground = false}) async {
//     if (_selectedLocationId == null) return;
//
//     if (!isBackground) {
//       setState(() => _isLoading = true);
//     }
//
//     try {
//       String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
//       List<dynamic> apiData = await _apiService.getAttendanceByDateAndLocation(dateStr, _selectedLocationId!);
//
//       List<Map<String, dynamic>> temp = [];
//       int totalCount = 0, presentCount = 0, lateCount = 0, absentCount = 0;
//
//       for (var item in apiData) {
//         totalCount++;
//         String name = item['name'] ?? "Unknown";
//         String designation = item['designation'] ?? "Staff";
//         String empId = item['employeeId'] ?? "";
//         var attendance = item['attendance'];
//
//         String status = "Absent";
//         String? checkIn;
//         String? checkOut;
//         bool isLate = false;
//
//         if (attendance != null && attendance is Map) {
//           checkIn = attendance['checkInTime'] ?? attendance['punchIn'];
//           checkOut = attendance['checkOutTime'] ?? attendance['punchOut'];
//           isLate = attendance['isLate'] == true;
//
//           if (checkIn != null || attendance['faceEmbedding'] != null) {
//             status = "Present";
//             presentCount++;
//             if (isLate) lateCount++;
//           } else {
//             status = "Absent";
//             absentCount++;
//           }
//         } else {
//           status = "Absent";
//           absentCount++;
//         }
//
//         temp.add({
//           '_id': empId,
//           'name': name,
//           'designation': designation,
//           'status': status,
//           'checkIn': checkIn,
//           'checkOut': checkOut,
//           'isLate': isLate,
//           'email': item['email'] ?? "",
//         });
//       }
//
//       if (mounted) {
//         setState(() {
//           _finalList = temp;
//           _totalStaff = totalCount;
//           _totalPresent = presentCount;
//           _totalLate = lateCount;
//           _totalAbsent = absentCount;
//
//           if (!isBackground) _isLoading = false;
//           _currentFilter = 'Total';
//         });
//       }
//     } catch (e) {
//       if (mounted && !isBackground) setState(() => _isLoading = false);
//     }
//   }
//
//   Future<void> _processCustomRangeExport() async {
//     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Export feature disabled.")));
//   }
//
//   Future<void> _pickDate() async {
//     final DateTime? picked = await showDatePicker(
//       context: context,
//       initialDate: _selectedDate,
//       firstDate: DateTime(2020),
//       lastDate: DateTime.now(),
//       builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
//     );
//     if (picked != null && picked != _selectedDate) {
//       setState(() => _selectedDate = picked);
//       _fetchData();
//     }
//   }
//
//   String _formatSafeTime(String? val) {
//     if (val == null || val.toString().isEmpty) return "--:--";
//     try {
//       return DateFormat('hh:mm a').format(DateTime.parse(val).toLocal());
//     } catch (_) { return val; }
//   }
//
//   List<Map<String, dynamic>> _getFilteredList() {
//     if (_currentFilter == 'Present') return _finalList.where((e) => e['status'] == 'Present').toList();
//     if (_currentFilter == 'Late') return _finalList.where((e) => e['isLate'] == true).toList();
//     if (_currentFilter == 'Absent') return _finalList.where((e) => e['status'] == 'Absent').toList();
//     return _finalList;
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     String day = DateFormat('d').format(_selectedDate);
//     String month = DateFormat('MMMM').format(_selectedDate);
//     String year = DateFormat('yyyy').format(_selectedDate);
//     String weekDay = DateFormat('EEEE').format(_selectedDate);
//
//     // Filtered list nikal lo
//     List<Map<String, dynamic>> displayList = _getFilteredList();
//
//     return Scaffold(
//       backgroundColor: const Color(0xFFF5F7FA),
//       body: Stack(
//         children: [
//           // 🔴 LAYER 1: LIST (CRASH PROOF LOGIC)
//           _isLoading
//               ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
//               : RefreshIndicator(
//             onRefresh: () => _fetchData(isBackground: false),
//             color: const Color(0xFF2E3192),
//             edgeOffset: 340, // Header ke neeche loader
//
//             // 🔴 FIX: Yahan Check lagaya hai.
//             // Agar List khali hai to 'ListView' return karo (builder nahi).
//             // Agar Data hai to 'ListView.builder' return karo.
//             child: displayList.isEmpty
//                 ? ListView(
//               physics: const AlwaysScrollableScrollPhysics(), // Scroll chalu rakho refresh ke liye
//               padding: EdgeInsets.only(top: _headerHeight + 50),
//               children: [
//                 Center(
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Icon(Icons.person_off_rounded, size: 80, color: Colors.grey.shade300),
//                       const SizedBox(height: 15),
//                       Text("No Attendance Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600))
//                     ],
//                   ),
//                 )
//               ],
//             )
//                 : ListView.builder(
//               physics: const AlwaysScrollableScrollPhysics(),
//               padding: EdgeInsets.fromLTRB(16, _headerHeight + 20, 16, 30),
//               itemCount: displayList.length, // Ab ye kabhi 0 hone par crash nahi karega
//               itemBuilder: (context, index) {
//                 return _buildUltraModernCard(displayList[index]);
//               },
//             ),
//           ),
//
//           // LAYER 2: HEADER (Unchanged)
//           Positioned(
//             top: 0, left: 0, right: 0,
//             child: Container(
//               height: _headerHeight,
//               decoration: const BoxDecoration(
//                 gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF00D2FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
//                 borderRadius: BorderRadius.only(bottomLeft: Radius.circular(36), bottomRight: Radius.circular(36)),
//                 boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10), spreadRadius: -5)],
//               ),
//               child: SafeArea(
//                 bottom: false,
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         children: [
//                           GestureDetector(
//                             onTap: () => Navigator.pop(context),
//                             child: Container(
//                               width: 42, height: 42,
//                               decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
//                               child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Expanded(
//                             child: Container(
//                               height: 42,
//                               padding: const EdgeInsets.symmetric(horizontal: 16),
//                               decoration: BoxDecoration(
//                                 color: Colors.white.withOpacity(0.15),
//                                 borderRadius: BorderRadius.circular(12),
//                                 border: Border.all(color: Colors.white.withOpacity(0.2)),
//                               ),
//                               child: DropdownButtonHideUnderline(
//                                 child: DropdownButton<String>(
//                                   value: _selectedLocationId,
//                                   dropdownColor: const Color(0xFF2E3192),
//                                   icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
//                                   hint: const Text("Select Location", style: TextStyle(color: Colors.white70)),
//                                   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
//                                   items: _locations.map<DropdownMenuItem<String>>((dynamic loc) {
//                                     return DropdownMenuItem<String>(value: loc['_id'], child: Text(loc['name'], overflow: TextOverflow.ellipsis));
//                                   }).toList(),
//                                   onChanged: (val) {
//                                     setState(() => _selectedLocationId = val);
//                                     _fetchData(isBackground: false);
//                                   },
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//
//                       const Spacer(),
//
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         crossAxisAlignment: CrossAxisAlignment.end,
//                         children: [
//                           GestureDetector(
//                             onTap: _pickDate,
//                             child: Column(
//                               crossAxisAlignment: CrossAxisAlignment.start,
//                               mainAxisSize: MainAxisSize.min,
//                               children: [
//                                 Row(
//                                   crossAxisAlignment: CrossAxisAlignment.baseline,
//                                   textBaseline: TextBaseline.alphabetic,
//                                   children: [
//                                     Text(day, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1)),
//                                     const SizedBox(width: 8),
//                                     Text(weekDay.substring(0,3).toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
//                                   ],
//                                 ),
//                                 Text("$month $year", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
//                               ],
//                             ),
//                           ),
//                           GestureDetector(
//                             onTap: _isExporting ? null : _processCustomRangeExport,
//                             child: Container(
//                               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
//                               decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
//                               child: Row(
//                                 children: [
//                                   const Icon(Icons.file_download_outlined, color: Color(0xFF2E3192), size: 20),
//                                   const SizedBox(width: 8),
//                                   const Text("Export", style: TextStyle(color: Color(0xFF2E3192), fontWeight: FontWeight.bold)),
//                                 ],
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//
//                       const SizedBox(height: 25),
//
//                       Container(
//                         padding: const EdgeInsets.symmetric(vertical: 16),
//                         decoration: BoxDecoration(
//                           color: Colors.white,
//                           borderRadius: BorderRadius.circular(24),
//                           boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))],
//                         ),
//                         child: Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                           children: [
//                             _buildCompactStat("Total", _totalStaff.toString(), Colors.blue.shade800, 'Total'),
//                             Container(width: 1, height: 25, color: Colors.grey.shade200),
//                             _buildCompactStat("Present", _totalPresent.toString(), Colors.green.shade600, 'Present'),
//                             Container(width: 1, height: 25, color: Colors.grey.shade200),
//                             _buildCompactStat("Late", _totalLate.toString(), Colors.orange.shade700, 'Late'),
//                             Container(width: 1, height: 25, color: Colors.grey.shade200),
//                             _buildCompactStat("Absent", _totalAbsent.toString(), Colors.red.shade600, 'Absent'),
//                           ],
//                         ),
//                       ),
//                       const SizedBox(height: 10),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildCompactStat(String label, String value, Color color, String filterKey) {
//     bool isSelected = _currentFilter == filterKey;
//     return InkWell(
//       onTap: () => setState(() => _currentFilter = filterKey),
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
//         decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.08) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
//         child: Column(children: [Text(value, style: TextStyle(color: isSelected ? color : Colors.black87, fontSize: 19, fontWeight: FontWeight.w800)), Text(label, style: TextStyle(color: isSelected ? color : Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600))]),
//       ),
//     );
//   }
//
//   Widget _buildUltraModernCard(Map<String, dynamic> item) {
//     String name = item['name'] ?? "Unknown";
//     String designation = item['designation'] ?? "Staff";
//     bool isPresent = item['status'] == 'Present';
//     bool isLate = item['isLate'] ?? false;
//     String inTime = isPresent && item['checkIn'] != null ? _formatSafeTime(item['checkIn']) : "--:--";
//     String outTime = isPresent && item['checkOut'] != null ? _formatSafeTime(item['checkOut']) : "Working";
//     Color statusColor = !isPresent ? const Color(0xFFFF4B4B) : (isLate ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6));
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 14),
//       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10)]),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(18),
//         child: Material(
//           color: Colors.transparent,
//           child: InkWell(
//             onTap: () {
//               Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(employeeName: name, employeeId: item['_id'], locationId: _selectedLocationId!)))
//                   .then((_) => _fetchData(isBackground: false));
//             },
//             child: Row(
//               children: [
//                 Container(width: 6, height: 90, color: statusColor),
//                 Expanded(
//                   child: Padding(
//                     padding: const EdgeInsets.all(14),
//                     child: Row(children: [
//                       CircleAvatar(radius: 24, backgroundColor: const Color(0xFFF0F2F5), child: Text(name.isNotEmpty ? name[0] : "?", style: const TextStyle(fontWeight: FontWeight.bold))),
//                       const SizedBox(width: 14),
//                       Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(designation, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))])),
//                       Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
//                         if (!isPresent)
//                           Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text("ABSENT", style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)))
//                         else ...[Text("In: $inTime", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)), Text(outTime == "Working" ? "Active" : outTime, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: outTime == "Working" ? Colors.green : Colors.black87))]
//                       ])
//                     ]),
//                   ),
//                 )
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
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
// // import 'dart:io';
// // import 'dart:typed_data';
// // import 'package:excel/excel.dart' hide Border;
// // import 'package:file_saver/file_saver.dart';
// // import 'package:flutter/material.dart';
// // import 'package:flutter_file_dialog/flutter_file_dialog.dart';
// // import 'package:intl/intl.dart';
// // import 'package:path_provider/path_provider.dart';
// // import 'package:share_plus/share_plus.dart';
// // import '../../services/api_service.dart';
// // import 'attendance_history_screen.dart';
// //
// // class AllEmployeesAttendanceList extends StatefulWidget {
// //   const AllEmployeesAttendanceList({super.key});
// //
// //   @override
// //   State<AllEmployeesAttendanceList> createState() => _AllEmployeesAttendanceListState();
// // }
// //
// // class _AllEmployeesAttendanceListState extends State<AllEmployeesAttendanceList> {
// //   final ApiService _apiService = ApiService();
// //   List<Map<String, dynamic>> _finalList = [];
// //   bool _isLoading = true;
// //
// //   bool _isExporting = false;
// //   String _exportStatus = "";
// //   double _exportProgress = 0.0;
// //
// //   DateTime _selectedDate = DateTime.now();
// //   List<dynamic> _locations = [];
// //   String? _selectedLocationId;
// //   String _currentFilter = 'Total';
// //
// //   // Stats
// //   int _totalStaff = 0;
// //   int _totalPresent = 0;
// //   int _totalLate = 0;
// //   int _totalAbsent = 0;
// //
// //   // Constants for UI Layout
// //   final double _headerHeight = 330.0; // Fixed height for the header
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _fetchLocations();
// //   }
// //
// //   void _fetchLocations() async {
// //     try {
// //       var locs = await _apiService.getLocations();
// //       if (mounted) {
// //         setState(() {
// //           _locations = locs;
// //           if (_locations.isNotEmpty) {
// //             _selectedLocationId = _locations[0]['_id'];
// //           }
// //         });
// //         if (_selectedLocationId != null) {
// //           _fetchData();
// //         } else {
// //           setState(() => _isLoading = false);
// //         }
// //       }
// //     } catch (e) {
// //       if (mounted) {
// //         setState(() => _isLoading = false);
// //         // 🔴 FIX: Error dikhana zaruri hai
// //         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to load locations: $e")));
// //       }
// //     }
// //   }
// //
// //   void _fetchData() async {
// //     if (_selectedLocationId == null) return;
// //     setState(() => _isLoading = true);
// //     try {
// //       String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
// //       List<dynamic> apiData = await _apiService.getAttendanceByDateAndLocation(dateStr, _selectedLocationId!);
// //
// //       List<Map<String, dynamic>> temp = [];
// //       int totalCount = 0, presentCount = 0, lateCount = 0, absentCount = 0;
// //
// //       for (var item in apiData) {
// //         totalCount++;
// //         String name = item['name'] ?? "Unknown";
// //         String designation = item['designation'] ?? "Staff";
// //         String empId = item['employeeId'] ?? "";
// //         var attendance = item['attendance'];
// //
// //         String status = "Absent";
// //         String? checkIn;
// //         String? checkOut;
// //         bool isLate = false;
// //
// //         if (attendance != null && attendance is Map) {
// //           checkIn = attendance['checkInTime'] ?? attendance['punchIn'];
// //           checkOut = attendance['checkOutTime'] ?? attendance['punchOut'];
// //           // 🔴 IMP: Checking Late Status from API
// //           isLate = attendance['isLate'] == true;
// //
// //           if (checkIn != null || attendance['faceEmbedding'] != null) {
// //             status = "Present";
// //             presentCount++;
// //             if (isLate) lateCount++;
// //           } else {
// //             status = "Absent";
// //             absentCount++;
// //           }
// //         } else {
// //           status = "Absent";
// //           absentCount++;
// //         }
// //
// //         temp.add({
// //           '_id': empId,
// //           'name': name,
// //           'designation': designation,
// //           'status': status,
// //           'checkIn': checkIn,
// //           'checkOut': checkOut,
// //           'isLate': isLate, // Saving Late status
// //           'email': item['email'] ?? "",
// //         });
// //       }
// //
// //       if (mounted) {
// //         setState(() {
// //           _finalList = temp;
// //           _totalStaff = totalCount;
// //           _totalPresent = presentCount;
// //           _totalLate = lateCount;
// //           _totalAbsent = absentCount;
// //           _isLoading = false;
// //           _currentFilter = 'Total';
// //         });
// //       }
// //     } catch (e) {
// //       if (mounted) {
// //         setState(() => _isLoading = false);
// //         // 🔴 FIX: Error handling
// //         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to load data. Check internet.")));
// //       }
// //     }
// //   }
// //
// //   // 🔴🔴 EXPORT FUNCTION 🔴🔴
// //   // Future<void> _processCustomRangeExport() async {
// //   //   if (_selectedLocationId == null || _finalList.isEmpty) {
// //   //     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to export")));
// //   //     return;
// //   //   }
// //   //
// //   //   // 1. DATE PICKER
// //   //   final DateTimeRange? pickedRange = await showDateRangePicker(
// //   //     context: context,
// //   //     firstDate: DateTime(2023),
// //   //     lastDate: DateTime.now(),
// //   //     builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
// //   //   );
// //   //
// //   //   if (pickedRange == null) return;
// //   //
// //   //   setState(() {
// //   //     _isExporting = true;
// //   //     _exportStatus = "Initializing...";
// //   //     _exportProgress = 0.0;
// //   //   });
// //   //
// //   //   try {
// //   //     var excel = Excel.createExcel();
// //   //     Sheet sheet = excel['Attendance Report'];
// //   //     excel.setDefaultSheet('Attendance Report');
// //   //
// //   //     DateTime startDate = pickedRange.start;
// //   //     DateTime endDate = pickedRange.end;
// //   //     int totalDays = endDate.difference(startDate).inDays + 1;
// //   //
// //   //     // 🔄 LOOP THROUGH EMPLOYEES
// //   //     for (int i = 0; i < _finalList.length; i++) {
// //   //       var emp = _finalList[i];
// //   //       String empId = emp['_id'];
// //   //       String empName = emp['name'];
// //   //       String empEmail = emp['email'] ?? "N/A";
// //   //       String empDesig = emp['designation'] ?? "N/A";
// //   //
// //   //       // 🧠 SMART LOGIC: Identify which months are involved
// //   //       Set<String> monthsToFetch = {};
// //   //       DateTime loopDate = startDate;
// //   //       while (loopDate.isBefore(endDate) || loopDate.isAtSameMomentAs(endDate)) {
// //   //         monthsToFetch.add(DateFormat('MM-yyyy').format(loopDate));
// //   //         loopDate = DateTime(loopDate.year, loopDate.month + 1, 1); // Move to next month
// //   //       }
// //   //
// //   //       // 📦 CONTAINER FOR ALL DATA (Merged)
// //   //       Map<String, dynamic> mergedAttendanceMap = {};
// //   //
// //   //       // 📡 API CALL LOOP
// //   //       for (String monthStr in monthsToFetch) {
// //   //         if (mounted) {
// //   //           setState(() {
// //   //             _exportStatus = "Fetching $empName ($monthStr)";
// //   //             _exportProgress = (i + 1) / _finalList.length;
// //   //           });
// //   //         }
// //   //
// //   //         Map<String, dynamic>? reportData = await _apiService.getMonthlyReport(
// //   //             empId,
// //   //             monthStr,
// //   //             _selectedLocationId!
// //   //         );
// //   //
// //   //         if (reportData != null && reportData['attendance'] is List) {
// //   //           int m = int.parse(monthStr.split('-')[0]);
// //   //           int y = int.parse(monthStr.split('-')[1]);
// //   //
// //   //           for (var item in reportData['attendance']) {
// //   //             int? d = item['day'];
// //   //             if (d != null) {
// //   //               String dateKey = "$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}";
// //   //               mergedAttendanceMap[dateKey] = item;
// //   //             }
// //   //           }
// //   //         }
// //   //       }
// //   //
// //   //       // --- EXCEL WRITING ---
// //   //       sheet.appendRow([
// //   //         TextCellValue("ID: $empId"),
// //   //         TextCellValue("Name: $empName"),
// //   //         TextCellValue("Email: $empEmail"),
// //   //         TextCellValue("Designation: $empDesig"),
// //   //       ]);
// //   //
// //   //       List<CellValue> daysRow = [TextCellValue("Date")];
// //   //       for (int d = 0; d < totalDays; d++) {
// //   //         DateTime date = startDate.add(Duration(days: d));
// //   //         daysRow.add(TextCellValue(DateFormat('dd-MMM').format(date)));
// //   //       }
// //   //       sheet.appendRow(daysRow);
// //   //
// //   //       List<CellValue> arrRow = [TextCellValue("Arr Time")];
// //   //       List<CellValue> depRow = [TextCellValue("Dep Time")];
// //   //       List<CellValue> workRow = [TextCellValue("Working Hrs")];
// //   //       List<CellValue> otRow = [TextCellValue("Over Time")];
// //   //       List<CellValue> statusRow = [TextCellValue("Status")];
// //   //
// //   //       for (int d = 0; d < totalDays; d++) {
// //   //         DateTime date = startDate.add(Duration(days: d));
// //   //         String lookupKey = DateFormat('yyyy-MM-dd').format(date);
// //   //
// //   //         String arr = "0";
// //   //         String dep = "0";
// //   //         String work = "0";
// //   //         String ot = "0";
// //   //         String status = "A";
// //   //
// //   //         if (mergedAttendanceMap.containsKey(lookupKey)) {
// //   //           var dayObj = mergedAttendanceMap[lookupKey];
// //   //           var innerData = dayObj['data'];
// //   //           String? note = dayObj['note'];
// //   //
// //   //           if (note != null && note.isNotEmpty) {
// //   //             if (note.toLowerCase().contains("sunday")) status = "S";
// //   //             else if (note.toLowerCase().contains("holiday")) status = "H";
// //   //           }
// //   //
// //   //           if (innerData != null && innerData is Map && innerData.isNotEmpty) {
// //   //             arr = (innerData['punchIn'] ?? innerData['checkInTime'] ?? "0").toString();
// //   //             dep = (innerData['punchOut'] ?? innerData['checkOutTime'] ?? "0").toString();
// //   //             work = (innerData['duration'] ?? innerData['workingHours'] ?? "0").toString();
// //   //             ot = (innerData['overtime'] ?? "0").toString();
// //   //             if (arr != "0" && arr != "") status = "P";
// //   //           }
// //   //         }
// //   //
// //   //         arrRow.add(TextCellValue(arr));
// //   //         depRow.add(TextCellValue(dep));
// //   //         workRow.add(TextCellValue(work));
// //   //         otRow.add(TextCellValue(ot));
// //   //         statusRow.add(TextCellValue(status));
// //   //       }
// //   //
// //   //       sheet.appendRow(arrRow);
// //   //       sheet.appendRow(depRow);
// //   //       sheet.appendRow(workRow);
// //   //       sheet.appendRow(otRow);
// //   //       sheet.appendRow(statusRow);
// //   //       sheet.appendRow([TextCellValue("")]);
// //   //     }
// //   //
// //   //     setState(() => _exportStatus = "Saving...");
// //   //     var fileBytes = excel.save();
// //   //     String fileName = "Attendance_${DateFormat('ddMM').format(startDate)}_to_${DateFormat('ddMM').format(endDate)}.xlsx";
// //   //
// //   //     if (fileBytes != null) {
// //   //       Uint8List bytes = Uint8List.fromList(fileBytes);
// //   //       if(mounted) {
// //   //         setState(() => _isExporting = false);
// //   //         _showSuccessDialog(bytes, fileName);
// //   //       }
// //   //     }
// //   //
// //   //   } catch (e) {
// //   //     debugPrint("Export Error: $e");
// //   //     if (mounted) {
// //   //       setState(() => _isExporting = false);
// //   //       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
// //   //     }
// //   //   }
// //   // }
// //
// //
// //   Future<void> _processCustomRangeExport() async {
// //     if (_selectedLocationId == null || _finalList.isEmpty) {
// //       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to export")));
// //       return;
// //     }
// //
// //     // 1. DATE PICKER
// //     final DateTimeRange? pickedRange = await showDateRangePicker(
// //       context: context,
// //       firstDate: DateTime(2023),
// //       lastDate: DateTime.now(),
// //       builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
// //     );
// //
// //     if (pickedRange == null) return;
// //
// //     setState(() {
// //       _isExporting = true;
// //       _exportStatus = "Initializing...";
// //       _exportProgress = 0.0;
// //     });
// //
// //     try {
// //       var excel = Excel.createExcel();
// //       Sheet sheet = excel['Attendance Report'];
// //       excel.setDefaultSheet('Attendance Report');
// //
// //       DateTime startDate = pickedRange.start;
// //       DateTime endDate = pickedRange.end;
// //       int totalDays = endDate.difference(startDate).inDays + 1;
// //
// //       // 🔄 LOOP THROUGH EMPLOYEES
// //       for (int i = 0; i < _finalList.length; i++) {
// //         var emp = _finalList[i];
// //         String empId = emp['_id'];
// //         String empName = emp['name'];
// //         String empEmail = emp['email'] ?? "N/A";
// //         String empDesig = emp['designation'] ?? "N/A";
// //
// //         // 🧠 MONTH CALCULATION
// //         Set<String> monthsToFetch = {};
// //         DateTime loopDate = startDate;
// //         while (loopDate.isBefore(endDate) || loopDate.isAtSameMomentAs(endDate)) {
// //           monthsToFetch.add(DateFormat('MM-yyyy').format(loopDate));
// //           loopDate = DateTime(loopDate.year, loopDate.month + 1, 1);
// //         }
// //
// //         // 📦 DATA CONTAINER
// //         Map<String, dynamic> mergedAttendanceMap = {};
// //
// //         // 📡 API CALLS
// //         for (String monthStr in monthsToFetch) {
// //           if (mounted) {
// //             setState(() {
// //               _exportStatus = "Fetching $empName ($monthStr)";
// //               _exportProgress = (i + 1) / _finalList.length;
// //             });
// //           }
// //
// //           Map<String, dynamic>? reportData = await _apiService.getMonthlyReport(
// //               empId,
// //               monthStr,
// //               _selectedLocationId!
// //           );
// //
// //           if (reportData != null && reportData['attendance'] is List) {
// //             int m = int.parse(monthStr.split('-')[0]);
// //             int y = int.parse(monthStr.split('-')[1]);
// //
// //             for (var item in reportData['attendance']) {
// //               int? d = item['day'];
// //               if (d != null) {
// //                 String dateKey = "$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}";
// //                 mergedAttendanceMap[dateKey] = item;
// //               }
// //             }
// //           }
// //         }
// //
// //         // --- EXCEL HEADER ---
// //         sheet.appendRow([
// //           TextCellValue("ID: $empId"),
// //           TextCellValue("Name: $empName"),
// //           TextCellValue("Email: $empEmail"),
// //           TextCellValue("Designation: $empDesig"),
// //         ]);
// //
// //         List<CellValue> daysRow = [TextCellValue("Date")];
// //         for (int d = 0; d < totalDays; d++) {
// //           DateTime date = startDate.add(Duration(days: d));
// //           daysRow.add(TextCellValue(DateFormat('dd-MMM').format(date)));
// //         }
// //         sheet.appendRow(daysRow);
// //
// //         List<CellValue> arrRow = [TextCellValue("Arr Time")];
// //         List<CellValue> depRow = [TextCellValue("Dep Time")];
// //         List<CellValue> workRow = [TextCellValue("Working Hrs")];
// //         List<CellValue> otRow = [TextCellValue("Over Time")];
// //         List<CellValue> statusRow = [TextCellValue("Status")];
// //
// //         // 🔴🔴 DATA FILLING LOOP (Backend Logic) 🔴🔴
// //         for (int d = 0; d < totalDays; d++) {
// //           DateTime date = startDate.add(Duration(days: d));
// //           String lookupKey = DateFormat('yyyy-MM-dd').format(date);
// //
// //           // Default values = Empty (Backend se nahi aaya to khali rakho)
// //           String arr = "0";
// //           String dep = "0";
// //           String work = "0";
// //           String ot = "0";
// //           String status = "A"; // Default fallback (Last else case)
// //
// //           if (mergedAttendanceMap.containsKey(lookupKey)) {
// //             var dayObj = mergedAttendanceMap[lookupKey];
// //             var innerData = dayObj['data']; // Ye wo object hai jo aapne bheja
// //             String? note = dayObj['note'];
// //
// //             // --- 1. EXTRACT DATA DIRECTLY FROM BACKEND KEYS ---
// //             if (innerData != null && innerData is Map && innerData.isNotEmpty) {
// //               arr = (innerData['checkInTime'] ?? "").toString();
// //               dep = (innerData['checkOutTime'] ?? "").toString();
// //               work = (innerData['workingHours'] ?? "").toString();
// //               ot = (innerData['overtimeHours'] ?? "").toString(); // Backend key: overtimeHours
// //             }
// //
// //             // --- 2. STATUS LOGIC (Based on Angular Logic) ---
// //             int? backendStatus = (innerData != null && innerData['status'] != null)
// //                 ? innerData['status']
// //                 : null;
// //
// //             bool isLate = (innerData != null && innerData['isLate'] == true);
// //
// //             if (note == 'Sunday') {
// //               status = "S";
// //             } else if (backendStatus == 4) {
// //               status = "H";
// //             } else if (backendStatus == 3 || isLate) {
// //               status = "L";
// //             } else if (backendStatus == 1) {
// //               status = "P";
// //             } else if (backendStatus == 2) {
// //               status = "A";
// //             } else {
// //               status = "A"; // Agar data khali hai ya koi status match nahi hua
// //             }
// //           }
// //
// //           // Add to Excel Rows
// //           arrRow.add(TextCellValue(arr));
// //           depRow.add(TextCellValue(dep));
// //           workRow.add(TextCellValue(work));
// //           otRow.add(TextCellValue(ot));
// //           statusRow.add(TextCellValue(status));
// //         }
// //
// //         sheet.appendRow(arrRow);
// //         sheet.appendRow(depRow);
// //         sheet.appendRow(workRow);
// //         sheet.appendRow(otRow);
// //         sheet.appendRow(statusRow);
// //         sheet.appendRow([TextCellValue("")]); // Gap
// //       }
// //
// //       setState(() => _exportStatus = "Saving...");
// //       var fileBytes = excel.save();
// //       String fileName = "Attendance_${DateFormat('ddMM').format(startDate)}_to_${DateFormat('ddMM').format(endDate)}.xlsx";
// //
// //       if (fileBytes != null) {
// //         Uint8List bytes = Uint8List.fromList(fileBytes);
// //         if(mounted) {
// //           setState(() => _isExporting = false);
// //           _showSuccessDialog(bytes, fileName);
// //         }
// //       }
// //
// //     } catch (e) {
// //       debugPrint("Export Error: $e");
// //       if (mounted) {
// //         setState(() => _isExporting = false);
// //         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
// //       }
// //     }
// //   }
// //   void _showSuccessDialog(Uint8List bytes, String fileName) {
// //     showDialog(
// //       context: context,
// //       barrierDismissible: false,
// //       builder: (context) => AlertDialog(
// //         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
// //         title: Column(
// //           children: [
// //             const Icon(Icons.check_circle, color: Colors.green, size: 50),
// //             const SizedBox(height: 10),
// //             const Text("Report Ready!", style: TextStyle(fontWeight: FontWeight.bold)),
// //           ],
// //         ),
// //         content: const Text("Select an option below:", textAlign: TextAlign.center),
// //         actionsAlignment: MainAxisAlignment.center,
// //         actions: [
// //           ElevatedButton.icon(
// //             onPressed: () async {
// //               Navigator.pop(context);
// //               await _saveToDownloads(bytes, fileName);
// //             },
// //             icon: const Icon(Icons.save_alt, size: 18),
// //             label: const Text("Save As"),
// //             style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
// //           ),
// //           ElevatedButton.icon(
// //             onPressed: () async {
// //               Navigator.pop(context);
// //               await _shareFile(bytes, fileName);
// //             },
// //             icon: const Icon(Icons.share, size: 18),
// //             label: const Text("Share"),
// //             style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3192), foregroundColor: Colors.white),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   Future<void> _saveToDownloads(Uint8List bytes, String fileName) async {
// //     try {
// //       final dir = await getTemporaryDirectory();
// //       final tempFile = File('${dir.path}/$fileName');
// //       await tempFile.writeAsBytes(bytes);
// //
// //       final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
// //       final filePath = await FlutterFileDialog.saveFile(params: params);
// //
// //       if (mounted && filePath != null) {
// //         ScaffoldMessenger.of(context).showSnackBar(
// //             const SnackBar(content: Text("Saved Successfully!"), backgroundColor: Colors.green)
// //         );
// //       }
// //     } catch (e) {
// //       print("Save Error: $e");
// //     }
// //   }
// //
// //   Future<void> _shareFile(Uint8List bytes, String name) async {
// //     try {
// //       final tempDir = await getTemporaryDirectory();
// //       final file = File('${tempDir.path}/$name');
// //       await file.writeAsBytes(bytes);
// //       await Share.shareXFiles([XFile(file.path)], text: 'Attendance Report');
// //     } catch (e) {
// //       debugPrint("Share Error: $e");
// //     }
// //   }
// //
// //   // Helpers
// //   List<Map<String, dynamic>> _getFilteredList() {
// //     if (_currentFilter == 'Present') return _finalList.where((e) => e['status'] == 'Present').toList();
// //     if (_currentFilter == 'Late') return _finalList.where((e) => e['isLate'] == true).toList();
// //     if (_currentFilter == 'Absent') return _finalList.where((e) => e['status'] == 'Absent').toList();
// //     return _finalList;
// //   }
// //
// //   Future<void> _pickDate() async {
// //     final DateTime? picked = await showDatePicker(
// //       context: context,
// //       initialDate: _selectedDate,
// //       firstDate: DateTime(2020),
// //       lastDate: DateTime.now(),
// //       builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
// //     );
// //     if (picked != null && picked != _selectedDate) {
// //       setState(() => _selectedDate = picked);
// //       _fetchData();
// //     }
// //   }
// //
// //   String _formatSafeTime(String? val) {
// //     if (val == null || val.toString().isEmpty) return "--:--";
// //     try {
// //       return DateFormat('hh:mm a').format(DateTime.parse(val).toLocal());
// //     } catch (_) { return val; }
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     String day = DateFormat('d').format(_selectedDate);
// //     String month = DateFormat('MMMM').format(_selectedDate);
// //     String year = DateFormat('yyyy').format(_selectedDate);
// //     String weekDay = DateFormat('EEEE').format(_selectedDate);
// //     List<Map<String, dynamic>> displayList = _getFilteredList();
// //
// //     return Scaffold(
// //       backgroundColor: const Color(0xFFF5F7FA), // Very light cool grey background
// //       body: Stack(
// //         children: [
// //           // ---------------------------------------------
// //           // LAYER 1: THE LIST (Scrolls behind header)
// //           // ---------------------------------------------
// //           _isLoading
// //               ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// //               : (displayList.isEmpty
// //               ? Center(child: Column(
// //             mainAxisAlignment: MainAxisAlignment.center,
// //             children: [
// //               Icon(Icons.person_off_rounded, size: 80, color: Colors.grey.shade300),
// //               const SizedBox(height: 15),
// //               Text("No Attendance Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600))
// //             ],
// //           ))
// //               : ListView.builder(
// //             // 🔴🔴 FIX: Reduced bottom padding from 100 to 30
// //             padding: EdgeInsets.fromLTRB(16, _headerHeight + 20, 16, 30),
// //             itemCount: displayList.length,
// //             itemBuilder: (context, index) => _buildUltraModernCard(displayList[index]),
// //           )),
// //
// //           // ---------------------------------------------
// //           // LAYER 2: THE FIXED HEADER
// //           // ---------------------------------------------
// //           Positioned(
// //             top: 0,
// //             left: 0,
// //             right: 0,
// //             child: Container(
// //               height: _headerHeight,
// //               decoration: const BoxDecoration(
// //                 gradient: LinearGradient(
// //                     colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
// //                     begin: Alignment.topLeft,
// //                     end: Alignment.bottomRight),
// //                 borderRadius: BorderRadius.only(
// //                     bottomLeft: Radius.circular(36),
// //                     bottomRight: Radius.circular(36)),
// //                 boxShadow: [
// //                   BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10), spreadRadius: -5)
// //                 ],
// //               ),
// //               child: SafeArea(
// //                 bottom: false,
// //                 child: Padding(
// //                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
// //                   child: Column(
// //                     crossAxisAlignment: CrossAxisAlignment.start,
// //                     children: [
// //                       // --- ROW 1: BACK & LOCATION ---
// //                       Row(
// //                         children: [
// //                           GestureDetector(
// //                             onTap: () => Navigator.pop(context),
// //                             child: Container(
// //                               width: 42, height: 42,
// //                               decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
// //                               child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
// //                             ),
// //                           ),
// //                           const SizedBox(width: 12),
// //                           Expanded(
// //                             child: Container(
// //                               height: 42,
// //                               padding: const EdgeInsets.symmetric(horizontal: 16),
// //                               decoration: BoxDecoration(
// //                                 color: Colors.white.withOpacity(0.15),
// //                                 borderRadius: BorderRadius.circular(12),
// //                                 border: Border.all(color: Colors.white.withOpacity(0.2)),
// //                               ),
// //                               child: DropdownButtonHideUnderline(
// //                                 child: DropdownButton<String>(
// //                                   value: _selectedLocationId,
// //                                   dropdownColor: const Color(0xFF2E3192),
// //                                   icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
// //                                   hint: const Text("Select Location", style: TextStyle(color: Colors.white70)),
// //                                   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
// //                                   items: _locations.map<DropdownMenuItem<String>>((dynamic loc) {
// //                                     return DropdownMenuItem<String>(value: loc['_id'], child: Text(loc['name'], overflow: TextOverflow.ellipsis));
// //                                   }).toList(),
// //                                   onChanged: (val) { setState(() => _selectedLocationId = val); _fetchData(); },
// //                                 ),
// //                               ),
// //                             ),
// //                           ),
// //                         ],
// //                       ),
// //
// //                       const Spacer(),
// //
// //                       // --- ROW 2: DATE & EXPORT BUTTON ---
// //                       Row(
// //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                         crossAxisAlignment: CrossAxisAlignment.end,
// //                         children: [
// //                           // Date Section
// //                           GestureDetector(
// //                             onTap: _pickDate,
// //                             child: Column(
// //                               crossAxisAlignment: CrossAxisAlignment.start,
// //                               mainAxisSize: MainAxisSize.min,
// //                               children: [
// //                                 Row(
// //                                   crossAxisAlignment: CrossAxisAlignment.baseline,
// //                                   textBaseline: TextBaseline.alphabetic,
// //                                   children: [
// //                                     Text(day, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1)),
// //                                     const SizedBox(width: 8),
// //                                     Text(weekDay.substring(0,3).toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
// //                                   ],
// //                                 ),
// //                                 Row(
// //                                   children: [
// //                                     Text("$month $year", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
// //                                     const SizedBox(width: 6),
// //                                     const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16)
// //                                   ],
// //                                 ),
// //                               ],
// //                             ),
// //                           ),
// //
// //                           // Export Button (Modern Pill Style)
// //                           GestureDetector(
// //                             onTap: _isExporting ? null : _processCustomRangeExport,
// //                             child: Container(
// //                               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
// //                               decoration: BoxDecoration(
// //                                 color: Colors.white,
// //                                 borderRadius: BorderRadius.circular(30),
// //                                 boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
// //                               ),
// //                               child: Row(
// //                                 mainAxisSize: MainAxisSize.min,
// //                                 children: _isExporting
// //                                     ? [
// //                                   SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, value: _exportProgress, color: const Color(0xFF2E3192))),
// //                                   const SizedBox(width: 10),
// //                                   Text("${(_exportProgress * 100).toInt()}%", style: const TextStyle(color: Color(0xFF2E3192), fontWeight: FontWeight.bold))
// //                                 ]
// //                                     : [
// //                                   const Icon(Icons.file_download_outlined, color: Color(0xFF2E3192), size: 20),
// //                                   const SizedBox(width: 8),
// //                                   const Text("Export", style: TextStyle(color: Color(0xFF2E3192), fontWeight: FontWeight.bold, fontSize: 14)),
// //                                 ],
// //                               ),
// //                             ),
// //                           ),
// //                         ],
// //                       ),
// //
// //                       if (_isExporting)
// //                         Align(
// //                             alignment: Alignment.centerRight,
// //                             child: Padding(
// //                               padding: const EdgeInsets.only(top: 4, right: 10),
// //                               child: Text(_exportStatus, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10)),
// //                             )
// //                         ),
// //
// //                       const SizedBox(height: 25),
// //
// //                       // --- ROW 3: STATS CARD (The "Floating" Dashboard) ---
// //                       Container(
// //                         padding: const EdgeInsets.symmetric(vertical: 16),
// //                         decoration: BoxDecoration(
// //                           color: Colors.white,
// //                           borderRadius: BorderRadius.circular(24),
// //                           boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))],
// //                         ),
// //                         child: Row(
// //                           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
// //                           children: [
// //                             _buildCompactStat("Total", _totalStaff.toString(), Colors.blue.shade800, 'Total'),
// //                             Container(width: 1, height: 25, color: Colors.grey.shade200),
// //                             _buildCompactStat("Present", _totalPresent.toString(), Colors.green.shade600, 'Present'),
// //                             Container(width: 1, height: 25, color: Colors.grey.shade200),
// //                             _buildCompactStat("Late", _totalLate.toString(), Colors.orange.shade700, 'Late'),
// //                             Container(width: 1, height: 25, color: Colors.grey.shade200),
// //                             _buildCompactStat("Absent", _totalAbsent.toString(), Colors.red.shade600, 'Absent'),
// //                           ],
// //                         ),
// //                       ),
// //                       const SizedBox(height: 10), // Bottom padding of header
// //                     ],
// //                   ),
// //                 ),
// //               ),
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   Widget _buildCompactStat(String label, String value, Color color, String filterKey) {
// //     bool isSelected = _currentFilter == filterKey;
// //     return InkWell(
// //       onTap: () => setState(() => _currentFilter = filterKey),
// //       child: Container(
// //         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
// //         decoration: BoxDecoration(
// //           color: isSelected ? color.withOpacity(0.08) : Colors.transparent,
// //           borderRadius: BorderRadius.circular(12),
// //         ),
// //         child: Column(
// //           mainAxisSize: MainAxisSize.min,
// //           children: [
// //             Text(value, style: TextStyle(color: isSelected ? color : Colors.black87, fontSize: 19, fontWeight: FontWeight.w800)),
// //             const SizedBox(height: 2),
// //             Text(label, style: TextStyle(color: isSelected ? color : Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600)),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// //
// //   // ---------------------------------------------
// //   // CARD DESIGN: Clean, Status Bar on Left
// //   // ---------------------------------------------
// //   Widget _buildUltraModernCard(Map<String, dynamic> item) {
// //     String name = item['name'] ?? "Unknown";
// //     String designation = item['designation'] ?? "Staff";
// //     bool isPresent = item['status'] == 'Present';
// //     bool isLate = item['isLate'] ?? false;
// //
// //     String inTime = isPresent && item['checkIn'] != null ? _formatSafeTime(item['checkIn']) : "--:--";
// //     String outTime = isPresent && item['checkOut'] != null ? _formatSafeTime(item['checkOut']) : "Working";
// //
// //     // Colors
// //     Color statusColor = !isPresent ? const Color(0xFFFF4B4B) : (isLate ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6));
// //     Color bgStatusColor = statusColor.withOpacity(0.08);
// //
// //     return Container(
// //       margin: const EdgeInsets.only(bottom: 14),
// //       decoration: BoxDecoration(
// //         color: Colors.white,
// //         borderRadius: BorderRadius.circular(18),
// //         boxShadow: [
// //           BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))
// //         ],
// //       ),
// //       child: ClipRRect(
// //         borderRadius: BorderRadius.circular(18),
// //         child: Material(
// //           color: Colors.transparent,
// //           child: InkWell(
// //             onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(employeeName: name, employeeId: item['_id'], locationId: _selectedLocationId!))),
// //             child: Row(
// //               children: [
// //                 // 1. Colored Status Strip (Left)
// //                 Container(
// //                   width: 6,
// //                   height: 90,
// //                   color: statusColor,
// //                 ),
// //
// //                 Expanded(
// //                   child: Padding(
// //                     padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
// //                     child: Row(
// //                       children: [
// //                         // 2. Avatar
// //                         CircleAvatar(
// //                           radius: 24,
// //                           backgroundColor: const Color(0xFFF0F2F5),
// //                           child: Text(
// //                             name.isNotEmpty ? name[0].toUpperCase() : "?",
// //                             style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700),
// //                           ),
// //                         ),
// //                         const SizedBox(width: 14),
// //
// //                         // 3. Name & Role
// //                         Expanded(
// //                           child: Column(
// //                             crossAxisAlignment: CrossAxisAlignment.start,
// //                             children: [
// //                               Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
// //                               const SizedBox(height: 4),
// //                               Text(designation, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
// //                             ],
// //                           ),
// //                         ),
// //
// //                         // 4. Time & Badge
// //                         Column(
// //                           crossAxisAlignment: CrossAxisAlignment.end,
// //                           children: [
// //                             if (!isPresent)
// //                               Container(
// //                                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
// //                                 decoration: BoxDecoration(color: bgStatusColor, borderRadius: BorderRadius.circular(8)),
// //                                 child: Text("ABSENT", style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
// //                               )
// //                             else ...[
// //                               // IN TIME
// //                               Row(
// //                                 children: [
// //                                   Text("In: ", style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
// //                                   Text(inTime, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
// //                                 ],
// //                               ),
// //                               const SizedBox(height: 4),
// //                               // OUT TIME
// //                               Row(
// //                                 children: [
// //                                   Text("Out: ", style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
// //                                   Text(
// //                                       outTime == "Working" ? "Active" : outTime,
// //                                       style: TextStyle(
// //                                           fontSize: 13,
// //                                           fontWeight: FontWeight.w700,
// //                                           color: outTime == "Working" ? Colors.green : Colors.black87
// //                                       )
// //                                   ),
// //                                 ],
// //                               ),
// //                             ],
// //
// //                             // Late Badge small
// //                             if (isLate && isPresent)
// //                               Padding(
// //                                 padding: const EdgeInsets.only(top: 4),
// //                                 child: Text("• LATE", style: TextStyle(color: Colors.orange.shade700, fontSize: 9, fontWeight: FontWeight.w900)),
// //                               )
// //                           ],
// //                         )
// //                       ],
// //                     ),
// //                   ),
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
// //
// //
// //
// //
// // // import 'dart:io';
// // // import 'dart:typed_data';
// // // import 'package:excel/excel.dart' hide Border;
// // // import 'package:file_saver/file_saver.dart';
// // // import 'package:flutter/material.dart';
// // // import 'package:flutter_file_dialog/flutter_file_dialog.dart';
// // // import 'package:intl/intl.dart';
// // // import 'package:path_provider/path_provider.dart';
// // // import 'package:share_plus/share_plus.dart';
// // // import '../../services/api_service.dart';
// // // import 'attendance_history_screen.dart';
// // //
// // // class AllEmployeesAttendanceList extends StatefulWidget {
// // //   const AllEmployeesAttendanceList({super.key});
// // //
// // //   @override
// // //   State<AllEmployeesAttendanceList> createState() => _AllEmployeesAttendanceListState();
// // // }
// // //
// // // class _AllEmployeesAttendanceListState extends State<AllEmployeesAttendanceList> {
// // //   final ApiService _apiService = ApiService();
// // //   List<Map<String, dynamic>> _finalList = [];
// // //   bool _isLoading = true;
// // //
// // //   bool _isExporting = false;
// // //   String _exportStatus = "";
// // //   double _exportProgress = 0.0;
// // //
// // //   DateTime _selectedDate = DateTime.now();
// // //   List<dynamic> _locations = [];
// // //   String? _selectedLocationId;
// // //   String _currentFilter = 'Total';
// // //
// // //   // Stats
// // //   int _totalStaff = 0;
// // //   int _totalPresent = 0;
// // //   int _totalLate = 0;
// // //   int _totalAbsent = 0;
// // //
// // //   // Constants for UI Layout
// // //   final double _headerHeight = 330.0; // Fixed height for the header
// // //
// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     _fetchLocations();
// // //   }
// // //
// // //   void _fetchLocations() async {
// // //     try {
// // //       var locs = await _apiService.getLocations();
// // //       if (mounted) {
// // //         setState(() {
// // //           _locations = locs;
// // //           if (_locations.isNotEmpty) {
// // //             _selectedLocationId = _locations[0]['_id'];
// // //           }
// // //         });
// // //         if (_selectedLocationId != null) {
// // //           _fetchData();
// // //         } else {
// // //           setState(() => _isLoading = false);
// // //         }
// // //       }
// // //     } catch (e) {
// // //       if (mounted) setState(() => _isLoading = false);
// // //     }
// // //   }
// // //
// // //   void _fetchData() async {
// // //     if (_selectedLocationId == null) return;
// // //     setState(() => _isLoading = true);
// // //     try {
// // //       String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
// // //       List<dynamic> apiData = await _apiService.getAttendanceByDateAndLocation(dateStr, _selectedLocationId!);
// // //
// // //       List<Map<String, dynamic>> temp = [];
// // //       int totalCount = 0, presentCount = 0, lateCount = 0, absentCount = 0;
// // //
// // //       for (var item in apiData) {
// // //         totalCount++;
// // //         String name = item['name'] ?? "Unknown";
// // //         String designation = item['designation'] ?? "Staff";
// // //         String empId = item['employeeId'] ?? "";
// // //         var attendance = item['attendance'];
// // //
// // //         String status = "Absent";
// // //         String? checkIn;
// // //         String? checkOut;
// // //         bool isLate = false;
// // //
// // //         if (attendance != null && attendance is Map) {
// // //           checkIn = attendance['checkInTime'] ?? attendance['punchIn'];
// // //           checkOut = attendance['checkOutTime'] ?? attendance['punchOut'];
// // //           // 🔴 IMP: Checking Late Status from API
// // //           isLate = attendance['isLate'] == true;
// // //
// // //           if (checkIn != null || attendance['faceEmbedding'] != null) {
// // //             status = "Present";
// // //             presentCount++;
// // //             if (isLate) lateCount++;
// // //           } else {
// // //             status = "Absent";
// // //             absentCount++;
// // //           }
// // //         } else {
// // //           status = "Absent";
// // //           absentCount++;
// // //         }
// // //
// // //         temp.add({
// // //           '_id': empId,
// // //           'name': name,
// // //           'designation': designation,
// // //           'status': status,
// // //           'checkIn': checkIn,
// // //           'checkOut': checkOut,
// // //           'isLate': isLate, // Saving Late status
// // //           'email': item['email'] ?? "",
// // //         });
// // //       }
// // //
// // //       if (mounted) {
// // //         setState(() {
// // //           _finalList = temp;
// // //           _totalStaff = totalCount;
// // //           _totalPresent = presentCount;
// // //           _totalLate = lateCount;
// // //           _totalAbsent = absentCount;
// // //           _isLoading = false;
// // //           _currentFilter = 'Total';
// // //         });
// // //       }
// // //     } catch (e) {
// // //       if (mounted) setState(() => _isLoading = false);
// // //     }
// // //   }
// // //
// // //   // 🔴🔴 SUPER UPDATED EXPORT FUNCTION (Handles Multiple Months) 🔴🔴
// // //   Future<void> _processCustomRangeExport() async {
// // //     if (_selectedLocationId == null || _finalList.isEmpty) {
// // //       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to export")));
// // //       return;
// // //     }
// // //
// // //     // 1. DATE PICKER
// // //     final DateTimeRange? pickedRange = await showDateRangePicker(
// // //       context: context,
// // //       firstDate: DateTime(2023),
// // //       lastDate: DateTime.now(),
// // //       builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
// // //     );
// // //
// // //     if (pickedRange == null) return;
// // //
// // //     setState(() {
// // //       _isExporting = true;
// // //       _exportStatus = "Initializing...";
// // //       _exportProgress = 0.0;
// // //     });
// // //
// // //     try {
// // //       var excel = Excel.createExcel();
// // //       Sheet sheet = excel['Attendance Report'];
// // //       excel.setDefaultSheet('Attendance Report');
// // //
// // //       DateTime startDate = pickedRange.start;
// // //       DateTime endDate = pickedRange.end;
// // //       int totalDays = endDate.difference(startDate).inDays + 1;
// // //
// // //       // 🔄 LOOP THROUGH EMPLOYEES
// // //       for (int i = 0; i < _finalList.length; i++) {
// // //         var emp = _finalList[i];
// // //         String empId = emp['_id'];
// // //         String empName = emp['name'];
// // //         String empEmail = emp['email'] ?? "N/A";
// // //         String empDesig = emp['designation'] ?? "N/A";
// // //
// // //         // 🧠 SMART LOGIC: Identify which months are involved
// // //         Set<String> monthsToFetch = {};
// // //         DateTime loopDate = startDate;
// // //         while (loopDate.isBefore(endDate) || loopDate.isAtSameMomentAs(endDate)) {
// // //           monthsToFetch.add(DateFormat('MM-yyyy').format(loopDate));
// // //           loopDate = DateTime(loopDate.year, loopDate.month + 1, 1); // Move to next month
// // //         }
// // //
// // //         // 📦 CONTAINER FOR ALL DATA (Merged)
// // //         Map<String, dynamic> mergedAttendanceMap = {};
// // //
// // //         // 📡 API CALL LOOP (Fetch data for ALL involved months)
// // //         for (String monthStr in monthsToFetch) {
// // //           if (mounted) {
// // //             setState(() {
// // //               _exportStatus = "Fetching $empName ($monthStr)";
// // //               _exportProgress = (i + 1) / _finalList.length;
// // //             });
// // //           }
// // //
// // //           Map<String, dynamic>? reportData = await _apiService.getMonthlyReport(
// // //               empId,
// // //               monthStr,
// // //               _selectedLocationId!
// // //           );
// // //
// // //           if (reportData != null && reportData['attendance'] is List) {
// // //             // Parse Month Year from "02-2026"
// // //             int m = int.parse(monthStr.split('-')[0]);
// // //             int y = int.parse(monthStr.split('-')[1]);
// // //
// // //             for (var item in reportData['attendance']) {
// // //               int? d = item['day'];
// // //               if (d != null) {
// // //                 // Create Key "2026-02-04"
// // //                 String dateKey = "$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}";
// // //                 mergedAttendanceMap[dateKey] = item;
// // //               }
// // //             }
// // //           }
// // //         }
// // //
// // //         // --- EXCEL WRITING START ---
// // //         sheet.appendRow([
// // //           TextCellValue("ID: $empId"),
// // //           TextCellValue("Name: $empName"),
// // //           TextCellValue("Email: $empEmail"),
// // //           TextCellValue("Designation: $empDesig"),
// // //         ]);
// // //
// // //         List<CellValue> daysRow = [TextCellValue("Date")];
// // //         for (int d = 0; d < totalDays; d++) {
// // //           DateTime date = startDate.add(Duration(days: d));
// // //           daysRow.add(TextCellValue(DateFormat('dd-MMM').format(date)));
// // //         }
// // //         sheet.appendRow(daysRow);
// // //
// // //         List<CellValue> arrRow = [TextCellValue("Arr Time")];
// // //         List<CellValue> depRow = [TextCellValue("Dep Time")];
// // //         List<CellValue> workRow = [TextCellValue("Working Hrs")];
// // //         List<CellValue> otRow = [TextCellValue("Over Time")];
// // //         List<CellValue> statusRow = [TextCellValue("Status")];
// // //
// // //         // --- FILL DATA FROM MERGED MAP ---
// // //         for (int d = 0; d < totalDays; d++) {
// // //           DateTime date = startDate.add(Duration(days: d));
// // //           String lookupKey = DateFormat('yyyy-MM-dd').format(date);
// // //
// // //           String arr = "0";
// // //           String dep = "0";
// // //           String work = "0";
// // //           String ot = "0";
// // //           String status = "A";
// // //
// // //           if (mergedAttendanceMap.containsKey(lookupKey)) {
// // //             var dayObj = mergedAttendanceMap[lookupKey];
// // //             var innerData = dayObj['data'];
// // //             String? note = dayObj['note'];
// // //
// // //             // 1. Status Priority: Note (Holiday) -> Data (Present)
// // //             if (note != null && note.isNotEmpty) {
// // //               if (note.toLowerCase().contains("sunday")) status = "S";
// // //               else if (note.toLowerCase().contains("holiday")) status = "H";
// // //             }
// // //
// // //             if (innerData != null && innerData is Map && innerData.isNotEmpty) {
// // //               // Data hai to overwrite kar do
// // //               arr = (innerData['punchIn'] ?? innerData['checkInTime'] ?? "0").toString();
// // //               dep = (innerData['punchOut'] ?? innerData['checkOutTime'] ?? "0").toString();
// // //               work = (innerData['duration'] ?? innerData['workingHours'] ?? "0").toString();
// // //               ot = (innerData['overtime'] ?? "0").toString();
// // //
// // //               if (arr != "0" && arr != "") status = "P";
// // //             }
// // //           }
// // //
// // //           arrRow.add(TextCellValue(arr));
// // //           depRow.add(TextCellValue(dep));
// // //           workRow.add(TextCellValue(work));
// // //           otRow.add(TextCellValue(ot));
// // //           statusRow.add(TextCellValue(status));
// // //         }
// // //
// // //         sheet.appendRow(arrRow);
// // //         sheet.appendRow(depRow);
// // //         sheet.appendRow(workRow);
// // //         sheet.appendRow(otRow);
// // //         sheet.appendRow(statusRow);
// // //         sheet.appendRow([TextCellValue("")]); // Gap
// // //       }
// // //
// // //       // 💾 SAVE
// // //       setState(() => _exportStatus = "Saving...");
// // //       var fileBytes = excel.save();
// // //       String fileName = "Attendance_${DateFormat('ddMM').format(startDate)}_to_${DateFormat('ddMM').format(endDate)}.xlsx";
// // //
// // //       if (fileBytes != null) {
// // //         Uint8List bytes = Uint8List.fromList(fileBytes);
// // //         if(mounted) {
// // //           setState(() => _isExporting = false);
// // //           _showSuccessDialog(bytes, fileName);
// // //         }
// // //       }
// // //
// // //     } catch (e) {
// // //       debugPrint("Export Error: $e");
// // //       if (mounted) {
// // //         setState(() => _isExporting = false);
// // //         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
// // //       }
// // //     }
// // //   }
// // //
// // //   void _showSuccessDialog(Uint8List bytes, String fileName) {
// // //     showDialog(
// // //       context: context,
// // //       barrierDismissible: false,
// // //       builder: (context) => AlertDialog(
// // //         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
// // //         title: Column(
// // //           children: [
// // //             const Icon(Icons.check_circle, color: Colors.green, size: 50),
// // //             const SizedBox(height: 10),
// // //             const Text("Report Ready!", style: TextStyle(fontWeight: FontWeight.bold)),
// // //           ],
// // //         ),
// // //         content: const Text("Select an option below:", textAlign: TextAlign.center),
// // //         actionsAlignment: MainAxisAlignment.center,
// // //         actions: [
// // //           ElevatedButton.icon(
// // //             onPressed: () async {
// // //               Navigator.pop(context);
// // //               await _saveToDownloads(bytes, fileName);
// // //             },
// // //             icon: const Icon(Icons.save_alt, size: 18),
// // //             label: const Text("Save As"),
// // //             style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
// // //           ),
// // //           ElevatedButton.icon(
// // //             onPressed: () async {
// // //               Navigator.pop(context);
// // //               await _shareFile(bytes, fileName);
// // //             },
// // //             icon: const Icon(Icons.share, size: 18),
// // //             label: const Text("Share"),
// // //             style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3192), foregroundColor: Colors.white),
// // //           ),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   Future<void> _saveToDownloads(Uint8List bytes, String fileName) async {
// // //     try {
// // //       final dir = await getTemporaryDirectory();
// // //       final tempFile = File('${dir.path}/$fileName');
// // //       await tempFile.writeAsBytes(bytes);
// // //
// // //       final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
// // //       final filePath = await FlutterFileDialog.saveFile(params: params);
// // //
// // //       if (mounted && filePath != null) {
// // //         ScaffoldMessenger.of(context).showSnackBar(
// // //             const SnackBar(content: Text("Saved Successfully!"), backgroundColor: Colors.green)
// // //         );
// // //       }
// // //     } catch (e) {
// // //       print("Save Error: $e");
// // //     }
// // //   }
// // //
// // //   Future<void> _shareFile(Uint8List bytes, String name) async {
// // //     try {
// // //       final tempDir = await getTemporaryDirectory();
// // //       final file = File('${tempDir.path}/$name');
// // //       await file.writeAsBytes(bytes);
// // //       await Share.shareXFiles([XFile(file.path)], text: 'Attendance Report');
// // //     } catch (e) {
// // //       debugPrint("Share Error: $e");
// // //     }
// // //   }
// // //
// // //   // Helpers
// // //   List<Map<String, dynamic>> _getFilteredList() {
// // //     if (_currentFilter == 'Present') return _finalList.where((e) => e['status'] == 'Present').toList();
// // //     if (_currentFilter == 'Late') return _finalList.where((e) => e['isLate'] == true).toList();
// // //     if (_currentFilter == 'Absent') return _finalList.where((e) => e['status'] == 'Absent').toList();
// // //     return _finalList;
// // //   }
// // //
// // //   Future<void> _pickDate() async {
// // //     final DateTime? picked = await showDatePicker(
// // //       context: context,
// // //       initialDate: _selectedDate,
// // //       firstDate: DateTime(2020),
// // //       lastDate: DateTime.now(),
// // //       builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
// // //     );
// // //     if (picked != null && picked != _selectedDate) {
// // //       setState(() => _selectedDate = picked);
// // //       _fetchData();
// // //     }
// // //   }
// // //
// // //   String _formatSafeTime(String? val) {
// // //     if (val == null || val.toString().isEmpty) return "--:--";
// // //     try {
// // //       return DateFormat('hh:mm a').format(DateTime.parse(val).toLocal());
// // //     } catch (_) { return val; }
// // //   }
// // //
// // //   @override
// // //   Widget build(BuildContext context) {
// // //     String day = DateFormat('d').format(_selectedDate);
// // //     String month = DateFormat('MMMM').format(_selectedDate);
// // //     String year = DateFormat('yyyy').format(_selectedDate);
// // //     String weekDay = DateFormat('EEEE').format(_selectedDate);
// // //     List<Map<String, dynamic>> displayList = _getFilteredList();
// // //
// // //     return Scaffold(
// // //       backgroundColor: const Color(0xFFF5F7FA), // Very light cool grey background
// // //       body: Stack(
// // //         children: [
// // //           // ---------------------------------------------
// // //           // LAYER 1: THE LIST (Scrolls behind header)
// // //           // ---------------------------------------------
// // //           _isLoading
// // //               ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// // //               : (displayList.isEmpty
// // //               ? Center(child: Column(
// // //             mainAxisAlignment: MainAxisAlignment.center,
// // //             children: [
// // //               Icon(Icons.person_off_rounded, size: 80, color: Colors.grey.shade300),
// // //               const SizedBox(height: 15),
// // //               Text("No Attendance Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600))
// // //             ],
// // //           ))
// // //               : ListView.builder(
// // //             // Key Fix: Padding Top = Header Height + Buffer
// // //             padding: EdgeInsets.fromLTRB(16, _headerHeight + 20, 16, 10),
// // //             itemCount: displayList.length,
// // //             itemBuilder: (context, index) => _buildUltraModernCard(displayList[index]),
// // //           )),
// // //
// // //           // ---------------------------------------------
// // //           // LAYER 2: THE FIXED HEADER
// // //           // ---------------------------------------------
// // //           Positioned(
// // //             top: 0,
// // //             left: 0,
// // //             right: 0,
// // //             child: Container(
// // //               height: _headerHeight,
// // //               decoration: const BoxDecoration(
// // //                 gradient: LinearGradient(
// // //                     colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
// // //                     begin: Alignment.topLeft,
// // //                     end: Alignment.bottomRight),
// // //                 borderRadius: BorderRadius.only(
// // //                     bottomLeft: Radius.circular(36),
// // //                     bottomRight: Radius.circular(36)),
// // //                 boxShadow: [
// // //                   BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10), spreadRadius: -5)
// // //                 ],
// // //               ),
// // //               child: SafeArea(
// // //                 bottom: false,
// // //                 child: Padding(
// // //                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
// // //                   child: Column(
// // //                     crossAxisAlignment: CrossAxisAlignment.start,
// // //                     children: [
// // //                       // --- ROW 1: BACK & LOCATION ---
// // //                       Row(
// // //                         children: [
// // //                           GestureDetector(
// // //                             onTap: () => Navigator.pop(context),
// // //                             child: Container(
// // //                               width: 42, height: 42,
// // //                               decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
// // //                               child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
// // //                             ),
// // //                           ),
// // //                           const SizedBox(width: 12),
// // //                           Expanded(
// // //                             child: Container(
// // //                               height: 42,
// // //                               padding: const EdgeInsets.symmetric(horizontal: 16),
// // //                               decoration: BoxDecoration(
// // //                                 color: Colors.white.withOpacity(0.15),
// // //                                 borderRadius: BorderRadius.circular(12),
// // //                                 border: Border.all(color: Colors.white.withOpacity(0.2)),
// // //                               ),
// // //                               child: DropdownButtonHideUnderline(
// // //                                 child: DropdownButton<String>(
// // //                                   value: _selectedLocationId,
// // //                                   dropdownColor: const Color(0xFF2E3192),
// // //                                   icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
// // //                                   hint: const Text("Select Location", style: TextStyle(color: Colors.white70)),
// // //                                   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
// // //                                   items: _locations.map<DropdownMenuItem<String>>((dynamic loc) {
// // //                                     return DropdownMenuItem<String>(value: loc['_id'], child: Text(loc['name'], overflow: TextOverflow.ellipsis));
// // //                                   }).toList(),
// // //                                   onChanged: (val) { setState(() => _selectedLocationId = val); _fetchData(); },
// // //                                 ),
// // //                               ),
// // //                             ),
// // //                           ),
// // //                         ],
// // //                       ),
// // //
// // //                       const Spacer(),
// // //
// // //                       // --- ROW 2: DATE & EXPORT BUTTON ---
// // //                       Row(
// // //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // //                         crossAxisAlignment: CrossAxisAlignment.end,
// // //                         children: [
// // //                           // Date Section
// // //                           GestureDetector(
// // //                             onTap: _pickDate,
// // //                             child: Column(
// // //                               crossAxisAlignment: CrossAxisAlignment.start,
// // //                               mainAxisSize: MainAxisSize.min,
// // //                               children: [
// // //                                 Row(
// // //                                   crossAxisAlignment: CrossAxisAlignment.baseline,
// // //                                   textBaseline: TextBaseline.alphabetic,
// // //                                   children: [
// // //                                     Text(day, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1)),
// // //                                     const SizedBox(width: 8),
// // //                                     Text(weekDay.substring(0,3).toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
// // //                                   ],
// // //                                 ),
// // //                                 Row(
// // //                                   children: [
// // //                                     Text("$month $year", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
// // //                                     const SizedBox(width: 6),
// // //                                     const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16)
// // //                                   ],
// // //                                 ),
// // //                               ],
// // //                             ),
// // //                           ),
// // //
// // //                           // Export Button (Modern Pill Style)
// // //                           GestureDetector(
// // //                             onTap: _isExporting ? null : _processCustomRangeExport,
// // //                             child: Container(
// // //                               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
// // //                               decoration: BoxDecoration(
// // //                                 color: Colors.white,
// // //                                 borderRadius: BorderRadius.circular(30),
// // //                                 boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
// // //                               ),
// // //                               child: Row(
// // //                                 mainAxisSize: MainAxisSize.min,
// // //                                 children: _isExporting
// // //                                     ? [
// // //                                   SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, value: _exportProgress, color: const Color(0xFF2E3192))),
// // //                                   const SizedBox(width: 10),
// // //                                   Text("${(_exportProgress * 100).toInt()}%", style: const TextStyle(color: Color(0xFF2E3192), fontWeight: FontWeight.bold))
// // //                                 ]
// // //                                     : [
// // //                                   const Icon(Icons.file_download_outlined, color: Colors.black, size: 20),
// // //                                   const SizedBox(width: 8),
// // //                                   const Text("Export", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
// // //                                 ],
// // //                               ),
// // //                             ),
// // //                           ),
// // //                         ],
// // //                       ),
// // //
// // //                       if (_isExporting)
// // //                         Align(
// // //                             alignment: Alignment.centerRight,
// // //                             child: Padding(
// // //                               padding: const EdgeInsets.only(top: 4, right: 10),
// // //                               child: Text(_exportStatus, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10)),
// // //                             )
// // //                         ),
// // //
// // //                       const SizedBox(height: 25),
// // //
// // //                       // --- ROW 3: STATS CARD (The "Floating" Dashboard) ---
// // //                       Container(
// // //                         padding: const EdgeInsets.symmetric(vertical: 16),
// // //                         decoration: BoxDecoration(
// // //                           color: Colors.white,
// // //                           borderRadius: BorderRadius.circular(24),
// // //                           boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))],
// // //                         ),
// // //                         child: Row(
// // //                           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
// // //                           children: [
// // //                             _buildCompactStat("Total", _totalStaff.toString(), Colors.blue.shade800, 'Total'),
// // //                             Container(width: 1, height: 25, color: Colors.grey.shade200),
// // //                             _buildCompactStat("Present", _totalPresent.toString(), Colors.green.shade600, 'Present'),
// // //                             Container(width: 1, height: 25, color: Colors.grey.shade200),
// // //                             _buildCompactStat("Late", _totalLate.toString(), Colors.orange.shade700, 'Late'),
// // //                             Container(width: 1, height: 25, color: Colors.grey.shade200),
// // //                             _buildCompactStat("Absent", _totalAbsent.toString(), Colors.red.shade600, 'Absent'),
// // //                           ],
// // //                         ),
// // //                       ),
// // //                       const SizedBox(height: 10), // Bottom padding of header
// // //                     ],
// // //                   ),
// // //                 ),
// // //               ),
// // //             ),
// // //           ),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   Widget _buildCompactStat(String label, String value, Color color, String filterKey) {
// // //     bool isSelected = _currentFilter == filterKey;
// // //     return InkWell(
// // //       onTap: () => setState(() => _currentFilter = filterKey),
// // //       child: Container(
// // //         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
// // //         decoration: BoxDecoration(
// // //           color: isSelected ? color.withOpacity(0.08) : Colors.transparent,
// // //           borderRadius: BorderRadius.circular(12),
// // //         ),
// // //         child: Column(
// // //           mainAxisSize: MainAxisSize.min,
// // //           children: [
// // //             Text(value, style: TextStyle(color: isSelected ? color : Colors.black87, fontSize: 19, fontWeight: FontWeight.w800)),
// // //             const SizedBox(height: 2),
// // //             Text(label, style: TextStyle(color: isSelected ? color : Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600)),
// // //           ],
// // //         ),
// // //       ),
// // //     );
// // //   }
// // //
// // //   // ---------------------------------------------
// // //   // CARD DESIGN: Clean, Status Bar on Left
// // //   // ---------------------------------------------
// // //   Widget _buildUltraModernCard(Map<String, dynamic> item) {
// // //     String name = item['name'] ?? "Unknown";
// // //     String designation = item['designation'] ?? "Staff";
// // //     bool isPresent = item['status'] == 'Present';
// // //     bool isLate = item['isLate'] ?? false;
// // //
// // //     String inTime = isPresent && item['checkIn'] != null ? _formatSafeTime(item['checkIn']) : "--:--";
// // //     String outTime = isPresent && item['checkOut'] != null ? _formatSafeTime(item['checkOut']) : "Working";
// // //
// // //     // Colors
// // //     Color statusColor = !isPresent ? const Color(0xFFFF4B4B) : (isLate ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6));
// // //     Color bgStatusColor = statusColor.withOpacity(0.08);
// // //
// // //     return Container(
// // //       margin: const EdgeInsets.only(bottom: 14),
// // //       decoration: BoxDecoration(
// // //         color: Colors.white,
// // //         borderRadius: BorderRadius.circular(18),
// // //         boxShadow: [
// // //           BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))
// // //         ],
// // //       ),
// // //       child: ClipRRect(
// // //         borderRadius: BorderRadius.circular(18),
// // //         child: Material(
// // //           color: Colors.transparent,
// // //           child: InkWell(
// // //             onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(employeeName: name, employeeId: item['_id'], locationId: _selectedLocationId!))),
// // //             child: Row(
// // //               children: [
// // //                 // 1. Colored Status Strip (Left)
// // //                 Container(
// // //                   width: 6,
// // //                   height: 90,
// // //                   color: statusColor,
// // //                 ),
// // //
// // //                 Expanded(
// // //                   child: Padding(
// // //                     padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
// // //                     child: Row(
// // //                       children: [
// // //                         // 2. Avatar
// // //                         CircleAvatar(
// // //                           radius: 24,
// // //                           backgroundColor: const Color(0xFFF0F2F5),
// // //                           child: Text(
// // //                             name.isNotEmpty ? name[0].toUpperCase() : "?",
// // //                             style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700),
// // //                           ),
// // //                         ),
// // //                         const SizedBox(width: 14),
// // //
// // //                         // 3. Name & Role
// // //                         Expanded(
// // //                           child: Column(
// // //                             crossAxisAlignment: CrossAxisAlignment.start,
// // //                             children: [
// // //                               Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
// // //                               const SizedBox(height: 4),
// // //                               Text(designation, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
// // //                             ],
// // //                           ),
// // //                         ),
// // //
// // //                         // 4. Time & Badge
// // //                         Column(
// // //                           crossAxisAlignment: CrossAxisAlignment.end,
// // //                           children: [
// // //                             if (!isPresent)
// // //                               Container(
// // //                                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
// // //                                 decoration: BoxDecoration(color: bgStatusColor, borderRadius: BorderRadius.circular(8)),
// // //                                 child: Text("ABSENT", style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
// // //                               )
// // //                             else ...[
// // //                               // IN TIME
// // //                               Row(
// // //                                 children: [
// // //                                   Text("In: ", style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
// // //                                   Text(inTime, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
// // //                                 ],
// // //                               ),
// // //                               const SizedBox(height: 4),
// // //                               // OUT TIME
// // //                               Row(
// // //                                 children: [
// // //                                   Text("Out: ", style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
// // //                                   Text(
// // //                                       outTime == "Working" ? "Active" : outTime,
// // //                                       style: TextStyle(
// // //                                           fontSize: 13,
// // //                                           fontWeight: FontWeight.w700,
// // //                                           color: outTime == "Working" ? Colors.green : Colors.black87
// // //                                       )
// // //                                   ),
// // //                                 ],
// // //                               ),
// // //                             ],
// // //
// // //                             // Late Badge small
// // //                             if (isLate && isPresent)
// // //                               Padding(
// // //                                 padding: const EdgeInsets.only(top: 4),
// // //                                 child: Text("• LATE", style: TextStyle(color: Colors.orange.shade700, fontSize: 9, fontWeight: FontWeight.w900)),
// // //                               )
// // //                           ],
// // //                         )
// // //                       ],
// // //                     ),
// // //                   ),
// // //                 )
// // //               ],
// // //             ),
// // //           ),
// // //         ),
// // //       ),
// // //     );
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
// // // // import 'dart:io';
// // // // import 'dart:typed_data';
// // // // import 'package:excel/excel.dart' hide Border;
// // // // import 'package:file_saver/file_saver.dart';
// // // // import 'package:flutter/material.dart';
// // // // import 'package:flutter_file_dialog/flutter_file_dialog.dart';
// // // // import 'package:intl/intl.dart';
// // // // import 'package:path_provider/path_provider.dart';
// // // // import 'package:share_plus/share_plus.dart';
// // // // import '../../services/api_service.dart';
// // // // import 'attendance_history_screen.dart';
// // // //
// // // // class AllEmployeesAttendanceList extends StatefulWidget {
// // // //   const AllEmployeesAttendanceList({super.key});
// // // //
// // // //   @override
// // // //   State<AllEmployeesAttendanceList> createState() => _AllEmployeesAttendanceListState();
// // // // }
// // // //
// // // // class _AllEmployeesAttendanceListState extends State<AllEmployeesAttendanceList> {
// // // //   final ApiService _apiService = ApiService();
// // // //   List<Map<String, dynamic>> _finalList = [];
// // // //   bool _isLoading = true;
// // // //
// // // //   bool _isExporting = false;
// // // //   String _exportStatus = "";
// // // //   double _exportProgress = 0.0;
// // // //
// // // //   DateTime _selectedDate = DateTime.now();
// // // //   List<dynamic> _locations = [];
// // // //   String? _selectedLocationId;
// // // //   String _currentFilter = 'Total';
// // // //
// // // //   int _totalStaff = 0;
// // // //   int _totalPresent = 0;
// // // //   int _totalLate = 0;
// // // //   int _totalAbsent = 0;
// // // //
// // // //   @override
// // // //   void initState() {
// // // //     super.initState();
// // // //     _fetchLocations();
// // // //   }
// // // //
// // // //   void _fetchLocations() async {
// // // //     try {
// // // //       var locs = await _apiService.getLocations();
// // // //       if (mounted) {
// // // //         setState(() {
// // // //           _locations = locs;
// // // //           if (_locations.isNotEmpty) {
// // // //             _selectedLocationId = _locations[0]['_id'];
// // // //           }
// // // //         });
// // // //         if (_selectedLocationId != null) {
// // // //           _fetchData();
// // // //         } else {
// // // //           setState(() => _isLoading = false);
// // // //         }
// // // //       }
// // // //     } catch (e) {
// // // //       if (mounted) setState(() => _isLoading = false);
// // // //     }
// // // //   }
// // // //
// // // //   void _fetchData() async {
// // // //     if (_selectedLocationId == null) return;
// // // //     setState(() => _isLoading = true);
// // // //     try {
// // // //       String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
// // // //       List<dynamic> apiData = await _apiService.getAttendanceByDateAndLocation(dateStr, _selectedLocationId!);
// // // //
// // // //       List<Map<String, dynamic>> temp = [];
// // // //       int totalCount = 0, presentCount = 0, lateCount = 0, absentCount = 0;
// // // //
// // // //       for (var item in apiData) {
// // // //         totalCount++;
// // // //         String name = item['name'] ?? "Unknown";
// // // //         String designation = item['designation'] ?? "Staff";
// // // //         String empId = item['employeeId'] ?? "";
// // // //         var attendance = item['attendance'];
// // // //
// // // //         String status = "Absent";
// // // //         String? checkIn;
// // // //         String? checkOut;
// // // //         bool isLate = false;
// // // //
// // // //         if (attendance != null && attendance is Map) {
// // // //           checkIn = attendance['checkInTime'] ?? attendance['punchIn'];
// // // //           checkOut = attendance['checkOutTime'] ?? attendance['punchOut'];
// // // //           isLate = attendance['isLate'] == true;
// // // //
// // // //           if (checkIn != null || attendance['faceEmbedding'] != null) {
// // // //             status = "Present";
// // // //             presentCount++;
// // // //             if (isLate) lateCount++;
// // // //           } else {
// // // //             status = "Absent";
// // // //             absentCount++;
// // // //           }
// // // //         } else {
// // // //           status = "Absent";
// // // //           absentCount++;
// // // //         }
// // // //
// // // //         temp.add({
// // // //           '_id': empId,
// // // //           'name': name,
// // // //           'designation': designation,
// // // //           'status': status,
// // // //           'checkIn': checkIn,
// // // //           'checkOut': checkOut,
// // // //           'isLate': isLate,
// // // //           'email': item['email'] ?? "",
// // // //         });
// // // //       }
// // // //
// // // //       if (mounted) {
// // // //         setState(() {
// // // //           _finalList = temp;
// // // //           _totalStaff = totalCount;
// // // //           _totalPresent = presentCount;
// // // //           _totalLate = lateCount;
// // // //           _totalAbsent = absentCount;
// // // //           _isLoading = false;
// // // //           _currentFilter = 'Total';
// // // //         });
// // // //       }
// // // //     } catch (e) {
// // // //       if (mounted) setState(() => _isLoading = false);
// // // //     }
// // // //   }
// // // //
// // // //   // 🔴🔴 CORRECTED EXPORT FUNCTION (Updated Parsing Logic) 🔴🔴
// // // //   // 🔴🔴 SUPER UPDATED EXPORT FUNCTION (Handles Multiple Months) 🔴🔴
// // // //   Future<void> _processCustomRangeExport() async {
// // // //     if (_selectedLocationId == null || _finalList.isEmpty) {
// // // //       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to export")));
// // // //       return;
// // // //     }
// // // //
// // // //     // 1. DATE PICKER
// // // //     final DateTimeRange? pickedRange = await showDateRangePicker(
// // // //       context: context,
// // // //       firstDate: DateTime(2023),
// // // //       lastDate: DateTime.now(),
// // // //       builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
// // // //     );
// // // //
// // // //     if (pickedRange == null) return;
// // // //
// // // //     setState(() {
// // // //       _isExporting = true;
// // // //       _exportStatus = "Initializing...";
// // // //       _exportProgress = 0.0;
// // // //     });
// // // //
// // // //     try {
// // // //       var excel = Excel.createExcel();
// // // //       Sheet sheet = excel['Attendance Report'];
// // // //       excel.setDefaultSheet('Attendance Report');
// // // //
// // // //       DateTime startDate = pickedRange.start;
// // // //       DateTime endDate = pickedRange.end;
// // // //       int totalDays = endDate.difference(startDate).inDays + 1;
// // // //
// // // //       // 🔄 LOOP THROUGH EMPLOYEES
// // // //       for (int i = 0; i < _finalList.length; i++) {
// // // //         var emp = _finalList[i];
// // // //         String empId = emp['_id'];
// // // //         String empName = emp['name'];
// // // //         String empEmail = emp['email'] ?? "N/A";
// // // //         String empDesig = emp['designation'] ?? "N/A";
// // // //
// // // //         // 🧠 SMART LOGIC: Identify which months are involved
// // // //         // Agar range Jan 28 se Feb 5 hai, to humein Jan aur Feb dono chahiye.
// // // //         Set<String> monthsToFetch = {};
// // // //         DateTime loopDate = startDate;
// // // //         while (loopDate.isBefore(endDate) || loopDate.isAtSameMomentAs(endDate)) {
// // // //           monthsToFetch.add(DateFormat('MM-yyyy').format(loopDate));
// // // //           loopDate = DateTime(loopDate.year, loopDate.month + 1, 1); // Move to next month
// // // //         }
// // // //
// // // //         // 📦 CONTAINER FOR ALL DATA (Merged)
// // // //         // Key: "yyyy-MM-dd", Value: Data Object
// // // //         Map<String, dynamic> mergedAttendanceMap = {};
// // // //
// // // //         // 📡 API CALL LOOP (Fetch data for ALL involved months)
// // // //         for (String monthStr in monthsToFetch) {
// // // //           if (mounted) {
// // // //             setState(() {
// // // //               _exportStatus = "Fetching $empName ($monthStr)";
// // // //               _exportProgress = (i + 1) / _finalList.length;
// // // //             });
// // // //           }
// // // //
// // // //           Map<String, dynamic>? reportData = await _apiService.getMonthlyReport(
// // // //               empId,
// // // //               monthStr,
// // // //               _selectedLocationId!
// // // //           );
// // // //
// // // //           if (reportData != null && reportData['attendance'] is List) {
// // // //             // Parse Month Year from "02-2026"
// // // //             int m = int.parse(monthStr.split('-')[0]);
// // // //             int y = int.parse(monthStr.split('-')[1]);
// // // //
// // // //             for (var item in reportData['attendance']) {
// // // //               int? d = item['day'];
// // // //               if (d != null) {
// // // //                 // Create Key "2026-02-04"
// // // //                 String dateKey = "$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}";
// // // //                 mergedAttendanceMap[dateKey] = item;
// // // //               }
// // // //             }
// // // //           }
// // // //         }
// // // //
// // // //         // --- EXCEL WRITING START ---
// // // //
// // // //         // Header Row
// // // //         sheet.appendRow([
// // // //           TextCellValue("ID: $empId"),
// // // //           TextCellValue("Name: $empName"),
// // // //           TextCellValue("Email: $empEmail"),
// // // //           TextCellValue("Designation: $empDesig"),
// // // //         ]);
// // // //
// // // //         // Days Header
// // // //         List<CellValue> daysRow = [TextCellValue("Date")];
// // // //         for (int d = 0; d < totalDays; d++) {
// // // //           DateTime date = startDate.add(Duration(days: d));
// // // //           daysRow.add(TextCellValue(DateFormat('dd-MMM').format(date)));
// // // //         }
// // // //         sheet.appendRow(daysRow);
// // // //
// // // //         // Data Rows
// // // //         List<CellValue> arrRow = [TextCellValue("Arr Time")];
// // // //         List<CellValue> depRow = [TextCellValue("Dep Time")];
// // // //         List<CellValue> workRow = [TextCellValue("Working Hrs")];
// // // //         List<CellValue> otRow = [TextCellValue("Over Time")];
// // // //         List<CellValue> statusRow = [TextCellValue("Status")];
// // // //
// // // //         // --- FILL DATA FROM MERGED MAP ---
// // // //         for (int d = 0; d < totalDays; d++) {
// // // //           DateTime date = startDate.add(Duration(days: d));
// // // //           String lookupKey = DateFormat('yyyy-MM-dd').format(date);
// // // //
// // // //           String arr = "0";
// // // //           String dep = "0";
// // // //           String work = "0";
// // // //           String ot = "0";
// // // //           String status = "A";
// // // //
// // // //           if (mergedAttendanceMap.containsKey(lookupKey)) {
// // // //             var dayObj = mergedAttendanceMap[lookupKey];
// // // //             var innerData = dayObj['data'];
// // // //             String? note = dayObj['note'];
// // // //
// // // //             // 1. Status Priority: Note (Holiday) -> Data (Present)
// // // //             if (note != null && note.isNotEmpty) {
// // // //               if (note.toLowerCase().contains("sunday")) status = "S";
// // // //               else if (note.toLowerCase().contains("holiday")) status = "H";
// // // //             }
// // // //
// // // //             if (innerData != null && innerData is Map && innerData.isNotEmpty) {
// // // //               // Data hai to overwrite kar do
// // // //               arr = (innerData['punchIn'] ?? innerData['checkInTime'] ?? "0").toString();
// // // //               dep = (innerData['punchOut'] ?? innerData['checkOutTime'] ?? "0").toString();
// // // //               work = (innerData['duration'] ?? innerData['workingHours'] ?? "0").toString();
// // // //               ot = (innerData['overtime'] ?? "0").toString();
// // // //
// // // //               if (arr != "0" && arr != "") status = "P";
// // // //             }
// // // //           }
// // // //
// // // //           arrRow.add(TextCellValue(arr));
// // // //           depRow.add(TextCellValue(dep));
// // // //           workRow.add(TextCellValue(work));
// // // //           otRow.add(TextCellValue(ot));
// // // //           statusRow.add(TextCellValue(status));
// // // //         }
// // // //
// // // //         sheet.appendRow(arrRow);
// // // //         sheet.appendRow(depRow);
// // // //         sheet.appendRow(workRow);
// // // //         sheet.appendRow(otRow);
// // // //         sheet.appendRow(statusRow);
// // // //         sheet.appendRow([TextCellValue("")]); // Gap
// // // //       }
// // // //
// // // //       // 💾 SAVE
// // // //       setState(() => _exportStatus = "Saving...");
// // // //       var fileBytes = excel.save();
// // // //       String fileName = "Attendance_${DateFormat('ddMM').format(startDate)}_to_${DateFormat('ddMM').format(endDate)}.xlsx";
// // // //
// // // //       if (fileBytes != null) {
// // // //         Uint8List bytes = Uint8List.fromList(fileBytes);
// // // //         if(mounted) {
// // // //           setState(() => _isExporting = false);
// // // //           _showSuccessDialog(bytes, fileName);
// // // //         }
// // // //       }
// // // //
// // // //     } catch (e) {
// // // //       debugPrint("Export Error: $e");
// // // //       if (mounted) {
// // // //         setState(() => _isExporting = false);
// // // //         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
// // // //       }
// // // //     }
// // // //   }
// // // //
// // // //   void _showSuccessDialog(Uint8List bytes, String fileName) {
// // // //     showDialog(
// // // //       context: context,
// // // //       barrierDismissible: false,
// // // //       builder: (context) => AlertDialog(
// // // //         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
// // // //         title: Column(
// // // //           children: [
// // // //             const Icon(Icons.check_circle, color: Colors.green, size: 50),
// // // //             const SizedBox(height: 10),
// // // //             const Text("Report Ready!", style: TextStyle(fontWeight: FontWeight.bold)),
// // // //           ],
// // // //         ),
// // // //         content: const Text("Select an option below:", textAlign: TextAlign.center),
// // // //         actionsAlignment: MainAxisAlignment.center,
// // // //         actions: [
// // // //           ElevatedButton.icon(
// // // //             onPressed: () async {
// // // //               Navigator.pop(context);
// // // //               await _saveToDownloads(bytes, fileName);
// // // //             },
// // // //             icon: const Icon(Icons.save_alt, size: 18),
// // // //             label: const Text("Save As"),
// // // //             style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
// // // //           ),
// // // //           ElevatedButton.icon(
// // // //             onPressed: () async {
// // // //               Navigator.pop(context);
// // // //               await _shareFile(bytes, fileName);
// // // //             },
// // // //             icon: const Icon(Icons.share, size: 18),
// // // //             label: const Text("Share"),
// // // //             style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3192), foregroundColor: Colors.white),
// // // //           ),
// // // //         ],
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   Future<void> _saveToDownloads(Uint8List bytes, String fileName) async {
// // // //     try {
// // // //       final dir = await getTemporaryDirectory();
// // // //       final tempFile = File('${dir.path}/$fileName');
// // // //       await tempFile.writeAsBytes(bytes);
// // // //
// // // //       final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
// // // //       final filePath = await FlutterFileDialog.saveFile(params: params);
// // // //
// // // //       if (mounted && filePath != null) {
// // // //         ScaffoldMessenger.of(context).showSnackBar(
// // // //             const SnackBar(content: Text("Saved Successfully!"), backgroundColor: Colors.green)
// // // //         );
// // // //       }
// // // //     } catch (e) {
// // // //       print("Save Error: $e");
// // // //     }
// // // //   }
// // // //
// // // //   Future<void> _shareFile(Uint8List bytes, String name) async {
// // // //     try {
// // // //       final tempDir = await getTemporaryDirectory();
// // // //       final file = File('${tempDir.path}/$name');
// // // //       await file.writeAsBytes(bytes);
// // // //       await Share.shareXFiles([XFile(file.path)], text: 'Attendance Report');
// // // //     } catch (e) {
// // // //       debugPrint("Share Error: $e");
// // // //     }
// // // //   }
// // // //
// // // //   // --- Helpers ---
// // // //   List<Map<String, dynamic>> _getFilteredList() {
// // // //     if (_currentFilter == 'Present') return _finalList.where((e) => e['status'] == 'Present').toList();
// // // //     if (_currentFilter == 'Late') return _finalList.where((e) => e['isLate'] == true).toList();
// // // //     if (_currentFilter == 'Absent') return _finalList.where((e) => e['status'] == 'Absent').toList();
// // // //     return _finalList;
// // // //   }
// // // //
// // // //   Future<void> _pickDate() async {
// // // //     final DateTime? picked = await showDatePicker(
// // // //       context: context,
// // // //       initialDate: _selectedDate,
// // // //       firstDate: DateTime(2020),
// // // //       lastDate: DateTime.now(),
// // // //       builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
// // // //     );
// // // //     if (picked != null && picked != _selectedDate) {
// // // //       setState(() => _selectedDate = picked);
// // // //       _fetchData();
// // // //     }
// // // //   }
// // // //
// // // //   String _formatSafeTime(String? val) {
// // // //     if (val == null || val.toString().isEmpty) return "--:--";
// // // //     try {
// // // //       return DateFormat('hh:mm a').format(DateTime.parse(val).toLocal());
// // // //     } catch (_) { return val; }
// // // //   }
// // // //
// // // //   @override
// // // //   Widget build(BuildContext context) {
// // // //     String day = DateFormat('d').format(_selectedDate);
// // // //     String month = DateFormat('MMMM').format(_selectedDate);
// // // //     String year = DateFormat('yyyy').format(_selectedDate);
// // // //     String weekDay = DateFormat('EEEE').format(_selectedDate);
// // // //     List<Map<String, dynamic>> displayList = _getFilteredList();
// // // //
// // // //     return Scaffold(
// // // //       backgroundColor: const Color(0xFFF2F5F9),
// // // //       body: Stack(
// // // //         children: [
// // // //           // List
// // // //           _isLoading
// // // //               ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
// // // //               : (displayList.isEmpty
// // // //               ? Center(child: Text("No Data for $day-$month", style: const TextStyle(color: Colors.grey)))
// // // //               : ListView.builder(
// // // //             padding: const EdgeInsets.fromLTRB(20, 360, 20, 20),
// // // //             itemCount: displayList.length,
// // // //             itemBuilder: (context, index) => _buildModernEmployeeCard(displayList[index]),
// // // //           )),
// // // //
// // // //           // Header
// // // //           Container(
// // // //             height: 340,
// // // //             decoration: const BoxDecoration(
// // // //                 gradient: LinearGradient(
// // // //                     colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
// // // //                     begin: Alignment.topLeft,
// // // //                     end: Alignment.bottomRight),
// // // //                 borderRadius: BorderRadius.only(
// // // //                     bottomLeft: Radius.circular(35),
// // // //                     bottomRight: Radius.circular(35)),
// // // //                 boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]
// // // //             ),
// // // //             child: SafeArea(
// // // //               child: Padding(
// // // //                 padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
// // // //                 child: Column(
// // // //                   crossAxisAlignment: CrossAxisAlignment.start,
// // // //                   mainAxisSize: MainAxisSize.min,
// // // //                   children: [
// // // //                     // Top Bar
// // // //                     Row(
// // // //                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // // //                       children: [
// // // //                         GestureDetector(
// // // //                           onTap: () => Navigator.pop(context),
// // // //                           child: Container(
// // // //                             padding: const EdgeInsets.all(8),
// // // //                             decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
// // // //                             child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
// // // //                           ),
// // // //                         ),
// // // //                         // Dropdown
// // // //                         Flexible(
// // // //                           child: Container(
// // // //                             margin: const EdgeInsets.only(left: 10),
// // // //                             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
// // // //                             decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
// // // //                             child: DropdownButtonHideUnderline(
// // // //                               child: DropdownButton<String>(
// // // //                                 value: _selectedLocationId,
// // // //                                 isExpanded: true,
// // // //                                 dropdownColor: const Color(0xFF2E3192),
// // // //                                 icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
// // // //                                 hint: const Text("Select Location", style: TextStyle(color: Colors.white70)),
// // // //                                 items: _locations.map<DropdownMenuItem<String>>((dynamic loc) {
// // // //                                   return DropdownMenuItem<String>(value: loc['_id'], child: Text(loc['name'], overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)));
// // // //                                 }).toList(),
// // // //                                 onChanged: (val) { setState(() => _selectedLocationId = val); _fetchData(); },
// // // //                               ),
// // // //                             ),
// // // //                           ),
// // // //                         ),
// // // //                       ],
// // // //                     ),
// // // //                     const SizedBox(height: 20),
// // // //
// // // //                     // Date & Export Row
// // // //                     Row(
// // // //                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // // //                       crossAxisAlignment: CrossAxisAlignment.center,
// // // //                       children: [
// // // //                         // Left: Date
// // // //                         GestureDetector(
// // // //                           onTap: _pickDate,
// // // //                           child: Container(
// // // //                             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
// // // //                             decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white54)),
// // // //                             child: Row(
// // // //                               children: [
// // // //                                 Text(day, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
// // // //                                 const SizedBox(width: 12),
// // // //                                 Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
// // // //                                   Text(weekDay.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12)),
// // // //                                   Text("$month $year", style: const TextStyle(color: Colors.white, fontSize: 16)),
// // // //                                 ])
// // // //                               ],
// // // //                             ),
// // // //                           ),
// // // //                         ),
// // // //
// // // //                         // 🔴 EXPORT BUTTON 🔴
// // // //                         GestureDetector(
// // // //                           onTap: _isExporting ? null : _processCustomRangeExport,
// // // //                           child: Container(
// // // //                             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
// // // //                             decoration: BoxDecoration(
// // // //                                 color: Colors.white,
// // // //                                 borderRadius: BorderRadius.circular(20),
// // // //                                 boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)]
// // // //                             ),
// // // //                             child: _isExporting
// // // //                                 ? Row(
// // // //                               children: [
// // // //                                 SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, value: _exportProgress)),
// // // //                                 const SizedBox(width: 8),
// // // //                                 Text("${(_exportProgress * 100).toInt()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
// // // //                               ],
// // // //                             )
// // // //                                 : Row(
// // // //                               children: [
// // // //                                 const Icon(Icons.download_rounded, color: Color(0xFF2E3192), size: 18),
// // // //                                 const SizedBox(width: 5),
// // // //                                 const Text("Export", style: TextStyle(color: Color(0xFF2E3192), fontWeight: FontWeight.bold, fontSize: 12)),
// // // //                               ],
// // // //                             ),
// // // //                           ),
// // // //                         ),
// // // //                       ],
// // // //                     ),
// // // //
// // // //                     if (_isExporting)
// // // //                       Padding(
// // // //                         padding: const EdgeInsets.only(top: 5),
// // // //                         child: Align(
// // // //                             alignment: Alignment.centerRight,
// // // //                             child: Text(_exportStatus, style: const TextStyle(color: Colors.white, fontSize: 10))
// // // //                         ),
// // // //                       ),
// // // //
// // // //                     const Spacer(),
// // // //
// // // //                     // Stats
// // // //                     Container(
// // // //                       padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
// // // //                       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
// // // //                       child: Row(children: [
// // // //                         _buildStatColumn("Total", _totalStaff.toString(), Colors.blueAccent, 'Total'),
// // // //                         _buildDivider(),
// // // //                         _buildStatColumn("Present", _totalPresent.toString(), Colors.green, 'Present'),
// // // //                         _buildDivider(),
// // // //                         _buildStatColumn("Late", _totalLate.toString(), Colors.orange, 'Late'),
// // // //                         _buildDivider(),
// // // //                         _buildStatColumn("Absent", _totalAbsent.toString(), Colors.red, 'Absent'),
// // // //                       ]),
// // // //                     ),
// // // //                   ],
// // // //                 ),
// // // //               ),
// // // //             ),
// // // //           ),
// // // //         ],
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   // Helpers
// // // //   Widget _buildDivider() => Container(width: 1, height: 25, color: Colors.grey.shade200);
// // // //
// // // //   Widget _buildStatColumn(String label, String value, Color color, String filterKey) {
// // // //     bool isSelected = _currentFilter == filterKey;
// // // //     return Expanded(
// // // //       child: InkWell(
// // // //         onTap: () => setState(() => _currentFilter = filterKey),
// // // //         child: Container(
// // // //           decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
// // // //           child: Column(children: [Text(value, style: TextStyle(color: isSelected ? color : Colors.black87, fontSize: 18, fontWeight: FontWeight.w900)), Text(label, style: TextStyle(color: isSelected ? color : Colors.grey.shade500, fontSize: 10))]),
// // // //         ),
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildModernEmployeeCard(Map<String, dynamic> item) {
// // // //     String name = item['name'] ?? "Unknown";
// // // //     String designation = item['designation'] ?? "Staff";
// // // //     bool isPresent = item['status'] == 'Present';
// // // //     bool isLate = item['isLate'] ?? false;
// // // //     String inTime = isPresent && item['checkIn'] != null ? _formatSafeTime(item['checkIn']) : "--:--";
// // // //     String outTime = isPresent && item['checkOut'] != null ? _formatSafeTime(item['checkOut']) : "DUTY ON";
// // // //     Color statusColor = isPresent ? (isLate ? Colors.orange : Colors.green) : Colors.redAccent;
// // // //
// // // //     return Container(
// // // //       margin: const EdgeInsets.only(bottom: 12),
// // // //       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10)]),
// // // //       child: InkWell(
// // // //         onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(employeeName: name, employeeId: item['_id'], locationId: _selectedLocationId!))),
// // // //         child: IntrinsicHeight(
// // // //           child: Row(children: [
// // // //             Container(width: 5, decoration: BoxDecoration(color: statusColor, borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)))),
// // // //             Expanded(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
// // // //               CircleAvatar(backgroundColor: Colors.grey.shade100, child: Text(name.isNotEmpty ? name[0] : "?")),
// // // //               const SizedBox(width: 12),
// // // //               Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: TextStyle(fontWeight: FontWeight.bold)), Text(designation, style: TextStyle(fontSize: 12, color: Colors.grey))])),
// // // //               Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
// // // //                 if(!isPresent) Text("ABSENT", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
// // // //                 else ...[Text("IN: $inTime", style: TextStyle(fontSize: 11)), Text(outTime == "DUTY ON" ? outTime : "OUT: $outTime", style: TextStyle(fontSize: 11, color: outTime == "DUTY ON" ? Colors.green : Colors.blueGrey))]
// // // //               ])
// // // //             ])))
// // // //           ]),
// // // //         ),
// // // //       ),
// // // //     );
// // // //   }
// // // // }
