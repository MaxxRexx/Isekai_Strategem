import 'package:flutter/material.dart';

import 'home_screen.dart';

const _accent = Color(0xFF34D1C8);
const _background = Color(0xFF0B0F14);
const _panel = Color(0xFF121822);

/// Every button/chip in the app uses square corners (no circular edges).
const _rectShape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);

class IsekaiStrategemApp extends StatelessWidget {
  const IsekaiStrategemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Isekai Strategem',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ).copyWith(primary: _accent, surface: _panel),
        useMaterial3: true,
        cardColor: _panel,
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: _rectShape,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(shape: _rectShape),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(shape: _rectShape),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: _rectShape),
        ),
        segmentedButtonTheme: const SegmentedButtonThemeData(
          style: ButtonStyle(shape: WidgetStatePropertyAll(_rectShape)),
        ),
        toggleButtonsTheme: const ToggleButtonsThemeData(
          borderRadius: BorderRadius.zero,
        ),
        chipTheme: const ChipThemeData(shape: _rectShape),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          shape: _rectShape,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
