import 'package:flutter/material.dart';

import '../inventory/hold_sets_tab.dart';
import '../walls/walls_tab.dart';
import 'setters_screen.dart';

/// Vista de un boulder: sus muros, su inventario y sus setters.
class GymDetailScreen extends StatelessWidget {
  const GymDetailScreen({
    super.key,
    required this.gymId,
    required this.gymName,
    required this.isAdmin,
  });

  final String gymId;
  final String gymName;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(gymName),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.grid_on_outlined), text: 'Muros'),
              Tab(icon: Icon(Icons.category_outlined), text: 'Presas'),
              Tab(icon: Icon(Icons.groups_outlined), text: 'Setters'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            WallsTab(gymId: gymId),
            HoldSetsTab(gymId: gymId),
            SettersTab(gymId: gymId, isAdmin: isAdmin),
          ],
        ),
      ),
    );
  }
}
