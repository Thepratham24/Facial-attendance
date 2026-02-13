import 'package:flutter/material.dart';
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

  // Data Store
  Map<String, List<dynamic>> _groupedHolidays = {};
  int _totalHolidays = 0;

  // 🔴 Financial Year Variables
  List<dynamic> _financialYears = [];
  Map<String, dynamic>? _selectedFY; // Pura object store karenge (id, name)

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // 🔴 INITIAL DATA LOADING (Sequence: Get FY -> Get Holidays)
  Future<void> _initData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Financial Years fetch karo
      List<dynamic> fyList = await _apiService.getFinancialYears();

      if (fyList.isNotEmpty) {
        // 2. "isCurrent: true" wala dhundo, nahi to pehla wala lelo
        var currentFy = fyList.firstWhere(
                (element) => element['isCurrent'] == true,
            orElse: () => fyList[0]
        );

        setState(() {
          _financialYears = fyList;
          _selectedFY = currentFy;
        });

        // 3. Ab Holidays fetch karo selected ID ke sath
        await _fetchHolidays();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Init Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🔴 FETCH HOLIDAYS (With FY ID param)
  Future<void> _fetchHolidays({bool isRefresh = false}) async {
    if (!isRefresh) setState(() => _isLoading = true);

    try {
      // ID pass kar rahe hain API ko
      String? fyId = _selectedFY != null ? _selectedFY!['_id'] : null;

      if(fyId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // API Call with ID
      List<dynamic> rawList = await _apiService.getHolidays(financialYearId: fyId);

      // Sort Date wise
      rawList.sort((a, b) {
        DateTime dA = DateTime.parse(a['date']);
        DateTime dB = DateTime.parse(b['date']);
        return dA.compareTo(dB);
      });

      // Group by Month
      Map<String, List<dynamic>> tempGroup = {};
      for (var item in rawList) {
        if (item['date'] != null) {
          DateTime dt = DateTime.parse(item['date']);
          String monthKey = DateFormat('MMMM yyyy').format(dt);
          if (tempGroup[monthKey] == null) tempGroup[monthKey] = [];
          tempGroup[monthKey]!.add(item);
        }
      }

      if (mounted) {
        setState(() {
          _groupedHolidays = tempGroup;
          _totalHolidays = rawList.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🔴 BOTTOM SHEET TO SELECT YEAR
  void _showYearSelector() {
    if (_financialYears.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Select Financial Year", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2E3192))),
              const SizedBox(height: 15),
              ..._financialYears.map((fy) {
                bool isSelected = _selectedFY != null && _selectedFY!['_id'] == fy['_id'];
                return InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    if (!isSelected) {
                      setState(() {
                        _selectedFY = fy;
                      });
                      _fetchHolidays(); // Refresh data with new ID
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF2E3192).withOpacity(0.1) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? const Color(0xFF2E3192) : Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          fy['name'] ?? "Unknown",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? const Color(0xFF2E3192) : Colors.black87,
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle, color: Color(0xFF2E3192), size: 20)
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const double headerHeight = 200;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      body: Stack(
        children: [
          // 🔴 1. SCROLLABLE LIST
          RefreshIndicator(
            onRefresh: () async => await _fetchHolidays(isRefresh: true),
            color: const Color(0xFF2E3192),
            edgeOffset: headerHeight + 20,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
                : _groupedHolidays.isEmpty
                ? _buildEmptyState(headerHeight)
                : ListView.builder(
              padding: const EdgeInsets.only(top: headerHeight + 10, bottom: 30),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _groupedHolidays.keys.length,
              itemBuilder: (context, index) {
                String monthKey = _groupedHolidays.keys.elementAt(index);
                List<dynamic> holidaysInMonth = _groupedHolidays[monthKey]!;
                return _buildMonthSection(monthKey, holidaysInMonth);
              },
            ),
          ),

          // 🔴 2. FIXED HEADER
          Positioned(
            top: 0, left: 0, right: 0,
            height: headerHeight,
            child: _buildFixedHeader(),
          ),
        ],
      ),
    );
  }

  // 🔴 FIXED HEADER WIDGET (Modified Button UI)
  Widget _buildFixedHeader() {
    return Container(
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
          BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10))
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Top Row: Back Button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.3))
                  ),
                  child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                ),
              ),

              const SizedBox(height: 20),

              // Title Row with Year Selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          "Holidays",
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(height: 5),
                      Text(
                          "Total $_totalHolidays Found",
                          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)
                      ),
                    ],
                  ),

                  // 🔴 YEAR SELECTOR BUTTON (Dropdown Style)
                  // Ye UI clearly batata hai ki ispe click karke change hoga
                  GestureDetector(
                    onTap: _showYearSelector,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0,2))
                          ]
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            _selectedFY != null ? _selectedFY!['name'] : "Year",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13
                            ),
                          ),
                          const SizedBox(width: 4),
                          // const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔴 MONTH SECTION (Unchanged)
  Widget _buildMonthSection(String monthName, List<dynamic> holidays) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 20, 20, 10),
          child: Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: Color(0xFF2E3192), size: 18),
              const SizedBox(width: 8),
              Text(
                monthName.toUpperCase(),
                style: const TextStyle(
                    color: Color(0xFF2E3192),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2
                ),
              ),
            ],
          ),
        ),
        ...holidays.map((h) => _buildModernHolidayCard(h)),
      ],
    );
  }

  // 🔴 HOLIDAY CARD (Unchanged)
  Widget _buildModernHolidayCard(dynamic holiday) {
    DateTime dt = DateTime.parse(holiday['date']);
    String dayNumber = DateFormat('dd').format(dt);
    String dayName = DateFormat('EEEE').format(dt);
    String title = holiday['name'] ?? "Holiday";
    bool isPast = dt.isBefore(DateTime.now().subtract(const Duration(days: 1)));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 5))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Date Box
              Container(
                width: 80,
                decoration: BoxDecoration(
                    color: isPast ? Colors.grey.shade100 : const Color(0xFFF3F6FF),
                    border: Border(right: BorderSide(color: Colors.grey.shade100))
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(dayNumber, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: isPast ? Colors.grey : const Color(0xFF2E3192))),
                    Text(DateFormat('MMM').format(dt).toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isPast ? Colors.grey : Colors.blueAccent)),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade600 : const Color(0xFF2D3142))),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time_filled, size: 12, color: isPast ? Colors.grey : Colors.orange),
                          const SizedBox(width: 5),
                          Text(dayName, style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              if (!isPast) Container(width: 4, color: const Color(0xFF00D2FF)),
            ],
          ),
        ),
      ),
    );
  }

  // 🔴 EMPTY STATE
  Widget _buildEmptyState(double topPadding) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: topPadding),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.beach_access_rounded, size: 80, color: Colors.blue.shade100),
              const SizedBox(height: 20),
              Text("No Holidays Found", style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              // Show selected year in empty state
              Text("for ${_selectedFY != null ? _selectedFY!['name'] : 'selected year'}", style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}















// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import '../../services/api_service.dart';
//
// class HolidayCalendarScreen extends StatefulWidget {
//   const HolidayCalendarScreen({super.key});
//
//   @override
//   State<HolidayCalendarScreen> createState() => _HolidayCalendarScreenState();
// }
//
// class _HolidayCalendarScreenState extends State<HolidayCalendarScreen> {
//   final ApiService _apiService = ApiService();
//   bool _isLoading = true;
//
//   // Data Store
//   Map<String, List<dynamic>> _groupedHolidays = {};
//   int _totalHolidays = 0;
//
//   @override
//   void initState() {
//     super.initState();
//     _fetchHolidays();
//   }
//
//   // 🔴 FETCH LOGIC
//   Future<void> _fetchHolidays({bool isRefresh = false}) async {
//     if (!isRefresh) setState(() => _isLoading = true);
//
//     try {
//       List<dynamic> rawList = await _apiService.getHolidays();
//
//       // Sort Date wise
//       rawList.sort((a, b) {
//         DateTime dA = DateTime.parse(a['date']);
//         DateTime dB = DateTime.parse(b['date']);
//         return dA.compareTo(dB);
//       });
//
//       // Group by Month
//       Map<String, List<dynamic>> tempGroup = {};
//       for (var item in rawList) {
//         if (item['date'] != null) {
//           DateTime dt = DateTime.parse(item['date']);
//           String monthKey = DateFormat('MMMM yyyy').format(dt);
//           if (tempGroup[monthKey] == null) tempGroup[monthKey] = [];
//           tempGroup[monthKey]!.add(item);
//         }
//       }
//
//       if (mounted) {
//         setState(() {
//           _groupedHolidays = tempGroup;
//           _totalHolidays = rawList.length;
//           _isLoading = false;
//         });
//       }
//     } catch (e) {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     // Header Height variable taaki padding match ho sake
//     const double headerHeight = 200;
//
//     return Scaffold(
//       backgroundColor: const Color(0xFFF2F5F9),
//       body: Stack(
//         children: [
//           // 🔴 1. SCROLLABLE LIST (Layer 1 - Bottom)
//           // Isko humne Stack me pehle rakha taaki ye Header ke peeche chala jaye
//           RefreshIndicator(
//             onRefresh: () async => await _fetchHolidays(isRefresh: true),
//             color: const Color(0xFF2E3192),
//             edgeOffset: headerHeight + 20, // 🔥 Loader Header ke neeche dikhega
//             child: _isLoading
//                 ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E3192)))
//                 : _groupedHolidays.isEmpty
//                 ? _buildEmptyState(headerHeight) // Pass height for padding
//                 : ListView.builder(
//               // 🔥 IMPORTANT: Top Padding = Header Height
//               // Isse pehla item header ke neeche dikhega,
//               // par scroll karne par header ke peeche jayega.
//               padding: const EdgeInsets.only(top: headerHeight + 10, bottom: 30),
//               physics: const AlwaysScrollableScrollPhysics(),
//               itemCount: _groupedHolidays.keys.length,
//               itemBuilder: (context, index) {
//                 String monthKey = _groupedHolidays.keys.elementAt(index);
//                 List<dynamic> holidaysInMonth = _groupedHolidays[monthKey]!;
//                 return _buildMonthSection(monthKey, holidaysInMonth);
//               },
//             ),
//           ),
//
//           // 🔴 2. FIXED HEADER (Layer 2 - Top)
//           // Ye apni jagah se nahi hilega
//           Positioned(
//             top: 0, left: 0, right: 0,
//             height: headerHeight,
//             child: _buildFixedHeader(),
//           ),
//         ],
//       ),
//     );
//   }
//
//   // 🔴 FIXED HEADER WIDGET
//   Widget _buildFixedHeader() {
//     return Container(
//       decoration: const BoxDecoration(
//         gradient: LinearGradient(
//           colors: [Color(0xFF2E3192), Color(0xFF00D2FF)],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//         borderRadius: BorderRadius.only(
//           bottomLeft: Radius.circular(35),
//           bottomRight: Radius.circular(35),
//         ),
//         boxShadow: [
//           BoxShadow(color: Color(0x402E3192), blurRadius: 20, offset: Offset(0, 10))
//         ],
//       ),
//       child: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             mainAxisAlignment: MainAxisAlignment.center, // Center Vertically
//             children: [
//               // Top Row: Back Button
//               GestureDetector(
//                 onTap: () => Navigator.pop(context),
//                 child: Container(
//                   width: 40, height: 40,
//                   alignment: Alignment.center,
//                   decoration: BoxDecoration(
//                       color: Colors.white.withOpacity(0.2),
//                       borderRadius: BorderRadius.circular(12),
//                       border: Border.all(color: Colors.white.withOpacity(0.3))
//                   ),
//                   child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
//                 ),
//               ),
//
//               const SizedBox(height: 20),
//
//               // Title Row
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       const Text(
//                           "Yearly Holidays",
//                           style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
//                       ),
//                       const SizedBox(height: 5),
//                       Text(
//                           "Total $_totalHolidays Holidays Found",
//                           style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)
//                       ),
//                     ],
//                   ),
//
//                   // Decorative Icon
//                   Container(
//                     padding: const EdgeInsets.all(12),
//                     decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
//                     child: const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 28),
//                   )
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   // 🔴 MONTH SECTION
//   Widget _buildMonthSection(String monthName, List<dynamic> holidays) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Padding(
//           padding: const EdgeInsets.fromLTRB(25, 20, 20, 10),
//           child: Row(
//             children: [
//               const Icon(Icons.calendar_month_rounded, color: Color(0xFF2E3192), size: 18),
//               const SizedBox(width: 8),
//               Text(
//                 monthName.toUpperCase(),
//                 style: const TextStyle(
//                     color: Color(0xFF2E3192),
//                     fontWeight: FontWeight.bold,
//                     fontSize: 14,
//                     letterSpacing: 1.2
//                 ),
//               ),
//             ],
//           ),
//         ),
//         ...holidays.map((h) => _buildModernHolidayCard(h)),
//       ],
//     );
//   }
//
//   // 🔴 HOLIDAY CARD
//   Widget _buildModernHolidayCard(dynamic holiday) {
//     DateTime dt = DateTime.parse(holiday['date']);
//     String dayNumber = DateFormat('dd').format(dt);
//     String dayName = DateFormat('EEEE').format(dt);
//     String title = holiday['name'] ?? "Holiday";
//     bool isPast = dt.isBefore(DateTime.now().subtract(const Duration(days: 1)));
//
//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(18),
//         boxShadow: [
//           BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 5))
//         ],
//       ),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(18),
//         child: IntrinsicHeight(
//           child: Row(
//             children: [
//               // Date Box
//               Container(
//                 width: 80,
//                 decoration: BoxDecoration(
//                     color: isPast ? Colors.grey.shade100 : const Color(0xFFF3F6FF),
//                     border: Border(right: BorderSide(color: Colors.grey.shade100))
//                 ),
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Text(dayNumber, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: isPast ? Colors.grey : const Color(0xFF2E3192))),
//                     Text(DateFormat('MMM').format(dt).toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isPast ? Colors.grey : Colors.blueAccent)),
//                   ],
//                 ),
//               ),
//
//               // Content
//               Expanded(
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade600 : const Color(0xFF2D3142))),
//                       const SizedBox(height: 4),
//                       Row(
//                         children: [
//                           Icon(Icons.access_time_filled, size: 12, color: isPast ? Colors.grey : Colors.orange),
//                           const SizedBox(width: 5),
//                           Text(dayName, style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//
//               if (!isPast) Container(width: 4, color: const Color(0xFF00D2FF)),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   // 🔴 EMPTY STATE (Scrollable to allow refresh)
//   Widget _buildEmptyState(double topPadding) {
//     return ListView(
//       physics: const AlwaysScrollableScrollPhysics(),
//       padding: EdgeInsets.only(top: topPadding),
//       children: [
//         SizedBox(height: MediaQuery.of(context).size.height * 0.2),
//         Center(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Icon(Icons.beach_access_rounded, size: 80, color: Colors.blue.shade100),
//               const SizedBox(height: 20),
//               Text("No Holidays Found", style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
//               const SizedBox(height: 5),
//               const Text("Pull down to refresh", style: TextStyle(color: Colors.grey)),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }