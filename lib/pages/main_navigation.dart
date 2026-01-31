// // lib/pages/main_navigation.dart - Main navigation wrapper with bottom bar
// import 'package:flutter/material.dart';
// import '../home_screen.dart';
// import 'discovery_feed_page.dart';
// import 'create_post_page.dart';
// import 'profile_screen.dart';
// import 'messages_page.dart';

// class MainNavigation extends StatefulWidget {
//   final bool isPremium;
  
//   const MainNavigation({
//     super.key,
//     this.isPremium = false,
//   });

//   @override
//   State<MainNavigation> createState() => _MainNavigationState();
// }

// class _MainNavigationState extends State<MainNavigation> {
//   int _currentIndex = 0;
  
//   late List<Widget> _pages;

//   @override
//   void initState() {
//     super.initState();
//     _pages = [
//       HomePage(isPremium: widget.isPremium),
//       const DiscoveryFeedPage(),
//       const Placeholder(), // This will be replaced by create post action
//       MessagesPage(),
//       ProfileScreen(favoriteRecipes: const []),
//     ];
//   }

//   void _onTabTapped(int index) {
//     // Handle middle button (Create Post) separately
//     if (index == 2) {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => const CreatePostPage(),
//         ),
//       ).then((result) {
//         // If post was created, refresh feed
//         if (result == true && _currentIndex == 1) {
//           setState(() {
//             // Trigger rebuild of feed page
//             _pages[1] = const DiscoveryFeedPage();
//           });
//         }
//       });
//       return;
//     }

//     setState(() {
//       _currentIndex = index;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: IndexedStack(
//         index: _currentIndex == 2 ? 0 : _currentIndex, // Don't show placeholder
//         children: _pages,
//       ),
//       bottomNavigationBar: Container(
//         decoration: BoxDecoration(
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.1),
//               blurRadius: 10,
//               offset: const Offset(0, -5),
//             ),
//           ],
//         ),
//         child: BottomNavigationBar(
//           currentIndex: _currentIndex == 2 ? 0 : _currentIndex,
//           onTap: _onTabTapped,
//           type: BottomNavigationBarType.fixed,
//           backgroundColor: Colors.white,
//           selectedItemColor: Colors.orange,
//           unselectedItemColor: Colors.grey,
//           selectedFontSize: 12,
//           unselectedFontSize: 12,
//           items: [
//             const BottomNavigationBarItem(
//               icon: Icon(Icons.home),
//               activeIcon: Icon(Icons.home, size: 28),
//               label: 'Home',
//             ),
//             const BottomNavigationBarItem(
//               icon: Icon(Icons.explore),
//               activeIcon: Icon(Icons.explore, size: 28),
//               label: 'Feed',
//             ),
//             BottomNavigationBarItem(
//               icon: Container(
//                 padding: const EdgeInsets.all(8),
//                 decoration: BoxDecoration(
//                   color: Colors.orange,
//                   shape: BoxShape.circle,
//                 ),
//                 child: const Icon(Icons.add, color: Colors.white, size: 24),
//               ),
//               label: 'Post',
//             ),
//             const BottomNavigationBarItem(
//               icon: Icon(Icons.message),
//               activeIcon: Icon(Icons.message, size: 28),
//               label: 'Messages',
//             ),
//             const BottomNavigationBarItem(
//               icon: Icon(Icons.person),
//               activeIcon: Icon(Icons.person, size: 28),
//               label: 'Profile',
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }