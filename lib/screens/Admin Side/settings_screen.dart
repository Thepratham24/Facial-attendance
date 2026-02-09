import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../Result_StartLogin Side/login_screen.dart';
import 'holiday_calendar_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9), // Light Grey Background
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 🔴 1. PREMIUM HEADER (Gradient & Shapes)
            Container(
              height: 220,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(35),
                  bottomRight: Radius.circular(35),
                ),
                boxShadow: [
                  BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10)),
                ],
              ),
              child: Stack(
                children: [
                  // Decorative Circles
                  Positioned(top: -50, right: -50, child: _buildDecorationCircle(150)),
                  Positioned(bottom: 20, left: -30, child: _buildDecorationCircle(100)),

                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Settings",
                            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Manage preferences & account",
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 🔴 2. SETTINGS OPTIONS LIST
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Section Title
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("GENERAL", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 15),

                  _buildSettingTile(
                    context,
                    title: "Holiday Calendar",
                    icon: Icons.calendar_month_rounded,
                    color: Colors.orange,
                    onTap: () {
                      // 🔴 FIX: Correct Navigation Logic
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const HolidayCalendarScreen()),
                      );
                    },
                  ),

                  // _buildSettingTile(
                  //   context,
                  //   title: "App Notifications",
                  //   icon: Icons.notifications_active_rounded,
                  //   color: Colors.blueAccent,
                  //   onTap: () {
                  //     ScaffoldMessenger.of(context).showSnackBar(
                  //       const SnackBar(content: Text("Notification settings coming soon!")),
                  //     );
                  //   },
                  // ),

                  const SizedBox(height: 25),

                  // Section Title
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("ACCOUNT", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 15),

                  _buildSettingTile(
                    context,
                    title: "Logout",
                    icon: Icons.logout_rounded,
                    color: Colors.redAccent,
                    isDestructive: true,
                    onTap: () => _showLogoutDialog(context),
                  ),

                  const SizedBox(height: 40),

                  // Version Info
                  Column(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 40, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      Text("Version 1.0.0", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                      Text("Face Attendance System", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  // 🔴 DECORATION CIRCLE WIDGET
  Widget _buildDecorationCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
    );
  }

  // 🔴 PREMIUM TILE WIDGET
  Widget _buildSettingTile(BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDestructive ? Colors.red : const Color(0xFF2D3142),
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade300),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🔴 LOGOUT DIALOG
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Logout"),
          ],
        ),
        content: const Text("Are you sure you want to log out of the admin panel?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              // Close Dialog
              Navigator.pop(c);

              // Perform Logout
              await ApiService.logoutAdmin();

              // Navigate
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen(autoLogin: false)),
                        (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }
}