import 'package:flutter/material.dart';

import 'quick_battle/quick_battle_screen.dart';
import 'screens/guide_screen.dart';
import 'screens/play_flow_screen.dart';
import 'screens/simulate_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ISEKAI STRATEGEM',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A turn-based 3v3 tactical combat game.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PlayFlowScreen()),
                    ),
                    child: const Text('PLAY (DRAFT YOUR SQUAD)'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PlayFlowScreen(tutorial: true),
                      ),
                    ),
                    child: const Text('GUIDED TUTORIAL'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SimulateScreen()),
                    ),
                    child: const Text('SIMULATE (AI VS AI)'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QuickBattleScreen(),
                      ),
                    ),
                    child: const Text('QUICK BATTLE (ONE-SHOT)'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GuideScreen()),
                    ),
                    child: const Text('HOW TO PLAY'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
