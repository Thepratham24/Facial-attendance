import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // DateFormat ke liye

class ResultScreen extends StatefulWidget {
  final String name;
  final String imagePath;
  final String punchStatus; // New: "Punch In" ya "Punch Out"
  final String punchTime;   // New: "10:30 AM"

  const ResultScreen({
    super.key,
    required this.name,
    required this.imagePath,
    required this.punchStatus, // Ye naya add hua hai
    required this.punchTime,   // Ye naya add hua hai
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..forward();

    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0, curve: Curves.easeIn)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Current Date display ke liye (Time hum widget.punchTime se lenge)
    String currentDate = DateFormat('EEEE, d MMMM').format(DateTime.now());

    // Status ke hisaab se color decide karo (Out hai to Orange, In hai to Green)
    bool isOut = widget.punchStatus.toLowerCase().contains("out");
    Color statusColor = isOut ? Colors.orange : Colors.green;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // --- 1. BACKGROUND ---
          Positioned(top: -100, left: -100, child: Container(height: 400, width: 400, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.indigo.withOpacity(0.5)))),
          Positioned(top: -100, right: -100, child: Container(height: 400, width: 400, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.purple.withOpacity(0.5)))),
          Positioned(bottom: -100, left: 0, right: 0, child: Center(child: Container(height: 300, width: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent.withOpacity(0.4))))),
          Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80), child: Container(color: Colors.black.withOpacity(0.6)))),

          // --- 2. CONTENT ---
          Center(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 25),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)],
                        ),
                        child: Column(
                          children: [
                            // Profile Pic
                            Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Colors.blue, Colors.purple])),
                                  child: CircleAvatar(
                                    radius: 55,
                                    backgroundColor: Colors.grey.shade900,
                                    backgroundImage: widget.imagePath.isNotEmpty ? FileImage(File(widget.imagePath)) : null,
                                    child: widget.imagePath.isEmpty
                                        ? Text(widget.name.isNotEmpty ? widget.name[0].toUpperCase() : "U", style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold))
                                        : null,
                                  ),
                                ),
                                ScaleTransition(
                                  scale: _scaleAnimation,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)]),
                                    child: const Icon(Icons.check, color: Colors.white, size: 24),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 25),

                            // 🔴 DB DATA: STATUS
                            Text(
                              widget.punchStatus, // "Punch In Success" or "Punch Out Success"
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "Successfully Verified",
                              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6)),
                            ),
                            const SizedBox(height: 25),

                            // Name Row
                            _buildInfoRow(Icons.person, "Employee Name", widget.name),
                            const SizedBox(height: 15),

                            // 🔴 DB DATA: TIME
                            _buildInfoRow(Icons.access_time_filled, currentDate, widget.punchTime),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text("Done", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
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

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }
}