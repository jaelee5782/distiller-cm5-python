"""
Main bridge module that connects the UI to the backend.
This is a facade class that delegates to the modular components.
"""

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty
from PyQt6.QtWidgets import QApplication
from distiller_cm5_python.client.mid_layer.mcp_client import MCPClient
from qasync import asyncSlot
from distiller_cm5_python.utils.config import *
from distiller_cm5_python.client.ui.events.event_dispatcher import EventDispatcher
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
from typing import Union, Optional
import uuid
import logging

from distiller_cm5_python.client.ui.bridge.components.bridge_core import BridgeCore

logger = logging.getLogger(__name__)

# Exit delay constant
EXIT_DELAY_MS = 500  # Reduced delay from 1000ms to 500ms

class MCPClientBridge(BridgeCore):
    """
    Bridge between the UI and the MCPClient.

    This class is a facade that implements the same interface as the original
    MCPClientBridge, but delegates all functionality to the modular components.
    This approach allows for a gradual refactoring while maintaining compatibility
    with existing code.
    """

    # Redefine the signal in this class for the property to work
    bridgeReady = pyqtSignal()
    
    # Signal for receiving MessageSchema events - defined here to maintain compatibility
    messageSchemaReceived = pyqtSignal('QVariantMap')

    def __init__(self, parent=None):
        """
        Initialize the bridge.
        
        Args:
            parent: Optional parent object
        """
        super().__init__(parent=parent)
        logger.info("MCPClientBridge initialized using modular architecture")

        # Initialize sub-components
        self.status_manager = StatusManager(self)
        self.conversation_manager = ConversationManager(self)
        self.conversation_manager.reset_streaming_message()
        self.server_discovery = ServerDiscovery(self)
        self.network_utils = NetworkUtils()

        # Initialize event dispatcher
        self.dispatcher = EventDispatcher()

        # Initialize MCP client with dispatcher first
        self.mcp_client = MCPClient(dispatcher=self.dispatcher)

        # Initialize connection manager after MCP client
        # Import the ConnectionManager class here to avoid circular imports
        from distiller_cm5_python.client.ui.bridge.components.connection_manager import ConnectionManager
        self.connection_manager = ConnectionManager(
            self.status_manager,
            self.conversation_manager,
            self.server_discovery,
            self.is_connected.__class__  # Pass the property class
        )
        # Set up connection callback
        self.connection_manager.set_connection_callback(self._on_connection_changed)
        # Set the mcp_client in the connection manager
        self.connection_manager.mcp_client = self.mcp_client

        # Connect dispatcher signals to bridge slots
        self.dispatcher.message_dispatched.connect(self._handle_event)

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
        self.status_manager.update_status(self.status_manager.STATUS_INITIALIZING)

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

            if not self.is_connected:
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
            self.error_handler.handle_error(
                e,
                "Query submission",
                user_friendly_msg="Failed to submit query. Please check your connection and try again.",
            )

    async def process_query(self, query: str):
        """Process a user query through the MCP client."""
        logger.info(f"MCPClientBridge.process_query: Processing query: {query}")
        try:
            await self.connection_manager.process_query(query)
        except Exception as e:
            self.error_handler.handle_error(
                e,
                "Query processing",
                user_friendly_msg="Failed to process query. Please try again."
            )

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
        return self.config_manager.get_config_value(section, key)

    @pyqtSlot(str, str, "QVariant")
    def setConfigValue(self, section: str, key: str, value):
        """Set a configuration value and update the cache."""
        self.config_manager.set_config_value(section, key, value)

    @asyncSlot()
    async def applyConfig(self):
        """Apply configuration changes by restarting the client."""
        await self.config_manager.apply_config(
            self.mcp_client,
            self.error_handler.handle_error,
            self.connection_manager.connect_to_selected_server
        )

    @pyqtSlot()
    def saveConfigToFile(self):
        """Save the current configuration to file."""
        self.config_manager.save_config_to_file(self.error_handler.handle_error)

    async def connect_to_server(self):
        """Ask the user to select a server from the list of available servers."""
        success = await self.connection_manager.connect_to_server()
        if success:
            self.availableServersChanged.emit(self.server_discovery.available_servers)
        return success

    def _handle_event(self, event: Union[dict, object]) -> None:
        """
        Legacy method for backward compatibility.
        Events are now handled by the event handler component.
        """
        # Add debug logging
        logger.debug(f"MCPClientBridge received event: type={getattr(event, 'type', None)}, status={getattr(event, 'status', None)}")
        # Just delegate to the event handler
        self.event_handler.handle_event(event)

    @pyqtSlot(bool)
    def shutdownApplication(self, restart=False):
        """
        Handle application shutdown gracefully.
        
        Args:
            restart: Whether to restart after shutdown (currently unused)
        """
        logger.info(f"Shutdown requested from QML with restart={restart}")
        asyncio.create_task(self.lifecycle_manager.shutdown_process(self.mcp_client))
        return True

    @pyqtSlot()
    def reset_status(self):
        """Reset the status to idle."""
        if self.is_connected:
            self.status_manager.update_status(self.status_manager.STATUS_IDLE)
        else:
            self.status_manager.update_status(self.status_manager.STATUS_DISCONNECTED)

    @pyqtSlot()
    def getAvailableServers(self):
        """Get the list of available MCP servers."""
        servers = self.connection_manager.get_available_servers()
        self.availableServersChanged.emit(servers)
        return servers

    @pyqtSlot(str)
    def setServerPath(self, server_path):
        """Set the path to the MCP server script."""
        self.connection_manager.set_server_path(server_path)

    @pyqtSlot(result=str)
    def connectToServer(self):
        """Connect to the selected MCP server."""
        try:
            if not self.connection_manager.selected_server_path:
                raise ValueError("No server selected. Please choose a server before connecting.")

            # Extract server name for status messages
            server_name = (
                os.path.basename(self.connection_manager.selected_server_path)
                .replace("_server.py", "")
                .replace(".py", "")
            )

            if not os.path.exists(self.connection_manager.selected_server_path):
                raise FileNotFoundError(f"Server script not found: {self.connection_manager.selected_server_path}")

            # Update UI immediately to show connecting status
            self.status_manager.update_status(self.status_manager.STATUS_CONNECTING)

            # Create task to connect in the background
            asyncio.create_task(self.connection_manager.connect_to_selected_server(server_name))
            return ""  # Empty string indicates success (no error)

        except Exception as e:
            error_msg = self.error_handler.handle_error(
                e,
                "Server connection",
                user_friendly_msg=f"Failed to connect to server: {str(e)}",
            )
            return error_msg  # Return error message string

    @pyqtSlot(result=bool)
    def isConnected(self):
        """Check if the client is connected to a server."""
        return self.is_connected

    @pyqtSlot()
    def disconnectFromServer(self):
        """Disconnect from the MCP server."""
        logger.info("Disconnecting from server")
        asyncio.create_task(self.connection_manager.disconnect_from_server())

    @pyqtSlot(result=str)
    def getWifiIpAddress(self):
        """Get the WiFi IP address of the system."""
        return self.network_utils.get_wifi_ip_address()

    @pyqtSlot(result=str)
    def getWifiMacAddress(self):
        """Get the WiFi MAC address of the system."""
        try:
            # This is a new method we'll add to NetworkUtils
            return self.network_utils.get_wifi_mac_address()
        except Exception as e:
            logger.error(f"Error getting WiFi MAC address: {e}")
            return "Error getting MAC address"
            
    @pyqtSlot(result=str)
    def getWifiSignalStrength(self):
        """Get the WiFi signal strength."""
        try:
            # This is a new method we'll add to NetworkUtils
            return self.network_utils.get_wifi_signal_strength()
        except Exception as e:
            logger.error(f"Error getting WiFi signal strength: {e}")
            return "Error getting signal strength"
            
    @pyqtSlot(result="QVariant")
    def getNetworkDetails(self):
        """Get detailed information about the network."""
        try:
            # This is a new method we'll add to NetworkUtils
            return self.network_utils.get_network_details()
        except Exception as e:
            logger.error(f"Error getting network details: {e}")
            return {"error": "Failed to get network details"}

    @pyqtSlot()
    def restartApplication(self):
        """Restart the application without completely shutting down."""
        logger.info("Application restart requested")
        self.status_manager.update_status(self.status_manager.STATUS_RESTARTING)
        asyncio.create_task(self._do_restart())

    async def _do_restart(self):
        """Perform application restart by resetting state and reconnecting."""
        await self.lifecycle_manager.restart_application(
            type(self).is_connected,
            self.mcp_client,
            self.connection_manager.disconnect_from_server,
            self.connection_manager.connect_to_selected_server
        )
        
        # Emit bridge ready signal to refresh UI components
        logger.info("Emitting bridgeReady signal to reinitialize UI")
        self.bridgeReady.emit()

    def _on_connection_changed(self, value):
        """Handle connection state changes from the connection manager"""
        self.is_connected = value  # This will emit the signal
