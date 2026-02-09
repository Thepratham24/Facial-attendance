import 'package:face_attendance/screens/Admin%20Side/admin_dashboard_screen.dart';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'admin_attendance_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool _isLoading = false;

  void _handleLogin() async {
    if (_emailController.text.isEmpty || _passController.text.isEmpty) return;

    setState(() => _isLoading = true);

    bool success = await ApiService().adminLogin(
      _emailController.text.trim(),
      _passController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AdminDashboard()),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Login Failed! Please check credentials."),
            backgroundColor: Colors.redAccent
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Light Grey Background
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- 1. HEADER SECTION ---
            Container(
              width: double.infinity,
              height: 300,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A), // Slate 900 (Admin Dark Theme)
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(50),
                  bottomRight: Radius.circular(50),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded, size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Admin Portal",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Sign in to manage attendance",
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // --- 2. FORM SECTION ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                children: [
                  // Email Field
                  _buildCustomTextField(
                    controller: _emailController,
                    label: "Admin Email",
                    icon: Icons.email_outlined,
                    obscureText: false,
                  ),

                  const SizedBox(height: 20),

                  // Password Field
                  _buildCustomTextField(
                    controller: _passController,
                    label: "Password",
                    icon: Icons.lock_outline_rounded,
                    obscureText: true,
                  ),

                  const SizedBox(height: 40),

                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A), // Match Header
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 5,
                        shadowColor: const Color(0xFF0F172A).withOpacity(0.4),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                        "SECURE LOGIN",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Back Button (Optional UX improvement)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Back to Home", style: TextStyle(color: Colors.grey[600])),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- REUSABLE TEXT FIELD WIDGET ---
  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool obscureText,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey[400]),
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
          ),
        ),
      ),
    );
  }
}