import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import 'face_capture_update_screen.dart'; // 🔴 IMPORT ZAROORI HAI

class EmployeeDetailScreen extends StatefulWidget {
  final String employeeId;

  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  final ApiService _apiService = ApiService();

  // Data variables
  Map<String, dynamic>? employeeData;
  bool isLoading = true;
  String errorMessage = "";

  // 🔴 TRICK: Image cache todne ke liye unique ID
  int _imageRefreshKey = 0;

  @override
  void initState() {
    super.initState();
    _fetchEmployeeDetails();
  }

  Future<void> _fetchEmployeeDetails() async {
    try {
      final data = await _apiService.getSingleEmployee(widget.employeeId);
      if (mounted) {
        setState(() {
          employeeData = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = "Failed to load: $e";
          isLoading = false;
        });
      }
    }
  }

  // 🔴 FACE UPDATE LOGIC
  void _handleUpdateFace() async {
    String name = employeeData?['name'] ?? "Employee";

    // 1. Confirmation Dialog
    bool? confirm = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Update Photo?"),
        content: Text("Are you sure you want to update the face data for $name?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E3192)),
            child: const Text("Yes, Update", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 2. Open Camera Screen
    final List<double>? newEmbedding = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FaceCaptureScreen()),
    );

    // 3. API Call & Refresh
    if (newEmbedding != null) {
      setState(() => isLoading = true); // Loading shuru

      bool success = await _apiService.updateEmployeeFace(widget.employeeId, newEmbedding);

      if (success) {
        // 🟢 IMPORTANT: Image Key badhao taaki nayi photo load ho
        _imageRefreshKey++;
        await _fetchEmployeeDetails(); // Data wapis load karo

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Face Updated Successfully! ✅"), backgroundColor: Colors.green)
          );
        }
      } else {
        setState(() => isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Failed to update face ❌"), backgroundColor: Colors.red)
          );
        }
      }
    }
  }

  String _getFormattedDate(String? rawDate) {
    if (rawDate == null || rawDate.toString().isEmpty) return "N/A";
    try {
      DateTime date = DateTime.parse(rawDate.toString());
      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return rawDate.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
          : errorMessage.isNotEmpty
          ? Center(child: Text(errorMessage))
          : employeeData == null
          ? _buildNotFoundState()
          : Stack(
        children: [
          _buildPremiumHeader(),
          SingleChildScrollView(
            padding: const EdgeInsets.only(top: 100),
            child: _buildEmployeeContent(),
          ),
          Positioned(
            top: 50, left: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumHeader() {
    return Container(
      height: 250,
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
      ),
      child: Stack(
        children: [
          Positioned(top: -50, right: -30, child: _buildDecorativeCircle(150)),
          Positioned(bottom: 20, left: -40, child: _buildDecorativeCircle(100)),
        ],
      ),
    );
  }

  Widget _buildDecorativeCircle(double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
    );
  }

  Widget _buildNotFoundState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 15),
          Text("Employee Not Found", style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmployeeContent() {
    String? imageUrl;
    String imagePath = "";

    if (employeeData!['faceImage'] != null && employeeData!['faceImage'].toString().isNotEmpty) {
      imagePath = employeeData!['faceImage'];
    } else if (employeeData!['trim_faceImage'] != null && employeeData!['trim_faceImage'].toString().isNotEmpty) {
      imagePath = employeeData!['trim_faceImage'];
    }

    if (imagePath.isNotEmpty) {
      // 🔴 TRICK: URL ke peeche '?v=1', '?v=2' lagayenge taaki nayi photo load ho
      imageUrl = "http://192.168.10.85:6002/$imagePath?v=$_imageRefreshKey";
    }

    String name = employeeData!['name'] ?? "Unknown";
    String designation = employeeData!['designation'] ?? "Staff";

    String locationName = "General";
    var locData = employeeData!['locations'];
    if (locData is List && locData.isNotEmpty) {
      locationName = locData[0]['name'] ?? "General";
    } else if (locData is Map) {
      locationName = locData['name'] ?? "General";
    }

    String departmentName = "General";
    var deptData = employeeData!['departmentId'];
    if (deptData is Map) departmentName = deptData['name'] ?? "General";
    else if (deptData is String) departmentName = deptData;

    return Column(
      children: [
        const SizedBox(height: 40),

        // --- 1. PROFILE IMAGE WITH UPDATE BUTTON ---
        Stack(
          children: [
            // A. The Image
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))
                ],
              ),
              child: ClipOval(
                child: SizedBox(
                  width: 130, // Radius 65 * 2 = 130 diameter
                  height: 130,
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    // 🔴 MAGIC FIX: Agar Server ne mana kiya (403/404), to ye chalega
                    errorBuilder: (context, error, stackTrace) {
                      return Image.asset(
                        'assets/img.png',
                        fit: BoxFit.cover,
                      );
                    },
                    // 🔴 Loading state (Jab tak photo load ho rahi hai)
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                              : null,
                          color: const Color(0xFF2E3192),
                        ),
                      );
                    },
                  )
                      : Image.asset( // Agar URL hi null hai
                    'assets/img.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),

            // B. The Update Button (Camera Icon)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: _handleUpdateFace,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E3192), // Premium Blue
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 15),

        Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF2E3192).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            designation.toUpperCase(),
            style: const TextStyle(fontSize: 12, color: Color(0xFF2E3192), fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
        ),

        const SizedBox(height: 30),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              children: [
                _buildDetailRow(Icons.email_outlined, "Email Address", employeeData!['email'] ?? "N/A"),
                const Divider(height: 30, thickness: 0.5),
                _buildDetailRow(Icons.phone_outlined, "Phone Number", employeeData!['phone']?.toString() ?? "N/A"),
                const Divider(height: 30, thickness: 0.5),
                _buildDetailRow(Icons.calendar_today_outlined, "Date of Joining", _getFormattedDate(employeeData!['joiningDate'])),
                const Divider(height: 30, thickness: 0.5),
                _buildDetailRow(Icons.apartment_outlined, "Department", departmentName),
                const Divider(height: 30, thickness: 0.5),
                _buildDetailRow(Icons.location_on_outlined, "Work Location", locationName),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF3F6FF), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: const Color(0xFF2E3192), size: 22),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF2D3142))),
            ],
          ),
        ),
      ],
    );
  }
}