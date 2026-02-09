import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';

class HolidayCalendarScreen extends StatefulWidget {
  const HolidayCalendarScreen({super.key});

  @override
  State<HolidayCalendarScreen> createState() => _HolidayCalendarScreenState();
}

class _HolidayCalendarScreenState extends State<HolidayCalendarScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  // 🔴 CALENDAR VARIABLES
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Data Store (Key: Date, Value: List of Holiday Objects)
  Map<DateTime, List<dynamic>> _holidaysMap = {};

  // List for bottom view
  List<dynamic> _selectedDayHolidays = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchHolidays();
  }

  // 🔴 PARSING LOGIC FOR YOUR JSON
  void _fetchHolidays() async {
    setState(() => _isLoading = true);
    try {
      // API Call (Returns the 'data' list from your JSON)
      List<dynamic> data = await _apiService.getHolidays();

      Map<DateTime, List<dynamic>> tempMap = {};

      for (var item in data) {
        // JSON: "date": "2026-02-11T00:00:00.000Z"
        String? dateStr = item['date'];

        if (dateStr != null && dateStr.isNotEmpty) {
          try {
            // 1. String to DateTime
            DateTime apiDate = DateTime.parse(dateStr).toLocal();

            // 2. Normalize (Remove Time) - Zaroori hai Calendar ke liye
            // Sirf Year, Month, Day rakhenge taaki match ho sake
            DateTime dateKey = DateTime.utc(apiDate.year, apiDate.month, apiDate.day);

            if (tempMap[dateKey] == null) {
              tempMap[dateKey] = [];
            }
            tempMap[dateKey]!.add(item);
          } catch (e) {
            print("Date Parse Error: $e");
          }
        }
      }

      if (mounted) {
        setState(() {
          _holidaysMap = tempMap;

          // Auto-load data if today has holiday
          DateTime todayKey = DateTime.utc(_focusedDay.year, _focusedDay.month, _focusedDay.day);
          _selectedDayHolidays = _holidaysMap[todayKey] ?? [];

          _isLoading = false;
        });
      }
    } catch (e) {
      print("Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🔴 EVENT LOADER (Ye Calendar par DOTS lagata hai)
  List<dynamic> _getHolidaysForDay(DateTime day) {
    // Calendar jo date bhejta hai, use Normalize karke map me dhundo
    return _holidaysMap[DateTime.utc(day.year, day.month, day.day)] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      body: Stack(
        children: [
          Column(
            children: [
              // 🔴 HEADER (Premium Gradient)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35)),
                  boxShadow: [BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10))],
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 15),
                    const Text("Holiday Calendar", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 🔴 CALENDAR
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,

                  // Styles
                  calendarStyle: const CalendarStyle(
                    todayDecoration: BoxDecoration(color: Color(0xFF818CF8), shape: BoxShape.circle),
                    selectedDecoration: BoxDecoration(color: Color(0xFF2E3192), shape: BoxShape.circle),
                    markerDecoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle), // 🔴 The Dot
                  ),
                  headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)
                  ),

                  // Selection Logic
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                      // Load details for selected day
                      _selectedDayHolidays = _getHolidaysForDay(selectedDay);
                    });
                  },

                  // 🔴 YE IMPORTANT HAI (Dots ke liye)
                  eventLoader: _getHolidaysForDay,
                ),
              ),

              const SizedBox(height: 25),

              // 🔴 HOLIDAY LIST SECTION
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
                    : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedDay != null
                            ? DateFormat('EEEE, d MMMM yyyy').format(_selectedDay!)
                            : "Select a date",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 1),
                      ),
                      const SizedBox(height: 15),

                      if (_selectedDayHolidays.isEmpty)
                        Expanded(child: _buildEmptyState())
                      else
                        Expanded(
                          child: ListView.builder(
                            itemCount: _selectedDayHolidays.length,
                            itemBuilder: (context, index) {
                              var holiday = _selectedDayHolidays[index];
                              return _buildHolidayCard(holiday);
                            },
                          ),
                        )
                    ],
                  ),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  // 🔴 CARD: Shows "New Year" & "Hello"
  Widget _buildHolidayCard(dynamic holiday) {
    String name = holiday['name'] ?? "Holiday";
    String description = holiday['description'] ?? "No description";

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: Colors.redAccent.withOpacity(0.8), width: 5)),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.celebration_rounded, color: Colors.redAccent, size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 5),
                Text(description, style: TextStyle(color: Colors.grey.shade500, fontSize: 13, height: 1.3)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note_rounded, size: 60, color: Colors.grey.shade200),
          const SizedBox(height: 15),
          Text("No Holiday on this date", style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}