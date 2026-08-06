import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/game_provider.dart';
import 'providers/web_socket_provider.dart';
import 'providers/eye_tracking_provider.dart';
import 'providers/eeg_provider.dart';
import 'providers/eeg_control_provider.dart';
import 'providers/session_provider.dart';
import 'providers/vr_simulation_provider.dart';
import 'screens/app_shell.dart';
import 'services/session_api.dart';
import 'services/eeg_control_api.dart';
import 'theme/app_style.dart';
import 'utils/backend_url.dart';

void main() => runApp(const ViewerApp());

class ViewerApp extends StatelessWidget {
  const ViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WebSocketProvider()),
        ChangeNotifierProvider(create: (_) => GameProvider()),
        ChangeNotifierProvider(create: (_) => VrSimulationProvider()),
        ChangeNotifierProvider(create: (_) => EyeTrackingProvider()),
        ChangeNotifierProvider(create: (_) => EegProvider()),
        ChangeNotifierProvider(
          create: (_) => EegControlProvider(
            api: HttpEegControlApi(
              baseUri: resolveBackendHttpBase(
                Uri.base,
                useDevelopmentBackend: kDebugMode,
              ),
            ),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SessionProvider(
            api: HttpSessionApi(
              baseUri: resolveBackendHttpBase(
                Uri.base,
                useDevelopmentBackend: kDebugMode,
              ),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Panel VR',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
            surface: AppColors.surface,
          ),
          scaffoldBackgroundColor: AppColors.background,
          cardColor: AppColors.surface,
          dividerColor: AppColors.border,
          fontFamily: 'Roboto',
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const AppShell(),
      ),
    );
  }
}
