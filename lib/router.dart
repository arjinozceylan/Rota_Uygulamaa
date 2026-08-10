import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rota360/core/models/address.dart';
import 'package:rota360/screens/map_picker_page.dart';
import 'services/home_page.dart';
import 'services/reports_page.dart';
import 'screens/saved_routes_page.dart';
import 'screens/excel_uploads_page.dart';
import 'screens/help_page.dart';
import 'screens/calendar_page.dart';
import 'screens/calendar_month_overview.dart';
import 'screens/login_page.dart';

// Login dışındaki her route, giriş yapmış (auth_token) olmayı gerektirir —
// aksi halde URL doğrudan yazılarak login hiç yapılmadan panele
// girilebiliyordu. Panel yalnızca hastane personeli (admin) içindir
// (backend'de dispatcher rolü kaldırıldı), misafir girişi kaldırıldı.
Future<String?> _authGuard(BuildContext context, GoRouterState state) async {
  if (state.matchedLocation == '/login') return null;
  final prefs = await SharedPreferences.getInstance();
  final hasToken = prefs.getString('auth_token') != null;
  if (hasToken) return null;
  return '/login';
}

final GoRouter router = GoRouter(
  initialLocation: '/login',
  redirect: _authGuard,
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
        // `extra` doesn't survive a browser refresh/history restore on web —
        // guard the cast instead of trusting it's always an Address.
        final extra = state.extra;
        final fixedHomeAddress = extra is Address ? extra : null;
        return CalendarMonthOverview(fixedHomeAddress: fixedHomeAddress);
      },
    ),
    GoRoute(
      path: '/calendar/day',
      builder: (context, state) {
        final extra = state.extra;
        if (extra is! CalendarDayRouteArgs) {
          // No valid day was passed (e.g. stale browser history state) —
          // fall back to the month view instead of crashing.
          return const CalendarMonthOverview();
        }
        return CalendarPage(
          fixedHomeAddress: extra.fixedHomeAddress,
          initialDay: extra.day,
        );
      },
    ),
    GoRoute(
      path: '/map-picker',
      builder: (context, state) => const MapPickerPage(),
    ),
  ],
);