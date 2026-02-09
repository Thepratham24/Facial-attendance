import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../main.dart'; // Access global variables if needed
import 'attendance_history_screen.dart';
import 'face_capture_update_screen.dart';

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _employees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    // 🔴 Timer Removed completely
  }

  // 🔴 Changed to Future<void> for RefreshIndicator
  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);

    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Check Internet Connection")));
        }
        return;
      }

      var list = await _apiService.getAllEmployees();

      if (mounted) {
        setState(() {
          _employees = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // UPDATE FACE LOGIC (Unchanged)
  void _handleUpdateFace(String empId, String empName) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Update Face Data?"),
        content: Text("This will overwrite the existing face data for $empName. Are you sure?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Yes, Update", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final List<double>? newEmbedding = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FaceCaptureScreen()),
    );

    if (newEmbedding != null) {
      setState(() => _isLoading = true);

      bool success = await _apiService.updateEmployeeFace(empId, newEmbedding);

      setState(() => _isLoading = false);
      _loadEmployees(); // Manual Refresh after update

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Face Updated Successfully!"), backgroundColor: Colors.green)
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Failed to update face."), backgroundColor: Colors.red)
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
          : Stack(
        children: [
          // 🔴 REFRESH INDICATOR ADDED HERE
          RefreshIndicator(
            onRefresh: _loadEmployees,
            color: const Color(0xFF2E3192),
            edgeOffset: 270, // 🔥 ISSE LOADER HEADER KE NEECHE DIKHEGA
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(), // Ensures refresh works even if list is short
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 280)),
                _employees.isEmpty
                    ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
                    : SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: _buildPremiumEmployeeCard(_employees[index]),
                      );
                    },
                    childCount: _employees.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 30)),
              ],
            ),
          ),
          _buildPremiumHeader(),
        ],
      ),
    );
  }

  Widget _buildPremiumHeader() {
    return Container(
      height: 260,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
        boxShadow: [
          BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(top: -60, right: -40, child: _buildDecorativeCircle(180)),
          Positioned(bottom: 40, left: -20, child: _buildDecorativeCircle(100)),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                        ),
                      ),
                      const SizedBox(width: 15),
                      const Text(
                        "Staff Directory",
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Total Employees", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14, letterSpacing: 1)),
                          const SizedBox(height: 5),
                          Text("${_employees.length}", style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 32),
                      )
                    ],
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecorativeCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), shape: BoxShape.circle),
    );
  }

  Widget _buildPremiumEmployeeCard(dynamic emp) {
    String name = emp['name'] ?? "Unknown";
    String empId = emp['_id'] ?? emp['id'] ?? "";

    // Designation Logic
    String designation = "Staff";
    var rawDesig = emp['designation'];
    if (rawDesig is String) designation = rawDesig;
    else if (rawDesig is Map) designation = rawDesig['name'] ?? "Staff";

    String phone = emp['phone']?.toString() ?? "N/A";
    String email = emp['email']?.toString() ?? "N/A";
    String firstLetter = name.isNotEmpty ? name[0].toUpperCase() : "?";

    // Location Logic (Fixed for Array)
    String locationId = "";

    if (emp['locations'] != null && emp['locations'] is List && emp['locations'].isNotEmpty) {
      locationId = emp['locations'][0]['_id'] ?? ""; // Array se ID nikala
    } else if (emp['locationId'] is String) {
      locationId = emp['locationId'];
    } else if (emp['location'] is Map) {
      locationId = emp['location']['_id'] ?? "";
    }

    String departmentId = "";
    var rawDept = emp['departmentId'];
    if (rawDept is String) {
      departmentId = rawDept;
    } else if (rawDept is Map) {
      departmentId = rawDept['_id'] ?? "";
    }

    // Image Logic
    String imagePath = emp['trim_faceImage'] ?? emp['faceImage'] ?? "";
    String fullImageUrl = imagePath.isNotEmpty ? "${_apiService.baseUrl}/$imagePath" : "";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            // Passing Correct Location ID
            Navigator.push(context, MaterialPageRoute(builder: (context) => AttendanceHistoryScreen(
                employeeName: name,
                employeeId: empId,
                locationId: locationId,
                departmentId: departmentId,
            )));
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2E3192).withOpacity(0.2), width: 2)),
                  child: SecureAvatar(imageUrl: fullImageUrl, initials: firstLetter),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with Menu
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF2D3142))),
                          ),
                          SizedBox(
                            height: 24, width: 24,
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'update',
                                  child: Row(children: [
                                    Icon(Icons.face, color: Colors.blueAccent, size: 18),
                                    SizedBox(width: 10),
                                    Text("Update Face", style: TextStyle(fontSize: 13))
                                  ]),
                                )
                              ],
                              onSelected: (val) {
                                if(val == 'update') _handleUpdateFace(empId, name);
                              },
                            ),
                          )
                        ],
                      ),

                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFF3F6FF), borderRadius: BorderRadius.circular(8)),
                        child: Text(designation.toUpperCase(), style: const TextStyle(color: Color(0xFF2E3192), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      ),
                      const SizedBox(height: 10),
                      _buildContactRow(Icons.phone_rounded, phone),
                      const SizedBox(height: 4),
                      _buildContactRow(Icons.email_rounded, email),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String text) {
    return Row(children: [Icon(icon, size: 12, color: Colors.grey.shade400), const SizedBox(width: 6), Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis))]);
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.person_add_disabled, size: 50, color: Colors.indigo.withOpacity(0.3)), const SizedBox(height: 20), Text("No Employees Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600))]));
  }
}

class SecureAvatar extends StatefulWidget {
  final String imageUrl;
  final String initials;

  const SecureAvatar({super.key, required this.imageUrl, required this.initials});

  @override
  State<SecureAvatar> createState() => _SecureAvatarState();
}

class _SecureAvatarState extends State<SecureAvatar> {
  Uint8List? _imageBytes;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.imageUrl.isNotEmpty) _fetchImage();
  }

  Future<void> _fetchImage() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(widget.imageUrl));
      if (response.statusCode == 200 && mounted) {
        setState(() { _imageBytes = response.bodyBytes; _isLoading = false; });
      } else {
        if (mounted) setState(() { _hasError = true; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 26,
      backgroundColor: const Color(0xFFF3F6FF),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (widget.imageUrl.isEmpty || _hasError) return Text(widget.initials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2E3192)));
    if (_isLoading) return const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E3192)));
    if (_imageBytes != null) return ClipOval(child: Image.memory(_imageBytes!, width: 52, height: 52, fit: BoxFit.cover));
    return Text(widget.initials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2E3192)));
  }
}





























// import 'dart:async'; // 🔴 Timer ke liye
// import 'dart:io';
// import 'dart:typed_data';
// import 'package:http/http.dart' as http;
// import 'package:flutter/material.dart';
//
// // Aapke Project Imports
// import '../../services/api_service.dart';
// import '../../main.dart'; // Access global variables if needed
// import 'attendance_history_screen.dart';
// import 'face_capture_update_screen.dart';
//
// class EmployeeListScreen extends StatefulWidget {
//   const EmployeeListScreen({super.key});
//
//   @override
//   State<EmployeeListScreen> createState() => _EmployeeListScreenState();
// }
//
// class _EmployeeListScreenState extends State<EmployeeListScreen> {
//   final ApiService _apiService = ApiService();
//   List<dynamic> _employees = [];
//   bool _isLoading = true;
//
//   // 🔴 TIMER VARIABLE
//   Timer? _timer;
//
//   @override
//   void initState() {
//     super.initState();
//     _loadEmployees(); // Pehli baar load karo
//
//     // 🔴 AUTO REFRESH (Har 5 second mein chupke se data layega)
//     _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
//       if (mounted) {
//         _loadEmployees(isBackground: true);
//       }
//     });
//   }
//
//   @override
//   void dispose() {
//     _timer?.cancel(); // 🔴 Screen band hone par timer roko
//     super.dispose();
//   }
//
//   // 🔴 LOAD EMPLOYEES (Modified for Silent Refresh)
//   void _loadEmployees({bool isBackground = false}) async {
//     // Agar background refresh hai to Loading mat dikhao
//     if (!isBackground) {
//       setState(() => _isLoading = true);
//     }
//
//     try {
//       // Internet Check (Background me skip kar sakte hain taaki bar bar toast na aaye)
//       if (!isBackground) {
//         final result = await InternetAddress.lookup('google.com');
//         if (result.isEmpty || result[0].rawAddress.isEmpty) {
//           if (mounted) {
//             setState(() => _isLoading = false);
//             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Check Internet Connection")));
//           }
//           return;
//         }
//       }
//
//       var list = await _apiService.getAllEmployees();
//
//       if (mounted) {
//         setState(() {
//           _employees = list;
//           _isLoading = false; // Loader band
//         });
//       }
//     } catch (e) {
//       if (mounted) {
//         if (!isBackground) {
//           setState(() => _isLoading = false);
//         }
//       }
//     }
//   }
//
//   // 🔴 UPDATE FACE LOGIC
//   void _handleUpdateFace(String empId, String empName) async {
//     bool? confirm = await showDialog(
//       context: context,
//       builder: (c) => AlertDialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
//         title: const Text("Update Face Data?"),
//         content: Text("This will overwrite the existing face data for $empName. Are you sure?"),
//         actions: [
//           TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
//           ElevatedButton(
//             onPressed: () => Navigator.pop(c, true),
//             style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
//             child: const Text("Yes, Update", style: TextStyle(color: Colors.white)),
//           ),
//         ],
//       ),
//     );
//
//     if (confirm != true) return;
//
//     // Open Camera
//     final List<double>? newEmbedding = await Navigator.push(
//       context,
//       MaterialPageRoute(builder: (context) => const FaceCaptureScreen()),
//     );
//
//     if (newEmbedding != null) {
//       setState(() => _isLoading = true);
//
//       bool success = await _apiService.updateEmployeeFace(empId, newEmbedding);
//
//       setState(() => _isLoading = false);
//       _loadEmployees(isBackground: true); // Refresh List
//
//       if (mounted) {
//         if (success) {
//           ScaffoldMessenger.of(context).showSnackBar(
//               const SnackBar(content: Text("Face Updated Successfully!"), backgroundColor: Colors.green)
//           );
//         } else {
//           ScaffoldMessenger.of(context).showSnackBar(
//               const SnackBar(content: Text("Failed to update face."), backgroundColor: Colors.red)
//           );
//         }
//       }
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF2F5F9),
//       body: _isLoading
//           ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
//           : Stack(
//         children: [
//           CustomScrollView(
//             slivers: [
//               const SliverToBoxAdapter(child: SizedBox(height: 280)),
//               _employees.isEmpty
//                   ? SliverFillRemaining(
//                 hasScrollBody: false,
//                 child: _buildEmptyState(),
//               )
//                   : SliverList(
//                 delegate: SliverChildBuilderDelegate(
//                       (context, index) {
//                     return Padding(
//                       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
//                       child: _buildPremiumEmployeeCard(_employees[index]),
//                     );
//                   },
//                   childCount: _employees.length,
//                 ),
//               ),
//               const SliverToBoxAdapter(child: SizedBox(height: 30)),
//             ],
//           ),
//           _buildPremiumHeader(),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildPremiumHeader() {
//     return Container(
//       height: 260,
//       decoration: const BoxDecoration(
//         gradient: LinearGradient(
//           colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//         borderRadius: BorderRadius.only(
//           bottomLeft: Radius.circular(40),
//           bottomRight: Radius.circular(40),
//         ),
//         boxShadow: [
//           BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10)),
//         ],
//       ),
//       child: Stack(
//         children: [
//           Positioned(top: -60, right: -40, child: _buildDecorativeCircle(180)),
//           Positioned(bottom: 40, left: -20, child: _buildDecorativeCircle(100)),
//
//           SafeArea(
//             child: Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Row(
//                     children: [
//                       GestureDetector(
//                         onTap: () => Navigator.pop(context),
//                         child: Container(
//                           padding: const EdgeInsets.all(12),
//                           decoration: BoxDecoration(
//                             color: Colors.white.withOpacity(0.2),
//                             borderRadius: BorderRadius.circular(14),
//                             border: Border.all(color: Colors.white.withOpacity(0.1)),
//                           ),
//                           child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
//                         ),
//                       ),
//                       const SizedBox(width: 15),
//                       const Text(
//                         "Staff Directory",
//                         style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
//                       ),
//                     ],
//                   ),
//                   const Spacer(),
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     crossAxisAlignment: CrossAxisAlignment.end,
//                     children: [
//                       Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text("Total Employees", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14, letterSpacing: 1)),
//                           const SizedBox(height: 5),
//                           Text("${_employees.length}", style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1)),
//                         ],
//                       ),
//                       Container(
//                         padding: const EdgeInsets.all(15),
//                         decoration: BoxDecoration(
//                           color: Colors.white.withOpacity(0.15),
//                           borderRadius: BorderRadius.circular(20),
//                           border: Border.all(color: Colors.white.withOpacity(0.2)),
//                         ),
//                         child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 32),
//                       )
//                     ],
//                   ),
//                   const SizedBox(height: 30),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildDecorativeCircle(double size) {
//     return Container(
//       width: size,
//       height: size,
//       decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), shape: BoxShape.circle),
//     );
//   }
//
//   Widget _buildPremiumEmployeeCard(dynamic emp) {
//     String name = emp['name'] ?? "Unknown";
//     String empId = emp['_id'] ?? emp['id'] ?? "";
//
//     // Designation Logic
//     String designation = "Staff";
//     var rawDesig = emp['designation'];
//     if (rawDesig is String) designation = rawDesig;
//     else if (rawDesig is Map) designation = rawDesig['name'] ?? "Staff";
//
//     String phone = emp['phone']?.toString() ?? "N/A";
//     String email = emp['email']?.toString() ?? "N/A";
//     String firstLetter = name.isNotEmpty ? name[0].toUpperCase() : "?";
//
//     // 🔴 100% WORKING LOCATION FIX (Array Handling)
//     String locationId = "";
//     if (emp['locations'] != null && emp['locations'] is List && emp['locations'].isNotEmpty) {
//       locationId = emp['locations'][0]['_id'] ?? ""; // Array se ID nikala
//     } else if (emp['locationId'] is String) {
//       locationId = emp['locationId'];
//     } else if (emp['location'] is Map) {
//       locationId = emp['location']['_id'] ?? "";
//     }
//
//     // Image Logic
//     String imagePath = emp['trim_faceImage'] ?? emp['faceImage'] ?? "";
//     String fullImageUrl = imagePath.isNotEmpty ? "${_apiService.baseUrl}/$imagePath" : "";
//
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(24),
//         boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 8))],
//       ),
//       child: Material(
//         color: Colors.transparent,
//         child: InkWell(
//           borderRadius: BorderRadius.circular(24),
//           onTap: () {
//             // 🔴 Passing Correct Location ID
//             Navigator.push(context, MaterialPageRoute(builder: (context) => AttendanceHistoryScreen(
//                 employeeName: name,
//                 employeeId: empId,
//                 locationId: locationId
//             )));
//           },
//           child: Padding(
//             padding: const EdgeInsets.all(18),
//             child: Row(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Container(
//                   padding: const EdgeInsets.all(3),
//                   decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2E3192).withOpacity(0.2), width: 2)),
//                   child: SecureAvatar(imageUrl: fullImageUrl, initials: firstLetter),
//                 ),
//                 const SizedBox(width: 15),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       // Header with Menu
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Expanded(
//                             child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF2D3142))),
//                           ),
//                           SizedBox(
//                             height: 24, width: 24,
//                             child: PopupMenuButton<String>(
//                               padding: EdgeInsets.zero,
//                               icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade400),
//                               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                               itemBuilder: (context) => [
//                                 const PopupMenuItem(
//                                   value: 'update',
//                                   child: Row(children: [
//                                     Icon(Icons.face, color: Colors.blueAccent, size: 18),
//                                     SizedBox(width: 10),
//                                     Text("Update Face", style: TextStyle(fontSize: 13))
//                                   ]),
//                                 )
//                               ],
//                               onSelected: (val) {
//                                 if(val == 'update') _handleUpdateFace(empId, name);
//                               },
//                             ),
//                           )
//                         ],
//                       ),
//
//                       const SizedBox(height: 6),
//                       Container(
//                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//                         decoration: BoxDecoration(color: const Color(0xFFF3F6FF), borderRadius: BorderRadius.circular(8)),
//                         child: Text(designation.toUpperCase(), style: const TextStyle(color: Color(0xFF2E3192), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
//                       ),
//                       const SizedBox(height: 10),
//                       _buildContactRow(Icons.phone_rounded, phone),
//                       const SizedBox(height: 4),
//                       _buildContactRow(Icons.email_rounded, email),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildContactRow(IconData icon, String text) {
//     return Row(children: [Icon(icon, size: 12, color: Colors.grey.shade400), const SizedBox(width: 6), Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis))]);
//   }
//
//   Widget _buildEmptyState() {
//     return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.person_add_disabled, size: 50, color: Colors.indigo.withOpacity(0.3)), const SizedBox(height: 20), Text("No Employees Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600))]));
//   }
// }
//
// // 🔴 SECURE AVATAR
// class SecureAvatar extends StatefulWidget {
//   final String imageUrl;
//   final String initials;
//
//   const SecureAvatar({super.key, required this.imageUrl, required this.initials});
//
//   @override
//   State<SecureAvatar> createState() => _SecureAvatarState();
// }
//
// class _SecureAvatarState extends State<SecureAvatar> {
//   Uint8List? _imageBytes;
//   bool _isLoading = false;
//   bool _hasError = false;
//
//   @override
//   void initState() {
//     super.initState();
//     if (widget.imageUrl.isNotEmpty) _fetchImage();
//   }
//
//   Future<void> _fetchImage() async {
//     if (!mounted) return;
//     setState(() => _isLoading = true);
//     try {
//       final response = await http.get(Uri.parse(widget.imageUrl));
//       if (response.statusCode == 200 && mounted) {
//         setState(() { _imageBytes = response.bodyBytes; _isLoading = false; });
//       } else {
//         if (mounted) setState(() { _hasError = true; _isLoading = false; });
//       }
//     } catch (e) {
//       if (mounted) setState(() { _hasError = true; _isLoading = false; });
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return CircleAvatar(
//       radius: 26,
//       backgroundColor: const Color(0xFFF3F6FF),
//       child: _buildContent(),
//     );
//   }
//
//   Widget _buildContent() {
//     if (widget.imageUrl.isEmpty || _hasError) return Text(widget.initials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2E3192)));
//     if (_isLoading) return const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E3192)));
//     if (_imageBytes != null) return ClipOval(child: Image.memory(_imageBytes!, width: 52, height: 52, fit: BoxFit.cover));
//     return Text(widget.initials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2E3192)));
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
// // import 'dart:io';
// // import 'dart:convert';
// // import 'dart:typed_data';
// // import 'package:camera/camera.dart'; // 🔴 For Camera
// // import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'; // 🔴 For ML Kit
// // import 'package:http/http.dart' as http;
// // import 'package:flutter/material.dart';
// // import '../../services/api_service.dart';
// // import '../../services/ml_service.dart'; // 🔴 Ensure MLService import
// // import '../../main.dart'; // 🔴 To access 'cameras' list
// // import 'attendance_history_screen.dart';
// // import 'face_capture_update_screen.dart';
// //
// // class EmployeeListScreen extends StatefulWidget {
// //   const EmployeeListScreen({super.key});
// //
// //   @override
// //   State<EmployeeListScreen> createState() => _EmployeeListScreenState();
// // }
// //
// // class _EmployeeListScreenState extends State<EmployeeListScreen> {
// //   final ApiService _apiService = ApiService();
// //   List<dynamic> _employees = [];
// //   bool _isLoading = true;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _loadEmployees();
// //   }
// //
// //   // 🔴 LOAD EMPLOYEES (Safe Internet Check)
// //   void _loadEmployees() async {
// //     setState(() => _isLoading = true);
// //     try {
// //       final result = await InternetAddress.lookup('google.com');
// //       if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
// //         var list = await _apiService.getAllEmployees();
// //         if (mounted) {
// //           setState(() {
// //             _employees = list;
// //             _isLoading = false;
// //           });
// //         }
// //       }
// //     } catch (e) {
// //       if (mounted) {
// //         setState(() => _isLoading = false);
// //         ScaffoldMessenger.of(context).showSnackBar(
// //             const SnackBar(content: Text("Check Internet Connection"))
// //         );
// //       }
// //     }
// //   }
// //
// //   // 🔴 UPDATE FACE LOGIC
// //   void _handleUpdateFace(String empId, String empName) async {
// //     // 1. Confirm Dialog
// //     bool? confirm = await showDialog(
// //       context: context,
// //       builder: (c) => AlertDialog(
// //         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
// //         title: const Text("Update Face Data?"),
// //         content: Text("This will overwrite the existing face data for $empName. Are you sure?"),
// //         actions: [
// //           TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
// //           ElevatedButton(
// //             onPressed: () => Navigator.pop(c, true),
// //             style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
// //             child: const Text("Yes, Update", style: TextStyle(color: Colors.white)),
// //           ),
// //         ],
// //       ),
// //     );
// //
// //     if (confirm != true) return;
// //
// //     // 2. Open Camera & Get New Embedding
// //     final List<double>? newEmbedding = await Navigator.push(
// //       context,
// //       MaterialPageRoute(builder: (context) => const FaceCaptureScreen()),
// //     );
// //
// //     // 3. Call API if face captured
// //     if (newEmbedding != null) {
// //       setState(() => _isLoading = true);
// //
// //       bool success = await _apiService.updateEmployeeFace(empId, newEmbedding);
// //
// //       setState(() => _isLoading = false);
// //
// //       if (mounted) {
// //         if (success) {
// //           ScaffoldMessenger.of(context).showSnackBar(
// //               const SnackBar(content: Text("Face Updated Successfully!"), backgroundColor: Colors.green)
// //           );
// //         } else {
// //           ScaffoldMessenger.of(context).showSnackBar(
// //               const SnackBar(content: Text("Failed to update face."), backgroundColor: Colors.red)
// //           );
// //         }
// //       }
// //     }
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       backgroundColor: const Color(0xFFF2F5F9),
// //       body: _isLoading
// //           ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// //           : Stack(
// //         children: [
// //           CustomScrollView(
// //             slivers: [
// //               const SliverToBoxAdapter(child: SizedBox(height: 280)),
// //               _employees.isEmpty
// //                   ? SliverFillRemaining(
// //                 hasScrollBody: false,
// //                 child: _buildEmptyState(),
// //               )
// //                   : SliverList(
// //                 delegate: SliverChildBuilderDelegate(
// //                       (context, index) {
// //                     return Padding(
// //                       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
// //                       child: _buildPremiumEmployeeCard(_employees[index]),
// //                     );
// //                   },
// //                   childCount: _employees.length,
// //                 ),
// //               ),
// //               const SliverToBoxAdapter(child: SizedBox(height: 30)),
// //             ],
// //           ),
// //           _buildPremiumHeader(),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   Widget _buildPremiumHeader() {
// //     return Container(
// //       height: 260,
// //       decoration: const BoxDecoration(
// //         gradient: LinearGradient(
// //           colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
// //           begin: Alignment.topLeft,
// //           end: Alignment.bottomRight,
// //         ),
// //         borderRadius: BorderRadius.only(
// //           bottomLeft: Radius.circular(40),
// //           bottomRight: Radius.circular(40),
// //         ),
// //         boxShadow: [
// //           BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10)),
// //         ],
// //       ),
// //       child: Stack(
// //         children: [
// //           Positioned(top: -60, right: -40, child: _buildDecorativeCircle(180)),
// //           Positioned(bottom: 40, left: -20, child: _buildDecorativeCircle(100)),
// //
// //           SafeArea(
// //             child: Padding(
// //               padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
// //               child: Column(
// //                 crossAxisAlignment: CrossAxisAlignment.start,
// //                 children: [
// //                   Row(
// //                     children: [
// //                       GestureDetector(
// //                         onTap: () => Navigator.pop(context),
// //                         child: Container(
// //                           padding: const EdgeInsets.all(12),
// //                           decoration: BoxDecoration(
// //                             color: Colors.white.withOpacity(0.2),
// //                             borderRadius: BorderRadius.circular(14),
// //                             border: Border.all(color: Colors.white.withOpacity(0.1)),
// //                           ),
// //                           child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
// //                         ),
// //                       ),
// //                       const SizedBox(width: 15),
// //                       const Text(
// //                         "Staff Directory",
// //                         style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
// //                       ),
// //                     ],
// //                   ),
// //                   const Spacer(),
// //                   Row(
// //                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                     crossAxisAlignment: CrossAxisAlignment.end,
// //                     children: [
// //                       Column(
// //                         crossAxisAlignment: CrossAxisAlignment.start,
// //                         children: [
// //                           Text("Total Employees", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14, letterSpacing: 1)),
// //                           const SizedBox(height: 5),
// //                           Text("${_employees.length}", style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1)),
// //                         ],
// //                       ),
// //                       Container(
// //                         padding: const EdgeInsets.all(15),
// //                         decoration: BoxDecoration(
// //                           color: Colors.white.withOpacity(0.15),
// //                           borderRadius: BorderRadius.circular(20),
// //                           border: Border.all(color: Colors.white.withOpacity(0.2)),
// //                         ),
// //                         child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 32),
// //                       )
// //                     ],
// //                   ),
// //                   const SizedBox(height: 30),
// //                 ],
// //               ),
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   Widget _buildDecorativeCircle(double size) {
// //     return Container(
// //       width: size,
// //       height: size,
// //       decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), shape: BoxShape.circle),
// //     );
// //   }
// //
// //   Widget _buildPremiumEmployeeCard(dynamic emp) {
// //     String name = emp['name'] ?? "Unknown";
// //     String empId = emp['_id'] ?? ""; // 🔴 ID Needed for Update
// //
// //     // Safe Extraction Logic
// //     String designation = "Staff";
// //     var rawDesig = emp['designation'];
// //     if (rawDesig is String) designation = rawDesig;
// //     else if (rawDesig is Map) designation = rawDesig['name'] ?? "Staff";
// //
// //     String phone = emp['phone']?.toString() ?? "N/A";
// //     String email = emp['email']?.toString() ?? "N/A";
// //     String firstLetter = name.isNotEmpty ? name[0].toUpperCase() : "?";
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
// //       decoration: BoxDecoration(
// //         color: Colors.white,
// //         borderRadius: BorderRadius.circular(24),
// //         boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 8))],
// //       ),
// //       child: Material(
// //         color: Colors.transparent,
// //         child: InkWell(
// //           borderRadius: BorderRadius.circular(24),
// //           onTap: () {
// //             Navigator.push(context, MaterialPageRoute(builder: (context) => AttendanceHistoryScreen(employeeName: name, employeeId: empId, locationId: locationId)));
// //           },
// //           child: Padding(
// //             padding: const EdgeInsets.all(18),
// //             child: Row(
// //               crossAxisAlignment: CrossAxisAlignment.start,
// //               children: [
// //                 Container(
// //                   padding: const EdgeInsets.all(3),
// //                   decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2E3192).withOpacity(0.2), width: 2)),
// //                   child: SecureAvatar(imageUrl: fullImageUrl, initials: firstLetter),
// //                 ),
// //                 const SizedBox(width: 15),
// //                 Expanded(
// //                   child: Column(
// //                     crossAxisAlignment: CrossAxisAlignment.start,
// //                     children: [
// //                       // 🔴 HEADER ROW WITH MENU
// //                       Row(
// //                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //                         children: [
// //                           Expanded(
// //                             child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF2D3142))),
// //                           ),
// //                           // 3-DOTS MENU
// //                           SizedBox(
// //                             height: 24, width: 24,
// //                             child: PopupMenuButton<String>(
// //                               padding: EdgeInsets.zero,
// //                               icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade400),
// //                               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
// //                               itemBuilder: (context) => [
// //                                 const PopupMenuItem(
// //                                   value: 'update',
// //                                   child: Row(children: [
// //                                     Icon(Icons.face, color: Colors.blueAccent, size: 18),
// //                                     SizedBox(width: 10),
// //                                     Text("Update Face", style: TextStyle(fontSize: 13))
// //                                   ]),
// //                                 )
// //                               ],
// //                               onSelected: (val) {
// //                                 if(val == 'update') _handleUpdateFace(empId, name);
// //                               },
// //                             ),
// //                           )
// //                         ],
// //                       ),
// //
// //                       const SizedBox(height: 6),
// //                       Container(
// //                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
// //                         decoration: BoxDecoration(color: const Color(0xFFF3F6FF), borderRadius: BorderRadius.circular(8)),
// //                         child: Text(designation.toUpperCase(), style: const TextStyle(color: Color(0xFF2E3192), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
// //                       ),
// //                       const SizedBox(height: 10),
// //                       _buildContactRow(Icons.phone_rounded, phone),
// //                       const SizedBox(height: 4),
// //                       _buildContactRow(Icons.email_rounded, email),
// //                     ],
// //                   ),
// //                 ),
// //               ],
// //             ),
// //           ),
// //         ),
// //       ),
// //     );
// //   }
// //
// //   Widget _buildContactRow(IconData icon, String text) {
// //     return Row(children: [Icon(icon, size: 12, color: Colors.grey.shade400), const SizedBox(width: 6), Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis))]);
// //   }
// //
// //   Widget _buildEmptyState() {
// //     return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.person_add_disabled, size: 50, color: Colors.indigo.withOpacity(0.3)), const SizedBox(height: 20), Text("No Employees Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600))]));
// //   }
// // }
// //
// //
// // // -----------------------------------------------------------
// // // 🔴 SECURE AVATAR (Same as before)
// // // -----------------------------------------------------------
// // class SecureAvatar extends StatefulWidget {
// //   final String imageUrl;
// //   final String initials;
// //
// //   const SecureAvatar({super.key, required this.imageUrl, required this.initials});
// //
// //   @override
// //   State<SecureAvatar> createState() => _SecureAvatarState();
// // }
// //
// // class _SecureAvatarState extends State<SecureAvatar> {
// //   Uint8List? _imageBytes;
// //   bool _isLoading = false;
// //   bool _hasError = false;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     if (widget.imageUrl.isNotEmpty) _fetchImage();
// //   }
// //
// //   Future<void> _fetchImage() async {
// //     if (!mounted) return;
// //     setState(() => _isLoading = true);
// //     try {
// //       final response = await http.get(Uri.parse(widget.imageUrl));
// //       if (response.statusCode == 200 && mounted) {
// //         setState(() { _imageBytes = response.bodyBytes; _isLoading = false; });
// //       } else {
// //         if (mounted) setState(() { _hasError = true; _isLoading = false; });
// //       }
// //     } catch (e) {
// //       if (mounted) setState(() { _hasError = true; _isLoading = false; });
// //     }
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return CircleAvatar(
// //       radius: 26,
// //       backgroundColor: const Color(0xFFF3F6FF),
// //       child: _buildContent(),
// //     );
// //   }
// //
// //   Widget _buildContent() {
// //     if (widget.imageUrl.isEmpty || _hasError) return Text(widget.initials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2E3192)));
// //     if (_isLoading) return const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E3192)));
// //     if (_imageBytes != null) return ClipOval(child: Image.memory(_imageBytes!, width: 52, height: 52, fit: BoxFit.cover));
// //     return Text(widget.initials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2E3192)));
// //   }
// // }
// //
// //
// //
// //
// //
// //
// //
// // // import 'dart:typed_data'; // Bytes ke liye zaroori
// // // import 'package:http/http.dart' as http; // API Call ke liye
// // // import 'package:flutter/material.dart';
// // // import '../../services/api_service.dart';
// // // import 'attendance_history_screen.dart';
// // //
// // // class EmployeeListScreen extends StatefulWidget {
// // //   const EmployeeListScreen({super.key});
// // //
// // //   @override
// // //   State<EmployeeListScreen> createState() => _EmployeeListScreenState();
// // // }
// // //
// // // class _EmployeeListScreenState extends State<EmployeeListScreen> {
// // //   final ApiService _apiService = ApiService();
// // //   List<dynamic> _employees = [];
// // //   bool _isLoading = true;
// // //
// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     _loadEmployees();
// // //   }
// // //
// // //   void _loadEmployees() async {
// // //     var list = await _apiService.getAllEmployees();
// // //     if (mounted) {
// // //       setState(() {
// // //         _employees = list;
// // //         _isLoading = false;
// // //       });
// // //     }
// // //   }
// // //
// // //   @override
// // //   Widget build(BuildContext context) {
// // //     return Scaffold(
// // //       backgroundColor: const Color(0xFFF2F5F9), // Light Grey Background
// // //       body: _isLoading
// // //           ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
// // //           : Stack(
// // //         children: [
// // //           // 1. SCROLLABLE LIST (Slivers)
// // //           CustomScrollView(
// // //             slivers: [
// // //               // Header Space
// // //               const SliverToBoxAdapter(child: SizedBox(height: 280)),
// // //
// // //               // Employee List
// // //               _employees.isEmpty
// // //                   ? SliverFillRemaining(
// // //                 hasScrollBody: false,
// // //                 child: _buildEmptyState(),
// // //               )
// // //                   : SliverList(
// // //                 delegate: SliverChildBuilderDelegate(
// // //                       (context, index) {
// // //                     return Padding(
// // //                       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
// // //                       child: _buildPremiumEmployeeCard(_employees[index]),
// // //                     );
// // //                   },
// // //                   childCount: _employees.length,
// // //                 ),
// // //               ),
// // //
// // //               // Bottom Padding
// // //               const SliverToBoxAdapter(child: SizedBox(height: 30)),
// // //             ],
// // //           ),
// // //
// // //           // 2. FIXED PREMIUM HEADER (Top Layer)
// // //           _buildPremiumHeader(),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   // ✨ PREMIUM HEADER
// // //   Widget _buildPremiumHeader() {
// // //     return Container(
// // //       height: 260,
// // //       decoration: const BoxDecoration(
// // //         gradient: LinearGradient(
// // //           colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
// // //           begin: Alignment.topLeft,
// // //           end: Alignment.bottomRight,
// // //         ),
// // //         borderRadius: BorderRadius.only(
// // //           bottomLeft: Radius.circular(40),
// // //           bottomRight: Radius.circular(40),
// // //         ),
// // //         boxShadow: [
// // //           BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10)),
// // //         ],
// // //       ),
// // //       child: Stack(
// // //         children: [
// // //           Positioned(top: -60, right: -40, child: _buildDecorativeCircle(180)),
// // //           Positioned(bottom: 40, left: -20, child: _buildDecorativeCircle(100)),
// // //
// // //           SafeArea(
// // //             child: Padding(
// // //               padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
// // //               child: Column(
// // //                 crossAxisAlignment: CrossAxisAlignment.start,
// // //                 children: [
// // //                   Row(
// // //                     children: [
// // //                       GestureDetector(
// // //                         onTap: () => Navigator.pop(context),
// // //                         child: Container(
// // //                           padding: const EdgeInsets.all(12),
// // //                           decoration: BoxDecoration(
// // //                             color: Colors.white.withOpacity(0.2),
// // //                             borderRadius: BorderRadius.circular(14),
// // //                             border: Border.all(color: Colors.white.withOpacity(0.1)),
// // //                           ),
// // //                           child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
// // //                         ),
// // //                       ),
// // //                       const SizedBox(width: 15),
// // //                       const Text(
// // //                         "Staff Directory",
// // //                         style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
// // //                       ),
// // //                     ],
// // //                   ),
// // //
// // //                   const Spacer(),
// // //
// // //                   Row(
// // //                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // //                     crossAxisAlignment: CrossAxisAlignment.end,
// // //                     children: [
// // //                       Column(
// // //                         crossAxisAlignment: CrossAxisAlignment.start,
// // //                         children: [
// // //                           Text("Total Employees",
// // //                               style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14, letterSpacing: 1)),
// // //                           const SizedBox(height: 5),
// // //                           Text(
// // //                             "${_employees.length}",
// // //                             style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1),
// // //                           ),
// // //                         ],
// // //                       ),
// // //                       Container(
// // //                         padding: const EdgeInsets.all(15),
// // //                         decoration: BoxDecoration(
// // //                           color: Colors.white.withOpacity(0.15),
// // //                           borderRadius: BorderRadius.circular(20),
// // //                           border: Border.all(color: Colors.white.withOpacity(0.2)),
// // //                         ),
// // //                         child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 32),
// // //                       )
// // //                     ],
// // //                   ),
// // //                   const SizedBox(height: 30),
// // //                 ],
// // //               ),
// // //             ),
// // //           ),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // //
// // //   Widget _buildDecorativeCircle(double size) {
// // //     return Container(
// // //       width: size,
// // //       height: size,
// // //       decoration: BoxDecoration(
// // //         color: Colors.white.withOpacity(0.06),
// // //         shape: BoxShape.circle,
// // //       ),
// // //     );
// // //   }
// // //
// // //   // ✨ PREMIUM EMPLOYEE CARD (🔴 ERROR FIXED HERE)
// // //   Widget _buildPremiumEmployeeCard(dynamic emp) {
// // //     String name = emp['name'] ?? "Unknown";
// // //
// // //     // 🔴 FIX 1: Designation Safe Extraction (String vs Map)
// // //     String designation = "Staff";
// // //     var rawDesig = emp['designation'];
// // //     if (rawDesig is String) {
// // //       designation = rawDesig;
// // //     } else if (rawDesig is Map) {
// // //       designation = rawDesig['name'] ?? "Staff";
// // //     }
// // //
// // //     String phone = emp['phone']?.toString() ?? "N/A";
// // //     String email = emp['email']?.toString() ?? "N/A";
// // //     String firstLetter = name.isNotEmpty ? name[0].toUpperCase() : "?";
// // //
// // //     // 🔴 FIX 2: Location ID Safe Extraction
// // //     String locationId = "";
// // //     var rawLoc = emp['locationId'];
// // //     if (rawLoc is String) {
// // //       locationId = rawLoc;
// // //     } else if (rawLoc is Map) {
// // //       locationId = rawLoc['_id'] ?? "";
// // //     }
// // //
// // //     String imagePath = "";
// // //     if (emp['trim_faceImage'] != null && emp['trim_faceImage'].toString().isNotEmpty) {
// // //       imagePath = emp['trim_faceImage'];
// // //     } else if (emp['faceImage'] != null) {
// // //       imagePath = emp['faceImage'];
// // //     }
// // //
// // //     String fullImageUrl = imagePath.isNotEmpty ? "${_apiService.baseUrl}/$imagePath" : "";
// // //
// // //     return Container(
// // //       decoration: BoxDecoration(
// // //         color: Colors.white,
// // //         borderRadius: BorderRadius.circular(24),
// // //         boxShadow: [
// // //           BoxShadow(color: Colors.blueGrey.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 8)),
// // //         ],
// // //       ),
// // //       child: Material(
// // //         color: Colors.transparent,
// // //         child: InkWell(
// // //           borderRadius: BorderRadius.circular(24),
// // //           onTap: () {
// // //             Navigator.push(
// // //               context,
// // //               MaterialPageRoute(
// // //                 builder: (context) => AttendanceHistoryScreen(
// // //                   employeeName: name,
// // //                   employeeId: emp['_id'] ?? "",
// // //                   locationId: locationId, // 🔴 Using safe locationId
// // //                 ),
// // //               ),
// // //             );
// // //           },
// // //           child: Padding(
// // //             padding: const EdgeInsets.all(18),
// // //             child: Row(
// // //               crossAxisAlignment: CrossAxisAlignment.center,
// // //               children: [
// // //                 Container(
// // //                   padding: const EdgeInsets.all(3),
// // //                   decoration: BoxDecoration(
// // //                     shape: BoxShape.circle,
// // //                     border: Border.all(color: const Color(0xFF2E3192).withOpacity(0.2), width: 2),
// // //                   ),
// // //                   child: SecureAvatar(
// // //                     imageUrl: fullImageUrl,
// // //                     initials: firstLetter,
// // //                   ),
// // //                 ),
// // //                 const SizedBox(width: 18),
// // //
// // //                 Expanded(
// // //                   child: Column(
// // //                     crossAxisAlignment: CrossAxisAlignment.start,
// // //                     children: [
// // //                       Text(
// // //                         name,
// // //                         style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF2D3142)),
// // //                       ),
// // //                       const SizedBox(height: 6),
// // //                       Container(
// // //                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
// // //                         decoration: BoxDecoration(
// // //                           color: const Color(0xFFF3F6FF),
// // //                           borderRadius: BorderRadius.circular(8),
// // //                         ),
// // //                         child: Text(
// // //                           designation.toUpperCase(),
// // //                           style: const TextStyle(color: Color(0xFF2E3192), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5),
// // //                         ),
// // //                       ),
// // //                       const SizedBox(height: 10),
// // //                       _buildContactRow(Icons.phone_rounded, phone),
// // //                       const SizedBox(height: 4),
// // //                       _buildContactRow(Icons.email_rounded, email),
// // //                     ],
// // //                   ),
// // //                 ),
// // //
// // //                 Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade300),
// // //               ],
// // //             ),
// // //           ),
// // //         ),
// // //       ),
// // //     );
// // //   }
// // //
// // //   Widget _buildContactRow(IconData icon, String text) {
// // //     return Row(
// // //       children: [
// // //         Icon(icon, size: 12, color: Colors.grey.shade400),
// // //         const SizedBox(width: 6),
// // //         Expanded(
// // //           child: Text(
// // //             text,
// // //             style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
// // //             overflow: TextOverflow.ellipsis,
// // //           ),
// // //         ),
// // //       ],
// // //     );
// // //   }
// // //
// // //   Widget _buildEmptyState() {
// // //     return Center(
// // //       child: Column(
// // //         mainAxisAlignment: MainAxisAlignment.center,
// // //         children: [
// // //           Container(
// // //             padding: const EdgeInsets.all(20),
// // //             decoration: BoxDecoration(
// // //               color: Colors.white,
// // //               shape: BoxShape.circle,
// // //               boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
// // //             ),
// // //             child: Icon(Icons.person_add_disabled, size: 50, color: Colors.indigo.withOpacity(0.3)),
// // //           ),
// // //           const SizedBox(height: 20),
// // //           Text("No Employees Found", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600)),
// // //         ],
// // //       ),
// // //     );
// // //   }
// // // }
// // //
// // // class SecureAvatar extends StatefulWidget {
// // //   final String imageUrl;
// // //   final String initials;
// // //
// // //   const SecureAvatar({super.key, required this.imageUrl, required this.initials});
// // //
// // //   @override
// // //   State<SecureAvatar> createState() => _SecureAvatarState();
// // // }
// // //
// // // class _SecureAvatarState extends State<SecureAvatar> {
// // //   Uint8List? _imageBytes;
// // //   bool _isLoading = false;
// // //   bool _hasError = false;
// // //
// // //   @override
// // //   void initState() {
// // //     super.initState();
// // //     if (widget.imageUrl.isNotEmpty) {
// // //       _fetchImage();
// // //     }
// // //   }
// // //
// // //   Future<void> _fetchImage() async {
// // //     if (!mounted) return;
// // //     setState(() => _isLoading = true);
// // //
// // //     try {
// // //       final response = await http.get(Uri.parse(widget.imageUrl));
// // //
// // //       if (response.statusCode == 200 && mounted) {
// // //         setState(() {
// // //           _imageBytes = response.bodyBytes;
// // //           _isLoading = false;
// // //         });
// // //       } else {
// // //         if (mounted) setState(() { _hasError = true; _isLoading = false; });
// // //       }
// // //     } catch (e) {
// // //       if (mounted) setState(() { _hasError = true; _isLoading = false; });
// // //     }
// // //   }
// // //
// // //   @override
// // //   Widget build(BuildContext context) {
// // //     return CircleAvatar(
// // //       radius: 26,
// // //       backgroundColor: const Color(0xFFF3F6FF),
// // //       child: _buildContent(),
// // //     );
// // //   }
// // //
// // //   Widget _buildContent() {
// // //     if (widget.imageUrl.isEmpty || _hasError) {
// // //       return Text(widget.initials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2E3192)));
// // //     }
// // //     if (_isLoading) {
// // //       return const SizedBox(
// // //         height: 15, width: 15,
// // //         child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E3192)),
// // //       );
// // //     }
// // //     if (_imageBytes != null) {
// // //       return ClipOval(
// // //         child: Image.memory(
// // //           _imageBytes!,
// // //           width: 52,
// // //           height: 52,
// // //           fit: BoxFit.cover,
// // //         ),
// // //       );
// // //     }
// // //     return Text(widget.initials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2E3192)));
// // //   }
// // // }
// // //
// // //
// // //
// // // // import 'dart:typed_data'; // Bytes ke liye zaroori
// // // // import 'package:http/http.dart' as http; // API Call ke liye
// // // // import 'package:flutter/material.dart';
// // // // import '../../services/api_service.dart';
// // // // import 'attendance_history_screen.dart';
// // // //
// // // // class EmployeeListScreen extends StatefulWidget {
// // // //   const EmployeeListScreen({super.key});
// // // //
// // // //   @override
// // // //   State<EmployeeListScreen> createState() => _EmployeeListScreenState();
// // // // }
// // // //
// // // // class _EmployeeListScreenState extends State<EmployeeListScreen> {
// // // //   final ApiService _apiService = ApiService();
// // // //   List<dynamic> _employees = [];
// // // //   bool _isLoading = true;
// // // //
// // // //   @override
// // // //   void initState() {
// // // //     super.initState();
// // // //     _loadEmployees();
// // // //   }
// // // //
// // // //   void _loadEmployees() async {
// // // //     var list = await _apiService.getAllEmployees();
// // // //     if (mounted) {
// // // //       setState(() {
// // // //         _employees = list;
// // // //         _isLoading = false;
// // // //       });
// // // //     }
// // // //   }
// // // //
// // // //   @override
// // // //   Widget build(BuildContext context) {
// // // //     return Scaffold(
// // // //       backgroundColor: const Color(0xFFF2F5F9),
// // // //       // 🔴 CHANGE: Stack hata kar CustomScrollView lagaya
// // // //       // Isse Header aur List ek saath scroll honge
// // // //       body: _isLoading
// // // //           ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
// // // //           : CustomScrollView(
// // // //         slivers: [
// // // //           // 1. HEADER (Jo ab scroll karega)
// // // //           SliverToBoxAdapter(
// // // //             child: _buildHeader(),
// // // //           ),
// // // //
// // // //           // 2. LIST (SliverList for performance)
// // // //           _employees.isEmpty
// // // //               ? SliverFillRemaining(
// // // //             // Agar list khali hai to Center me dikhao
// // // //             hasScrollBody: false,
// // // //             child: _buildEmptyState(),
// // // //           )
// // // //               : SliverList(
// // // //             delegate: SliverChildBuilderDelegate(
// // // //                   (context, index) {
// // // //                 // Padding list item ke aaspas
// // // //                 return Padding(
// // // //                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
// // // //                   child: _buildEmployeeCard(_employees[index]),
// // // //                 );
// // // //               },
// // // //               childCount: _employees.length,
// // // //             ),
// // // //           ),
// // // //
// // // //           // Bottom Padding taaki last card chipke nahi
// // // //           const SliverToBoxAdapter(child: SizedBox(height: 20)),
// // // //         ],
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   // --- HEADER WIDGET ---
// // // //   Widget _buildHeader() {
// // // //     return Container(
// // // //       // Height thodi adjust ki taaki content kat na jaye
// // // //       padding: const EdgeInsets.only(bottom: 20),
// // // //       decoration: const BoxDecoration(
// // // //         gradient: LinearGradient(
// // // //           colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
// // // //           begin: Alignment.topLeft,
// // // //           end: Alignment.bottomRight,
// // // //         ),
// // // //         borderRadius: BorderRadius.only(
// // // //           bottomLeft: Radius.circular(40),
// // // //           bottomRight: Radius.circular(40),
// // // //         ),
// // // //       ),
// // // //       child: SafeArea(
// // // //         bottom: false, // Bottom safe area ignore karo taaki design na bigde
// // // //         child: Padding(
// // // //           padding: const EdgeInsets.fromLTRB(25, 10, 25, 20),
// // // //           child: Column(
// // // //             crossAxisAlignment: CrossAxisAlignment.start,
// // // //             children: [
// // // //               // 🔴 CENTERED TITLE LOGIC
// // // //               Stack(
// // // //                 alignment: Alignment.center,
// // // //                 children: [
// // // //                   Align(
// // // //                     alignment: Alignment.centerLeft,
// // // //                     child: GestureDetector(
// // // //                       onTap: () => Navigator.pop(context),
// // // //                       child: Container(
// // // //                         padding: const EdgeInsets.all(8),
// // // //                         decoration: BoxDecoration(
// // // //                             color: Colors.white.withOpacity(0.2),
// // // //                             borderRadius: BorderRadius.circular(12)),
// // // //                         child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
// // // //                       ),
// // // //                     ),
// // // //                   ),
// // // //                   const Text(
// // // //                     "All Employees",
// // // //                     style: TextStyle(
// // // //                       color: Colors.white,
// // // //                       fontSize: 20,
// // // //                       fontWeight: FontWeight.bold,
// // // //                     ),
// // // //                   ),
// // // //                 ],
// // // //               ),
// // // //
// // // //               const SizedBox(height: 35),
// // // //
// // // //               // Bottom part of header
// // // //               Row(
// // // //                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
// // // //                 children: [
// // // //                   Column(
// // // //                     crossAxisAlignment: CrossAxisAlignment.start,
// // // //                     children: [
// // // //                       const Text(
// // // //                         "List of Employees",
// // // //                         style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
// // // //                       ),
// // // //                       const SizedBox(height: 5),
// // // //                       Text(
// // // //                         "${_employees.length} Active Staff",
// // // //                         style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
// // // //                       ),
// // // //                     ],
// // // //                   ),
// // // //                   Container(
// // // //                     padding: const EdgeInsets.all(12),
// // // //                     decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
// // // //                     child: const Icon(Icons.groups, color: Colors.white, size: 30),
// // // //                   ),
// // // //                 ],
// // // //               ),
// // // //             ],
// // // //           ),
// // // //         ),
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   // --- EMPLOYEE CARD (Same Design) ---
// // // //   Widget _buildEmployeeCard(dynamic emp) {
// // // //     String name = emp['name'] ?? "Unknown";
// // // //     String designation = emp['designation'] ?? "Staff";
// // // //     String phone = emp['phone']?.toString() ?? "No Phone";
// // // //     String email = emp['email']?.toString() ?? "No Email";
// // // //     String firstLetter = name.isNotEmpty ? name[0].toUpperCase() : "?";
// // // //
// // // //     String imagePath = "";
// // // //     if (emp['trim_faceImage'] != null && emp['trim_faceImage'].toString().isNotEmpty) {
// // // //       imagePath = emp['trim_faceImage'];
// // // //     } else if (emp['faceImage'] != null) {
// // // //       imagePath = emp['faceImage'];
// // // //     }
// // // //
// // // //     String fullImageUrl = imagePath.isNotEmpty ? "${_apiService.baseUrl}/$imagePath" : "";
// // // //
// // // //     return Container(
// // // //       // Margin hata diya kyunki ab hum ListView me Padding de rahe hain
// // // //       // margin: const EdgeInsets.only(bottom: 16),
// // // //       decoration: BoxDecoration(
// // // //         color: Colors.white,
// // // //         borderRadius: BorderRadius.circular(20),
// // // //         boxShadow: [
// // // //           BoxShadow(color: Colors.indigo.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5)),
// // // //         ],
// // // //       ),
// // // //       child: Material(
// // // //         color: Colors.transparent,
// // // //         child: InkWell(
// // // //           borderRadius: BorderRadius.circular(20),
// // // //           onTap: () {
// // // //             Navigator.push(
// // // //               context,
// // // //               MaterialPageRoute(
// // // //                 builder: (context) => AttendanceHistoryScreen(
// // // //                   employeeName: name,
// // // //                   employeeId: emp['_id'] ?? "",
// // // //                   // Use employee's assigned location or empty if not strictly needed/available
// // // //                   locationId: emp['locationId'] ?? "",
// // // //                 ),
// // // //               ),
// // // //             );
// // // //           },
// // // //           child: Padding(
// // // //             padding: const EdgeInsets.all(16),
// // // //             child: Row(
// // // //               children: [
// // // //                 Container(
// // // //                   decoration: BoxDecoration(
// // // //                     shape: BoxShape.circle,
// // // //                     border: Border.all(color: Colors.indigo.withOpacity(0.1), width: 2),
// // // //                   ),
// // // //                   child: SecureAvatar(
// // // //                     imageUrl: fullImageUrl,
// // // //                     initials: firstLetter,
// // // //                   ),
// // // //                 ),
// // // //                 const SizedBox(width: 15),
// // // //
// // // //                 Expanded(
// // // //                   child: Column(
// // // //                     crossAxisAlignment: CrossAxisAlignment.start,
// // // //                     children: [
// // // //                       Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
// // // //                       const SizedBox(height: 6),
// // // //                       Container(
// // // //                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
// // // //                         decoration: BoxDecoration(
// // // //                           color: Colors.blue.withOpacity(0.08),
// // // //                           borderRadius: BorderRadius.circular(6),
// // // //                         ),
// // // //                         child: Text(
// // // //                           designation.toUpperCase(),
// // // //                           style: const TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold),
// // // //                         ),
// // // //                       ),
// // // //                       const SizedBox(height: 8),
// // // //                       Row(
// // // //                         children: [
// // // //                           Icon(Icons.phone, size: 12, color: Colors.grey.shade400),
// // // //                           const SizedBox(width: 4),
// // // //                           Text(phone, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
// // // //                         ],
// // // //                       ),
// // // //                       Row(
// // // //                         children: [
// // // //                           Icon(Icons.email, size: 12, color: Colors.grey.shade400),
// // // //                           const SizedBox(width: 4),
// // // //                           Expanded( // Email lamba ho to overflow na kare
// // // //                             child: Text(
// // // //                               email,
// // // //                               style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
// // // //                               overflow: TextOverflow.ellipsis,
// // // //                             ),
// // // //                           ),
// // // //                         ],
// // // //                       ),
// // // //                     ],
// // // //                   ),
// // // //                 ),
// // // //               ],
// // // //             ),
// // // //           ),
// // // //         ),
// // // //       ),
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildEmptyState() {
// // // //     return Center(
// // // //       child: Column(
// // // //         mainAxisAlignment: MainAxisAlignment.center,
// // // //         children: [
// // // //           Icon(Icons.person_add_disabled, size: 40, color: Colors.indigo.shade200),
// // // //           const SizedBox(height: 15),
// // // //           Text("No Employees Registered", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
// // // //         ],
// // // //       ),
// // // //     );
// // // //   }
// // // // }
// // // //
// // // // // -----------------------------------------------------------
// // // // // 🔴 SECURE AVATAR (Same as before)
// // // // // -----------------------------------------------------------
// // // // class SecureAvatar extends StatefulWidget {
// // // //   final String imageUrl;
// // // //   final String initials;
// // // //
// // // //   const SecureAvatar({super.key, required this.imageUrl, required this.initials});
// // // //
// // // //   @override
// // // //   State<SecureAvatar> createState() => _SecureAvatarState();
// // // // }
// // // //
// // // // class _SecureAvatarState extends State<SecureAvatar> {
// // // //   Uint8List? _imageBytes;
// // // //   bool _isLoading = false;
// // // //   bool _hasError = false;
// // // //
// // // //   @override
// // // //   void initState() {
// // // //     super.initState();
// // // //     if (widget.imageUrl.isNotEmpty) {
// // // //       _fetchImage();
// // // //     }
// // // //   }
// // // //
// // // //   Future<void> _fetchImage() async {
// // // //     if (!mounted) return;
// // // //     setState(() => _isLoading = true);
// // // //
// // // //     try {
// // // //       final response = await http.get(Uri.parse(widget.imageUrl));
// // // //
// // // //       if (response.statusCode == 200 && mounted) {
// // // //         setState(() {
// // // //           _imageBytes = response.bodyBytes;
// // // //           _isLoading = false;
// // // //         });
// // // //       } else {
// // // //         if (mounted) setState(() { _hasError = true; _isLoading = false; });
// // // //       }
// // // //     } catch (e) {
// // // //       if (mounted) setState(() { _hasError = true; _isLoading = false; });
// // // //     }
// // // //   }
// // // //
// // // //   @override
// // // //   Widget build(BuildContext context) {
// // // //     return CircleAvatar(
// // // //       radius: 28,
// // // //       backgroundColor: Colors.indigo.shade50,
// // // //       child: _buildContent(),
// // // //     );
// // // //   }
// // // //
// // // //   Widget _buildContent() {
// // // //     if (widget.imageUrl.isEmpty || _hasError) {
// // // //       return Text(widget.initials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.indigo));
// // // //     }
// // // //     if (_isLoading) {
// // // //       return const SizedBox(
// // // //         height: 15, width: 15,
// // // //         child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo),
// // // //       );
// // // //     }
// // // //     if (_imageBytes != null) {
// // // //       return ClipOval(
// // // //         child: Image.memory(
// // // //           _imageBytes!,
// // // //           width: 56,
// // // //           height: 56,
// // // //           fit: BoxFit.cover,
// // // //         ),
// // // //       );
// // // //     }
// // // //     return Text(widget.initials, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.indigo));
// // // //   }
// // // // }