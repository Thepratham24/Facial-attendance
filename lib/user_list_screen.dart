// import 'package:flutter/material.dart';
// import '../db_service.dart';
// import '../services/db_service.dart';
//
// class UserListScreen extends StatefulWidget {
//   const UserListScreen({super.key});
//
//   @override
//   State<UserListScreen> createState() => _UserListScreenState();
// }
//
// class _UserListScreenState extends State<UserListScreen> {
//   final DBService _dbService = DBService();
//   Map<dynamic, dynamic> _users = {};
//
//   @override
//   void initState() {
//     super.initState();
//     _loadUsers();
//   }
//
//
//   void _loadUsers() async{
//     setState(() {
//       // Fetch all users from Hive
//       _users =  _dbService.getAllUsers();
//     });
//   }
//   void _confirmDelete(String name) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text("Delete User?"),
//         content: Text("Are you sure you want to remove $name?"),
//         actions: [
//           TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
//           TextButton(
//             onPressed: () async {
//               await _dbService.deleteUser(name);
//               Navigator.pop(context);
//               _loadUsers(); // Refresh the list
//               _showTopNotification("Success: Deleted: $name", false);
//             },
//             child: const Text("Delete", style: TextStyle(color: Colors.red)),
//           ),
//         ],
//       ),
//     );
//   }
//
//   void _showTopNotification(String message, bool isError) {
//     OverlayEntry overlayEntry = OverlayEntry(
//       builder: (context) => Positioned(
//         top: 50.0, // Appears below the status bar
//         left: 20.0,
//         right: 20.0,
//         child: Material(
//           color: Colors.transparent,
//           child: Container(
//             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
//             decoration: BoxDecoration(
//               color: isError ? Colors.redAccent : Colors.green,
//               borderRadius: BorderRadius.circular(10),
//               boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
//             ),
//             child: Row(
//               children: [
//                 Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
//                 const SizedBox(width: 12),
//                 Expanded(
//                   child: Text(
//                     message,
//                     style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//
//     // Show it
//     Overlay.of(context).insert(overlayEntry);
//
//     // Remove it automatically after 2 seconds
//     Future.delayed(const Duration(seconds: 2), () {
//       overlayEntry.remove();
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Registered Members"),
//         backgroundColor: Colors.indigo,
//         foregroundColor: Colors.white,
//       ),
//       body: _users.isEmpty
//           ? const Center(
//         child: Text("No users registered yet.",
//             style: TextStyle(fontSize: 16, color: Colors.grey)),
//       )
//           : ListView.builder(
//         padding: const EdgeInsets.all(10),
//         itemCount: _users.length,
//         itemBuilder: (context,index) {
//           String name = _users.keys.elementAt(index);
//           if (name == 'office_lat' || name == 'office_lng') {
//             return const SizedBox.shrink(); // Khali jagah, kuch nahi dikhega
//           }
//           return Card(
//             elevation: 2,
//             margin: const EdgeInsets.symmetric(vertical: 8),
//             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//             child: ListTile(
//               leading: CircleAvatar(
//                 backgroundColor: Colors.indigoAccent,
//                 child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
//               ),
//               title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
//               // ADD THE DELETE BUTTON HERE
//               trailing: IconButton(
//                 icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
//                 onPressed: () => _confirmDelete(name),
//               ),
//             ),
//           );
//         },
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
// // import 'package:flutter/material.dart';
// // import '../services/db_service.dart';
// //
// // class UserListScreen extends StatefulWidget {
// //   const UserListScreen({super.key});
// //
// //   @override
// //   State<UserListScreen> createState() => _UserListScreenState();
// // }
// //
// // class _UserListScreenState extends State<UserListScreen> {
// //   final DBService _dbService = DBService();
// //   Map<dynamic, dynamic> _users = {};
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     _loadUsers();
// //   }
// //
// //   // --- UPDATE: Added async/await ---
// //   void _loadUsers() async {
// //     // 1. Wait for data to come from DB (Hive/Firebase)
// //     Map<dynamic, dynamic> users = await _dbService.getAllUsers();
// //
// //     // 2. Update UI
// //     if (mounted) {
// //       setState(() {
// //         _users = users;
// //       });
// //     }
// //   }
// //
// //   void _confirmDelete(String name) {
// //     showDialog(
// //       context: context,
// //       builder: (context) => AlertDialog(
// //         title: const Text("Delete User?"),
// //         content: Text("Are you sure you want to remove $name?"),
// //         actions: [
// //           TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
// //           TextButton(
// //             onPressed: () async {
// //               // --- UPDATE: await is already here, which is good ---
// //               await _dbService.deleteUser(name);
// //
// //               if (mounted) {
// //                 Navigator.pop(context); // Close dialog
// //                 _loadUsers(); // Refresh the list
// //                 _showTopNotification("Success: Deleted: $name", false);
// //               }
// //             },
// //             child: const Text("Delete", style: TextStyle(color: Colors.red)),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   void _showTopNotification(String message, bool isError) {
// //     OverlayEntry overlayEntry = OverlayEntry(
// //       builder: (context) => Positioned(
// //         top: 50.0,
// //         left: 20.0,
// //         right: 20.0,
// //         child: Material(
// //           color: Colors.transparent,
// //           child: Container(
// //             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
// //             decoration: BoxDecoration(
// //               color: isError ? Colors.redAccent : Colors.green,
// //               borderRadius: BorderRadius.circular(10),
// //               boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
// //             ),
// //             child: Row(
// //               children: [
// //                 Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
// //                 const SizedBox(width: 12),
// //                 Expanded(
// //                   child: Text(
// //                     message,
// //                     style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
// //                   ),
// //                 ),
// //               ],
// //             ),
// //           ),
// //         ),
// //       ),
// //     );
// //
// //     Overlay.of(context).insert(overlayEntry);
// //     Future.delayed(const Duration(seconds: 2), () {
// //       overlayEntry.remove();
// //     });
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text("Registered Members"),
// //         backgroundColor: Colors.indigo,
// //         foregroundColor: Colors.white,
// //       ),
// //       body: _users.isEmpty
// //           ? const Center(
// //         child: Text("No users registered yet.",
// //             style: TextStyle(fontSize: 16, color: Colors.grey)),
// //       )
// //           : ListView.builder(
// //         padding: const EdgeInsets.all(10),
// //         itemCount: _users.length,
// //         itemBuilder: (context, index) {
// //           String name = _users.keys.elementAt(index);
// //
// //           // Filter out system keys
// //           if (name == 'office_lat' || name == 'office_lng') {
// //             return const SizedBox.shrink();
// //           }
// //
// //           return Card(
// //             elevation: 2,
// //             margin: const EdgeInsets.symmetric(vertical: 8),
// //             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
// //             child: ListTile(
// //               leading: CircleAvatar(
// //                 backgroundColor: Colors.indigoAccent,
// //                 child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
// //               ),
// //               title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
// //               trailing: IconButton(
// //                 icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
// //                 onPressed: () => _confirmDelete(name),
// //               ),
// //             ),
// //           );
// //         },
// //       ),
// //     );
// //   }
// // }
// //