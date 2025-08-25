import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/constants.dart';
import 'secure_storage_service.dart';
import 'error_handling_service.dart';
import 'loading_service.dart';

class ApiService {
  static Future<ApiResponse> login(String token, String deploymentCode) async {
    final url = Uri.parse('${AppConstants.baseUrl}setUnit');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'action': 'login',
      'timestamp': DateTime.now().toIso8601String(),
      'deviceInfo': await _getDeviceInfo(),
    });

    try {
      final response = await http.post(url, headers: headers, body: body);
      return ApiResponse.fromResponse(response);
    } catch (e) {
      return ApiResponse.error(ErrorHandlingService.getUserFriendlyError(e));
    }
  }

  static Future<ApiResponse> logout(String token, String deploymentCode) async {
    final url = Uri.parse('${AppConstants.baseUrl}setUnit');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'action': 'logout',
      'timestamp': DateTime.now().toIso8601String(),
    });

    try {
      final response = await http.post(url, headers: headers, body: body);
      return ApiResponse.fromResponse(response);
    } catch (e) {
      return ApiResponse.error(ErrorHandlingService.getUserFriendlyError(e));
    }
  }

  // Enhanced checkStatus with timeout and better error handling
  static Future<ApiResponse> checkStatus(String token, String deploymentCode) async {
    final url = Uri.parse('${AppConstants.baseUrl}checkStatus');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'timestamp': DateTime.now().toIso8601String(),
    });

    try {
      final response = await http.post(
        url, 
        headers: headers, 
        body: body,
      ).timeout(const Duration(seconds: 8)); // Timeout for session checks
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ApiResponse(
          success: true,
          message: 'Status checked successfully',
          data: data,
        );
      } else if (response.statusCode == 401) {
        return ApiResponse(
          success: false,
          message: 'Authentication failed - token may be invalid',
          data: {'isLoggedIn': false},
        );
      } else {
        return ApiResponse(
          success: false,
          message: 'Server error checking status',
          data: {'isLoggedIn': false},
        );
      }
    } on TimeoutException {
      return ApiResponse.error('Session check timed out');
    } catch (e) {
      return ApiResponse.error('Network error checking status: ${e.toString()}');
    }
  }

  // ENHANCED: updateLocation with aggressive sync support
  static Future<ApiResponse> updateLocation({
    required String token,
    required String deploymentCode,
    required Position position,
    required int batteryLevel,
    required String signalStrength,
    bool isAggressiveSync = false,
  }) async {
    final url = Uri.parse('${AppConstants.baseUrl}updateLocation');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-Sync-Type': isAggressiveSync ? 'aggressive' : 'normal', // Custom header for aggressive sync
    };
    
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'location': {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
      },
      'batteryStatus': batteryLevel,
      'signal': signalStrength,
      'timestamp': DateTime.now().toIso8601String(),
      'syncType': isAggressiveSync ? 'aggressive' : 'normal',
      'deviceInfo': isAggressiveSync ? await _getDeviceInfo() : null,
    });

    try {
      final response = await http.post(
        url, 
        headers: headers, 
        body: body
      ).timeout(Duration(seconds: isAggressiveSync ? 15 : 10));
      
      // Handle session expired or logged out
      if (response.statusCode == 403) {
        return ApiResponse.error('Session expired. Please login again.');
      }
      
      final apiResponse = ApiResponse.fromResponse(response);
      
      if (apiResponse.success && isAggressiveSync) {
        print('ApiService: ✅ SYNC successful - device should show ONLINE');
      }
      
      return apiResponse;
    } catch (e) {
      return ApiResponse.error('Network error updating location: ${e.toString()}');
    }
  }

  // NEW: Send multiple aggressive sync updates
  static Future<List<ApiResponse>> sendAggressiveSyncBurst({
    required String token,
    required String deploymentCode,
    required Position position,
    int burstCount = 3,
  }) async {
    print('ApiService: Starting aggressive sync burst ($burstCount updates)...');
    
    List<ApiResponse> results = [];
    
    try {
      // Get current device info
      final batteryLevel = await _getBatteryLevel();
      final signalStrength = await _getSignalStrength();
      
      // Send multiple rapid updates
      for (int i = 0; i < burstCount; i++) {
        print('ApiService: Sending sync ${i + 1}/$burstCount...');
        
        final response = await updateLocation(
          token: token,
          deploymentCode: deploymentCode,
          position: position,
          batteryLevel: batteryLevel,
          signalStrength: signalStrength,
          isAggressiveSync: true,
        );
        
        results.add(response);
        
        print('ApiService: sync ${i + 1}/$burstCount: ${response.success ? "✅ SUCCESS" : "❌ FAILED"}');
        
        // Brief delay between requests (except for the last one)
        if (i < burstCount - 1) {
          await Future.delayed(Duration(milliseconds: 500));
        }
      }
      
      final successCount = results.where((r) => r.success).length;
      print('ApiService: sync burst completed - $successCount/$burstCount successful');
      
    } catch (e) {
      print('ApiService: Error in sync burst: $e');
      results.add(ApiResponse.error('sync burst failed: $e'));
    }
    
    return results;
  }

  // NEW: Send immediate online status update
  static Future<ApiResponse> sendImmediateOnlineStatus({
    required String token,
    required String deploymentCode,
    Position? position,
  }) async {
    print('ApiService: Sending immediate online status update...');
    
    try {
      // If no position provided, try to get a quick location fix
      Position? currentPosition = position;
      
      if (currentPosition == null) {
        try {
          currentPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          );
        } catch (e) {
          print('ApiService: Could not get quick location for online status: $e');
          // Continue without location
        }
      }
      
      // If we have a position, send location update
      if (currentPosition != null) {
        final batteryLevel = await _getBatteryLevel();
        final signalStrength = await _getSignalStrength();
        
        return await updateLocation(
          token: token,
          deploymentCode: deploymentCode,
          position: currentPosition,
          batteryLevel: batteryLevel,
          signalStrength: signalStrength,
          isAggressiveSync: true,
        );
      } else {
        // Send a heartbeat-style update without location
        return await _sendHeartbeatUpdate(token, deploymentCode);
      }
      
    } catch (e) {
      print('ApiService: Error sending immediate online status: $e');
      return ApiResponse.error('Failed to send online status: $e');
    }
  }

  // NEW: Send heartbeat update without location
  static Future<ApiResponse> _sendHeartbeatUpdate(String token, String deploymentCode) async {
    final url = Uri.parse('${AppConstants.baseUrl}heartbeat'); // Assuming heartbeat endpoint exists
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'status': 'online',
      'timestamp': DateTime.now().toIso8601String(),
      'batteryStatus': await _getBatteryLevel(),
      'signal': await _getSignalStrength(),
    });

    try {
      final response = await http.post(url, headers: headers, body: body);
      return ApiResponse.fromResponse(response);
    } catch (e) {
      return ApiResponse.error('Heartbeat update failed: ${e.toString()}');
    }
  }

  // Helper methods for device information
  static Future<String> _getDeviceInfo() async {
    try {
      return 'Mobile Device - ${DateTime.now().toIso8601String()}';
    } catch (e) {
      return 'Unknown Device';
    }
  }

  static Future<int> _getBatteryLevel() async {
    try {
      final battery = Battery();
      return await battery.batteryLevel;
    } catch (e) {
      return 100; // Default value
    }
  }

  static Future<String> _getSignalStrength() async {
    try {
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity();
      
      switch (result) {
        case ConnectivityResult.wifi:
        case ConnectivityResult.ethernet:
          return 'strong';
        case ConnectivityResult.mobile:
          return 'moderate';
        case ConnectivityResult.bluetooth:
          return 'weak';
        default:
          return 'poor';
      }
    } catch (e) {
      return 'poor';
    }
  }
}

class ApiResponse {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  ApiResponse({
    required this.success,
    required this.message,
    this.data,
  });

  factory ApiResponse.fromResponse(http.Response response) {
    try {
      final body = json.decode(response.body);
      return ApiResponse(
        success: response.statusCode == 200 && (body['success'] ?? false),
        message: body['message'] ?? 'Request completed',
        data: body,
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Invalid response format from server',
      );
    }
  }

  factory ApiResponse.error(String message) {
    return ApiResponse(success: false, message: message);
  }
}