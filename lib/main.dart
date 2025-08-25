import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_nexusv2/services/background_service.dart';
import 'package:project_nexusv2/services/permission_service.dart';
import 'package:project_nexusv2/services/theme_provider.dart';
import 'package:project_nexusv2/services/api_service.dart';
import 'screens/permission_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'utils/constants.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    print('Main: Flutter initialized');
    
    // This is intentionally not awaited to avoid blocking the UI thread.
    // Any errors during background service initialization will be handled
    // within the function itself and will not crash the app.
    _initializeBackgroundServiceAsync();
    
    print('Main: Starting app...');
    runApp(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const MyApp(),
      ),
    );
  } catch (e, stackTrace) {
    print('Main: Error in main: $e');
    print('Main: Stack trace: $stackTrace');
    // Still try to run the app
    runApp(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const MyApp(),
      ),
    );
  }
}

// Initialize background service asynchronously without blocking app startup
void _initializeBackgroundServiceAsync() {
  Future.delayed(const Duration(milliseconds: 500), () async {
    try {
      print('Main: Initializing background service asynchronously...');
      await initializeService();
      print('Main: Background service initialization completed');
    } catch (e) {
      print('Main: Background service initialization failed: $e');
      // App continues normally even if background service fails
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: AppConstants.appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: themeProvider.themeMode,
          home: const StartupScreen(),
        );
      },
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final _permissionService = PermissionService();

  @override
  void initState() {
    super.initState();
    _checkStartupConditions();
  }

  Future<void> _checkStartupConditions() async {
    try {
      print('StartupScreen: Checking startup conditions...');
      
      // Add a small delay to show the splash screen briefly
      await Future.delayed(const Duration(milliseconds: 1500));
      
      // Check for stored credentials
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString('token');
      final storedDeploymentCode = prefs.getString('deploymentCode');
      
      if (storedToken != null && storedDeploymentCode != null) {
        print('StartupScreen: Found stored credentials, validating session...');
        
        // Validate session is still active
        final isSessionValid = await _validateStoredSession(storedToken, storedDeploymentCode);
        
        if (isSessionValid) {
          // Check if critical permissions are still granted
          final hasPermissions = await _permissionService.hasAllCriticalPermissions();
          
          if (hasPermissions) {
            print('StartupScreen: Session valid and permissions granted, navigating to dashboard...');
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => DashboardScreen(
                    token: storedToken,
                    deploymentCode: storedDeploymentCode,
                  ),
                ),
              );
            }
            return;
          } else {
            print('StartupScreen: Critical permissions missing, going to login...');
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            }
            return;
          }
        } else {
          print('StartupScreen: Stored session is invalid, clearing credentials...');
          await _clearInvalidSession(prefs);
        }
      } else {
        print('StartupScreen: No stored credentials, checking permissions...');
        
        // No stored credentials, check if permissions are granted
        final hasPermissions = await _permissionService.hasAllCriticalPermissions();
        
        if (hasPermissions) {
          print('StartupScreen: Permissions granted, going to login...');
          
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          }
        } else {
          print('StartupScreen: Permissions needed, going to permission screen...');
          
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const PermissionScreen()),
            );
          }
        }
      }
    } catch (e) {
      print('StartupScreen: Error checking startup conditions: $e');
      
      // On error, default to permission screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PermissionScreen()),
        );
      }
    }
  }

  Future<bool> _validateStoredSession(String token, String deploymentCode) async {
    try {
      print('StartupScreen: Validating stored session...');
      
      final statusResponse = await ApiService.checkStatus(token, deploymentCode);
      
      if (statusResponse.success && statusResponse.data != null) {
        final isLoggedIn = statusResponse.data!['isLoggedIn'] ?? false;
        print('StartupScreen: Session validation result - isLoggedIn: $isLoggedIn');
        return isLoggedIn;
      }
      
      print('StartupScreen: Session validation failed - invalid response');
      return false;
    } catch (e) {
      print('StartupScreen: Session validation failed: $e');
      return false;
    }
  }
  
  Future<void> _clearInvalidSession(SharedPreferences prefs) async {
    try {
      await prefs.remove('token');
      await prefs.remove('deploymentCode');
      await prefs.setBool('isTokenLocked', false);
      print('StartupScreen: Invalid session credentials cleared');
    } catch (e) {
      print('StartupScreen: Error clearing invalid session: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive sizing
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isTablet = screenWidth > 600;
    final isSmallScreen = screenHeight < 700;
    
    // Calculate responsive values
    final logoSize = isTablet ? 160.0 : (isSmallScreen ? 80.0 : 120.0);
    final titleFontSize = isTablet ? 32.0 : (isSmallScreen ? 18.0 : 24.0);
    final mottoFontSize = isTablet ? 18.0 : (isSmallScreen ? 12.0 : 14.0);
    final statusFontSize = isTablet ? 20.0 : (isSmallScreen ? 14.0 : 16.0);
    final horizontalPadding = isTablet ? 40.0 : (isSmallScreen ? 20.0 : 30.0);
    final verticalPadding = isTablet ? 12.0 : (isSmallScreen ? 6.0 : 8.0);
    final spacingLarge = isTablet ? 64.0 : (isSmallScreen ? 32.0 : 48.0);
    final spacingMedium = isTablet ? 48.0 : (isSmallScreen ? 24.0 : 32.0);
    final spacingSmall = isTablet ? 24.0 : (isSmallScreen ? 12.0 : 16.0);
    final borderRadius = isTablet ? 32.0 : (isSmallScreen ? 16.0 : 20.0);
    
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with responsive sizing
                Image.asset(
                  'assets/images/pnp_logo.png',
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: spacingMedium),
                
                // Title with responsive font size
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    AppConstants.appTitle.toUpperCase(),
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: spacingSmall),
                
                // Motto container with responsive sizing
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding * 0.5, 
                    vertical: verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                  child: Text(
                    AppConstants.appMotto,
                    style: TextStyle(
                      fontSize: mottoFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: spacingLarge),
                
                // Progress indicator with responsive sizing
                SizedBox(
                  width: isTablet ? 48.0 : (isSmallScreen ? 32.0 : 40.0),
                  height: isTablet ? 48.0 : (isSmallScreen ? 32.0 : 40.0),
                  child: CircularProgressIndicator(
                    strokeWidth: isTablet ? 4.0 : (isSmallScreen ? 2.0 : 3.0),
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                  ),
                ),
                SizedBox(height: spacingSmall),
                
                // Status text with responsive font size
                Text(
                  'Validating Session...',
                  style: TextStyle(
                    fontSize: statusFontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}