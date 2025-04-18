# pyright: reportArgumentType=false
from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot, QTimer, pyqtProperty
from PyQt6.QtWidgets import QApplication
from client.mid_layer.mcp_client import MCPClient
from qasync import asyncSlot
from utils.config import *
from utils.logger import logger
import asyncio
import os
import sys
import time  # Add time import for debouncing

from client.ui.bridge.ConversationManager import ConversationManager
from client.ui.bridge.StatusManager import StatusManager
from client.ui.bridge.ServerDiscovery import ServerDiscovery
from client.ui.utils.NetworkUtils import NetworkUtils


class MCPClientBridge(QObject):
    """
    Bridge between the UI and the MCPClient.

    Handles the communication between the QML UI and the Python backend.
    Manages conversation state, server discovery, and client connection.
    """

    conversationChanged = pyqtSignal()  # Signal for conversation changes
    logLevelChanged = pyqtSignal(str)  # Signal for logging level changes
    statusChanged = pyqtSignal(str)  # Signal for status changes
    availableServersChanged = pyqtSignal(list)  # Signal for available servers list
    isConnectedChanged = pyqtSignal(bool)  # Signal for connection status
    messageReceived = pyqtSignal(
        str, str
    )  # Signal for new messages (message, timestamp)
    listeningStarted = pyqtSignal()  # Signal for when listening starts
    listeningStopped = pyqtSignal()  # Signal for when listening stops
    errorOccurred = pyqtSignal(str)  # Signal for errors
    bridgeReady = pyqtSignal()  # Signal for when the bridge is fully initialized

    def __init__(self, parent=None):
        """MCPClientBridge initializes the MCPClient and manages the conversation state."""
        super().__init__(parent=parent)

        # Initialize sub-components
        self.status_manager = StatusManager(self)
        self.conversation_manager = ConversationManager(self)
        # Ensure streaming message is reset at startup
        self.conversation_manager.reset_streaming_message()
        self.server_discovery = ServerDiscovery(self)
        self.network_utils = NetworkUtils()

        # Initialize client-related properties
        self._is_connected = False
        self._is_ready = False
        self._loop = asyncio.get_event_loop()
        self.config_path = DEFAULT_CONFIG_PATH
        # Get logging level with proper default value
        self._current_log_level = config.get("logging", "level", default="DEBUG").upper()
        self._selected_server_path = None
        self.client = None  # Will be initialized when a server is selected
        
        # Server discovery cache for debouncing
        self._last_server_discovery_time = 0
        self._server_discovery_cache_timeout = 5  # seconds

    @pyqtProperty(bool, notify=bridgeReady)
    def ready(self):
        """Return whether the bridge is fully initialized and ready for use."""
        return self._is_ready

    @pyqtSlot(bool)
    def setReady(self, value):
        """Set the ready state of the bridge and emit the bridgeReady signal."""
        if self._is_ready != value:
            self._is_ready = value
            if self._is_ready:
                self.bridgeReady.emit()
            logger.info(f"Bridge ready state set to: {self._is_ready}")

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

    async def initialize(self):
        """Initialize the client and connect to the server"""
        logger.info("Initializing bridge components")
        self.status_manager.update_status(StatusManager.STATUS_INITIALIZING)
        
        # Pre-discover available servers during initialization
        self.server_discovery.discover_mcp_servers()
        
        logger.info("Bridge initialization completed")
        return True

    @pyqtSlot(result=str)
    def get_status(self):
        """Return the current status of the client"""
        return self.status_manager.status

    @pyqtSlot(result=list)
    def get_conversation(self):
        """Return the current conversation as a list of formatted messages"""
        return self.conversation_manager.get_formatted_messages()

    @asyncSlot(str)
    async def submit_query(self, query: str):
        """Submit a query to the server and update the conversation"""
        if not query.strip():
            return
        if not self._is_connected:
            message = {
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "ERROR: Not connected",
            }
            self.conversation_manager.add_message(message)
            self.errorOccurred.emit("Not connected")
            logger.error("Query submitted before server connection established")
            return

        # Add user message
        user_message = {
            "timestamp": self.conversation_manager.get_timestamp(),
            "content": f"You: {query}",
        }
        self.conversation_manager.add_message(user_message)
        logger.info(f"User query added to conversation: {query}")
        
        # Process the query in a separate task to avoid blocking the UI
        # This is particularly important for long running queries
        asyncio.create_task(self._process_query_task(query))
        
    async def _process_query_task(self, query: str):
        """Process query in a separate task to avoid blocking the UI thread."""
        try:
            await self.process_query(query)
        except Exception as e:
            logger.error(f"Error in query processing task: {e}", exc_info=True)
            self.errorOccurred.emit(f"Error processing query: {str(e)}")

    @pyqtSlot()
    def clear_conversation(self):
        """Clear the conversation history"""
        self.conversation_manager.clear()
        clear_message = {
            "timestamp": self.conversation_manager.get_timestamp(),
            "content": "Conversation cleared.",
        }
        self.conversation_manager.add_message(clear_message)
        logger.info("Conversation cleared")

    @pyqtSlot(bool)
    def toggle_streaming(self, enabled: bool):
        """Enable or disable streaming mode, streaming here refers to the ability to receive partial responses from the server."""
        if self.client is None:
            logger.error("Client is not initialized")
            return
        self.client.streaming = enabled
        self.client.llm_provider.streaming = enabled
        status = "enabled" if enabled else "disabled"
        self.status_manager.status = f"Streaming {status}"
        self.conversation_manager.add_message(
            {
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": f"Streaming {status}",
            }
        )
        logger.info(f"Streaming {status}")
        self.statusChanged.emit(self.status_manager.status)

    @pyqtSlot(str, str, result="QVariant")
    def getConfigValue(self, section: str, key: str) -> str:
        """Get a configuration value, always returning a string."""
        # Get the active provider name for LLM-specific configs
        active_provider_name = config.get("active_llm_provider")
        
        # Special cases for provider-specific configuration
        if section == "llm":
            # Map old flat "llm" section to new "llm_providers.{active_provider}" structure
            value = config.get("llm_providers", active_provider_name, key)
            logger.debug(
                f"Getting provider config value {key} for {active_provider_name}: {value} (type: {type(value)})"
            )
        elif section == "llama_cpp" and key == "start_wait_time":
            # Special case for llama_cpp specific settings
            value = config.get(section, key, default=30)
            logger.debug(
                f"Getting config value for {section}.{key}: {value} (type: {type(value)})"
            )
        else:
            # Regular configuration paths
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
        # Process the value first
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

        # Special cases for provider-specific configuration
        if section == "llm":
            # Map flat "llm" section to proper nested path
            active_provider_name = config.get("active_llm_provider")
            config.set("llm_providers", active_provider_name, key, value)
            logger.debug(f"Setting LLM provider config: llm_providers.{active_provider_name}.{key} = {value}")
        elif section == "llama_cpp" and key == "start_wait_time":
            # Special case for llama_cpp specific settings
            config.set(section, key, value)
        else:
            # Regular configuration paths
            config.set(section, key, value)

    @asyncSlot()
    async def applyConfig(self):
        """Apply configuration changes by restarting the client."""
        try:
            self.status_manager.update_status(StatusManager.STATUS_INITIALIZING)
            self.conversation_manager.add_message(
                {
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": "Applying configuration changes...",
                }
            )

            # Store the current conversation
            current_conversation = self.conversation_manager.get_messages_copy()

            # Clean up existing client
            if self.client:
                self.conversation_manager.add_message(
                    {
                        "timestamp": self.conversation_manager.get_timestamp(),
                        "content": "Disconnecting from server...",
                    }
                )

                # First attempt - normal cleanup
                try:
                    cleanup_task = asyncio.create_task(self.client.cleanup())
                    await asyncio.wait_for(cleanup_task, timeout=5.0)
                    await asyncio.sleep(1)
                except asyncio.TimeoutError:
                    self.conversation_manager.add_message(
                        {
                            "timestamp": self.conversation_manager.get_timestamp(),
                            "content": "Cleanup is taking longer than expected, forcing disconnect...",
                        }
                    )
                except Exception as cleanup_error:
                    logger.error(
                        f"Error during client cleanup: {cleanup_error}", exc_info=True
                    )
                    self.conversation_manager.add_message(
                        {
                            "timestamp": self.conversation_manager.get_timestamp(),
                            "content": f"Cleanup warning: {str(cleanup_error)}",
                        }
                    )

                # Ensure client is fully reset regardless of cleanup success
                self.client = None
                self.is_connected = False
                self.isConnectedChanged.emit(False)

            # Extra delay to ensure all resources are released
            await asyncio.sleep(1.0)

            # Reload the configuration from file
            self.conversation_manager.add_message(
                {
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": "Reloading configuration...",
                }
            )
            config.reload()

            # Add a small delay after config reload
            await asyncio.sleep(0.5)

            # Update global variables after config reload
            global SERVER_URL, MODEL_NAME, PROVIDER_TYPE, API_KEY, TIMEOUT, STREAMING_ENABLED
            # Get the active provider configuration
            active_provider_name = config.get("active_llm_provider")
            active_provider_config = config.get("llm_providers", active_provider_name)
            
            # Update global variables from the active provider
            SERVER_URL = active_provider_config.get("server_url")
            MODEL_NAME = active_provider_config.get("model_name")
            PROVIDER_TYPE = active_provider_config.get("provider_type", active_provider_name)
            API_KEY = active_provider_config.get("api_key", "")
            TIMEOUT = active_provider_config.get("timeout", 120)
            STREAMING_ENABLED = active_provider_config.get("streaming", True)

            # Create new client with updated config
            self.conversation_manager.add_message(
                {
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": "Creating new client with updated configuration...",
                }
            )

            # Reconnect if previously connected
            if self._selected_server_path:
                await self._connect_to_selected_server(
                    os.path.basename(self._selected_server_path)
                )

            self.status_manager.update_status(StatusManager.STATUS_CONFIG_APPLIED)
            # Ensure we keep current conversation
            self.conversation_manager.set_messages(current_conversation)
            self.conversation_manager.add_message(
                {
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": "Configuration applied successfully.",
                }
            )

        except Exception as e:
            logger.error(f"Error applying configuration: {e}", exc_info=True)
            self.status_manager.update_status(StatusManager.STATUS_ERROR, error=str(e))
            self.conversation_manager.add_message(
                {
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": f"Error applying configuration: {str(e)}",
                }
            )
            self.errorOccurred.emit(str(e))

    @pyqtSlot()
    def saveConfigToFile(self):
        """Save the current configuration to file."""
        config.save_to_file(self.config_path)
        logger.info(f"Configuration saved to {self.config_path}")

    async def connect_to_server(self):
        """Ask the user to select a server from the list of available servers."""
        self.status_manager.update_status(StatusManager.STATUS_INITIALIZING)

        if not self.server_discovery.available_servers:
            self.server_discovery.discover_mcp_servers()

        if not self.server_discovery.available_servers:
            self.status_manager.update_status(
                StatusManager.STATUS_ERROR, error="No MCP servers found"
            )
            self.conversation_manager.add_message(
                {
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": "Error: No MCP servers found.",
                }
            )
            self.errorOccurred.emit("No MCP servers found")
            return False

        # Wait for user to select a server in UI before proceeding
        logger.info("Available servers discovered. Waiting for user selection.")
        self.status_manager.update_status(StatusManager.STATUS_DISCONNECTED)
        self.availableServersChanged.emit(self.server_discovery.available_servers)

        return True

    async def process_query(self, query: str):
        """Process the user query and handle the response from the server."""
        if not self.client:
            self.status_manager.update_status(
                StatusManager.STATUS_ERROR, error="Not connected to server"
            )
            self.conversation_manager.add_message(
                {
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": "ERROR: Not connected to server",
                }
            )
            self.errorOccurred.emit("Not connected to server")
            return

        self.status_manager.update_status(StatusManager.STATUS_PROCESSING)

        # Reset any existing streaming message to ensure we don't append to it
        # This is crucial to prevent new responses from being added to previous chat bubbles
        self.conversation_manager.reset_streaming_message()
        
        # Start tracking response content
        assistant_message = {
            "timestamp": self.conversation_manager.get_timestamp(),
            "content": "",
        }
        self.conversation_manager.add_message(assistant_message)
        self.conversation_manager.current_streaming_message = assistant_message

        # Use a batching mechanism for updating the UI to avoid excessive redraws
        last_update_time = time.time()
        update_interval = 0.05  # 50ms minimum between UI updates
        accumulated_chunks = ""

        try:
            self.status_manager.update_status(StatusManager.STATUS_STREAMING)

            # Use the MCPClient process_query interface, which now returns a generator for streaming responses
            async for chunk in self.client.process_query(query):
                if chunk.startswith("\n[Error:") or chunk.startswith("\n[Unexpected Error:") or chunk.startswith("\n[Reached max tool iterations"):
                    # Error messages from the MCP client
                    if self.conversation_manager.current_streaming_message:
                        self.conversation_manager.current_streaming_message["content"] += chunk
                        # Force immediate update for error messages
                        self.conversationChanged.emit()
                    continue
                
                # Handle special marker to create a new message bubble after tool calls
                if chunk == "__NEW_RESPONSE_AFTER_TOOL_CALLS__":
                    # Reset the current streaming message to ensure we create a new one
                    self.conversation_manager.reset_streaming_message()
                    # Create a new message bubble for the response after tool calls
                    assistant_message = {
                        "timestamp": self.conversation_manager.get_timestamp(),
                        "content": "",
                    }
                    self.conversation_manager.add_message(assistant_message)
                    self.conversation_manager.current_streaming_message = assistant_message
                    # Reset accumulated chunks for the new message
                    accumulated_chunks = ""
                    continue

                # If this is a new response after tool calls (in case marker wasn't received)
                if chunk and chunk.strip() and not self.conversation_manager.current_streaming_message:
                    # Create a new message bubble for the response after tool calls
                    logger.info("Creating new message bubble for response after tool calls")
                    assistant_message = {
                        "timestamp": self.conversation_manager.get_timestamp(),
                        "content": "",
                    }
                    self.conversation_manager.add_message(assistant_message)
                    self.conversation_manager.current_streaming_message = assistant_message
                    # Reset accumulated chunks for the new message
                    accumulated_chunks = ""

                if self.conversation_manager.current_streaming_message:
                    # Accumulate chunks before updating the UI
                    accumulated_chunks += chunk
                    
                    # Update the message content with the new chunk
                    self.conversation_manager.current_streaming_message["content"] += chunk
                    
                    # Only update the UI at the specified interval to avoid excessive redraws
                    current_time = time.time()
                    if current_time - last_update_time >= update_interval:
                        self.conversationChanged.emit()
                        last_update_time = current_time

            # Final update after streaming is complete
            self.status_manager.update_status(StatusManager.STATUS_IDLE)
            
            # Force a final UI update to ensure the last chunks are displayed
            if accumulated_chunks:
                self.conversationChanged.emit()

            # Emit the messageReceived signal when the response is complete
            if self.conversation_manager.current_streaming_message:
                timestamp = self.conversation_manager.current_streaming_message[
                    "timestamp"
                ]
                message = self.conversation_manager.current_streaming_message["content"]
                self.conversation_manager.reset_streaming_message()
                self.messageReceived.emit(message, timestamp)

        except Exception as e:
            logger.error(f"Error processing query: {e}", exc_info=True)
            error_msg = f"Error: {str(e)}"
            if self.conversation_manager.current_streaming_message:
                self.conversation_manager.current_streaming_message["content"] = (
                    error_msg
                )
                self.conversation_manager.reset_streaming_message()
            else:
                self.conversation_manager.add_message(
                    {
                        "timestamp": self.conversation_manager.get_timestamp(),
                        "content": error_msg,
                    }
                )
            self.status_manager.update_status(StatusManager.STATUS_ERROR, error=str(e))
            self.errorOccurred.emit(str(e))

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
                # Ensure client is set to None even if cleanup fails
                self.client = None

        # Reset conversation state to free memory
        if hasattr(self, 'conversation_manager') and self.conversation_manager:
            self.conversation_manager.reset_streaming_message()
            # Only keep the last 5 messages to free memory
            messages = self.conversation_manager.get_messages()
            if len(messages) > 5:
                self.conversation_manager.set_messages(messages[-5:])
        
        # Reset server discovery cache
        if hasattr(self, '_last_server_discovery_time'):
            self._last_server_discovery_time = 0

        self.is_connected = False
        self.status_manager.update_status(StatusManager.STATUS_DISCONNECTED)
        logger.info("MCPClientBridge cleanup completed")

    @pyqtSlot()
    def reset_status(self):
        """Reset the status to idle."""
        if self._is_connected:
            self.status_manager.update_status(StatusManager.STATUS_IDLE)
        else:
            self.status_manager.update_status(StatusManager.STATUS_DISCONNECTED)

    @pyqtSlot()
    def shutdown(self):
        """Handle application shutdown gracefully."""
        logger.info("Shutdown requested")
        self.status_manager.update_status(StatusManager.STATUS_SHUTTING_DOWN)

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
                sys.exit(1)

    @pyqtSlot()
    def getAvailableServers(self):
        """Get the list of available MCP servers."""
        current_time = time.time()
        if current_time - self._last_server_discovery_time < self._server_discovery_cache_timeout:
            logger.info("Using cached server discovery results")
            self.availableServersChanged.emit(self.server_discovery.available_servers)
            return self.server_discovery.available_servers

        self.server_discovery.discover_mcp_servers()
        self.availableServersChanged.emit(self.server_discovery.available_servers)
        self._last_server_discovery_time = current_time
        return self.server_discovery.available_servers

    @pyqtSlot(str)
    def setServerPath(self, server_path):
        """Set the path to the MCP server script."""
        logger.info(f"Setting server path: {server_path}")
        self._selected_server_path = server_path
        # Connection will be handled explicitly by the UI

    @pyqtSlot(result=str)
    def connectToServer(self):
        """Connect to the selected MCP server without blocking the UI thread."""
        if not self._selected_server_path:
            error_msg = "No server selected"
            logger.error(error_msg)
            self.status_manager.update_status(
                StatusManager.STATUS_ERROR, error=error_msg
            )
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
            self.status_manager.update_status(
                StatusManager.STATUS_ERROR, error=error_msg
            )
            self.errorOccurred.emit(error_msg)
            return error_msg

        # Update UI immediately to show connecting status
        self.status_manager.update_status(StatusManager.STATUS_CONNECTING)
        
        # Create task to connect in the background
        asyncio.create_task(self._connect_to_selected_server(server_name))
        return ""  # Empty string indicates success (no error)

    async def _connect_to_selected_server(self, server_name):
        """Connect to the selected server asynchronously."""
        # Status update moved to the calling method for immediate UI feedback
        self.conversation_manager.add_message(
            {
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": f"Connecting to server: {server_name}...",
            }
        )

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

            # Connect to server with explicit timeout to prevent hanging
            connect_task = self.client.connect_to_server(self._selected_server_path)
            connected = await asyncio.wait_for(connect_task, timeout=30.0)

            if connected:
                self.is_connected = True
                server_display_name = self.client.server_name or server_name
                self.status_manager.update_status(
                    StatusManager.STATUS_CONNECTED, server_name=server_display_name
                )
                self.conversation_manager.add_message(
                    {
                        "timestamp": self.conversation_manager.get_timestamp(),
                        "content": f"Connected to {server_display_name}",
                    }
                )
            else:
                self.status_manager.update_status(
                    StatusManager.STATUS_ERROR,
                    error=f"Failed to connect to {server_name}",
                )
                self.conversation_manager.add_message(
                    {
                        "timestamp": self.conversation_manager.get_timestamp(),
                        "content": f"Error: Failed to connect to {server_name}",
                    }
                )
                self.errorOccurred.emit(f"Failed to connect to {server_name}")
        except asyncio.TimeoutError:
            logger.error(f"Connection to server timed out after 30 seconds")
            self.status_manager.update_status(
                StatusManager.STATUS_ERROR, 
                error=f"Connection to {server_name} timed out"
            )
            self.conversation_manager.add_message(
                {
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": f"Error: Connection to {server_name} timed out after 30 seconds",
                }
            )
            self.errorOccurred.emit(f"Connection to {server_name} timed out")
        except Exception as e:
            logger.error(f"Error connecting to server: {e}", exc_info=True)
            self.status_manager.update_status(StatusManager.STATUS_ERROR, error=str(e))
            self.conversation_manager.add_message(
                {
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": f"Error connecting to server: {str(e)}",
                }
            )
            self.errorOccurred.emit(str(e))

    @pyqtSlot(result=bool)
    def isConnected(self):
        """Check if the client is connected to a server."""
        return self._is_connected

    @pyqtSlot()
    def start_listening(self):
        """Start voice listening (emit the signal for UI update)."""
        logger.info("Voice activation requested, but not implemented in this version")
        self.conversation_manager.add_message(
            {
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Voice activation is not implemented in this version.",
            }
        )
        # Emit signal for UI update
        self.listeningStarted.emit()
        # Future implementation would use Whisper or other voice recognition
        self.status_manager.update_status(
            StatusManager.STATUS_ERROR, error="Voice activation not implemented"
        )

    @pyqtSlot()
    def stop_listening(self):
        """Stop voice listening (emit the signal for UI update)."""
        logger.info("Voice deactivation requested, but not implemented in this version")
        # Emit signal for UI update
        self.listeningStopped.emit()
        self.status_manager.update_status(StatusManager.STATUS_IDLE)

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
                self.status_manager.update_status(StatusManager.STATUS_DISCONNECTED)
                self.conversation_manager.add_message(
                    {
                        "timestamp": self.conversation_manager.get_timestamp(),
                        "content": "Disconnected from server",
                    }
                )
            except Exception as e:
                logger.error(f"Error disconnecting from server: {e}", exc_info=True)
                self.status_manager.update_status(
                    StatusManager.STATUS_ERROR, error=f"Error disconnecting: {str(e)}"
                )
                self.errorOccurred.emit(f"Error disconnecting: {str(e)}")

        asyncio.create_task(_do_disconnect())

    @pyqtSlot(result=str)
    def getWifiIpAddress(self):
        """Get the WiFi IP address of the system."""
        return self.network_utils.get_wifi_ip_address()
