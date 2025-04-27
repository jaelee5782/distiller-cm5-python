"""
Configuration manager component for the MCPClientBridge.
Handles getting, setting, and applying configuration changes.
"""

from typing import Any, Dict, Optional
import logging
import asyncio

from distiller_cm5_python.utils.config import config, DEFAULT_CONFIG_PATH
from distiller_cm5_python.client.ui.bridge.StatusManager import StatusManager
from distiller_cm5_python.client.ui.bridge.ConversationManager import ConversationManager
from distiller_cm5_python.client.mid_layer.mcp_client import MCPClient

logger = logging.getLogger(__name__)

class ConfigManager:
    """
    Manages configuration operations for the bridge.
    Handles getting, setting, and applying configuration changes.
    """

    def __init__(
        self, 
        status_manager: StatusManager, 
        conversation_manager: ConversationManager,
        config_path: str = DEFAULT_CONFIG_PATH
    ):
        """
        Initialize the configuration manager.
        
        Args:
            status_manager: The status manager to update based on configuration changes
            conversation_manager: The conversation manager to add messages about config changes
            config_path: The path to the configuration file
        """
        self.status_manager = status_manager
        self.conversation_manager = conversation_manager
        self.config_path = config_path
        
        # Configuration cache
        self._config_cache: Dict[str, str] = {}
        self._config_dirty = False
        
        # Track current log level
        self._current_log_level = config.get("logging", "level", default="DEBUG").upper()
    
    def get_config_value(self, section: str, key: str) -> str:
        """
        Get a configuration value, always returning a string.
        
        Args:
            section: The configuration section
            key: The key within the section
            
        Returns:
            The string representation of the configuration value
        """
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

    def set_config_value(self, section: str, key: str, value: Any) -> None:
        """
        Set a configuration value and update the cache.
        
        Args:
            section: The configuration section
            key: The key within the section
            value: The value to set
        """
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
            active_provider_name = self.get_config_value("active_llm_provider", "")
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

    async def apply_config(
        self, 
        mcp_client: Optional[MCPClient], 
        error_handler: callable,
        connect_to_server: callable
    ) -> None:
        """
        Apply configuration changes by restarting the client.
        
        Args:
            mcp_client: The MCP client instance to reconfigure
            error_handler: Function to handle errors
            connect_to_server: Function to reconnect to a server
        """
        try:
            self.status_manager.update_status(StatusManager.STATUS_INITIALIZING)
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Applying configuration changes...",
            })

            # Store the current conversation
            current_conversation = self.conversation_manager.get_messages_copy()

            # Save config if needed
            await self._save_config_if_needed(error_handler)

            # Clean up existing client
            mcp_client_reference, selected_server_path = await self._cleanup_mcp_client(
                mcp_client, error_handler
            )

            # Reload the configuration
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Reloading configuration...",
            })

            # Clear cache and reload config
            await self._reload_config(error_handler)

            # Update global variables
            await self._update_global_variables(error_handler)

            # Create new client with updated config
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Creating new client with updated configuration...",
            })

            # Reconnect if previously connected
            if selected_server_path:
                await connect_to_server(selected_server_path)

            self.status_manager.update_status(StatusManager.STATUS_CONFIG_APPLIED)
            
            # Restore conversation
            self.conversation_manager.set_messages(current_conversation)
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Configuration applied successfully.",
            })

        except Exception as e:
            error_handler(
                e,
                "Configuration apply",
                user_friendly_msg=f"Failed to apply configuration changes: {str(e)}",
            )

    async def _save_config_if_needed(self, error_handler: callable) -> None:
        """
        Save the configuration to file if it's been modified.
        
        Args:
            error_handler: Function to handle errors
        """
        if self._config_dirty:
            try:
                config.save_to_file(self.config_path)
                self._config_dirty = False
                logger.info("Configuration saved successfully before apply")
            except Exception as save_error:
                error_handler(
                    save_error,
                    "Config save",
                    user_friendly_msg=f"Warning: Could not save pending changes: {str(save_error)}",
                )

    async def _cleanup_mcp_client(
        self, 
        mcp_client: Optional[MCPClient],
        error_handler: callable
    ) -> tuple:
        """
        Clean up the existing MCP client.
        
        Args:
            mcp_client: The MCP client to clean up
            error_handler: Function to handle errors
            
        Returns:
            Tuple of (None, selected_server_path)
        """
        selected_server_path = None
        
        if mcp_client:
            self.conversation_manager.add_message({
                "timestamp": self.conversation_manager.get_timestamp(),
                "content": "Disconnecting from server...",
            })

            # Store server path for reconnection
            if hasattr(mcp_client, 'server_script_path'):
                selected_server_path = getattr(mcp_client, 'server_script_path', None)

            try:
                cleanup_task = asyncio.create_task(mcp_client.cleanup())
                await asyncio.wait_for(cleanup_task, timeout=5.0)
            except asyncio.TimeoutError:
                logger.warning("Cleanup timeout during configuration apply, forcing disconnect")
                self.conversation_manager.add_message({
                    "timestamp": self.conversation_manager.get_timestamp(),
                    "content": "Cleanup is taking longer than expected, forcing disconnect...",
                })
            except Exception as cleanup_error:
                error_handler(
                    cleanup_error,
                    "Client cleanup",
                    user_friendly_msg="Warning: Client resources may not be properly released.",
                )

        return None, selected_server_path

    async def _reload_config(self, error_handler: callable) -> None:
        """
        Reload the configuration from file.
        
        Args:
            error_handler: Function to handle errors
        """
        try:
            # Clear cache and reload config
            self._config_cache = {}
            config.reload()
            logger.info("Configuration cache cleared and config reloaded")
        except Exception as config_error:
            raise ValueError(
                f"Failed to reload configuration: {str(config_error)}. Check your config file for syntax errors."
            )

    async def _update_global_variables(self, error_handler: callable) -> None:
        """
        Update global variables from the configuration.
        
        Args:
            error_handler: Function to handle errors
        """
        try:
            # Get the active provider configuration
            active_provider_name = config.get("active_llm_provider")
            if not active_provider_name:
                raise ValueError("No active LLM provider specified in configuration.")

            active_provider_config = config.get("llm_providers", active_provider_name)
            if not active_provider_config:
                raise ValueError(f"Configuration for provider '{active_provider_name}' not found.")

            # Update global variables from the active provider
            from distiller_cm5_python.utils.config import (
                SERVER_URL, MODEL_NAME, PROVIDER_TYPE, API_KEY, TIMEOUT, STREAMING_ENABLED
            )
            
            # These are updated via the module-level variables
            # The actual globals will be reimported when needed
            
        except ValueError as config_value_error:
            raise ValueError(f"Configuration error: {str(config_value_error)}")
        except Exception as config_extract_error:
            raise ValueError(f"Error extracting configuration values: {str(config_extract_error)}")

    def save_config_to_file(self, error_handler: callable) -> None:
        """
        Save the current configuration to file.
        
        Args:
            error_handler: Function to handle errors
        """
        if not self._config_dirty:
            logger.debug("Configuration not dirty, skipping save")
            return

        logger.info(f"Saving configuration to {self.config_path}")
        try:
            config.save_to_file(self.config_path)
            self._config_dirty = False
            logger.info(f"Configuration saved successfully to {self.config_path}")
        except Exception as e:
            error_handler(
                e,
                "Config save",
                user_friendly_msg=f"Failed to save configuration: {str(e)}",
            ) 
