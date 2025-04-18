# pyright: reportArgumentType=false
from PyQt6.QtCore import QUrl, pyqtSignal, pyqtSlot, QObject, QTimer
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtWidgets import QApplication
from client.mid_layer.mcp_client import MCPClient
from client.ui.AppInfoManager import AppInfoManager
from contextlib import AsyncExitStack
from datetime import datetime
from qasync import QEventLoop, asyncSlot
from utils.config import *
from utils.logger import logger
import asyncio
import os
import sys
import subprocess
import re


class MCPClientBridge(QObject):
    conversationChanged = pyqtSignal()  # Signal for conversation changes
    logLevelChanged = pyqtSignal(str)  # Signal for logging level changes
    statusChanged = pyqtSignal(str)  # Signal for status changes
    availableServersChanged = pyqtSignal(list)  # Signal for available servers list
    isConnectedChanged = pyqtSignal(bool)  # Signal for connection status
    messageReceived = pyqtSignal(str, str)  # Signal for new messages (message, timestamp)
    listeningStarted = pyqtSignal()  # Signal for when listening starts
    listeningStopped = pyqtSignal()  # Signal for when listening stops
    errorOccurred = pyqtSignal(str)  # Signal for errors

    # Status constants
    STATUS_INITIALIZING = "Initializing..."
    STATUS_CONNECTING = "Connecting to server..."
    STATUS_CONNECTED = "Connected to {server_name}"
    STATUS_DISCONNECTED = "Disconnected"
    STATUS_PROCESSING = "Processing query..."
    STATUS_STREAMING = "Streaming response..."
    STATUS_IDLE = "Ready"
    STATUS_ERROR = "Error: {error}"
    STATUS_CONFIG_APPLIED = "Configuration applied successfully"
    STATUS_SHUTTING_DOWN = "Shutting down..."

    def __init__(self, parent=None):
        """MCPClientBridge initializes the MCPClient and manages the conversation state."""
        super().__init__(parent=parent)
        self._conversation = []
        self._status = self.STATUS_INITIALIZING
        self._current_streaming_message = None
        self._is_connected = False
        self._loop = asyncio.get_event_loop()
        self.config_path = DEFAULT_CONFIG_PATH
        self._current_log_level = (
            config.get("logging", "level").upper()
            if config.get("logging", "level")
            else "DEBUG"
        )
        self._available_servers = []
        self._selected_server_path = None
        self.client = None  # Will be initialized when a server is selected

    @property
    def is_connected(self):
        """Return the connection status"""
        return self._is_connected

    @is_connected.setter
    def is_connected(self, value):
        """Set the connection status and emit the signal"""
        if self._is_connected != value:
            self._is_connected = value
            self.isConnectedChanged.emit(value)

    def _update_status(self, status: str, **kwargs):
        """Update the status and emit the statusChanged signal"""
        self._status = status.format(**kwargs)
        self.statusChanged.emit(self._status)
        logger.info(f"Status updated: {self._status}")

    async def initialize(self):
        """Initialize the client and connect to the server"""
        self._update_status(self.STATUS_INITIALIZING)
        await self.connect_to_server()

    @pyqtSlot(result=str)
    def get_status(self):
        """Return the current status of the client"""
        return self._status

    @pyqtSlot(result=list)
    def get_conversation(self):
        """Return the current conversation as a list of formatted messages"""
        formatted_messages = []
        for message in self._conversation:
            timestamp = message.get("timestamp", "")
            content = message.get("content", "")
            # Format message as expected by MessageItem: "[timestamp] sender: content"
            # If content starts with "You: ", it's a user message, otherwise it's an assistant message
            if content.startswith("You: "):
                formatted_messages.append(f"[{timestamp}] {content}")
            else:
                formatted_messages.append(f"[{timestamp}] Assistant: {content}")
        return formatted_messages

    @asyncSlot(str)
    async def submit_query(self, query: str):
        """Submit a query to the server and update the conversation"""
        if not query.strip():
            return
        if not self._is_connected:
            message = {
                "timestamp": self.get_timestamp(),
                "content": "ERROR: Not connected",
            }
            self._conversation.append(message)
            self.conversationChanged.emit()
            self.errorOccurred.emit("Not connected")
            logger.error("Query submitted before server connection established")
            return

        # Add user message
        user_message = {"timestamp": self.get_timestamp(), "content": f"You: {query}"}
        self._conversation.append(user_message)
        logger.info(f"User query added to conversation: {query}")
        self.conversationChanged.emit()
        await self.process_query(query)

    @pyqtSlot()
    def clear_conversation(self):
        """Clear the conversation history"""
        self._conversation = []
        clear_message = {
            "timestamp": self.get_timestamp(),
            "content": "Conversation cleared.",
        }
        self._conversation.append(clear_message)
        logger.info("Conversation cleared")
        self.conversationChanged.emit()

    @pyqtSlot(bool)
    def toggle_streaming(self, enabled: bool):
        """Enable or disable streaming mode, streaming here refers to the ability to receive partial responses from the server."""
        if self.client is None:
            logger.error("Client is not initialized")
            return
        self.client.streaming = enabled
        self.client.llm_provider.streaming = enabled
        status = "enabled" if enabled else "disabled"
        self._status = f"Streaming {status}"
        self._conversation.append(
            {"timestamp": self.get_timestamp(), "content": f"Streaming {status}"}
        )
        logger.info(f"Streaming {status}")
        self.conversationChanged.emit()
        self.statusChanged.emit(self._status)

    @pyqtSlot(str, str, result="QVariant")
    def getConfigValue(self, section: str, key: str) -> str:
        """Get a configuration value, always returning a string."""
        value = config.get(section, key)
        logger.debug(
            f"Getting config value for {section}.{key}: {value} (type: {type(value)})"
        )
        if value is None:
            logger.debug(f"Value is None, returning empty string")
            return ""
        elif isinstance(value, list):
            if key == "stop":
                # For stop sequences, escape special characters for QML
                return "\n".join(
                    str(v).encode("unicode_escape").decode("utf-8") for v in value
                )
            return ",".join(str(v) for v in value)
        elif section == "logging" and key == "level":
            # Return the current log level in uppercase
            return self._current_log_level
        result = str(value)
        logger.debug(f"Final value: {result}")
        return result

    @pyqtSlot(str, str, "QVariant")
    def setConfigValue(self, section: str, key: str, value):
        """Set a configuration value."""
        if key == "stop" and isinstance(value, str):
            # For stop sequences, escape special characters for QML
            value = [
                v.encode("utf-8").decode("unicode_escape")
                for v in value.split("\n")
                if v
            ]
        elif key in ["timeout", "top_k", "n_ctx", "max_tokens", "streaming_chunk_size"]:
            value = int(value) if value != "" else 0
        elif key in ["temperature", "top_p", "repetition_penalty"]:
            value = float(value) if value != "" else 0.0
        elif key == "streaming" or key == "file_enabled":
            value = bool(value)
        elif section == "logging" and key == "level":
            value = value.upper()

        config.set(section, key, value)

    @asyncSlot()
    async def applyConfig(self):
        """Apply configuration changes by restarting the client."""
        try:
            self._update_status(self.STATUS_INITIALIZING)
            self._conversation.append(
                {
                    "timestamp": self.get_timestamp(),
                    "content": "Applying configuration changes...",
                }
            )
            self.conversationChanged.emit()

            # Store the current conversation
            current_conversation = self._conversation.copy()

            # Clean up existing client
            if self.client:
                self._conversation.append(
                    {
                        "timestamp": self.get_timestamp(),
                        "content": "Disconnecting from server...",
                    }
                )
                self.conversationChanged.emit()

                # First attempt - normal cleanup
                try:
                    cleanup_task = asyncio.create_task(self.client.cleanup())
                    await asyncio.wait_for(cleanup_task, timeout=5.0)
                    await asyncio.sleep(1)
                except asyncio.TimeoutError:
                    self._conversation.append(
                        {
                            "timestamp": self.get_timestamp(),
                            "content": "Cleanup is taking longer than expected, forcing disconnect...",
                        }
                    )
                    self.conversationChanged.emit()
                except Exception as cleanup_error:
                    logger.error(
                        f"Error during client cleanup: {cleanup_error}", exc_info=True
                    )
                    self._conversation.append(
                        {
                            "timestamp": self.get_timestamp(),
                            "content": f"Cleanup warning: {str(cleanup_error)}",
                        }
                    )
                    self.conversationChanged.emit()

                # Ensure client is fully reset regardless of cleanup success
                self.client = None
                self._is_connected = False
                self.isConnectedChanged.emit(False)

            # Extra delay to ensure all resources are released
            await asyncio.sleep(1.0)

            # Reload the configuration from file
            self._conversation.append(
                {
                    "timestamp": self.get_timestamp(),
                    "content": "Reloading configuration...",
                }
            )
            self.conversationChanged.emit()
            config.reload()

            # Add a small delay after config reload
            await asyncio.sleep(0.5)

            # Update global variables after config reload
            global SERVER_URL, MODEL_NAME, PROVIDER_TYPE, API_KEY, TIMEOUT, STREAMING_ENABLED
            SERVER_URL = config.get("llm", "server_url")
            MODEL_NAME = config.get("llm", "model_name")
            PROVIDER_TYPE = config.get("llm", "provider_type")
            API_KEY = config.get("llm", "api_key")
            TIMEOUT = config.get("llm", "timeout")
            STREAMING_ENABLED = config.get("llm", "streaming")

            # Create new client with updated config
            self._conversation.append(
                {
                    "timestamp": self.get_timestamp(),
                    "content": "Creating new client with updated configuration...",
                }
            )
            self.conversationChanged.emit()

            # Reconnect if previously connected
            if self._selected_server_path:
                await self._connect_to_selected_server(
                    os.path.basename(self._selected_server_path)
                )

            self._update_status(self.STATUS_CONFIG_APPLIED)
            # Ensure we keep current conversation
            self._conversation = current_conversation
            self._conversation.append(
                {
                    "timestamp": self.get_timestamp(),
                    "content": "Configuration applied successfully.",
                }
            )
            self.conversationChanged.emit()

        except Exception as e:
            logger.error(f"Error applying configuration: {e}", exc_info=True)
            self._update_status(self.STATUS_ERROR, error=str(e))
            self._conversation.append(
                {
                    "timestamp": self.get_timestamp(),
                    "content": f"Error applying configuration: {str(e)}",
                }
            )
            self.conversationChanged.emit()
            self.errorOccurred.emit(str(e))

    @pyqtSlot()
    def saveConfigToFile(self):
        """Save the current configuration to file."""
        config.save_to_file(self.config_path)
        logger.info(f"Configuration saved to {self.config_path}")

    async def connect_to_server(self):
        """Ask the user to select a server from the list of available servers."""
        self._update_status(self.STATUS_INITIALIZING)

        if not self._available_servers:
            self._discover_mcp_servers()

        if not self._available_servers:
            self._update_status(self.STATUS_ERROR, error="No MCP servers found")
            self._conversation.append(
                {
                    "timestamp": self.get_timestamp(),
                    "content": "Error: No MCP servers found.",
                }
            )
            self.conversationChanged.emit()
            self.errorOccurred.emit("No MCP servers found")
            return False

        # Wait for user to select a server in UI before proceeding
        logger.info("Available servers discovered. Waiting for user selection.")
        self._update_status(self.STATUS_DISCONNECTED)
        self.availableServersChanged.emit(self._available_servers)

        return True

    async def process_query(self, query: str):
        """Process the user query and handle the response from the server."""
        if not self.client:
            self._update_status(self.STATUS_ERROR, error="Not connected to server")
            self._conversation.append(
                {
                    "timestamp": self.get_timestamp(),
                    "content": "ERROR: Not connected to server",
                }
            )
            self.conversationChanged.emit()
            self.errorOccurred.emit("Not connected to server")
            return

        self._update_status(self.STATUS_PROCESSING)

        # Start tracking response content
        assistant_message = {"timestamp": self.get_timestamp(), "content": ""}
        self._conversation.append(assistant_message)
        self._current_streaming_message = assistant_message
        self.conversationChanged.emit()

        try:
            self._update_status(self.STATUS_STREAMING)

            # Use the MCPClient process_query interface, which now returns a generator for streaming responses
            async for chunk in self.client.process_query(query):
                if self._current_streaming_message:
                    # Update the message content with the new chunk
                    self._current_streaming_message["content"] += chunk
                    # Ensure we emit the signal for each update
                    self.conversationChanged.emit()

            # Final update after streaming is complete
            self._update_status(self.STATUS_IDLE)
            
            # Emit the messageReceived signal when the response is complete
            if self._current_streaming_message:
                timestamp = self._current_streaming_message["timestamp"] 
                message = self._current_streaming_message["content"]
                self._current_streaming_message = None  # Reset current message
                self.messageReceived.emit(message, timestamp)

        except Exception as e:
            logger.error(f"Error processing query: {e}", exc_info=True)
            error_msg = f"Error: {str(e)}"
            if self._current_streaming_message:
                self._current_streaming_message["content"] = error_msg
                self._current_streaming_message = None
            else:
                self._conversation.append(
                    {"timestamp": self.get_timestamp(), "content": error_msg}
                )
            self.conversationChanged.emit()
            self._update_status(self.STATUS_ERROR, error=str(e))
            self.errorOccurred.emit(str(e))

    def get_timestamp(self) -> str:
        """Get the current timestamp for a message."""
        return datetime.now().strftime("%H:%M:%S")

    async def cleanup(self):
        """Clean up resources."""
        logger.info("Cleaning up MCPClientBridge resources")
        if self.client:
            try:
                await self.client.cleanup()
                self.client = None
                logger.info("Client cleanup completed")
            except Exception as e:
                logger.error(f"Error during cleanup: {e}", exc_info=True)

        self.is_connected = False
        self._update_status(self.STATUS_DISCONNECTED)
        logger.info("MCPClientBridge cleanup completed")

    @pyqtSlot()
    def reset_status(self):
        """Reset the status to idle."""
        if self._is_connected:
            self._update_status(self.STATUS_IDLE)
        else:
            self._update_status(self.STATUS_DISCONNECTED)

    @pyqtSlot()
    def shutdown(self):
        """Handle application shutdown gracefully."""
        logger.info("Shutdown requested")
        self._update_status(self.STATUS_SHUTTING_DOWN)

        try:
            # Schedule cleanup to run on the event loop
            coro = self._do_shutdown_cleanup()
            asyncio.create_task(coro)

            # We'll also set a timer to force quit after a timeout
            # This ensures the app exits even if async cleanup hangs
            QTimer.singleShot(5000, self._force_quit)

            logger.info("Shutdown initiated")
        except Exception as e:
            logger.error(f"Error during shutdown: {e}", exc_info=True)
            self._force_quit()

    def _force_quit(self):
        """Force the application to quit if normal shutdown doesn't complete."""
        logger.warning("Forcing application to quit")
        app_instance = QApplication.instance()
        if app_instance:
            app_instance.quit()
        else:
            logger.error("Failed to get QApplication instance for quit")
            # Force exit as fallback
            import sys

            sys.exit(1)

    async def _do_shutdown_cleanup(self):
        """Perform cleanup operations during shutdown."""
        try:
            logger.info("Performing shutdown cleanup")

            # Disconnect from server
            if self.client:
                logger.info("Cleaning up client during shutdown")
                try:
                    await asyncio.wait_for(self.client.cleanup(), timeout=3.0)
                except asyncio.TimeoutError:
                    logger.warning("Client cleanup timeout during shutdown")
                except Exception as e:
                    logger.error(
                        f"Error cleaning up client during shutdown: {e}", exc_info=True
                    )
                finally:
                    self.client = None

            logger.info("Shutdown cleanup completed")
        except Exception as e:
            logger.error(f"Error during shutdown cleanup: {e}", exc_info=True)
        finally:
            # Ensure the application quits
            app_instance = QApplication.instance()
            if app_instance:
                app_instance.quit()
            else:
                logger.error("Failed to get QApplication instance for quit")
                # Force exit as fallback
                import sys

                sys.exit(1)

    @pyqtSlot()
    def getAvailableServers(self):
        """Get the list of available MCP servers."""
        self._discover_mcp_servers()
        self.availableServersChanged.emit(self._available_servers)
        return self._available_servers

    def _discover_mcp_servers(self):
        """Discover available MCP servers from the file system."""
        logger.info("Discovering MCP servers")
        self._available_servers = []

        # Look in default server directory
        server_dirs = [
            os.path.abspath(os.path.join(os.path.dirname(__file__), "../../mcp_server"))
        ]

        # Add any custom server directories from config
        custom_server_dirs = config.get("server", "custom_server_dirs")
        if custom_server_dirs and isinstance(custom_server_dirs, list):
            server_dirs.extend(custom_server_dirs)

        for server_dir in server_dirs:
            if not os.path.exists(server_dir):
                logger.warning(f"Server directory does not exist: {server_dir}")
                continue

            logger.info(f"Searching for servers in: {server_dir}")
            try:
                for file in os.listdir(server_dir):
                    if file.endswith("_server.py") or (file == "server.py"):
                        file_path = os.path.join(server_dir, file)

                        # Try to extract server name
                        server_name = (
                            file.replace("_server.py", "").replace(".py", "").title()
                        )

                        # Try to parse server name from file
                        try:
                            with open(file_path, "r") as f:
                                content = f.read()
                                server_name_match = re.search(
                                    r'SERVER_NAME\s*=\s*[\'"](.+?)[\'"]', content
                                )
                                if server_name_match:
                                    server_name = server_name_match.group(1)
                        except Exception as e:
                            logger.warning(
                                f"Error parsing server name from {file_path}: {e}"
                            )

                        self._available_servers.append(
                            {"name": server_name, "path": file_path}
                        )
                        logger.info(f"Found server: {server_name} at {file_path}")
            except Exception as e:
                logger.error(
                    f"Error discovering servers in {server_dir}: {e}", exc_info=True
                )

        logger.info(f"Discovered {len(self._available_servers)} servers")

    @pyqtSlot(str)
    def setServerPath(self, server_path):
        """Set the path to the MCP server script."""
        logger.info(f"Setting server path: {server_path}")
        self._selected_server_path = server_path
        # Connection will be handled explicitly by the UI

    @pyqtSlot(result=str)
    def connectToServer(self):
        """Connect to the selected MCP server."""
        if not self._selected_server_path:
            error_msg = "No server selected"
            logger.error(error_msg)
            self._update_status(self.STATUS_ERROR, error=error_msg)
            self.errorOccurred.emit(error_msg)
            return error_msg

        # Extract server name for status messages
        server_name = (
            os.path.basename(self._selected_server_path)
            .replace("_server.py", "")
            .replace(".py", "")
        )

        if not os.path.exists(self._selected_server_path):
            error_msg = f"Server script not found: {self._selected_server_path}"
            logger.error(error_msg)
            self._update_status(self.STATUS_ERROR, error=error_msg)
            self.errorOccurred.emit(error_msg)
            return error_msg

        # Create task to connect
        asyncio.create_task(self._connect_to_selected_server(server_name))
        return ""  # Empty string indicates success (no error)

    async def _connect_to_selected_server(self, server_name):
        """Connect to the selected server asynchronously."""
        self._update_status(self.STATUS_CONNECTING)
        self._conversation.append(
            {
                "timestamp": self.get_timestamp(),
                "content": f"Connecting to server: {server_name}...",
            }
        )
        self.conversationChanged.emit()

        try:
            # Create new client if needed
            if not self.client:
                self.client = MCPClient(
                    streaming=STREAMING_ENABLED,
                    llm_server_url=SERVER_URL,
                    provider_type=PROVIDER_TYPE,
                    model=MODEL_NAME,
                    api_key=API_KEY,
                    timeout=TIMEOUT,
                )

            # Connect to server
            connected = await self.client.connect_to_server(self._selected_server_path)

            if connected:
                self.is_connected = True
                server_display_name = self.client.server_name or server_name
                self._update_status(
                    self.STATUS_CONNECTED, server_name=server_display_name
                )
                self._conversation.append(
                    {
                        "timestamp": self.get_timestamp(),
                        "content": f"Connected to {server_display_name}",
                    }
                )
                self.conversationChanged.emit()
            else:
                self._update_status(
                    self.STATUS_ERROR, error=f"Failed to connect to {server_name}"
                )
                self._conversation.append(
                    {
                        "timestamp": self.get_timestamp(),
                        "content": f"Error: Failed to connect to {server_name}",
                    }
                )
                self.conversationChanged.emit()
                self.errorOccurred.emit(f"Failed to connect to {server_name}")
        except Exception as e:
            logger.error(f"Error connecting to server: {e}", exc_info=True)
            self._update_status(self.STATUS_ERROR, error=str(e))
            self._conversation.append(
                {
                    "timestamp": self.get_timestamp(),
                    "content": f"Error connecting to server: {str(e)}",
                }
            )
            self.conversationChanged.emit()
            self.errorOccurred.emit(str(e))

    @pyqtSlot(result=bool)
    def isConnected(self):
        """Check if the client is connected to a server."""
        return self._is_connected

    @pyqtSlot()
    def start_listening(self):
        """Start voice listening (emit the signal for UI update)."""
        logger.info("Voice activation requested, but not implemented in this version")
        self._conversation.append(
            {
                "timestamp": self.get_timestamp(),
                "content": "Voice activation is not implemented in this version.",
            }
        )
        self.conversationChanged.emit()
        # Emit signal for UI update
        self.listeningStarted.emit()
        # Future implementation would use Whisper or other voice recognition
        self._update_status(self.STATUS_ERROR, error="Voice activation not implemented")

    @pyqtSlot()
    def stop_listening(self):
        """Stop voice listening (emit the signal for UI update)."""
        logger.info("Voice deactivation requested, but not implemented in this version")
        # Emit signal for UI update
        self.listeningStopped.emit()
        self._update_status(self.STATUS_IDLE)

    @pyqtSlot()
    def disconnectFromServer(self):
        """Disconnect from the MCP server."""
        logger.info("Disconnecting from server")

        async def _do_disconnect():
            try:
                if self.client:
                    await self.client.cleanup()
                    self.client = None
                self.is_connected = False
                self._update_status(self.STATUS_DISCONNECTED)
                self._conversation.append(
                    {
                        "timestamp": self.get_timestamp(),
                        "content": "Disconnected from server",
                    }
                )
                self.conversationChanged.emit()
            except Exception as e:
                logger.error(f"Error disconnecting from server: {e}", exc_info=True)
                self._update_status(
                    self.STATUS_ERROR, error=f"Error disconnecting: {str(e)}"
                )
                self.errorOccurred.emit(f"Error disconnecting: {str(e)}")

        asyncio.create_task(_do_disconnect())

    @pyqtSlot(result=str)
    def getWifiIpAddress(self):
        """Get the WiFi IP address of the system."""
        try:
            # Cross-platform method to get IP address
            if sys.platform == "win32":
                # Windows
                try:
                    result = subprocess.run(
                        ["ipconfig"], capture_output=True, text=True, check=True
                    )

                    # Parse output for WiFi adapter
                    output = result.stdout
                    wifi_section = False
                    ip_address = None

                    for line in output.split("\n"):
                        if "Wireless LAN adapter" in line or "Wi-Fi" in line:
                            wifi_section = True
                        elif wifi_section and ":" in line:
                            if "IPv4 Address" in line:
                                ip_address = line.split(":")[-1].strip()
                                # Remove potential parentheses with IPv6 info
                                if "(" in ip_address:
                                    ip_address = ip_address.split("(")[0].strip()
                                break
                        elif wifi_section and len(line.strip()) == 0:
                            # End of the WiFi section
                            wifi_section = False

                    if ip_address:
                        return ip_address
                    return "No WiFi IP found"

                except Exception as e:
                    logger.error(f"Error getting Windows IP address: {e}")
                    return "Error getting IP address"

            elif sys.platform == "darwin":
                # macOS
                try:
                    # Get the default interface
                    route_result = subprocess.run(
                        ["route", "get", "default"],
                        capture_output=True,
                        text=True,
                        check=True,
                    )

                    # Extract interface from route output
                    route_output = route_result.stdout
                    interface = None
                    for line in route_output.split("\n"):
                        if "interface:" in line:
                            interface = line.split(":")[-1].strip()
                            break

                    if not interface:
                        return "No default network interface found"

                    # Get IP for the interface
                    ifconfig_result = subprocess.run(
                        ["ifconfig", interface],
                        capture_output=True,
                        text=True,
                        check=True,
                    )

                    # Parse for inet address
                    ifconfig_output = ifconfig_result.stdout
                    for line in ifconfig_output.split("\n"):
                        if "inet " in line and "127.0.0.1" not in line:
                            # Extract IP address
                            ip_parts = line.strip().split()
                            if len(ip_parts) > 1:
                                return ip_parts[1]

                    return "No WiFi IP found for interface " + interface

                except Exception as e:
                    logger.error(f"Error getting macOS IP address: {e}")
                    return "Error getting IP address"

            elif sys.platform.startswith("linux"):
                # Linux
                try:
                    # Try using ip command first (modern)
                    try:
                        result = subprocess.run(
                            ["ip", "-4", "addr", "show"],
                            capture_output=True,
                            text=True,
                            check=True,
                        )

                        # Parse output looking for wifi interface (wlan0, wlp2s0, etc.)
                        output = result.stdout
                        wifi_regex = r"(wl\w+)"
                        wifi_interfaces = re.findall(wifi_regex, output)

                        if wifi_interfaces:
                            wifi_interface = wifi_interfaces[0]
                            # Look for inet address on this interface
                            interface_section = False
                            for line in output.split("\n"):
                                if wifi_interface in line:
                                    interface_section = True
                                elif interface_section and "inet " in line:
                                    # Extract IP
                                    ip_match = re.search(
                                        r"inet (\d+\.\d+\.\d+\.\d+)", line
                                    )
                                    if ip_match:
                                        return ip_match.group(1)
                                elif interface_section and len(line.strip()) == 0:
                                    interface_section = False

                        # If no WiFi, find any non-loopback IP
                        for line in output.split("\n"):
                            if "inet " in line and "127.0.0.1" not in line:
                                ip_match = re.search(r"inet (\d+\.\d+\.\d+\.\d+)", line)
                                if ip_match:
                                    return ip_match.group(1)

                    except FileNotFoundError:
                        # Fall back to ifconfig
                        result = subprocess.run(
                            ["ifconfig"], capture_output=True, text=True, check=True
                        )

                        output = result.stdout
                        wifi_regex = r"(wl\w+)"
                        wifi_interfaces = re.findall(wifi_regex, output)

                        if wifi_interfaces:
                            wifi_interface = wifi_interfaces[0]
                            interface_section = False
                            for line in output.split("\n"):
                                if wifi_interface in line:
                                    interface_section = True
                                elif interface_section and "inet " in line:
                                    ip_match = re.search(
                                        r"inet (\d+\.\d+\.\d+\.\d+)", line
                                    )
                                    if ip_match:
                                        return ip_match.group(1)
                                elif interface_section and len(line.strip()) == 0:
                                    interface_section = False

                        # If no WiFi, find any non-loopback IP
                        for line in output.split("\n"):
                            if "inet " in line and "127.0.0.1" not in line:
                                ip_match = re.search(r"inet (\d+\.\d+\.\d+\.\d+)", line)
                                if ip_match:
                                    return ip_match.group(1)

                    return "No network IP found"

                except Exception as e:
                    logger.error(f"Error getting Linux IP address: {e}")
                    return "Error getting IP address"

            else:
                # Unsupported platform
                return f"Unsupported platform: {sys.platform}"

        except Exception as e:
            logger.error(f"Error getting IP address: {e}")
            return "Error getting IP address"


class App:
    def __init__(self):
        """Initialize the Qt application and QML engine."""
        self.app = QApplication(sys.argv)
        self.app.setApplicationName("PamirAI Assistant")
        self.app.setOrganizationName("PamirAI Inc")

        # Set up the event loop
        self.loop = QEventLoop(self.app)
        asyncio.set_event_loop(self.loop)

        # Create QML engine
        self.engine = QQmlApplicationEngine()

        # Create the MCP client bridge and app info manager
        self.bridge = MCPClientBridge()
        self.app_info = AppInfoManager()

        # Connect signal to handle application quit
        self.app.aboutToQuit.connect(self.handle_quit)

    async def initialize(self):
        """Initialize the application."""
        # Register the bridge object with QML
        root_context = self.engine.rootContext()
        if root_context is None:
            logger.error("Failed to get QML root context")
            raise RuntimeError("Failed to get QML root context")

        root_context.setContextProperty("bridge", self.bridge)
        root_context.setContextProperty("AppInfo", self.app_info)

        # Get the directory containing the QML files
        current_dir = os.path.dirname(os.path.abspath(__file__))

        # Set import paths for QML modules
        qml_path = os.path.join(current_dir)
        self.engine.addImportPath(qml_path)

        # Find the main.qml file
        qml_file = os.path.join(current_dir, "main.qml")

        if not os.path.exists(qml_file):
            logger.error(f"QML file not found: {qml_file}")
            raise FileNotFoundError(f"QML file not found: {qml_file}")

        # Create source URL from file path
        url = QUrl.fromLocalFile(qml_file)

        # Make sure Qt can find its resources
        qt_conf_path = os.path.join(current_dir, "qt.conf")
        if not os.path.exists(qt_conf_path):
            # Create a minimal qt.conf if it doesn't exist
            with open(qt_conf_path, "w") as f:
                f.write("[Paths]\nPrefix=.\n")

        # Load the QML file
        self.engine.load(url)

        # Wait for the QML to load
        await asyncio.sleep(0.1)

        # Check if the QML was loaded successfully
        if not self.engine.rootObjects():
            logger.error("Failed to load QML")
            raise RuntimeError("Failed to load QML")

        # Initialize the bridge
        await self.bridge.initialize()

        logger.info("Application initialized successfully")

    async def run(self):
        """Run the application with async event loop."""
        try:
            # Initialize the application
            await self.initialize()

            # Use AsyncExitStack for resource management
            async with AsyncExitStack() as exit_stack:
                # Register cleanup callbacks if needed
                exit_stack.push_async_callback(self._cleanup_resources)

                # Schedule application execution
                run_app_task = asyncio.create_task(self.loop.run_forever())

                # Wait for the application to exit
                try:
                    await run_app_task
                except asyncio.CancelledError:
                    logger.info("Application task cancelled")

                # The AsyncExitStack's context manager will handle cleanup
        except Exception as e:
            logger.error(f"Error running application: {e}", exc_info=True)
            raise
        finally:
            # Ensure we exit cleanly
            if hasattr(self, "app") and self.app:
                self.app.quit()

            # Return exit code
            logger.info("Application exited")
            return 0

    async def _cleanup_resources(self):
        """Cleanup resources registered with exit_stack."""
        logger.info("Cleaning up resources from exit stack")
        try:
            # Ensure the bridge is cleaned up
            if hasattr(self, "bridge"):
                await self.bridge.cleanup()
        except Exception as e:
            logger.error(f"Error during resource cleanup: {e}", exc_info=True)
        finally:
            # Close the event loop if it exists and is open
            if hasattr(self, "loop") and self.loop and not self.loop.is_closed():
                self.loop.close()

    def handle_quit(self):
        """Handle application quit event."""
        logger.info("Application quit requested")

        # Schedule bridge shutdown
        try:
            self.bridge.shutdown()
        except Exception as e:
            logger.error(f"Error during shutdown: {e}", exc_info=True)
