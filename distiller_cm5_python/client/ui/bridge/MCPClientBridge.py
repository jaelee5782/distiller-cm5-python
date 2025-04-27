# pyright: reportArgumentType=false
from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty
from PyQt6.QtWidgets import QApplication
from distiller_cm5_python.client.mid_layer.mcp_client import MCPClient
from qasync import asyncSlot
from distiller_cm5_python.utils.config import *
from distiller_cm5_python.client.ui.events.event_types import EventType, UIEvent, StatusType, MessageSchema
from distiller_cm5_python.client.ui.events.event_dispatcher import EventDispatcher
from distiller_cm5_python.utils.logger import logger
from distiller_cm5_python.client.ui.bridge.ConversationManager import ConversationManager
from distiller_cm5_python.client.ui.bridge.StatusManager import StatusManager
from distiller_cm5_python.client.ui.bridge.ServerDiscovery import ServerDiscovery
from distiller_cm5_python.client.ui.utils.NetworkUtils import NetworkUtils
from distiller_cm5_python.utils.distiller_exception import UserVisibleError, LogOnlyError
import asyncio
import os
import sys
import time
import psutil
import threading
from typing import Union
import uuid

# Exit delay constant
EXIT_DELAY_MS = 500  # Reduced delay from 1000ms to 500ms

class MCPClientBridge(QObject):
    """
    Bridge between the UI and the MCPClient.

    Handles the communication between the QML UI and the Python backend.
    Manages conversation state, server discovery, and client connection.
    """

    conversationChanged = pyqtSignal()  # Signal for conversation changes
    statusChanged = pyqtSignal(str)  # Signal for status changes
    availableServersChanged = pyqtSignal(list)  # Signal for available servers list
    isConnectedChanged = pyqtSignal(bool)  # Signal for connection status
    messageReceived = pyqtSignal(str, str, str, str)  # Signal for new messages (content, event_id, timestamp, status)
    listeningStarted = pyqtSignal()  # Signal for when listening starts
    listeningStopped = pyqtSignal()  # Signal for when listening stops
    errorOccurred = pyqtSignal(str)  # Signal for errors
    bridgeReady = pyqtSignal()  # Signal for when the bridge is fully initialized
    recordingStateChanged = pyqtSignal(bool)  # Signal for recording state changes
    recordingError = pyqtSignal(str)  # Signal specifically for recording/transcription errors
    actionReceived = pyqtSignal(str, str, str)  # Signal for actions
    infoReceived = pyqtSignal(str, str, str)  # Signal for info messages
    warningReceived = pyqtSignal(str, str, str)  # Signal for warnings
    errorReceived = pyqtSignal(str, str, str)  # Signal for errors
    transcriptionUpdate = pyqtSignal(str, arguments=['transcription'])  # Signal for transcription updates
    transcriptionComplete = pyqtSignal(str, arguments=['full_text'])  # Signal for completed transcription
    # New signals for architecture diagram support
    sshInfoReceived = pyqtSignal(str, str, str)  # Signal for SSH info events (content, event_id, timestamp)
    functionReceived = pyqtSignal(str, str, str)  # Signal for function events (content, event_id, timestamp)
    observationReceived = pyqtSignal(str, str, str)  # Signal for observation events (content, event_id, timestamp)
    planReceived = pyqtSignal(str, str, str)  # Signal for plan events (content, event_id, timestamp)
    messageSchemaReceived = pyqtSignal('QVariantMap')  # Signal for raw message schema objects

    def __init__(self, parent=None):
        """MCPClientBridge initializes the MCPClient and manages the conversation state."""
        super().__init__(parent=parent)

        # Initialize sub-components
        self.status_manager = StatusManager(self)
        self.conversation_manager = ConversationManager(self)
        self.conversation_manager.reset_streaming_message()
        self.server_discovery = ServerDiscovery(self)
        self.network_utils = NetworkUtils()

        # Initialize event dispatcher
        self.dispatcher = EventDispatcher()

        # Initialize MCP client with dispatcher
        self.mcp_client = MCPClient(dispatcher=self.dispatcher)

        # Connect dispatcher signals to bridge slots
        self.dispatcher.event_dispatched.connect(self._handle_event)

        # Initialize client-related properties
        self._is_connected = False
        self._is_ready = False
        self._loop = asyncio.get_event_loop()
        self.config_path = DEFAULT_CONFIG_PATH
        self._current_log_level = config.get("logging", "level", default="DEBUG").upper()
        self._selected_server_path = None

        # Reference to the App instance
        self._app_instance = None

        # Server discovery cache
        self._last_server_discovery_time = 0
        self._server_discovery_cache_timeout = 5  # seconds

        # Configuration cache - simplified
        self._config_cache = {}
        self._config_dirty = False

    def set_app_instance(self, app_instance):
        """Set the reference to the App instance."""
        self._app_instance = app_instance
        logger.info("App instance reference set in bridge")

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
        try:
            if not query.strip():
                return

            if not self._is_connected:
                raise ConnectionError("Not connected to any server. Please connect first.")

            # Add user message
            user_message = {
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": f"You: {query}",
            }
            self.conversation_manager.add_message(user_message)
            logger.info(f"User query added to conversation: {query}")

            # Process the query in a separate task to avoid blocking the UI
            asyncio.create_task(self.process_query(query))

        except Exception as e:
            self._handle_error(
                e,
                "Query submission",
                user_friendly_msg="Failed to submit query. Please check your connection and try again.",
            )

    async def process_query(self, query: str):
        """Process a user query through the MCP client."""
        logger.info(f"MCPClientBridge.process_query: Processing query: {query}")
        try:
            # Update status to processing query
            self.status_manager.update_status(StatusManager.STATUS_PROCESSING_QUERY)
            await self.mcp_client.process_query(query)
        except LogOnlyError as e:
            # Explicitly handle connection errors
            logger.error(f"Connection error during query processing: {str(e)}")
            self._handle_error(
                e,
                "Query processing",
                user_friendly_msg="Connection to LLM server failed. Please check your connection and try again."
            )
            # Ensure error state is properly set
            self.status_manager.update_status(StatusManager.STATUS_ERROR, error=str(e))
        except Exception as e:
            # Handle other exceptions
            logger.error(f"Error processing query: {str(e)}", exc_info=True)
            self._handle_error(
                e,
                "Query processing",
                user_friendly_msg="Failed to process query. Please try again."
            )
        finally:
            # Reset to idle state if we're connected, otherwise disconnected
            if self._is_connected and not self.status_manager.is_error:
                self.status_manager.update_status(StatusManager.STATUS_IDLE)

    @pyqtSlot()
    def clear_conversation(self):
        """Clear the conversation history"""
        self.conversation_manager.clear()
        logger.info("Conversation cleared")

    @pyqtSlot(bool)
    def toggle_streaming(self, enabled: bool):
        """Enable or disable streaming mode."""
        if self.mcp_client is None:
            logger.error("Client is not initialized")
            return
            
        self.mcp_client.streaming = enabled
        status = "enabled" if enabled else "disabled"
        self.status_manager.status = f"Streaming {status}"
        self.conversation_manager.add_message({
            "timestamp": self.conversation_manager.get_timestamp(),
            "content": f"Streaming {status}",
        })
        logger.info(f"Streaming {status}")
        self.statusChanged.emit(self.status_manager.status)

    @pyqtSlot(str, str, result="QVariant")
    def getConfigValue(self, section: str, key: str) -> str:
        """Get a configuration value, always returning a string."""
        # Generate a cache key for this config value
        cache_key = f"{section}.{key}"
        
        # Check if the value is in the cache
        if cache_key in self._config_cache:
            logger.debug(f"Cache hit for {cache_key}")
            return self._config_cache[cache_key]

        # Not in cache, need to fetch from config
        logger.debug(f"Cache miss for {cache_key}, fetching from config")

        # Handle special cases
        if cache_key == "active_llm_provider":
            value = config.get("active_llm_provider")
        elif section == "llm":
            # Map to provider-specific structure
            active_provider_name = config.get("active_llm_provider")
            value = config.get("llm_providers", active_provider_name, key)
        elif section == "llama_cpp" and key == "start_wait_time":
            value = config.get(section, key, default=30)
        else:
            # Regular configuration paths
            value = config.get(section, key)

        # Format the value for QML
        if value is None:
            result = ""
        elif isinstance(value, list):
            if key == "stop":
                # Escape special characters for stop sequences
                result = "\n".join(str(v).encode("unicode_escape").decode("utf-8") for v in value)
            else:
                result = ",".join(str(v) for v in value)
        elif section == "logging" and key == "level":
            result = self._current_log_level
        else:
            result = str(value)

        # Cache the result
        self._config_cache[cache_key] = result
        return result

    @pyqtSlot(str, str, "QVariant")
    def setConfigValue(self, section: str, key: str, value):
        """Set a configuration value and update the cache."""
        # Cache key for consistent cache management
        cache_key = f"{section}.{key}"
        logger.debug(f"Setting config value: {cache_key} = {value}")

        # Process the value first
        if key == "stop" and isinstance(value, str):
            processed_value = [v.encode("utf-8").decode("unicode_escape") for v in value.split("\n") if v]
        elif key in ["timeout", "top_k", "n_ctx", "max_tokens", "streaming_chunk_size"]:
            processed_value = int(value) if value != "" else 0
        elif key in ["temperature", "top_p", "repetition_penalty"]:
            processed_value = float(value) if value != "" else 0.0
        elif key == "streaming" or key == "file_enabled":
            processed_value = bool(value)
        elif section == "logging" and key == "level":
            processed_value = value.upper()
            self._current_log_level = processed_value
        else:
            processed_value = value

        # Special cases for provider-specific configuration
        if section == "llm":
            active_provider_name = self.getConfigValue("active_llm_provider", "")
            config.set("llm_providers", active_provider_name, key, processed_value)
            
            # Update the cache
            provider_cache_key = f"llm_providers.{active_provider_name}.{key}"
            self._config_cache[provider_cache_key] = str(processed_value)
        else:
            # Regular configuration paths
            config.set(section, key, processed_value)
            self._config_cache[cache_key] = str(processed_value)

        # Mark configuration as dirty for save
        self._config_dirty = True

    @asyncSlot()
    async def applyConfig(self):
        """Apply configuration changes by restarting the client."""
        try:
            self.status_manager.update_status(StatusManager.STATUS_INITIALIZING)
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Applying configuration changes...",
            })

            # Store the current conversation
            current_conversation = self.conversation_manager.get_messages_copy()

            # Save config if needed
            if self._config_dirty:
                try:
                    config.save_to_file(self.config_path)
                    self._config_dirty = False
                    logger.info("Configuration saved successfully before apply")
                except Exception as save_error:
                    self._handle_error(
                        save_error,
                        "Config save",
                        user_friendly_msg=f"Warning: Could not save pending changes: {str(save_error)}",
                    )

            # Clean up existing client
            if self.mcp_client:
                self.conversation_manager.add_message({
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": "Disconnecting from server...",
                })

                try:
                    cleanup_task = asyncio.create_task(self.mcp_client.cleanup())
                    await asyncio.wait_for(cleanup_task, timeout=5.0)
                except asyncio.TimeoutError:
                    logger.warning("Cleanup timeout during configuration apply, forcing disconnect")
                    self.conversation_manager.add_message({
                        "timestamp": self.conversation_manager.get_timestamp(),
                        "content": "Cleanup is taking longer than expected, forcing disconnect...",
                    })
                except Exception as cleanup_error:
                    self._handle_error(
                        cleanup_error,
                        "Client cleanup",
                        user_friendly_msg="Warning: Client resources may not be properly released.",
                    )

                # Reset client
                self.mcp_client = None
                self.is_connected = False

            # Reload the configuration
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Reloading configuration...",
            })

            try:
                # Clear cache and reload config
                self._config_cache = {}
                config.reload()
                logger.info("Configuration cache cleared and config reloaded")
            except Exception as config_error:
                raise ValueError(
                    f"Failed to reload configuration: {str(config_error)}. Check your config file for syntax errors."
                )

            # Update global variables
            try:
                # Get the active provider configuration
                active_provider_name = config.get("active_llm_provider")
                if not active_provider_name:
                    raise ValueError("No active LLM provider specified in configuration.")

                active_provider_config = config.get("llm_providers", active_provider_name)
                if not active_provider_config:
                    raise ValueError(f"Configuration for provider '{active_provider_name}' not found.")

                # Update global variables from the active provider
                SERVER_URL = active_provider_config.get("server_url")
                if not SERVER_URL:
                    raise ValueError(f"No server URL specified for provider '{active_provider_name}'.")

                MODEL_NAME = active_provider_config.get("model_name")
                if not MODEL_NAME:
                    raise ValueError(f"No model name specified for provider '{active_provider_name}'.")

                PROVIDER_TYPE = active_provider_config.get("provider_type", active_provider_name)
                API_KEY = active_provider_config.get("api_key", "")
                TIMEOUT = active_provider_config.get("timeout", 120)
                STREAMING_ENABLED = active_provider_config.get("streaming", True)
            except ValueError as config_value_error:
                raise ValueError(f"Configuration error: {str(config_value_error)}")
            except Exception as config_extract_error:
                raise ValueError(f"Error extracting configuration values: {str(config_extract_error)}")

            # Create new client with updated config
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Creating new client with updated configuration...",
            })

            # Reconnect if previously connected
            if self._selected_server_path:
                await self._connect_to_selected_server(
                    os.path.basename(self._selected_server_path)
                )

            self.status_manager.update_status(StatusManager.STATUS_CONFIG_APPLIED)
            # Restore conversation
            self.conversation_manager.set_messages(current_conversation)
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Configuration applied successfully.",
            })

        except Exception as e:
            self._handle_error(
                e,
                "Configuration apply",
                user_friendly_msg=f"Failed to apply configuration changes: {str(e)}",
            )

    @pyqtSlot()
    def saveConfigToFile(self):
        """Save the current configuration to file."""
        if not self._config_dirty:
            logger.debug("Configuration not dirty, skipping save")
            return

        logger.info(f"Saving configuration to {self.config_path}")
        try:
            config.save_to_file(self.config_path)
            self._config_dirty = False
            logger.info(f"Configuration saved successfully to {self.config_path}")
        except Exception as e:
            self._handle_error(
                e,
                "Config save",
                user_friendly_msg=f"Failed to save configuration: {str(e)}",
            )

    async def connect_to_server(self):
        """Ask the user to select a server from the list of available servers."""
        self.status_manager.update_status(StatusManager.STATUS_INITIALIZING)

        if not self.server_discovery.available_servers:
            self.server_discovery.discover_mcp_servers()

        if not self.server_discovery.available_servers:
            self.status_manager.update_status(
                StatusManager.STATUS_ERROR, error="No MCP servers found"
            )
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Error: No MCP servers found.",
            })
            self.errorOccurred.emit("No MCP servers found")
            return False

        # Wait for user to select a server in UI before proceeding
        logger.info("Available servers discovered. Waiting for user selection.")
        self.status_manager.update_status(StatusManager.STATUS_DISCONNECTED)
        self.availableServersChanged.emit(self.server_discovery.available_servers)

        return True

    def _handle_event(self, event: Union[UIEvent, MessageSchema]) -> None:
        """Handle events from the dispatcher."""
        try:
            # Handle new MessageSchema format
            if isinstance(event, MessageSchema):
                # Convert timestamp to string if it exists
                timestamp_str = str(event.timestamp) if event.timestamp else None
                
                # Emit the raw message schema event
                try:
                    # Convert the MessageSchema to a dictionary for QML
                    event_dict = event.dict()
                    # Emit the messageSchemaReceived signal with the event data
                    self.messageSchemaReceived.emit(event_dict)
                except Exception as e:
                    logger.error(f"Error converting MessageSchema to dict: {e}", exc_info=True)
                
                # Emit the appropriate signal based on event type
                if event.type == EventType.MESSAGE:
                    # Pass status as string (.value from Enum) to the UI
                    status_value = event.status.value if hasattr(event.status, 'value') else event.status
                    self.messageReceived.emit(event.content, str(event.id), timestamp_str, status_value)
                    
                    # Update status when message is complete
                    if status_value == "success":
                        if self._is_connected:
                            self.status_manager.update_status(StatusManager.STATUS_IDLE)
                elif event.type == EventType.ACTION:
                    self.actionReceived.emit(event.content, str(event.id), timestamp_str)
                    
                    # Set executing tool status for actions
                    status_value = event.status.value if hasattr(event.status, 'value') else event.status
                    if status_value == "in_progress":
                        self.status_manager.update_status(StatusManager.STATUS_EXECUTING_TOOL)
                    elif status_value == "success":
                        # Don't reset state here as we wait for the full completion
                        pass
                elif event.type == EventType.INFO:
                    self.infoReceived.emit(event.content, str(event.id), timestamp_str)
                    
                    # For thinking info events, update status
                    if event.content and "Thinking" in event.content:
                        self.status_manager.update_status(StatusManager.STATUS_THINKING)
                elif event.type == EventType.WARNING:
                    self.warningReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.ERROR:
                    self.errorReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.SSH_INFO:
                    # Add handling for SSH_INFO events
                    # This would need a new signal in the bridge class
                    if hasattr(self, 'sshInfoReceived'):
                        self.sshInfoReceived.emit(event.content, str(event.id), timestamp_str)
                    else:
                        # Fall back to info message if no dedicated handler
                        self.infoReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.FUNCTION:
                    # Add handling for FUNCTION events
                    # This would need a new signal in the bridge class
                    if hasattr(self, 'functionReceived'):
                        self.functionReceived.emit(event.content, str(event.id), timestamp_str)
                    else:
                        # Fall back to info message if no dedicated handler
                        self.infoReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.OBSERVATION:
                    # Handle observation events - fallback to info for now
                    if hasattr(self, 'observationReceived'):
                        self.observationReceived.emit(event.content, str(event.id), timestamp_str)
                    else:
                        # Fall back to info message if no dedicated handler
                        self.infoReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.PLAN:
                    # Handle plan events - fallback to info for now
                    if hasattr(self, 'planReceived'):
                        self.planReceived.emit(event.content, str(event.id), timestamp_str)
                    else:
                        # Fall back to info message if no dedicated handler
                        self.infoReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.STATUS:
                    # Update status if STATUS event
                    status_str = event.content
                    self.status_manager.update_status(status_str)
                    self.statusChanged.emit(status_str)
                else:
                    logger.warning(f"MCPClientBridge._handle_event: Unknown event type: {event.type}")
            
            # Handle legacy UIEvent format (backward compatibility)
            elif isinstance(event, UIEvent):
                # Convert timestamp to string if it exists
                timestamp_str = str(event.timestamp) if event.timestamp else None

                # Emit the appropriate signal based on event type
                if event.type == EventType.MESSAGE:
                    # Pass status as string (.value from Enum) to the UI
                    status_value = event.status.value if hasattr(event.status, 'value') else event.status
                    self.messageReceived.emit(event.content, str(event.id), timestamp_str, status_value)
                elif event.type == EventType.ACTION:
                    self.actionReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.INFO:
                    self.infoReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.WARNING:
                    self.warningReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.ERROR:
                    self.errorReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.SSH_INFO:
                    # Handle SSH info with generic info signal if available
                    self.infoReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.FUNCTION:
                    # Handle function info with generic info signal if available
                    self.infoReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.OBSERVATION:
                    # Handle observation events with generic info signal
                    self.infoReceived.emit(event.content, str(event.id), timestamp_str)
                elif event.type == EventType.PLAN:
                    # Handle plan events with generic info signal
                    self.infoReceived.emit(event.content, str(event.id), timestamp_str)
                else:
                    logger.warning(f"MCPClientBridge._handle_event: Unknown event type: {event.type}")
            else:
                logger.error(f"MCPClientBridge._handle_event: Invalid event type: {type(event)}")
                return

        except Exception as e:
            logger.error(f"MCPClientBridge._handle_event: Error handling event: {e}", exc_info=True)

    @pyqtSlot(bool)
    def shutdownApplication(self, restart=False):
        """
        Handle application shutdown gracefully.
        Args:
            restart: Whether to restart after shutdown (currently unused)
        """
        logger.info(f"Shutdown requested from QML with restart={restart}")
        asyncio.create_task(self._shutdown_process())
        return True

    async def _shutdown_process(self):
        """Unified shutdown process to handle all cleanup."""
        logger.info("Bridge shutdown initiated")
        self.status_manager.update_status(StatusManager.STATUS_SHUTTING_DOWN)

        try:
            # Clean up client if exists
            if self.mcp_client:
                try:
                    await self.mcp_client.cleanup()
                    logger.info("Completed MCP client cleanup")
                except Exception as e:
                    logger.error(f"Error during client cleanup: {e}", exc_info=True)
            
            # Terminate dangling processes
            self._terminate_dangling_processes()
            
            logger.info("Force quitting application from bridge")
            # Use threading for final exit
            threading.Thread(target=self._force_exit, daemon=True).start()
            await asyncio.sleep(0.1)  # Short sleep to let logs flush
            os._exit(0)  # Force immediate exit
        except Exception as e:
            logger.error(f"Error during shutdown: {e}", exc_info=True)
            self._force_exit()
    
    def _force_exit(self):
        """Force the application to exit."""
        time.sleep(EXIT_DELAY_MS / 1000.0)
        logger.info("Executing final force exit")
        self._terminate_dangling_processes(force=True)
        os._exit(0)

    def _terminate_dangling_processes(self, force=False):
        """Find and terminate any dangling MCP processes."""
        logger.info("Checking for dangling MCP processes")

        try:
            # Find our process ID
            current_process = psutil.Process(os.getpid())
            children = current_process.children(recursive=True)

            for child in children:
                try:
                    # Check if it's an MCP-related process
                    if force or any(
                        mcp_name in " ".join(child.cmdline()).lower()
                        for mcp_name in ["mcp", "model-control"]
                    ):
                        logger.info(f"Terminating process {child.pid}: {' '.join(child.cmdline())}")
                        if force:
                            # Force kill
                            child.kill()
                        else:
                            # Try graceful termination first
                            child.terminate()
                            try:
                                child.wait(timeout=1)
                            except psutil.TimeoutExpired:
                                # Force kill if it doesn't terminate
                                logger.info(f"Process {child.pid} didn't terminate, force killing")
                                child.kill()
                except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                    # Process already gone or can't be accessed
                    pass
                except Exception as e:
                    logger.error(f"Error terminating process {child.pid}: {e}")
        except Exception as e:
            logger.error(f"Error finding/terminating dangling processes: {e}", exc_info=True)

    @pyqtSlot()
    def reset_status(self):
        """Reset the status to idle."""
        if self._is_connected:
            self.status_manager.update_status(StatusManager.STATUS_IDLE)
        else:
            self.status_manager.update_status(StatusManager.STATUS_DISCONNECTED)

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
        """Connect to the selected MCP server."""
        try:
            if not self._selected_server_path:
                raise ValueError("No server selected. Please choose a server before connecting.")

            # Extract server name for status messages
            server_name = (
                os.path.basename(self._selected_server_path)
                .replace("_server.py", "")
                .replace(".py", "")
            )

            if not os.path.exists(self._selected_server_path):
                raise FileNotFoundError(f"Server script not found: {self._selected_server_path}")

            # Update UI immediately to show connecting status
            self.status_manager.update_status(StatusManager.STATUS_CONNECTING)

            # Create task to connect in the background
            asyncio.create_task(self._connect_to_selected_server(server_name))
            return ""  # Empty string indicates success (no error)

        except Exception as e:
            error_msg = self._handle_error(
                e,
                "Server connection",
                user_friendly_msg=f"Failed to connect to server: {str(e)}",
            )
            return error_msg  # Return error message string

    async def _connect_to_selected_server(self, server_name):
        """Connect to the selected server asynchronously."""
        try:
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": f"Connecting to server: {server_name}...",
            })

            # Create new client if needed
            if not self.mcp_client:
                self.mcp_client = MCPClient(
                    streaming=STREAMING_ENABLED,
                    llm_server_url=SERVER_URL,
                    provider_type=PROVIDER_TYPE,
                    model=MODEL_NAME,
                    api_key=API_KEY,
                    timeout=TIMEOUT,
                    dispatcher=self.dispatcher
                )

            # Connect to server with explicit timeout
            try:
                connect_task = self.mcp_client.connect_to_server(self._selected_server_path)
                connected = await asyncio.wait_for(connect_task, timeout=30.0)
            except asyncio.TimeoutError:
                raise TimeoutError(
                    f"Connection to {server_name} timed out after 30 seconds. Server may be busy or unavailable."
                )

            if not connected:
                raise ConnectionError(
                    f"Failed to establish connection with {server_name} server. Check server status and configuration."
                )

            self.is_connected = True
            server_display_name = self.mcp_client.server_name or server_name
            self.status_manager.update_status(
                StatusManager.STATUS_CONNECTED, server_name=server_display_name
            )
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": f"Connected to {server_display_name}",
            })
        except Exception as e:
            # Ensure client is reset in case of errors
            if self.mcp_client:
                try:
                    await self.mcp_client.cleanup()
                except Exception as cleanup_e:
                    logger.error(f"Error cleaning up client after connection failure: {cleanup_e}")
                finally:
                    # Reset the client reference and connection state
                    self.mcp_client = None

            self._handle_error(e, f"Connection to server '{server_name}'")

    @pyqtSlot(result=bool)
    def isConnected(self):
        """Check if the client is connected to a server."""
        return self._is_connected

    @pyqtSlot()
    def startListening(self):
        """Start voice listening."""
        try:
            logger.info("Voice activation requested")

            # Check if client is connected
            if not self._is_connected:
                raise ConnectionError("Cannot activate voice: not connected to any server.")

            # Emit signal for UI update
            self.listeningStarted.emit()

            # Call startRecording
            self.startRecording()
        except Exception as e:
            self._handle_error(
                e,
                "Voice activation",
                user_friendly_msg="Voice activation failed. Please check your microphone settings.",
            )
            # Update UI appropriately
            self.listeningStopped.emit()

    @pyqtSlot()
    def stopListening(self):
        """Stop voice listening."""
        try:
            logger.info("Voice deactivation requested")
            # Emit signal for UI update
            self.listeningStopped.emit()
            self.status_manager.update_status(StatusManager.STATUS_IDLE)

            # Call stopAndTranscribe
            self.stopAndTranscribe()
        except Exception as e:
            self._handle_error(e, "Voice deactivation")

    @pyqtSlot()
    def startRecording(self):
        """Start recording audio with Whisper."""
        try:
            logger.info("Starting Whisper recording")

            # Check if client is connected
            if not self._is_connected:
                raise ConnectionError("Cannot record: not connected to any server.")

            # Use direct app instance reference
            if self._app_instance:
                self._app_instance.startRecording()
            else:
                raise RuntimeError("No App instance reference available")
        except Exception as e:
            self._handle_error(
                e,
                "Voice recording",
                user_friendly_msg="Failed to start recording. Please check your microphone settings.",
            )

    @pyqtSlot()
    def stopAndTranscribe(self):
        """Stop recording and transcribe the audio with Whisper."""
        try:
            logger.info("Stopping recording and starting transcription")

            # Use direct app instance reference
            if self._app_instance:
                self._app_instance.stopAndTranscribe()
            else:
                raise RuntimeError("No App instance reference available")
        except Exception as e:
            self._handle_error(
                e,
                "Voice transcription",
                user_friendly_msg="Failed to transcribe audio.",
            )
            # Update UI appropriately
            self.listeningStopped.emit()

    @pyqtSlot()
    def disconnectFromServer(self):
        """Disconnect from the MCP server."""
        logger.info("Disconnecting from server")
        asyncio.create_task(self._disconnect_process())

    async def _disconnect_process(self):
        """Disconnect process to clean up the client."""
        try:
            if self.mcp_client:
                try:
                    # Timeout the cleanup operation to prevent hanging
                    await asyncio.wait_for(self.mcp_client.cleanup(), timeout=5.0)
                except asyncio.TimeoutError:
                    logger.warning("Client cleanup timed out during disconnection")
                except Exception as e:
                    logger.error(f"Error during client cleanup in disconnection: {e}", exc_info=True)
                finally:
                    # Always reset the client reference
                    self.mcp_client = None

            # Update the connection state
            self.is_connected = False
            self.status_manager.update_status(StatusManager.STATUS_DISCONNECTED)
        except Exception as e:
            self._handle_error(
                e,
                "Server disconnection",
                user_friendly_msg="Error disconnecting from server. Some resources may not be properly released.",
            )

    @pyqtSlot(result=str)
    def getWifiIpAddress(self):
        """Get the WiFi IP address of the system."""
        return self.network_utils.get_wifi_ip_address()

    def _handle_error(self, error, error_context="Operation", log_error=True, user_friendly_msg=None):
        """Centralized error handling for consistent error reporting to UI and logs."""
        # Format different error types appropriately
        if isinstance(error, UserVisibleError):
            # UserVisibleError is already formatted for end users
            error_msg = str(error)
            log_with_traceback = False
        elif isinstance(error, LogOnlyError):
            # LogOnlyError should be logged with details but shown with generic message
            error_msg = user_friendly_msg or f"{error_context} failed. See logs for details."
            log_with_traceback = True
        elif isinstance(error, TimeoutError) or isinstance(error, asyncio.TimeoutError):
            error_msg = user_friendly_msg or f"{error_context} timed out. Server may be busy or unavailable."
            log_with_traceback = True
        elif isinstance(error, FileNotFoundError):
            error_msg = user_friendly_msg or f"Required file not found: {str(error)}"
            log_with_traceback = False
        elif isinstance(error, ConnectionError):
            error_msg = user_friendly_msg or f"Connection error: {str(error)}"
            log_with_traceback = True
        else:
            # For unexpected errors, use a generic message unless overridden
            error_msg = user_friendly_msg or f"{error_context} failed: {str(error)}"
            log_with_traceback = True

        # Log the error appropriately
        if log_error:
            if log_with_traceback:
                logger.error(f"{error_context} error: {error}", exc_info=True)
            else:
                logger.error(f"{error_context} error: {error}")

        # Update status and conversation with error
        self.status_manager.update_status(StatusManager.STATUS_ERROR, error=error_msg)

        # Add error to conversation
        self.conversation_manager.add_message({
            "timestamp": self.conversation_manager.get_timestamp(),
            "content": f"Error: {error_msg}",
        })

        # Emit the error signal for QML
        self.errorOccurred.emit(error_msg)
        
        # Force UI state reset
        # Create and emit an error event to ensure the UI transitions to error state
        error_event = MessageSchema(
            id=str(uuid.uuid4()),
            type=EventType.ERROR,
            content=error_msg,
            status=StatusType.FAILED,
            timestamp=time.time()
        )
        self.dispatcher.dispatch(error_event)

        return error_msg

    async def cleanup(self):
        """
        Compatibility method for the App class.
        Delegates to the _shutdown_process method which handles all cleanup.
        """
        logger.info("cleanup() called - delegating to shutdown process")
        # Don't actually exit the application from this method
        try:
            # Clean up client if exists
            if self.mcp_client:
                try:
                    await self.mcp_client.cleanup()
                    logger.info("Completed MCP client cleanup")
                except Exception as e:
                    logger.error(f"Error during client cleanup: {e}", exc_info=True)
            
            # Terminate dangling processes
            self._terminate_dangling_processes()
            
            logger.info("Bridge cleanup completed")
        except Exception as e:
            logger.error(f"Error during bridge cleanup: {e}", exc_info=True)

    def shutdown(self, restart=False):
        """
        Synchronous shutdown method for App.py compatibility.
        Creates an async task to perform the actual shutdown.
        
        Args:
            restart: Parameter for backward compatibility (unused)
        """
        logger.info(f"shutdown() called with restart={restart}")
        # Create a task to run the async shutdown process
        asyncio.create_task(self._shutdown_process())

    @pyqtSlot()
    def restartApplication(self):
        """Restart the application without completely shutting down."""
        logger.info("Application restart requested")
        self.status_manager.update_status(StatusManager.STATUS_RESTARTING)
        asyncio.create_task(self._do_restart())

    async def _do_restart(self):
        """Perform application restart by resetting state and reconnecting."""
        try:
            logger.info("Starting application restart")

            # Store the current server path for reconnection
            current_server_path = self._selected_server_path

            # Clear the conversation
            self.clear_conversation()

            # Disconnect from the server
            if self._is_connected:
                self.disconnectFromServer()
                # Wait for disconnect to complete
                await asyncio.sleep(0.5)

            # Reset processing state
            self.status_manager.update_status(StatusManager.STATUS_DISCONNECTED)

            # Emit signals to reset UI state
            self.conversationChanged.emit()

            # Try to reconnect to the same server
            if current_server_path and os.path.exists(current_server_path):
                logger.info(f"Restarting with server: {current_server_path}")
                self._selected_server_path = current_server_path

                # Extract server name for status messages
                server_name = (
                    os.path.basename(current_server_path)
                    .replace("_server.py", "")
                    .replace(".py", "")
                )

                # Update UI to show connecting status
                self.status_manager.update_status(StatusManager.STATUS_CONNECTING)

                # Connect to the same server
                try:
                    await self._connect_to_selected_server(server_name)
                except Exception as e:
                    logger.error(f"Failed to reconnect to server during restart: {e}")
                    # Fall back to server selection
                    await self.connect_to_server()
            else:
                # If no previous server or it doesn't exist, show server selection
                await self.connect_to_server()

            # Update status
            if self._is_connected:
                self.status_manager.update_status(StatusManager.STATUS_IDLE)
                logger.info("Application restart completed successfully")
            else:
                self.status_manager.update_status(StatusManager.STATUS_DISCONNECTED)
                logger.warning("Application restarted but not connected to server")

            # Emit bridge ready signal to refresh UI components
            logger.info("Emitting bridgeReady signal to reinitialize UI")
            self.bridgeReady.emit()
        except Exception as e:
            logger.error(f"Error during application restart: {e}", exc_info=True)
            self.status_manager.update_status(StatusManager.STATUS_ERROR)
            self._handle_error(
                e,
                "Application restart",
                user_friendly_msg="Failed to restart application. Please try again.",
            )
