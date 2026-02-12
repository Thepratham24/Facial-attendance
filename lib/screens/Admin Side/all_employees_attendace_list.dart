import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/api_service.dart';
import 'attendance_history_screen.dart';

class AllEmployeesAttendanceList extends StatefulWidget {
  const AllEmployeesAttendanceList({super.key});

  @override
  State<AllEmployeesAttendanceList> createState() =>
      _AllEmployeesAttendanceListState();
}

class _AllEmployeesAttendanceListState
    extends State<AllEmployeesAttendanceList> {
  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _finalList = [];
  List<dynamic> _locations = [];
  Map<String, String> _employeeDepartmentMap = {};

  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  String? _selectedLocationId;
  String _currentFilter = 'Total';

  bool _isExporting = false;
  String _exportStatus = "";
  double _exportProgress = 0.0;

  // Stats
  int _totalStaff = 0;
  int _totalPresent = 0;
  int _totalLate = 0;
  int _totalhalfDay = 0;
  int _totalAbsent = 0;

  final double _headerHeight = 330.0;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([_fetchLocations(), _fetchEmployeeMap()]);
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

  Future<void> _fetchEmployeeMap() async {
    try {
      var list = await _apiService.getAllEmployees();
      Map<String, String> tempMap = {};
      for (var emp in list) {
        String empId = emp['_id'] ?? emp['id'];
        String deptId = "";
        if (emp['departmentId'] != null) {
          if (emp['departmentId'] is Map) {
            deptId = emp['departmentId']['_id'] ?? "";
          } else if (emp['departmentId'] is String) {
            deptId = emp['departmentId'];
          }
        }
        if (empId.isNotEmpty) tempMap[empId] = deptId;
      }
      if (mounted) setState(() => _employeeDepartmentMap = tempMap);
    } catch (e) {
      debugPrint("Employee Map Error: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // 🔴 FETCH DATA (PURE BACKEND STATUS LOGIC)
  // ---------------------------------------------------------------------------
  Future<void> _fetchData({bool isBackground = false}) async {
    if (_selectedLocationId == null) return;
    if (!isBackground) setState(() => _isLoading = true);

    try {
      String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      List<dynamic> apiData = await _apiService.getAttendanceByDateAndLocation(
          dateStr, _selectedLocationId!);

      List<Map<String, dynamic>> temp = [];
      int totalCount = 0,
          presentCount = 0,
          lateCount = 0,
          halfDayCount = 0,
          absentCount = 0;

      for (var item in apiData) {
        totalCount++;
        String name = item['name'] ?? "Unknown";
        String designation = item['designation'] ?? "Staff";
        String empId = item['employeeId'] ?? item['_id'] ?? "";

        String deptId = "";
        if (item['departmentId'] != null) {
          if (item['departmentId'] is Map)
            deptId = item['departmentId']['_id'] ?? "";
          else if (item['departmentId'] is String)
            deptId = item['departmentId'];
        }
        if (deptId.isEmpty && _employeeDepartmentMap.containsKey(empId)) {
          deptId = _employeeDepartmentMap[empId] ?? "";
        }

        var attendance = item['attendance'];

        int status = 2; // Default Absent
        String? checkIn;
        String? checkOut;
        String workTime = "";
        bool isLate = false;
        if (attendance != null && attendance is Map) {
          // 🔴 TRUST BACKEND COMPLETELY
          status = attendance['status'] ?? 2;
          checkIn = attendance['checkInTime'] ?? attendance['punchIn'];
          checkOut = attendance['checkOutTime'] ?? attendance['punchOut'];
          workTime = attendance['workingHours'] ?? attendance['duration'] ?? "";
          isLate = attendance['isLate'] == true;
        }
        if (isLate || status == 3) {
          lateCount++;
          // Late log technically present hote hain, toh present count bhi badhana pad sakta hai
          // depend karta hai aap dashboard pe kaise dikhana chahte ho.
        }
        // 🔴 COUNTING LOGIC (Purely based on Status)
        if (status == 1) {
          presentCount++; // Present or Half Day
        } else if (status == 4) {
          halfDayCount++; // Late
        } else {
          absentCount++; // Absent (2) or Excused (5)
        }

        temp.add({
          '_id': empId,
          'name': name,
          'designation': designation,
          'departmentId': deptId,
          'status': status,
          'checkIn': checkIn,
          'checkOut': checkOut,
          'workTime': workTime,
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
          _totalhalfDay = halfDayCount;
          _totalAbsent = absentCount;
          if (!isBackground) _isLoading = false;
          _currentFilter = 'Total';
        });
      }
    } catch (e) {
      if (mounted && !isBackground) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 🔴 EXCEL EXPORT (TRUST BACKEND + SHOW TIME IF AVAILABLE)
  // ---------------------------------------------------------------------------
  Future<void> _processCustomRangeExport() async {
    if (_selectedLocationId == null || _finalList.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("No data to export")));
      return;
    }

    final DateTimeRange? pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))),
          child: child!),
    );

    if (pickedRange == null) return;

    setState(() {
      _isExporting = true;
      _exportStatus = "Calculating Data...";
      _exportProgress = 0.0;
    });

    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['Attendance Report'];
      excel.setDefaultSheet('Attendance Report');

      DateTime startDate = pickedRange.start;
      DateTime endDate = pickedRange.end;
      int totalDays = endDate.difference(startDate).inDays + 1;

      for (int i = 0; i < _finalList.length; i++) {
        var emp = _finalList[i];
        String empId = emp['_id'];
        String empName = emp['name'];
        String empDesig = emp['designation'] ?? "Staff";
        String deptId = emp['departmentId'] ?? "";

        Set<String> monthsToFetch = {};
        DateTime loopDate = startDate;
        while (
            loopDate.isBefore(endDate) || loopDate.isAtSameMomentAs(endDate)) {
          monthsToFetch.add(DateFormat('yyyy-MM').format(loopDate));
          loopDate = DateTime(loopDate.year, loopDate.month + 1, 1);
        }

        Map<String, dynamic> mergedData = {};

        for (String monthStr in monthsToFetch) {
          if (mounted) {
            setState(() {
              _exportStatus = "Processing $empName ($monthStr)";
              _exportProgress = (i + 1) / _finalList.length;
            });
          }

          var reportData = await _apiService.getMonthlyReport(
              empId, monthStr, _selectedLocationId!, deptId);

          if (reportData != null) {
            List<dynamic> attList = [];
            if (reportData['data'] is List && reportData['data'].isNotEmpty) {
              attList = reportData['data'][0]['attendance'] ?? [];
            } else if (reportData['attendance'] != null) {
              attList = reportData['attendance'];
            }

            for (var item in attList) {
              int? d = item['day'];
              if (d != null) {
                String dateKey = "$monthStr-${d.toString().padLeft(2, '0')}";
                mergedData[dateKey] = item;
              }
            }
          }
        }

        int totalPresent = 0;
        int totalLate = 0;
        int totalAbsent = 0;
        int totalHalfDay = 0;
        int totalWorkMinutes = 0;
        int totalOtMinutes = 0;

        List<List<CellValue>> dailyRows = [];

        for (int d = 0; d < totalDays; d++) {
          DateTime currentDate = startDate.add(Duration(days: d));
          String dateKey = DateFormat('yyyy-MM-dd').format(currentDate);

          String inTime = "-",
              outTime = "-",
              status = "A",
              work = "-",
              ot = "-";

          if (mergedData.containsKey(dateKey)) {
            var dayData = mergedData[dateKey];
            var inner = dayData['data'] ?? {};

            int rStatus = inner['status'] ?? 2;

            String? checkInVal = inner['checkInTime'] ?? inner['punchIn'];
            String? checkOutVal = inner['checkOutTime'] ?? inner['punchOut'];
            String rawWork = inner['workingHours'] ?? inner['duration'] ?? "";
            String rawOT = inner['overtime'] ?? "";

            // 🔴 STATUS DETERMINATION (Trust Backend)
            if (rStatus == 1) {
              status = "P";
              totalPresent++;
            } else if (rStatus == 3) {
              status = "L";
              totalLate++;
            } else if (rStatus == 4) {
              status = "HD";
              totalHalfDay++;
            } else if (rStatus == 2) {
              // Check if it's holiday or explicit absence
              String? note = dayData['note'];
              String? holiday = dayData['holiday'];
              if (holiday != null)
                status = "H";
              else if (note == "Sunday")
                status = "S";
              else if (note == "NotJoined")
                status = "NJ";
              else {
                status = "A";
                totalAbsent++;
              }
            } else {
              status = "A";
              totalAbsent++;
            }

            // 🔴 TIME FILLING (If time exists, write it, regardless of status)
            if (checkInVal != null && checkInVal.toString().isNotEmpty) {
              inTime = _formatTimeOnly(checkInVal);
              outTime = _formatTimeOnly(checkOutVal);
              work = rawWork.isNotEmpty ? rawWork : "-";
              ot = rawOT.isNotEmpty ? rawOT : "-";

              totalWorkMinutes += _parseDurationToMinutes(rawWork);
              totalOtMinutes += _parseDurationToMinutes(rawOT);
            }
          } else {
            if (currentDate.isAfter(DateTime.now())) {
              status = "-";
            } else {
              if (DateFormat('EEEE').format(currentDate) == 'Sunday') {
                status = "S";
              } else {
                status = "A";
                totalAbsent++;
              }
            }
          }

          dailyRows.add([
            TextCellValue(DateFormat('dd-MMM-yyyy').format(currentDate)),
            TextCellValue(inTime),
            TextCellValue(outTime),
            TextCellValue(work),
            TextCellValue(ot),
            TextCellValue(status),
          ]);
        }

        sheet.appendRow([TextCellValue("EMPLOYEE DETAILS")]);
        sheet.appendRow([
          TextCellValue("Name"),
          TextCellValue(empName),
          TextCellValue("ID"),
          TextCellValue(empId),
          TextCellValue("Role"),
          TextCellValue(empDesig)
        ]);

        sheet.appendRow([TextCellValue("")]);
        sheet.appendRow([TextCellValue("MONTHLY SUMMARY")]);
        sheet.appendRow([
          TextCellValue("Total Present"),
          TextCellValue("Total Late"),
          TextCellValue("Total HalfDay"),
          TextCellValue("Total Absent"),
          TextCellValue("Total Work Hrs"),
          TextCellValue("Total OT Hrs")
        ]);

        sheet.appendRow([
          IntCellValue(totalPresent),
          IntCellValue(totalLate),
          IntCellValue(totalHalfDay),
          IntCellValue(totalAbsent),
          TextCellValue(_formatMinutesToTime(totalWorkMinutes)),
          TextCellValue(_formatMinutesToTime(totalOtMinutes)),
        ]);

        sheet.appendRow([TextCellValue("")]);
        sheet.appendRow([
          TextCellValue("Date"),
          TextCellValue("In Time"),
          TextCellValue("Out Time"),
          TextCellValue("Working Hrs"),
          TextCellValue("Overtime"),
          TextCellValue("Status")
        ]);

        for (var row in dailyRows) {
          sheet.appendRow(row);
        }

        sheet.appendRow([TextCellValue("")]);
        sheet.appendRow([
          TextCellValue("--------------------------------------------------")
        ]);
        sheet.appendRow([TextCellValue("")]);
      }

      setState(() => _exportStatus = "Saving...");
      var fileBytes = excel.save();
      String fileName =
          "Attendance_${DateFormat('ddMMM').format(startDate)}_to_${DateFormat('ddMMM').format(endDate)}.xlsx";

      if (fileBytes != null && mounted) {
        _isExporting = false;
        _showSuccessDialog(Uint8List.fromList(fileBytes), fileName);
      }
    } catch (e) {
      if (mounted) setState(() => _isExporting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Export Error: $e")));
    }
  }

  // 🔴 PICK DATE HELPER
  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))),
          child: child!),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchData();
    }
  }

  int _parseDurationToMinutes(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 0;
    try {
      if (timeStr.contains(":")) {
        var parts = timeStr.split(":");
        int h = int.parse(parts[0]);
        int m = int.parse(parts[1]);
        return (h * 60) + m;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  String _formatMinutesToTime(int totalMinutes) {
    if (totalMinutes == 0) return "0h 0m";
    int h = totalMinutes ~/ 60;
    int m = totalMinutes % 60;
    return "${h}h ${m}m";
  }

  void _showSuccessDialog(Uint8List bytes, String fileName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.green.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.green, size: 48),
            ),
            const SizedBox(height: 16),
            const Text("Report Ready!",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: const Text("Select an option below:",
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _saveFileToDevice(bytes, fileName);
                  },
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: const Text("Save"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _shareFile(bytes, fileName);
                  },
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text("Share"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E3192),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _saveFileToDevice(Uint8List bytes, String fileName) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);
      final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
      final filePath = await FlutterFileDialog.saveFile(params: params);
      if (filePath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("File Saved Successfully!"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not save file.")));
    }
  }

  Future<void> _shareFile(Uint8List bytes, String fileName) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: 'Attendance Report - $fileName');
    } catch (e) {
      debugPrint("Share Error: $e");
    }
  }

  String _formatTimeOnly(String? val) {
    if (val == null) return "-";
    try {
      if (val.contains("T"))
        return DateFormat('HH:mm').format(DateTime.parse(val));
      return val;
    } catch (_) {
      return val;
    }
  }

  String _formatSafeTime(String? val) {
    if (val == null || val.toString().trim().isEmpty) return "--:--";
    try {
      DateTime dt;
      if (val.contains("T")) {
        dt = DateTime.parse(val).toLocal();
      } else {
        final now = DateTime.now();
        final parts = val.split(':');
        if (parts.length >= 2) {
          dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]),
              int.parse(parts[1]));
        } else {
          return val;
        }
      }
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return val;
    }
  }

  List<Map<String, dynamic>> _getFilteredList() {
    if (_currentFilter == 'Present')
      return _finalList.where((e) => e['status'] == 1).toList();
    if (_currentFilter == 'Late')
      return _finalList
          .where((e) => e['status'] == 3 || e['isLate'] == true)
          .toList();
    if (_currentFilter == 'Half day')
      return _finalList.where((e) => e['status'] == 4).toList();
    if (_currentFilter == 'Absent')
      return _finalList
          .where((e) => e['status'] == 2 || e['status'] == 5)
          .toList();
    return _finalList;
  }

  @override
  Widget build(BuildContext context) {
    String day = DateFormat('d').format(_selectedDate);
    String month = DateFormat('MMMM').format(_selectedDate);
    String year = DateFormat('yyyy').format(_selectedDate);
    String weekDay = DateFormat('EEEE').format(_selectedDate);
    List<Map<String, dynamic>> displayList = _getFilteredList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Stack(
        children: [
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF2E3192)))
              : RefreshIndicator(
                  onRefresh: () => _fetchData(isBackground: false),
                  color: const Color(0xFF2E3192),
                  edgeOffset: 340,
                  child: displayList.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.only(top: _headerHeight + 50),
                          children: [
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_off_rounded,
                                      size: 80, color: Colors.grey.shade300),
                                  const SizedBox(height: 15),
                                  Text("No Attendance Found",
                                      style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600))
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                              16, _headerHeight + 20, 16, 30),
                          itemCount: displayList.length,
                          itemBuilder: (context, index) {
                            return _buildUltraModernCard(displayList[index]);
                          },
                        ),
                ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: _headerHeight,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(36),
                    bottomRight: Radius.circular(36)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: Offset(0, 10),
                      spreadRadius: -5)
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.arrow_back_ios_new,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              height: 42,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.2)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedLocationId,
                                  dropdownColor: const Color(0xFF2E3192),
                                  icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Colors.white),
                                  hint: const Text("Select Location",
                                      style: TextStyle(color: Colors.white70)),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                  items: _locations
                                      .map<DropdownMenuItem<String>>(
                                          (dynamic loc) {
                                    return DropdownMenuItem<String>(
                                        value: loc['_id'],
                                        child: Text(loc['name'],
                                            overflow: TextOverflow.ellipsis));
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(day,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 48,
                                            fontWeight: FontWeight.bold,
                                            height: 1)),
                                    const SizedBox(width: 8),
                                    Text(weekDay.substring(0, 3).toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                Text("$month $year",
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),

                          // 🔴 SMALL GRADIENT EXPORT BUTTON
                          GestureDetector(
                            onTap:
                                _isExporting ? null : _processCustomRangeExport,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFF00C6FF),
                                  Color(0xFF0072FF)
                                ]),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 6,
                                      offset: const Offset(0, 3))
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isExporting)
                                    const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                  else
                                    const Icon(Icons.file_download_rounded,
                                        color: Colors.white, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isExporting ? "..." : "Export",
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  )
                                ],
                              ),
                            ),
                          )
                        ],
                      ),

                      const SizedBox(height: 25),

                      // Stats Row
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 15,
                                offset: const Offset(0, 8))
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildCompactStat("Total", _totalStaff.toString(),
                                Colors.blue.shade800, 'Total'),
                            Container(
                                width: 1,
                                height: 25,
                                color: Colors.grey.shade200),
                            _buildCompactStat(
                                "Present",
                                _totalPresent.toString(),
                                Colors.green.shade600,
                                'Present'),
                            Container(
                                width: 1,
                                height: 25,
                                color: Colors.grey.shade200),
                            _buildCompactStat("Late", _totalLate.toString(),
                                Colors.orange.shade700, 'Late'),
                            Container(
                                width: 1,
                                height: 25,
                                color: Colors.grey.shade200),
                            _buildCompactStat(
                                "Half Day",
                                _totalhalfDay.toString(),
                                Colors.orange.shade700,
                                'Half day'),
                            Container(
                                width: 1,
                                height: 25,
                                color: Colors.grey.shade200),
                            _buildCompactStat("Absent", _totalAbsent.toString(),
                                Colors.red.shade600, 'Absent'),
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

  Widget _buildCompactStat(
      String label, String value, Color color, String filterKey) {
    bool isSelected = _currentFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _currentFilter = filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  color: isSelected ? color : Colors.black87,
                  fontSize: 19,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(
                  color: isSelected ? color : Colors.grey.shade500,
                  fontSize: 11,
                  fontWeight: FontWeight.w600))
        ]),
      ),
    );
  }

  // 🔴 ULTRA MODERN CARD (STATUS BASED + SHOW TIME IF EXISTS)
  // Widget _buildUltraModernCard(Map<String, dynamic> item) {
  //   String name = item['name'] ?? "Unknown";
  //   String designation = item['designation'] ?? "Staff";
  //
  //   int status = item['status'];
  //   bool isLate = item['isLate'] ?? false;
  //   String? checkInVal = item['checkIn'];
  //   String? checkOutVal = item['checkOut'];
  //   String workTime = item['workTime'] ?? "";
  //
  //   String inTime = "--:--";
  //   String outTime = "Working";
  //
  //   // 🔴 CARD UI LOGIC
  //   // Status color strictly follows Status Code
  //   Color statusColor;
  //   String badgeText;
  //
  //   if (status == 1) { // Present
  //     statusColor = const Color(0xFF2EC4B6);
  //     badgeText = "PRESENT";
  //   } else if (status == 3) { // Late
  //     statusColor = const Color(0xFFFF9F1C);
  //     badgeText = "LATE";
  //   } else if (status == 4) { // Half Day
  //     statusColor = Colors.purpleAccent;
  //     badgeText = "HALF DAY";
  //   } else if (status == 5) { // Excused
  //     statusColor = Colors.blueGrey;
  //     badgeText = "EXCUSED";
  //   } else { // Absent
  //     statusColor = const Color(0xFFFF4B4B);
  //     badgeText = "ABSENT";
  //   }
  //
  //   // 🔴 TIME DISPLAY LOGIC
  //   // Show time if checkIn is available, regardless of status being Absent
  //   bool showTime = checkInVal != null && checkInVal.toString().isNotEmpty;
  //   if (showTime) {
  //     inTime = _formatSafeTime(checkInVal);
  //     outTime = checkOutVal != null ? _formatSafeTime(checkOutVal) : "Working";
  //   }
  //
  //   return Container(
  //     margin: const EdgeInsets.only(bottom: 14),
  //     decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10)]),
  //     child: ClipRRect(
  //       borderRadius: BorderRadius.circular(18),
  //       child: Material(
  //         color: Colors.transparent,
  //         child: InkWell(
  //           onTap: () {
  //             Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(
  //               employeeName: name,
  //               employeeId: item['_id'],
  //               locationId: _selectedLocationId!,
  //               departmentId: item['departmentId'] ?? "",
  //             )))
  //                 .then((_) => _fetchData(isBackground: false));
  //           },
  //           child: Row(
  //             children: [
  //               Container(width: 6, height: 90, color: statusColor),
  //               Expanded(
  //                 child: Padding(
  //                   padding: const EdgeInsets.all(14),
  //                   child: Row(children: [
  //                     CircleAvatar(radius: 24, backgroundColor: const Color(0xFFF0F2F5), child: Text(name.isNotEmpty ? name[0] : "?", style: const TextStyle(fontWeight: FontWeight.bold))),
  //                     const SizedBox(width: 14),
  //                     Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(designation, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))])),
  //                     Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
  //
  //                       // Status Badge
  //                       Container(
  //                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  //                           decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
  //                           child: Text(badgeText, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold))
  //                       ),
  //                       const SizedBox(height: 4),
  //
  //                       // 🔴 SHOW TIME IF EXISTS
  //                       if (showTime) ...[
  //                         Text("In: $inTime", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
  //                         Text(outTime == "Working" ? "Active" : "Out: $outTime", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: outTime == "Working" ? Colors.green : Colors.black87)),
  //                         if(workTime.isNotEmpty && workTime != "0")
  //                           Padding(
  //                             padding: const EdgeInsets.only(top: 2),
  //                             child: Row(children: [const Icon(Icons.timer, size: 10, color: Colors.grey), const SizedBox(width: 2), Text(workTime, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))]),
  //                           )
  //                       ]
  //                     ])
  //                   ]),
  //                 ),
  //               )
  //             ],
  //           ),
  //         ),
  //       ),
  //     ),
  //   );
  // }

// 🔴 Change 3: Update card UI logic
  Widget _buildUltraModernCard(Map<String, dynamic> item) {
    String name = item['name'] ?? "Unknown";
    String designation = item['designation'] ?? "Staff";

    int status = item['status'];
    bool isLate = item['isLate'] ?? false; // 🔴 isLate fetch karo

    String? checkInVal = item['checkIn'];
    String? checkOutVal = item['checkOut'];
    String workTime = item['workTime'] ?? "";

    String inTime = "--:--";
    String outTime = "Working";

    // ... (Status Color Logic Same Rehne Do) ...
    Color statusColor;
    String badgeText;

    if (status == 1) {
      statusColor = const Color(0xFF2EC4B6);
      badgeText = "PRESENT";
    } else if (status == 3) {
      statusColor = const Color(0xFFFF9F1C);
      badgeText = "LATE";
    } else if (status == 4) {
      statusColor = Colors.purpleAccent;
      badgeText = "HALF DAY";
    } else if (status == 5) {
      statusColor = Colors.blueGrey;
      badgeText = "EXCUSED";
    } else {
      statusColor = const Color(0xFFFF4B4B);
      badgeText = "ABSENT";
    }

    // ... (Time Logic Same Rehne Do) ...
    bool showTime = checkInVal != null && checkInVal.toString().isNotEmpty;
    if (showTime) {
      inTime = _formatSafeTime(checkInVal);
      outTime = checkOutVal != null ? _formatSafeTime(checkOutVal) : "Working";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10)
          ]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (c) => AttendanceHistoryScreen(
                            employeeName: name,
                            employeeId: item['_id'],
                            locationId: _selectedLocationId!,
                            departmentId: item['departmentId'] ?? "",
                          ))).then((_) => _fetchData(isBackground: false));
            },
            child: Row(
              children: [
                Container(width: 6, height: 90, color: statusColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFFF0F2F5),
                          child: Text(name.isNotEmpty ? name[0] : "?",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold))),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(designation,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade500))
                          ])),

                      // 🔴 RIGHT SIDE COLUMN START
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // 🔴 ROW FOR BADGES (Late Tag Logic Added Here)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 🔴 Agar Late hai, to Red Badge dikhao
                                if (isLate)
                                  Container(
                                      margin: const EdgeInsets.only(right: 5),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.red.shade100)),
                                      child: Text("LATE",
                                          style: TextStyle(
                                              color: Colors.red.shade700,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold))),

                                // Original Status Badge
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6)),
                                    child: Text(badgeText,
                                        style: TextStyle(
                                            color: statusColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold))),
                              ],
                            ),

                            const SizedBox(height: 4),

                            if (showTime) ...[
                              Text("In: $inTime",
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  outTime == "Working"
                                      ? "Active"
                                      : "Out: $outTime",
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: outTime == "Working"
                                          ? Colors.green
                                          : Colors.black87)),
                              if (workTime.isNotEmpty && workTime != "0")
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(children: [
                                    const Icon(Icons.timer,
                                        size: 10, color: Colors.grey),
                                    const SizedBox(width: 2),
                                    Text(workTime,
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.bold))
                                  ]),
                                )
                            ]
                          ])
                      // 🔴 RIGHT SIDE COLUMN END
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
// import 'package:flutter/material.dart';
// import 'package:flutter_file_dialog/flutter_file_dialog.dart'; // Save ke liye
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
//
//   List<Map<String, dynamic>> _finalList = [];
//   List<dynamic> _locations = [];
//   Map<String, String> _employeeDepartmentMap = {};
//
//   bool _isLoading = true;
//   DateTime _selectedDate = DateTime.now();
//   String? _selectedLocationId;
//   String _currentFilter = 'Total';
//
//   bool _isExporting = false;
//   String _exportStatus = "";
//   double _exportProgress = 0.0;
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
//     _initData();
//   }
//
//   void _initData() async {
//     setState(() => _isLoading = true);
//     try {
//       await Future.wait([_fetchLocations(), _fetchEmployeeMap()]);
//       if (_selectedLocationId != null) {
//         _fetchData(isBackground: false);
//       } else {
//         setState(() => _isLoading = false);
//       }
//     } catch (e) {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }
//
//   Future<void> _fetchLocations() async {
//     try {
//       var locs = await _apiService.getLocations();
//       if (mounted) {
//         setState(() {
//           _locations = locs;
//           if (_locations.isNotEmpty) {
//             _selectedLocationId = _locations[0]['_id'];
//           }
//         });
//       }
//     } catch (e) {
//       debugPrint("Loc Error: $e");
//     }
//   }
//
//   Future<void> _fetchEmployeeMap() async {
//     try {
//       var list = await _apiService.getAllEmployees();
//       Map<String, String> tempMap = {};
//       for (var emp in list) {
//         String empId = emp['_id'] ?? emp['id'];
//         String deptId = "";
//         if (emp['departmentId'] != null) {
//           if (emp['departmentId'] is Map) {
//             deptId = emp['departmentId']['_id'] ?? "";
//           } else if (emp['departmentId'] is String) {
//             deptId = emp['departmentId'];
//           }
//         }
//         if (empId.isNotEmpty) tempMap[empId] = deptId;
//       }
//       if (mounted) setState(() => _employeeDepartmentMap = tempMap);
//     } catch (e) {
//       debugPrint("Employee Map Error: $e");
//     }
//   }
//
//   Future<void> _fetchData({bool isBackground = false}) async {
//     if (_selectedLocationId == null) return;
//     if (!isBackground) setState(() => _isLoading = true);
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
//         String empId = item['employeeId'] ?? item['_id'] ?? "";
//
//         String deptId = "";
//         if (item['departmentId'] != null) {
//           if (item['departmentId'] is Map) deptId = item['departmentId']['_id'] ?? "";
//           else if (item['departmentId'] is String) deptId = item['departmentId'];
//         }
//         if (deptId.isEmpty && _employeeDepartmentMap.containsKey(empId)) {
//           deptId = _employeeDepartmentMap[empId] ?? "";
//         }
//
//         var attendance = item['attendance'];
//         String status = "Absent";
//         String? checkIn;
//         String? checkOut;
//         String workTime = "";
//         bool isLate = false;
//
//         if (attendance != null && attendance is Map) {
//           checkIn = attendance['checkInTime'] ?? attendance['punchIn'];
//           checkOut = attendance['checkOutTime'] ?? attendance['punchOut'];
//           isLate = attendance['isLate'] == true;
//           workTime = attendance['workingHours'] ?? attendance['duration'] ?? "";
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
//           'departmentId': deptId,
//           'status': status,
//           'checkIn': checkIn,
//           'checkOut': checkOut,
//           'workTime': workTime,
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
//           if (!isBackground) _isLoading = false;
//           _currentFilter = 'Total';
//         });
//       }
//     } catch (e) {
//       if (mounted && !isBackground) setState(() => _isLoading = false);
//     }
//   }
//
//   // 🔴🔴 EXPORT EXCEL (VERTICAL WITH SUMMARY) 🔴🔴
//   Future<void> _processCustomRangeExport() async {
//     if (_selectedLocationId == null || _finalList.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to export")));
//       return;
//     }
//
//     final DateTimeRange? pickedRange = await showDateRangePicker(
//       context: context,
//       firstDate: DateTime(2023),
//       lastDate: DateTime.now(),
//       builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF2E3192))), child: child!),
//     );
//
//     if (pickedRange == null) return;
//
//     setState(() {
//       _isExporting = true;
//       _exportStatus = "Calculating Data...";
//       _exportProgress = 0.0;
//     });
//
//     try {
//       var excel = Excel.createExcel();
//       Sheet sheet = excel['Attendance Report'];
//       excel.setDefaultSheet('Attendance Report');
//
//       DateTime startDate = pickedRange.start;
//       DateTime endDate = pickedRange.end;
//       int totalDays = endDate.difference(startDate).inDays + 1;
//
//       // Loop Employees
//       for (int i = 0; i < _finalList.length; i++) {
//         var emp = _finalList[i];
//         String empId = emp['_id'];
//         String empName = emp['name'];
//         String empDesig = emp['designation'] ?? "Staff";
//         String deptId = emp['departmentId'] ?? "";
//
//         // Identify Months
//         Set<String> monthsToFetch = {};
//         DateTime loopDate = startDate;
//         while (loopDate.isBefore(endDate) || loopDate.isAtSameMomentAs(endDate)) {
//           monthsToFetch.add(DateFormat('yyyy-MM').format(loopDate));
//           loopDate = DateTime(loopDate.year, loopDate.month + 1, 1);
//         }
//
//         Map<String, dynamic> mergedData = {};
//
//         // Fetch Data
//         for (String monthStr in monthsToFetch) {
//           if (mounted) {
//             setState(() {
//               _exportStatus = "Processing $empName ($monthStr)";
//               _exportProgress = (i + 1) / _finalList.length;
//             });
//           }
//
//           var reportData = await _apiService.getMonthlyReport(empId, monthStr, _selectedLocationId!, deptId);
//
//           if (reportData != null) {
//             List<dynamic> attList = [];
//             if (reportData['data'] is List && reportData['data'].isNotEmpty) {
//               attList = reportData['data'][0]['attendance'] ?? [];
//             } else if (reportData['attendance'] != null) {
//               attList = reportData['attendance'];
//             }
//
//             for (var item in attList) {
//               int? d = item['day'];
//               if (d != null) {
//                 String dateKey = "$monthStr-${d.toString().padLeft(2, '0')}";
//                 mergedData[dateKey] = item;
//               }
//             }
//           }
//         }
//
//         // 🔴 CALCULATE TOTALS FIRST
//         int totalPresent = 0;
//         int totalLate = 0;
//         int totalAbsent = 0;
//         int totalWorkMinutes = 0;
//         int totalOtMinutes = 0;
//
//         List<List<CellValue>> dailyRows = [];
//
//         // Loop Days to Calculate & Prepare Rows
//         for (int d = 0; d < totalDays; d++) {
//           DateTime currentDate = startDate.add(Duration(days: d));
//           String dateKey = DateFormat('yyyy-MM-dd').format(currentDate);
//
//           String inTime = "-", outTime = "-", status = "A", work = "-", ot = "-";
//
//           if (mergedData.containsKey(dateKey)) {
//             var dayData = mergedData[dateKey];
//             var inner = dayData['data'] ?? {};
//             String? note = dayData['note'];
//             String? holiday = dayData['holiday'];
//             bool isLate = inner['isLate'] == true;
//
//             // Get Backend Values
//             String rawWork = inner['workingHours'] ?? inner['duration'] ?? "";
//             String rawOT = inner['overtime'] ?? "";
//
//             if (inner['checkInTime'] != null || inner['punchIn'] != null) {
//               status = "P";
//               totalPresent++;
//               if (isLate) {
//                 status = "L"; // Late is also Present
//                 totalLate++;
//               }
//
//               inTime = _formatTimeOnly(inner['checkInTime'] ?? inner['punchIn']);
//               outTime = _formatTimeOnly(inner['checkOutTime'] ?? inner['punchOut']);
//               work = rawWork.isNotEmpty ? rawWork : "-";
//               ot = rawOT.isNotEmpty ? rawOT : "-";
//
//               // 🔢 ADD TO TOTALS
//               totalWorkMinutes += _parseDurationToMinutes(rawWork);
//               totalOtMinutes += _parseDurationToMinutes(rawOT);
//
//             } else if (holiday != null) {
//               status = "H";
//             } else if (note == "Sunday") {
//               status = "S";
//             } else if (note == "NotJoined") {
//               status = "NJ";
//             }
//           } else {
//             if (currentDate.isAfter(DateTime.now())) {
//               status = "-";
//             } else {
//               totalAbsent++;
//             }
//           }
//
//           // Prepare Row for later writing
//           dailyRows.add([
//             TextCellValue(DateFormat('dd-MMM-yyyy').format(currentDate)),
//             TextCellValue(inTime),
//             TextCellValue(outTime),
//             TextCellValue(work),
//             TextCellValue(ot),
//             TextCellValue(status),
//           ]);
//         }
//
//         // 📝 WRITE TO EXCEL
//         // 1. Employee Header
//         sheet.appendRow([TextCellValue("EMPLOYEE DETAILS")]);
//         sheet.appendRow([TextCellValue("Name"), TextCellValue(empName), TextCellValue("ID"), TextCellValue(empId), TextCellValue("Role"), TextCellValue(empDesig)]);
//
//         // 2. SUMMARY TABLE
//         sheet.appendRow([TextCellValue("")]);
//         sheet.appendRow([TextCellValue("MONTHLY SUMMARY")]);
//         sheet.appendRow([
//           TextCellValue("Total Present"),
//           TextCellValue("Total Late"),
//           TextCellValue("Total Absent"),
//           TextCellValue("Total Work Hrs"),
//           TextCellValue("Total OT Hrs")
//         ]);
//
//         sheet.appendRow([
//           IntCellValue(totalPresent),
//           IntCellValue(totalLate),
//           IntCellValue(totalAbsent),
//           TextCellValue(_formatMinutesToTime(totalWorkMinutes)),
//           TextCellValue(_formatMinutesToTime(totalOtMinutes)),
//         ]);
//
//         // 3. DAILY LOGS HEADER
//         sheet.appendRow([TextCellValue("")]);
//         sheet.appendRow([
//           TextCellValue("Date"),
//           TextCellValue("In Time"),
//           TextCellValue("Out Time"),
//           TextCellValue("Working Hrs"),
//           TextCellValue("Overtime"),
//           TextCellValue("Status")
//         ]);
//
//         // 4. DAILY LOGS
//         for (var row in dailyRows) {
//           sheet.appendRow(row);
//         }
//
//         // 5. Gap between employees
//         sheet.appendRow([TextCellValue("")]);
//         sheet.appendRow([TextCellValue("--------------------------------------------------")]);
//         sheet.appendRow([TextCellValue("")]);
//       }
//
//       setState(() => _exportStatus = "Saving...");
//       var fileBytes = excel.save();
//       String fileName = "Attendance_Report_${DateFormat('ddMM').format(startDate)}_to_${DateFormat('ddMM').format(endDate)}.xlsx";
//
//       if (fileBytes != null && mounted) {
//         _isExporting = false;
//         _showSuccessDialog(Uint8List.fromList(fileBytes), fileName);
//       }
//
//     } catch (e) {
//       if (mounted) setState(() => _isExporting = false);
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export Error: $e")));
//     }
//   }
//
//   // 🔢 Helper: Parse "08:30" or "8.5" to Minutes
//   int _parseDurationToMinutes(String? timeStr) {
//     if (timeStr == null || timeStr.isEmpty) return 0;
//     try {
//       if (timeStr.contains(":")) {
//         var parts = timeStr.split(":");
//         int h = int.parse(parts[0]);
//         int m = int.parse(parts[1]);
//         return (h * 60) + m;
//       }
//       return 0;
//     } catch (_) { return 0; }
//   }
//
//   // 🔢 Helper: Convert Minutes back to "XXh YYm"
//   String _formatMinutesToTime(int totalMinutes) {
//     if (totalMinutes == 0) return "0h 0m";
//     int h = totalMinutes ~/ 60;
//     int m = totalMinutes % 60;
//     return "${h}h ${m}m";
//   }
//
//   void _showSuccessDialog(Uint8List bytes, String fileName) {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) => AlertDialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
//         backgroundColor: Colors.white,
//         title: Column(
//           children: [
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
//               child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
//             ),
//             const SizedBox(height: 16),
//             const Text("Report Ready!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
//           ],
//         ),
//         content: const Text("Select an option below:", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
//         actionsAlignment: MainAxisAlignment.center,
//         actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
//         actions: [
//           Row(
//             children: [
//               Expanded(
//                 child: ElevatedButton.icon(
//                   onPressed: () async {
//                     Navigator.pop(context);
//                     await _saveFileToDevice(bytes, fileName);
//                   },
//                   icon: const Icon(Icons.save_alt_rounded, size: 18),
//                   label: const Text("Save"),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.white,
//                     foregroundColor: Colors.black87,
//                     elevation: 0,
//                     side: BorderSide(color: Colors.grey.shade300),
//                     padding: const EdgeInsets.symmetric(vertical: 12),
//                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                   ),
//                 ),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: ElevatedButton.icon(
//                   onPressed: () async {
//                     Navigator.pop(context);
//                     await _shareFile(bytes, fileName);
//                   },
//                   icon: const Icon(Icons.share_rounded, size: 18),
//                   label: const Text("Share"),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: const Color(0xFF2E3192),
//                     foregroundColor: Colors.white,
//                     elevation: 2,
//                     padding: const EdgeInsets.symmetric(vertical: 12),
//                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                   ),
//                 ),
//               ),
//             ],
//           )
//         ],
//       ),
//     );
//   }
//
//   Future<void> _saveFileToDevice(Uint8List bytes, String fileName) async {
//     try {
//       final tempDir = await getTemporaryDirectory();
//       final tempFile = File('${tempDir.path}/$fileName');
//       await tempFile.writeAsBytes(bytes);
//       final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
//       final filePath = await FlutterFileDialog.saveFile(params: params);
//       if (filePath != null && mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("File Saved Successfully!"), backgroundColor: Colors.green));
//       }
//     } catch (e) {
//       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not save file.")));
//     }
//   }
//
//   Future<void> _shareFile(Uint8List bytes, String fileName) async {
//     try {
//       final tempDir = await getTemporaryDirectory();
//       final file = File('${tempDir.path}/$fileName');
//       await file.writeAsBytes(bytes);
//       await Share.shareXFiles([XFile(file.path)], text: 'Attendance Report - $fileName');
//     } catch (e) {
//       debugPrint("Share Error: $e");
//     }
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
//   String _formatTimeOnly(String? val) {
//     if (val == null) return "-";
//     try {
//       if(val.contains("T")) return DateFormat('HH:mm').format(DateTime.parse(val));
//       return val;
//     } catch (_) { return val; }
//   }
//
//   String _formatSafeTime(String? val) {
//     if (val == null || val.toString().trim().isEmpty) return "--:--";
//     try {
//       DateTime dt;
//       if (val.contains("T")) {
//         dt = DateTime.parse(val).toLocal();
//       } else {
//         final now = DateTime.now();
//         final parts = val.split(':');
//         if (parts.length >= 2) {
//           dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
//         } else {
//           return val;
//         }
//       }
//       return DateFormat('hh:mm a').format(dt);
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
//     List<Map<String, dynamic>> displayList = _getFilteredList();
//
//     return Scaffold(
//       backgroundColor: const Color(0xFFF5F7FA),
//       body: Stack(
//         children: [
//           _isLoading
//               ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
//               : RefreshIndicator(
//             onRefresh: () => _fetchData(isBackground: false),
//             color: const Color(0xFF2E3192),
//             edgeOffset: 340,
//             child: displayList.isEmpty
//                 ? ListView(
//               physics: const AlwaysScrollableScrollPhysics(),
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
//                 ),
//               ],
//             )
//                 : ListView.builder(
//               physics: const AlwaysScrollableScrollPhysics(),
//               padding: EdgeInsets.fromLTRB(16, _headerHeight + 20, 16, 30),
//               itemCount: displayList.length,
//               itemBuilder: (context, index) {
//                 return _buildUltraModernCard(displayList[index]);
//               },
//             ),
//           ),
//
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
//                                     _fetchData();
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
//
//                           GestureDetector(
//                             onTap: _isExporting ? null : _processCustomRangeExport,
//                             child: Container(
//                               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
//                               decoration: BoxDecoration(
//                                 color: Colors.white,
//                                 borderRadius: BorderRadius.circular(30),
//                                 boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 4))],
//                               ),
//                               child: Row(
//                                 children: [
//                                   if (_isExporting)
//                                     SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, value: _exportProgress > 0 ? _exportProgress : null))
//                                   else
//                                     const Icon(Icons.file_download_outlined, color: Color(0xFF2E3192), size: 20),
//                                   const SizedBox(width: 8),
//                                   Text(
//                                     _isExporting ? "Exporting..." : "Excel Export",
//                                     style: const TextStyle(color: Color(0xFF2E3192), fontWeight: FontWeight.bold, fontSize: 13),
//                                   )
//                                 ],
//                               ),
//                             ),
//                           )
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
//     String workTime = item['workTime'] ?? "";
//
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
//               Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(
//                 employeeName: name,
//                 employeeId: item['_id'],
//                 locationId: _selectedLocationId!,
//                 departmentId: item['departmentId'] ?? "",
//               )))
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
//                         else ...[
//                           Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               if (isLate)
//                                 Container(
//                                     margin: const EdgeInsets.only(left: 6),
//                                     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                                     decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
//                                     child: const Text("LATE", style: TextStyle(color: Colors.deepOrange, fontSize: 9, fontWeight: FontWeight.bold))
//                                 )
//                             ],
//                           ),
//                           Text("In: $inTime", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
//                           Text(outTime == "Working" ? "Active" : "Out: $outTime", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: outTime == "Working" ? Colors.green : Colors.black87)),
//                           if(workTime.isNotEmpty && workTime != "0")
//                             Padding(
//                               padding: const EdgeInsets.only(top: 2),
//                               child: Row(children: [const Icon(Icons.timer, size: 10, color: Colors.grey), const SizedBox(width: 2), Text(workTime, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))]),
//                             )
//                         ]
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
// // import 'dart:async';
// // import 'dart:io';
// // import 'package:flutter/material.dart';
// // import 'package:intl/intl.dart';
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
// //   DateTime _selectedDate = DateTime.now();
// //   List<dynamic> _locations = [];
// //   String? _selectedLocationId;
// //   String _currentFilter = 'Total';
// //
// //   // 🔴 MASTER MAP FOR DEPARTMENT IDs
// //   Map<String, String> _employeeDepartmentMap = {};
// //
// //   // Stats
// //   int _totalStaff = 0;
// //   int _totalPresent = 0;
// //   int _totalLate = 0;
// //   int _totalAbsent = 0;
// //
// //   final double _headerHeight = 330.0;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _initData();
// //   }
// //
// //   // 🔴 INITIALIZE ALL DATA
// //   void _initData() async {
// //     setState(() => _isLoading = true);
// //
// //     try {
// //       await Future.wait([
// //         _fetchLocations(),
// //         _fetchEmployeeMap(),
// //       ]);
// //
// //       if (_selectedLocationId != null) {
// //         _fetchData(isBackground: false);
// //       } else {
// //         setState(() => _isLoading = false);
// //       }
// //     } catch (e) {
// //       if (mounted) setState(() => _isLoading = false);
// //     }
// //   }
// //
// //   Future<void> _fetchLocations() async {
// //     try {
// //       var locs = await _apiService.getLocations();
// //       if (mounted) {
// //         setState(() {
// //           _locations = locs;
// //           if (_locations.isNotEmpty) {
// //             _selectedLocationId = _locations[0]['_id'];
// //           }
// //         });
// //       }
// //     } catch (e) {
// //       debugPrint("Loc Error: $e");
// //     }
// //   }
// //
// //   Future<void> _fetchEmployeeMap() async {
// //     try {
// //       var list = await _apiService.getAllEmployees();
// //       Map<String, String> tempMap = {};
// //
// //       for (var emp in list) {
// //         String empId = emp['_id'] ?? emp['id'];
// //         String deptId = "";
// //
// //         if (emp['departmentId'] != null) {
// //           if (emp['departmentId'] is Map) {
// //             deptId = emp['departmentId']['_id'] ?? "";
// //           } else if (emp['departmentId'] is String) {
// //             deptId = emp['departmentId'];
// //           }
// //         }
// //
// //         if (empId.isNotEmpty) {
// //           tempMap[empId] = deptId;
// //         }
// //       }
// //
// //       if (mounted) {
// //         setState(() {
// //           _employeeDepartmentMap = tempMap;
// //         });
// //       }
// //     } catch (e) {
// //       debugPrint("Employee Map Error: $e");
// //     }
// //   }
// //
// //   Future<void> _fetchData({bool isBackground = false}) async {
// //     if (_selectedLocationId == null) return;
// //
// //     if (!isBackground) {
// //       setState(() => _isLoading = true);
// //     }
// //
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
// //         String empId = item['employeeId'] ?? item['_id'] ?? "";
// //
// //         String deptId = "";
// //         if (item['departmentId'] != null) {
// //           if (item['departmentId'] is Map) {
// //             deptId = item['departmentId']['_id'] ?? "";
// //           } else if (item['departmentId'] is String) {
// //             deptId = item['departmentId'];
// //           }
// //         }
// //
// //         if (deptId.isEmpty && _employeeDepartmentMap.containsKey(empId)) {
// //           deptId = _employeeDepartmentMap[empId] ?? "";
// //         }
// //
// //         var attendance = item['attendance'];
// //         String status = "Absent";
// //         String? checkIn;
// //         String? checkOut;
// //         bool isLate = false;
// //
// //         if (attendance != null && attendance is Map) {
// //           checkIn = attendance['checkInTime'] ?? attendance['punchIn'];
// //           checkOut = attendance['checkOutTime'] ?? attendance['punchOut'];
// //           // 🔴 FETCHING LATE STATUS FROM BACKEND
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
// //           'departmentId': deptId,
// //           'status': status,
// //           'checkIn': checkIn,
// //           'checkOut': checkOut,
// //           'isLate': isLate,
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
// //
// //           if (!isBackground) _isLoading = false;
// //           _currentFilter = 'Total';
// //         });
// //       }
// //     } catch (e) {
// //       if (mounted && !isBackground) setState(() => _isLoading = false);
// //     }
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
// //   // 🔴 12-HOUR FORMAT CONVERTER (AM/PM)
// //   String _formatSafeTime(String? val) {
// //     if (val == null || val.toString().trim().isEmpty) return "--:--";
// //     try {
// //       DateTime dt;
// //       // Handle "2023-01-01T15:30:00" format
// //       if (val.contains("T")) {
// //         dt = DateTime.parse(val).toLocal();
// //       }
// //       // Handle "15:30" or "15:30:00" format
// //       else {
// //         final now = DateTime.now();
// //         final parts = val.split(':');
// //         if (parts.length >= 2) {
// //           dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
// //         } else {
// //           return val;
// //         }
// //       }
// //       return DateFormat('hh:mm a').format(dt); // Returns "03:30 PM"
// //     } catch (_) {
// //       return val;
// //     }
// //   }
// //
// //   List<Map<String, dynamic>> _getFilteredList() {
// //     if (_currentFilter == 'Present') return _finalList.where((e) => e['status'] == 'Present').toList();
// //     if (_currentFilter == 'Late') return _finalList.where((e) => e['isLate'] == true).toList();
// //     if (_currentFilter == 'Absent') return _finalList.where((e) => e['status'] == 'Absent').toList();
// //     return _finalList;
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     String day = DateFormat('d').format(_selectedDate);
// //     String month = DateFormat('MMMM').format(_selectedDate);
// //     String year = DateFormat('yyyy').format(_selectedDate);
// //     String weekDay = DateFormat('EEEE').format(_selectedDate);
// //
// //     List<Map<String, dynamic>> displayList = _getFilteredList();
// //
// //     return Scaffold(
// //       backgroundColor: const Color(0xFFF5F7FA),
// //       body: Stack(
// //         children: [
// //           _isLoading
// //               ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// //               : RefreshIndicator(
// //             onRefresh: () => _fetchData(isBackground: false),
// //             color: const Color(0xFF2E3192),
// //             edgeOffset: 340,
// //             child: displayList.isEmpty
// //                 ? ListView(
// //               physics: const AlwaysScrollableScrollPhysics(),
// //               padding: EdgeInsets.only(top: _headerHeight + 50),
// //               children: [
// //                 Center(
// //                   child: Column(
// //                     mainAxisAlignment: MainAxisAlignment.center,
// //                     children: [
// //                       Icon(Icons.person_off_rounded, size: 80, color: Colors.grey.shade300),
// //                       const SizedBox(height: 15),
// //                       Text("No Attendance Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600))
// //                     ],
// //                   ),
// //                 ),
// //               ],
// //             )
// //                 : ListView.builder(
// //               physics: const AlwaysScrollableScrollPhysics(),
// //               padding: EdgeInsets.fromLTRB(16, _headerHeight + 20, 16, 30),
// //               itemCount: displayList.length,
// //               itemBuilder: (context, index) {
// //                 return _buildUltraModernCard(displayList[index]);
// //               },
// //             ),
// //           ),
// //
// //           Positioned(
// //             top: 0, left: 0, right: 0,
// //             child: Container(
// //               height: _headerHeight,
// //               decoration: const BoxDecoration(
// //                 gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF00D2FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
// //                 borderRadius: BorderRadius.only(bottomLeft: Radius.circular(36), bottomRight: Radius.circular(36)),
// //                 boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10), spreadRadius: -5)],
// //               ),
// //               child: SafeArea(
// //                 bottom: false,
// //                 child: Padding(
// //                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
// //                   child: Column(
// //                     crossAxisAlignment: CrossAxisAlignment.start,
// //                     children: [
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
// //                                   onChanged: (val) {
// //                                     setState(() => _selectedLocationId = val);
// //                                     _fetchData();
// //                                   },
// //                                 ),
// //                               ),
// //                             ),
// //                           ),
// //                         ],
// //                       ),
// //
// //                       const Spacer(),
// //
// //                       Row(
// //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                         crossAxisAlignment: CrossAxisAlignment.end,
// //                         children: [
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
// //                                 Text("$month $year", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
// //                               ],
// //                             ),
// //                           ),
// //                         ],
// //                       ),
// //
// //                       const SizedBox(height: 25),
// //
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
// //                       const SizedBox(height: 10),
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
// //         decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.08) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
// //         child: Column(children: [Text(value, style: TextStyle(color: isSelected ? color : Colors.black87, fontSize: 19, fontWeight: FontWeight.w800)), Text(label, style: TextStyle(color: isSelected ? color : Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600))]),
// //       ),
// //     );
// //   }
// //
// //   // 🔴 CARD UI WITH AM/PM AND LATE BADGE
// //   Widget _buildUltraModernCard(Map<String, dynamic> item) {
// //     String name = item['name'] ?? "Unknown";
// //     String designation = item['designation'] ?? "Staff";
// //     bool isPresent = item['status'] == 'Present';
// //     bool isLate = item['isLate'] ?? false;
// //
// //     // Time formatted to AM/PM
// //     String inTime = isPresent && item['checkIn'] != null ? _formatSafeTime(item['checkIn']) : "--:--";
// //     String outTime = isPresent && item['checkOut'] != null ? _formatSafeTime(item['checkOut']) : "Working";
// //
// //     Color statusColor = !isPresent ? const Color(0xFFFF4B4B) : (isLate ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6));
// //
// //     return Container(
// //       margin: const EdgeInsets.only(bottom: 14),
// //       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10)]),
// //       child: ClipRRect(
// //         borderRadius: BorderRadius.circular(18),
// //         child: Material(
// //           color: Colors.transparent,
// //           child: InkWell(
// //             onTap: () {
// //               Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(
// //                 employeeName: name,
// //                 employeeId: item['_id'],
// //                 locationId: _selectedLocationId!,
// //                 departmentId: item['departmentId'] ?? "",
// //               )))
// //                   .then((_) => _fetchData(isBackground: false));
// //             },
// //             child: Row(
// //               children: [
// //                 Container(width: 6, height: 90, color: statusColor),
// //                 Expanded(
// //                   child: Padding(
// //                     padding: const EdgeInsets.all(14),
// //                     child: Row(children: [
// //                       CircleAvatar(radius: 24, backgroundColor: const Color(0xFFF0F2F5), child: Text(name.isNotEmpty ? name[0] : "?", style: const TextStyle(fontWeight: FontWeight.bold))),
// //                       const SizedBox(width: 14),
// //                       Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(designation, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))])),
// //                       Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
// //                         if (!isPresent)
// //                           Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text("ABSENT", style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)))
// //                         else ...[
// //                           Row(
// //                             mainAxisSize: MainAxisSize.min,
// //                             children: [
// //
// //                               // 🔴 LATE BADGE
// //                               if (isLate)
// //                                 Container(
// //                                     margin: const EdgeInsets.only(left: 6),
// //                                     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
// //                                     decoration: BoxDecoration(
// //                                         color: Colors.orange.withOpacity(0.2),
// //                                         borderRadius: BorderRadius.circular(4)
// //                                     ),
// //                                     child: const Text("LATE", style: TextStyle(color: Colors.deepOrange, fontSize: 9, fontWeight: FontWeight.bold))
// //                                 )
// //                             ],
// //                           ),
// //                           Text("In: $inTime", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
// //                           Text(
// //                               outTime == "Working" ? "Active" : "Out: $outTime",
// //                               style: TextStyle(
// //                                   fontSize: 13,
// //                                   fontWeight: FontWeight.w700,
// //                                   color: outTime == "Working" ? Colors.green : Colors.black87
// //                               )
// //                           )
// //                         ]                        ]
// //                       )
// //                     ]),
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
// //
// //
// //
// // //
// // // import 'dart:async';
// // // import 'dart:io';
// // // import 'package:flutter/material.dart';
// // // import 'package:intl/intl.dart';
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
// // //   DateTime _selectedDate = DateTime.now();
// // //   List<dynamic> _locations = [];
// // //   String? _selectedLocationId;
// // //   String _currentFilter = 'Total';
// // //
// // //   // 🔴 MASTER MAP FOR DEPARTMENT IDs
// // //   // Key: EmployeeID, Value: DepartmentID
// // //   Map<String, String> _employeeDepartmentMap = {};
// // //
// // //   // Stats
// // //   int _totalStaff = 0;
// // //   int _totalPresent = 0;
// // //   int _totalLate = 0;
// // //   int _totalAbsent = 0;
// // //
// // //   final double _headerHeight = 330.0;
// // //
// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     _initData();
// // //   }
// // //
// // //   // 🔴 INITIALIZE ALL DATA
// // //   void _initData() async {
// // //     setState(() => _isLoading = true);
// // //
// // //     // 1. Fetch Locations
// // //     // 2. Fetch All Employees (To get Department IDs)
// // //     try {
// // //       await Future.wait([
// // //         _fetchLocations(),
// // //         _fetchEmployeeMap(),
// // //       ]);
// // //
// // //       // Data aane ke baad attendance fetch karo
// // //       if (_selectedLocationId != null) {
// // //         _fetchData(isBackground: false);
// // //       } else {
// // //         setState(() => _isLoading = false);
// // //       }
// // //     } catch (e) {
// // //       if (mounted) setState(() => _isLoading = false);
// // //     }
// // //   }
// // //
// // //   Future<void> _fetchLocations() async {
// // //     try {
// // //       var locs = await _apiService.getLocations();
// // //       if (mounted) {
// // //         setState(() {
// // //           _locations = locs;
// // //           if (_locations.isNotEmpty) {
// // //             _selectedLocationId = _locations[0]['_id'];
// // //           }
// // //         });
// // //       }
// // //     } catch (e) {
// // //       debugPrint("Loc Error: $e");
// // //     }
// // //   }
// // //
// // //   // 🔴 FETCH ALL EMPLOYEES TO MAP DEPARTMENTS
// // //   Future<void> _fetchEmployeeMap() async {
// // //     try {
// // //       var list = await _apiService.getAllEmployees();
// // //       Map<String, String> tempMap = {};
// // //
// // //       for (var emp in list) {
// // //         String empId = emp['_id'] ?? emp['id'];
// // //         String deptId = "";
// // //
// // //         // Department Extract Logic
// // //         if (emp['departmentId'] != null) {
// // //           if (emp['departmentId'] is Map) {
// // //             deptId = emp['departmentId']['_id'] ?? "";
// // //           } else if (emp['departmentId'] is String) {
// // //             deptId = emp['departmentId'];
// // //           }
// // //         }
// // //
// // //         if (empId.isNotEmpty) {
// // //           tempMap[empId] = deptId;
// // //         }
// // //       }
// // //
// // //       if (mounted) {
// // //         setState(() {
// // //           _employeeDepartmentMap = tempMap;
// // //         });
// // //         print("✅ Employee Dept Map Loaded: ${tempMap.length} entries");
// // //       }
// // //     } catch (e) {
// // //       debugPrint("Employee Map Error: $e");
// // //     }
// // //   }
// // //
// // //   Future<void> _fetchData({bool isBackground = false}) async {
// // //     if (_selectedLocationId == null) return;
// // //
// // //     if (!isBackground) {
// // //       setState(() => _isLoading = true);
// // //     }
// // //
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
// // //         String empId = item['employeeId'] ?? item['_id'] ?? "";
// // //
// // //         // 🔴 1. TRY TO GET DEPT ID FROM API RESPONSE
// // //         String deptId = "";
// // //         if (item['departmentId'] != null) {
// // //           if (item['departmentId'] is Map) {
// // //             deptId = item['departmentId']['_id'] ?? "";
// // //           } else if (item['departmentId'] is String) {
// // //             deptId = item['departmentId'];
// // //           }
// // //         }
// // //
// // //         // 🔴 2. FALLBACK: IF EMPTY, GET FROM MASTER MAP
// // //         if (deptId.isEmpty && _employeeDepartmentMap.containsKey(empId)) {
// // //           deptId = _employeeDepartmentMap[empId] ?? "";
// // //         }
// // //
// // //         var attendance = item['attendance'];
// // //         String status = "Absent";
// // //         String? checkIn;
// // //         String? checkOut;
// // //         bool isLate = false;
// // //
// // //         if (attendance != null && attendance is Map) {
// // //           checkIn = attendance['checkInTime'] ?? attendance['punchIn'];
// // //           checkOut = attendance['checkOutTime'] ?? attendance['punchOut'];
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
// // //           'departmentId': deptId, // 🔴 Passed Successfully
// // //           'status': status,
// // //           'checkIn': checkIn,
// // //           'checkOut': checkOut,
// // //           'isLate': isLate,
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
// // //
// // //           if (!isBackground) _isLoading = false;
// // //           _currentFilter = 'Total';
// // //         });
// // //       }
// // //     } catch (e) {
// // //       if (mounted && !isBackground) setState(() => _isLoading = false);
// // //     }
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
// // //   List<Map<String, dynamic>> _getFilteredList() {
// // //     if (_currentFilter == 'Present') return _finalList.where((e) => e['status'] == 'Present').toList();
// // //     if (_currentFilter == 'Late') return _finalList.where((e) => e['isLate'] == true).toList();
// // //     if (_currentFilter == 'Absent') return _finalList.where((e) => e['status'] == 'Absent').toList();
// // //     return _finalList;
// // //   }
// // //
// // //   @override
// // //   Widget build(BuildContext context) {
// // //     String day = DateFormat('d').format(_selectedDate);
// // //     String month = DateFormat('MMMM').format(_selectedDate);
// // //     String year = DateFormat('yyyy').format(_selectedDate);
// // //     String weekDay = DateFormat('EEEE').format(_selectedDate);
// // //
// // //     // Filtered List
// // //     List<Map<String, dynamic>> displayList = _getFilteredList();
// // //
// // //     return Scaffold(
// // //       backgroundColor: const Color(0xFFF5F7FA),
// // //       body: Stack(
// // //         children: [
// // //           // LAYER 1: LIST WITH PULL TO REFRESH
// // //           _isLoading
// // //               ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// // //               : RefreshIndicator(
// // //             onRefresh: () => _fetchData(isBackground: false),
// // //             color: const Color(0xFF2E3192),
// // //             edgeOffset: 340, // 🔴 Loader Header ke neeche aayega
// // //
// // //             // 🔴 FIX: Empty Check
// // //             child: displayList.isEmpty
// // //                 ? ListView(
// // //               physics: const AlwaysScrollableScrollPhysics(),
// // //               padding: EdgeInsets.only(top: _headerHeight + 50),
// // //               children: [
// // //                 Center(
// // //                   child: Column(
// // //                     mainAxisAlignment: MainAxisAlignment.center,
// // //                     children: [
// // //                       Icon(Icons.person_off_rounded, size: 80, color: Colors.grey.shade300),
// // //                       const SizedBox(height: 15),
// // //                       Text("No Attendance Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600))
// // //                     ],
// // //                   ),
// // //                 ),
// // //               ],
// // //             )
// // //                 : ListView.builder(
// // //               physics: const AlwaysScrollableScrollPhysics(),
// // //               padding: EdgeInsets.fromLTRB(16, _headerHeight + 20, 16, 30),
// // //               itemCount: displayList.length,
// // //               itemBuilder: (context, index) {
// // //                 return _buildUltraModernCard(displayList[index]);
// // //               },
// // //             ),
// // //           ),
// // //
// // //           // LAYER 2: HEADER (Unchanged)
// // //           Positioned(
// // //             top: 0, left: 0, right: 0,
// // //             child: Container(
// // //               height: _headerHeight,
// // //               decoration: const BoxDecoration(
// // //                 gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF00D2FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
// // //                 borderRadius: BorderRadius.only(bottomLeft: Radius.circular(36), bottomRight: Radius.circular(36)),
// // //                 boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10), spreadRadius: -5)],
// // //               ),
// // //               child: SafeArea(
// // //                 bottom: false,
// // //                 child: Padding(
// // //                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
// // //                   child: Column(
// // //                     crossAxisAlignment: CrossAxisAlignment.start,
// // //                     children: [
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
// // //                                   onChanged: (val) {
// // //                                     setState(() => _selectedLocationId = val);
// // //                                     _fetchData();
// // //                                   },
// // //                                 ),
// // //                               ),
// // //                             ),
// // //                           ),
// // //                         ],
// // //                       ),
// // //
// // //                       const Spacer(),
// // //
// // //                       // Date Row
// // //                       Row(
// // //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // //                         crossAxisAlignment: CrossAxisAlignment.end,
// // //                         children: [
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
// // //                                 Text("$month $year", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
// // //                               ],
// // //                             ),
// // //                           ),
// // //                           // Export removed as per previous code
// // //                         ],
// // //                       ),
// // //
// // //                       const SizedBox(height: 25),
// // //
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
// // //                       const SizedBox(height: 10),
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
// // //         decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.08) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
// // //         child: Column(children: [Text(value, style: TextStyle(color: isSelected ? color : Colors.black87, fontSize: 19, fontWeight: FontWeight.w800)), Text(label, style: TextStyle(color: isSelected ? color : Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600))]),
// // //       ),
// // //     );
// // //   }
// // //
// // //   Widget _buildUltraModernCard(Map<String, dynamic> item) {
// // //     String name = item['name'] ?? "Unknown";
// // //     String designation = item['designation'] ?? "Staff";
// // //     bool isPresent = item['status'] == 'Present';
// // //     bool isLate = item['isLate'] ?? false;
// // //     String inTime = isPresent && item['checkIn'] != null ? _formatSafeTime(item['checkIn']) : "--:--";
// // //     String outTime = isPresent && item['checkOut'] != null ? _formatSafeTime(item['checkOut']) : "Working";
// // //     Color statusColor = !isPresent ? const Color(0xFFFF4B4B) : (isLate ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6));
// // //
// // //     return Container(
// // //       margin: const EdgeInsets.only(bottom: 14),
// // //       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10)]),
// // //       child: ClipRRect(
// // //         borderRadius: BorderRadius.circular(18),
// // //         child: Material(
// // //           color: Colors.transparent,
// // //           child: InkWell(
// // //             onTap: () {
// // //               Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(
// // //                 employeeName: name,
// // //                 employeeId: item['_id'],
// // //                 locationId: _selectedLocationId!,
// // //                 departmentId: item['departmentId'] ?? "", // 🔴 USING FETCHED/MAPPED DEPT ID
// // //               )))
// // //                   .then((_) => _fetchData(isBackground: false));
// // //             },
// // //             child: Row(
// // //               children: [
// // //                 Container(width: 6, height: 90, color: statusColor),
// // //                 Expanded(
// // //                   child: Padding(
// // //                     padding: const EdgeInsets.all(14),
// // //                     child: Row(children: [
// // //                       CircleAvatar(radius: 24, backgroundColor: const Color(0xFFF0F2F5), child: Text(name.isNotEmpty ? name[0] : "?", style: const TextStyle(fontWeight: FontWeight.bold))),
// // //                       const SizedBox(width: 14),
// // //                       Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(designation, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))])),
// // //                       Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
// // //                         if (!isPresent)
// // //                           Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text("ABSENT", style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)))
// // //                         else ...[Text("In: $inTime", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)), Text(outTime == "Working" ? "Active" : outTime, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: outTime == "Working" ? Colors.green : Colors.black87))]
// // //                       ])
// // //                     ]),
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
// // // // import 'dart:async';
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
// // // //   // Stats
// // // //   int _totalStaff = 0;
// // // //   int _totalPresent = 0;
// // // //   int _totalLate = 0;
// // // //   int _totalAbsent = 0;
// // // //
// // // //   final double _headerHeight = 330.0;
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
// // // //   Future<void> _fetchData({bool isBackground = false}) async {
// // // //     if (_selectedLocationId == null) return;
// // // //
// // // //     if (!isBackground) {
// // // //       setState(() => _isLoading = true);
// // // //     }
// // // //
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
// // // //
// // // //           if (!isBackground) _isLoading = false;
// // // //           _currentFilter = 'Total';
// // // //         });
// // // //       }
// // // //     } catch (e) {
// // // //       if (mounted && !isBackground) setState(() => _isLoading = false);
// // // //     }
// // // //   }
// // // //
// // // //   Future<void> _processCustomRangeExport() async {
// // // //     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Export feature disabled.")));
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
// // // //   List<Map<String, dynamic>> _getFilteredList() {
// // // //     if (_currentFilter == 'Present') return _finalList.where((e) => e['status'] == 'Present').toList();
// // // //     if (_currentFilter == 'Late') return _finalList.where((e) => e['isLate'] == true).toList();
// // // //     if (_currentFilter == 'Absent') return _finalList.where((e) => e['status'] == 'Absent').toList();
// // // //     return _finalList;
// // // //   }
// // // //
// // // //   @override
// // // //   Widget build(BuildContext context) {
// // // //     String day = DateFormat('d').format(_selectedDate);
// // // //     String month = DateFormat('MMMM').format(_selectedDate);
// // // //     String year = DateFormat('yyyy').format(_selectedDate);
// // // //     String weekDay = DateFormat('EEEE').format(_selectedDate);
// // // //
// // // //     // Filtered list nikal lo
// // // //     List<Map<String, dynamic>> displayList = _getFilteredList();
// // // //
// // // //     return Scaffold(
// // // //       backgroundColor: const Color(0xFFF5F7FA),
// // // //       body: Stack(
// // // //         children: [
// // // //           // 🔴 LAYER 1: LIST (CRASH PROOF LOGIC)
// // // //           _isLoading
// // // //               ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// // // //               : RefreshIndicator(
// // // //             onRefresh: () => _fetchData(isBackground: false),
// // // //             color: const Color(0xFF2E3192),
// // // //             edgeOffset: 340, // Header ke neeche loader
// // // //
// // // //             // 🔴 FIX: Yahan Check lagaya hai.
// // // //             // Agar List khali hai to 'ListView' return karo (builder nahi).
// // // //             // Agar Data hai to 'ListView.builder' return karo.
// // // //             child: displayList.isEmpty
// // // //                 ? ListView(
// // // //               physics: const AlwaysScrollableScrollPhysics(), // Scroll chalu rakho refresh ke liye
// // // //               padding: EdgeInsets.only(top: _headerHeight + 50),
// // // //               children: [
// // // //                 Center(
// // // //                   child: Column(
// // // //                     mainAxisAlignment: MainAxisAlignment.center,
// // // //                     children: [
// // // //                       Icon(Icons.person_off_rounded, size: 80, color: Colors.grey.shade300),
// // // //                       const SizedBox(height: 15),
// // // //                       Text("No Attendance Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600))
// // // //                     ],
// // // //                   ),
// // // //                 )
// // // //               ],
// // // //             )
// // // //                 : ListView.builder(
// // // //               physics: const AlwaysScrollableScrollPhysics(),
// // // //               padding: EdgeInsets.fromLTRB(16, _headerHeight + 20, 16, 30),
// // // //               itemCount: displayList.length, // Ab ye kabhi 0 hone par crash nahi karega
// // // //               itemBuilder: (context, index) {
// // // //                 return _buildUltraModernCard(displayList[index]);
// // // //               },
// // // //             ),
// // // //           ),
// // // //
// // // //           // LAYER 2: HEADER (Unchanged)
// // // //           Positioned(
// // // //             top: 0, left: 0, right: 0,
// // // //             child: Container(
// // // //               height: _headerHeight,
// // // //               decoration: const BoxDecoration(
// // // //                 gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF00D2FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
// // // //                 borderRadius: BorderRadius.only(bottomLeft: Radius.circular(36), bottomRight: Radius.circular(36)),
// // // //                 boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10), spreadRadius: -5)],
// // // //               ),
// // // //               child: SafeArea(
// // // //                 bottom: false,
// // // //                 child: Padding(
// // // //                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
// // // //                   child: Column(
// // // //                     crossAxisAlignment: CrossAxisAlignment.start,
// // // //                     children: [
// // // //                       Row(
// // // //                         children: [
// // // //                           GestureDetector(
// // // //                             onTap: () => Navigator.pop(context),
// // // //                             child: Container(
// // // //                               width: 42, height: 42,
// // // //                               decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
// // // //                               child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
// // // //                             ),
// // // //                           ),
// // // //                           const SizedBox(width: 12),
// // // //                           Exapanded(
// // // //                             child: Container(
// // // //                               height: 42,
// // // //                               padding: const EdgeInsets.symmetric(horizontal: 16),
// // // //                               decoration: BoxDecoration(
// // // //                                 color: Colors.white.withOpacity(0.15),
// // // //                                 borderRadius: BorderRadius.circular(12),
// // // //                                 border: Border.all(color: Colors.white.withOpacity(0.2)),
// // // //                               ),
// // // //                               child: DropdownButtonHideUnderline(
// // // //                                 child: DropdownButton<String>(
// // // //                                   value: _selectedLocationId,
// // // //                                   dropdownColor: const Color(0xFF2E3192),
// // // //                                   icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
// // // //                                   hint: const Text("Select Location", style: TextStyle(color: Colors.white70)),
// // // //                                   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
// // // //                                   items: _locations.map<DropdownMenuItem<String>>((dynamic loc) {
// // // //                                     return DropdownMenuItem<String>(value: loc['_id'], child: Text(loc['name'], overflow: TextOverflow.ellipsis));
// // // //                                   }).toList(),
// // // //                                   onChanged: (val) {
// // // //                                     setState(() => _selectedLocationId = val);
// // // //                                     _fetchData(isBackground: false);
// // // //                                   },
// // // //                                 ),
// // // //                               ),
// // // //                             ),
// // // //                           ),
// // // //                         ],
// // // //                       ),
// // // //
// // // //                       const Spacer(),
// // // //
// // // //                       Row(
// // // //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // // //                         crossAxisAlignment: CrossAxisAlignment.end,
// // // //                         children: [
// // // //                           GestureDetector(
// // // //                             onTap: _pickDate,
// // // //                             child: Column(
// // // //                               crossAxisAlignment: CrossAxisAlignment.start,
// // // //                               mainAxisSize: MainAxisSize.min,
// // // //                               children: [
// // // //                                 Row(
// // // //                                   crossAxisAlignment: CrossAxisAlignment.baseline,
// // // //                                   textBaseline: TextBaseline.alphabetic,
// // // //                                   children: [
// // // //                                     Text(day, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1)),
// // // //                                     const SizedBox(width: 8),
// // // //                                     Text(weekDay.substring(0,3).toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
// // // //                                   ],
// // // //                                 ),
// // // //                                 Text("$month $year", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
// // // //                               ],
// // // //                             ),
// // // //                           ),
// // // //                           GestureDetector(
// // // //                             onTap: _isExporting ? null : _processCustomRangeExport,
// // // //                             child: Container(
// // // //                               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
// // // //                               decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
// // // //                               child: Row(
// // // //                                 children: [
// // // //                                   const Icon(Icons.file_download_outlined, color: Color(0xFF2E3192), size: 20),
// // // //                                   const SizedBox(width: 8),
// // // //                                   const Text("Export", style: TextStyle(color: Color(0xFF2E3192), fontWeight: FontWeight.bold)),
// // // //                                 ],
// // // //                               ),
// // // //                             ),
// // // //                           ),
// // // //                         ],
// // // //                       ),
// // // //
// // // //                       const SizedBox(height: 25),
// // // //
// // // //                       Container(
// // // //                         padding: const EdgeInsets.symmetric(vertical: 16),
// // // //                         decoration: BoxDecoration(
// // // //                           color: Colors.white,
// // // //                           borderRadius: BorderRadius.circular(24),
// // // //                           boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))],
// // // //                         ),
// // // //                         child: Row(
// // // //                           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
// // // //                           children: [
// // // //                             _buildCompactStat("Total", _totalStaff.toString(), Colors.blue.shade800, 'Total'),
// // // //                             Container(width: 1, height: 25, color: Colors.grey.shade200),
// // // //                             _buildCompactStat("Present", _totalPresent.toString(), Colors.green.shade600, 'Present'),
// // // //                             Container(width: 1, height: 25, color: Colors.grey.shade200),
// // // //                             _buildCompactStat("Late", _totalLate.toString(), Colors.orange.shade700, 'Late'),
// // // //                             Container(width: 1, height: 25, color: Colors.grey.shade200),
// // // //                             _buildCompactStat("Absent", _totalAbsent.toString(), Colors.red.shade600, 'Absent'),
// // // //                           ],
// // // //                         ),
// // // //                       ),
// // // //                       const SizedBox(height: 10),
// // // //                     ],
// // // //                   ),
// // // //                 ),
// // // //               ),
// // // //             ),
// // // //           ),
// // // //         ],
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildCompactStat(String label, String value, Color color, String filterKey) {
// // // //     bool isSelected = _currentFilter == filterKey;
// // // //     return InkWell(
// // // //       onTap: () => setState(() => _currentFilter = filterKey),
// // // //       child: Container(
// // // //         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
// // // //         decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.08) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
// // // //         child: Column(children: [Text(value, style: TextStyle(color: isSelected ? color : Colors.black87, fontSize: 19, fontWeight: FontWeight.w800)), Text(label, style: TextStyle(color: isSelected ? color : Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600))]),
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildUltraModernCard(Map<String, dynamic> item) {
// // // //     String name = item['name'] ?? "Unknown";
// // // //     String designation = item['designation'] ?? "Staff";
// // // //     bool isPresent = item['status'] == 'Present';
// // // //     bool isLate = item['isLate'] ?? false;
// // // //     String inTime = isPresent && item['checkIn'] != null ? _formatSafeTime(item['checkIn']) : "--:--";
// // // //     String outTime = isPresent && item['checkOut'] != null ? _formatSafeTime(item['checkOut']) : "Working";
// // // //     Color statusColor = !isPresent ? const Color(0xFFFF4B4B) : (isLate ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6));
// // // //
// // // //     return Container(
// // // //       margin: const EdgeInsets.only(bottom: 14),
// // // //       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10)]),
// // // //       child: ClipRRect(
// // // //         borderRadius: BorderRadius.circular(18),
// // // //         child: Material(
// // // //           color: Colors.transparent,
// // // //           child: InkWell(
// // // //             onTap: () {
// // // //               Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceHistoryScreen(employeeName: name, employeeId: item['_id'], locationId: _selectedLocationId!)))
// // // //                   .then((_) => _fetchData(isBackground: false));
// // // //             },
// // // //             child: Row(
// // // //               children: [
// // // //                 Container(width: 6, height: 90, color: statusColor),
// // // //                 Expanded(
// // // //                   child: Padding(
// // // //                     padding: const EdgeInsets.all(14),
// // // //                     child: Row(children: [
// // // //                       CircleAvatar(radius: 24, backgroundColor: const Color(0xFFF0F2F5), child: Text(name.isNotEmpty ? name[0] : "?", style: const TextStyle(fontWeight: FontWeight.bold))),
// // // //                       const SizedBox(width: 14),
// // // //                       Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(designation, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))])),
// // // //                       Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
// // // //                         if (!isPresent)
// // // //                           Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text("ABSENT", style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)))
// // // //                         else ...[Text("In: $inTime", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)), Text(outTime == "Working" ? "Active" : outTime, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: outTime == "Working" ? Colors.green : Colors.black87))]
// // // //                       ])
// // // //                     ]),
// // // //                   ),
// // // //                 )
// // // //               ],
// // // //             ),
// // // //           ),
// // // //         ),
// // // //       ),
// // // //     );
// // // //   }
// // // // }
// // // //
// // // //
