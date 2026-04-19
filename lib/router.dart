import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rota_desktop/core/models/address.dart';
import 'package:rota_desktop/screens/map_picker_page.dart';

import 'services/home_page.dart';
import 'services/reports_page.dart';
import 'screens/saved_routes_page.dart';
import 'screens/excel_uploads_page.dart';
import 'screens/help_page.dart';
import 'screens/calendar_page.dart';
import 'screens/login_page.dart';

final GoRouter router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: '/reports',
      builder: (context, state) => const ReportsPage(),
    ),
    GoRoute(
      path: '/routes',
      builder: (context, state) => const SavedRoutesPage(),
    ),
    GoRoute(
      path: '/excel-uploads',
      builder: (context, state) => const ExcelUploadsPage(),
    ),
    GoRoute(
      path: '/help',
      builder: (context, state) => const HelpPage(),
    ),
    GoRoute(
      path: '/calendar',
      builder: (context, state) {
        final fixedHomeAddress = state.extra as Address?;
        return CalendarPage(fixedHomeAddress: fixedHomeAddress);
      },
    ),
    GoRoute(
      path: '/map-picker',
      builder: (context, state) => const MapPickerPage(),
    ),
  ],
);
