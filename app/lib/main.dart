import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/game/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Wire the accounts / XP backend (Supabase when configured, stubs otherwise).
  // Never blocks the game: init falls back to stubs on any failure.
  await Services.init();
  runApp(const IsekaiStrategemApp());
}
