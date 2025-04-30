import time
import asyncio
from typing import Optional, List, Dict, Any, AsyncGenerator, Callable, Union
import json
import logging

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
import sys
import os

# Change back to absolute imports
from distiller_cm5_python.client.mid_layer.llm_client import LLMClient
from distiller_cm5_python.client.mid_layer.processors import MessageProcessor, ToolProcessor, PromptProcessor
from distiller_cm5_python.utils.config import (STREAMING_ENABLED, LOGGING_LEVEL,
                          SERVER_URL, PROVIDER_TYPE, MODEL_NAME, TIMEOUT)
from contextlib import AsyncExitStack
# Remove colorama import
from distiller_cm5_python.utils.distiller_exception import UserVisibleError, LogOnlyError
import signal
import traceback
import concurrent.futures
import uuid
from distiller_cm5_python.client.ui.events.event_dispatcher import EventDispatcher
from distiller_cm5_python.client.ui.events.event_types import (
    EventType, StatusType, MessageSchema, 
    MessageEvent, ActionEvent, StatusEvent, ObservationEvent
)

# Get logger instance for this module
logger = logging.getLogger(__name__)


class MCPClient:
    def __init__(
            self,
            streaming: Optional[bool] = None,
            llm_server_url: Optional[str] = None,
            provider_type: Optional[str] = None,
            model: Optional[str] = None,
            api_key: Optional[str] = None,
            timeout: Optional[int] = None,
            dispatcher: Optional[EventDispatcher] = None
    ):
        self.session = None
        self.write = None
        self.stdio = None
        self.exit_stack = AsyncExitStack()
        # Use provided value or fallback to config default
        # The streaming flag here is primarily for informing the UI layer.
        # MCPClient internal logic will use non-streaming calls.
        self.streaming = streaming if streaming is not None else STREAMING_ENABLED
        _llm_server_url = llm_server_url or SERVER_URL
        _provider_type = provider_type or PROVIDER_TYPE
        _model = model or MODEL_NAME
        _api_key = api_key # Optional, can be None
        _timeout = timeout or TIMEOUT
        # TODO questionable if we need to keep both config system and init params system
        self.server_name = None
        self._is_connected = False  # Track connection status

        # Initialize available tools, resources, and prompts
        self.available_tools = []
        self.available_resources = [] # Store for potential future use/inspection
        self.available_prompts = [] # Store for potential future use/inspection

        # Initialize processors
        self.message_processor = MessageProcessor()
        self.prompt_processor = PromptProcessor()

        # Initialize the LLM provider with unified configuration
        # Pass the streaming flag to LLMClient as it might have internal uses
        logger.debug(
            f"Initializing LLMClient with server_url={_llm_server_url}, model={_model}, type={_provider_type}, stream={self.streaming}")
        self.llm_provider = LLMClient(
            server_url=_llm_server_url,
            model=_model,
            provider_type=_provider_type,
            api_key=_api_key,
            timeout=_timeout,
            streaming=self.streaming
        )

        # ToolProcessor initialized after session creation in connect_to_server
        self.tool_processor = None

        logger.debug("Client initialized with components")

        self.dispatcher = dispatcher

    async def connect_to_server(self, server_script_path: str) -> bool:
        """Connect to an MCP server"""

        if not server_script_path.endswith('.py'):
            raise UserVisibleError("Server script must be a .py file")

        # use current python interpreter by default
        server_params = StdioServerParameters(
            command=sys.executable,
            args=[server_script_path],
            env=None
        )

        try:
            logger.debug(f"Setting up stdio transport")

            start_time = time.time()
            stdio_transport = await self.exit_stack.enter_async_context(stdio_client(server_params))
            self.stdio, self.write = stdio_transport
            self.session = await self.exit_stack.enter_async_context(ClientSession(self.stdio, self.write))

            logger.debug(f"Session established, initializing")

            init_result = await self.session.initialize()
            self.server_name = init_result.serverInfo.name

            # If the server reports a generic "cli" name, try to get a better name from the script path
            if self.server_name == "cli":
                try:
                    # First attempt to extract SERVER_NAME from the script file
                    with open(server_script_path, 'r') as f:
                        for line in f:
                            line = line.strip()
                            if line.startswith('SERVER_NAME ='):
                                extracted_name = line.split('=', 1)[1].strip().strip('"\'')
                                if extracted_name:
                                    self.server_name = extracted_name
                                    logger.debug(f"Extracted server name from script: {self.server_name}")
                                    break
                    
                    # If we couldn't find SERVER_NAME, fall back to the script name
                    if self.server_name == "cli":
                        # Extract the name from the script path (e.g., wifi_server.py -> WiFi)
                        script_name = os.path.basename(server_script_path)
                        if script_name.endswith('_server.py'):
                            script_name = script_name[:-10]  # Remove "_server.py"
                        self.server_name = script_name.replace('_', ' ').title()
                        logger.debug(f"Using script name as server name: {self.server_name}")
                except Exception as name_error:
                    logger.warning(f"Failed to extract server name from script: {name_error}")
                    # Keep the original server name if extraction failed

            end_time = time.time()
            logger.debug(f"Server connection completed in {end_time - start_time:.2f}s")

            # Initialize tool processor after session is created
            self.tool_processor = ToolProcessor(self.session)

            logger.debug(f"Refreshing tool capabilities")

            await self.refresh_capabilities()

            # setup system prompt
            self.message_processor.set_system_message(self.prompt_processor.generate_system_prompt())

            # setup sample (few shot) prompts
            for prompt in self.available_prompts:
                for message in prompt["messages"]:
                    if message["role"] in ["user", "assistant"]:
                        self.message_processor.add_message(message["role"], message["content"])
                    else:
                        logger.warning(f"Few shot injection message role not supported: {message['role']}")

            # enable cache restore if provider is llama-cpp
            if self.llm_provider.provider_type == "llama-cpp":
                await self.llm_provider.restore_cache(self.message_processor.get_formatted_messages(), self.available_tools)

            # Set the connection status to True
            self._is_connected = True
            return True

        except Exception as e:
            logger.error(f"Failed to connect to server: {e}")
            return False

    async def refresh_capabilities(self):
        """Refresh the client's knowledge of server capabilities"""
        if not self.session:
            raise UserVisibleError("Not connected to Mcp Server, so can't refresh capabilities")

        # First refresh tools through the tool processor
        await self.tool_processor.refresh_capabilities()

        # Set available tools
        self.available_tools = self.tool_processor.format_tools()

        # Set available resources
        try:
            resources_response = await self.session.list_resources()
            self.available_resources = resources_response.resources
        except Exception as e:
            logger.warning(f"Failed to get resources: {e}")
            self.available_resources = []

        # Set available prompts
        try:
            self.available_prompts = await self.prompt_processor.format_prompts(self.session)

        except Exception as e:
            logger.warning(f"Failed to get prompts: {e}")
            self.available_prompts = []

    async def _execute_tool_calls(self, tool_calls: List[Dict[str, Any]]) -> None:
        """Helper method to execute tool calls and add results to history."""
        if not tool_calls:
            return

        logger.info(f"Found {len(tool_calls)} tool calls to execute")
        for i, tool_call in enumerate(tool_calls):
            logger.info(f"Executing tool call {i + 1}/{len(tool_calls)}")
            tool_result_content = "Error: Tool call execution failed."
            
            # Create action event for tool execution start
            tool_name = tool_call.get('function', {}).get('name', 'unknown') if 'function' in tool_call else tool_call.get('name', 'unknown')
            
            raw_tool_args = tool_call.get('function', {}).get('arguments', '{}') # Default to empty JSON string
            parsed_tool_args = {}
            try:
                # Only parse if raw_tool_args is a non-empty string
                if isinstance(raw_tool_args, str) and raw_tool_args.strip():
                    parsed_tool_args = json.loads(raw_tool_args)
                elif isinstance(raw_tool_args, dict):
                    parsed_tool_args = raw_tool_args # Already a dict, use as is
            except json.JSONDecodeError:
                logger.error(f"Failed to parse tool arguments: {raw_tool_args}", exc_info=True)
                # Keep parsed_tool_args as empty dict or handle error as needed

            action_event = ActionEvent(
                type=EventType.ACTION,
                content=f"Executing tool: {tool_name}",
                status=StatusType.IN_PROGRESS,
                tool_name=tool_name,
                tool_args=parsed_tool_args, # Use the parsed dictionary
                data={"tool_call": tool_call}
            )
            self.dispatcher.dispatch(action_event)
            
            try:
                if not isinstance(tool_call, dict) or 'function' not in tool_call:
                    error_msg = f"Invalid tool call format: {tool_call}"
                    logger.error(error_msg)
                    tool_result_content = error_msg
                    
                    # Dispatch error event
                    error_event = ActionEvent(
                        type=EventType.ERROR,
                        content=error_msg,
                        status=StatusType.FAILED,
                        tool_name=tool_name,
                        data={"tool_call": tool_call}
                    )
                    self.dispatcher.dispatch(error_event)
                else:
                    self.message_processor.add_tool_call(tool_call)
                    tool_result_content = await self.tool_processor.execute_tool_call_async(tool_call)
                    logger.info(f"Executed tool name: {tool_call.get('id', 'N/A')}")
                    logger.info(f"Executed tool result: {tool_result_content}")
                    
                    # Dispatch success event
                    result_event = ActionEvent(
                        type=EventType.ACTION,
                        content=f"Tool result: {tool_result_content}",
                        status=StatusType.SUCCESS,
                        tool_name=tool_name,
                        tool_args=parsed_tool_args, # Use the parsed dictionary here too
                        data={"tool_call": tool_call, "result": tool_result_content}
                    )
                    self.dispatcher.dispatch(result_event)

            except Exception as e:
                error_msg = f"Error executing tool call {tool_call.get('function',{}).get('name', 'N/A')}: {e}"
                logger.error(f"{error_msg}")
                tool_result_content = error_msg # Store error as result
                
                # Dispatch error event
                error_event = ActionEvent(
                    type=EventType.ERROR,
                    content=error_msg,
                    status=StatusType.FAILED,
                    tool_name=tool_name,
                    tool_args=parsed_tool_args, # Use the parsed dictionary here too
                    data={"tool_call": tool_call, "error": str(e)}
                )
                self.dispatcher.dispatch(error_event)
            finally:
                # Add the tool call result (or error) to the message history
                self.message_processor.add_tool_result(
                    tool_call, # Pass the original tool_call dict
                    tool_result_content
                )

    async def process_query(self, query: str) -> Dict[str, Any]:
        """Process a query through the LLM client.

        Args:
            query: The query to process.
        Returns:
            The processed response from the LLM client.
        """
        import time, uuid
        
        # Create standard message schema for thinking state
        thinking_msg = MessageEvent(
            type=EventType.INFO,
            content="Thinking...",
            status=StatusType.IN_PROGRESS,
            role="assistant",
            data=None
        )
        
        # Dispatch using new message schema
        self.dispatcher.dispatch(thinking_msg)

        # Record the user's message
        user_msg = self.message_processor.add_message("user", query)
        
        # Dispatch user message event 
        # self.dispatcher.dispatch(user_msg)

        messages = self.message_processor.get_formatted_messages()
        max_tool_iterations = 5
        current_iteration = 0

        try:
            while current_iteration < max_tool_iterations:
                current_iteration += 1
                use_stream = self.streaming

                try:
                    if use_stream:
                        # Stream and dispatch events via LLM client
                        response = await self.llm_provider.get_chat_completion_streaming_response(
                            messages=messages,
                            tools=self.available_tools,
                            dispatcher=self.dispatcher
                        )
                    else:
                        # Non-streaming
                        resp = await self.llm_provider.get_chat_completion_response(messages, self.available_tools)
                        content = resp.get("message", {}).get("content", "")
                        
                        # Create and dispatch message with new schema
                        msg_event = MessageEvent(
                            type=EventType.MESSAGE,
                            content=content,
                            status=StatusType.IN_PROGRESS,
                            role="assistant"
                        )
                        self.dispatcher.dispatch(msg_event)
                        response = resp
                except LogOnlyError as e:
                    # Create proper error message in case of streaming failure
                    error_event = MessageEvent(
                        type=EventType.ERROR,
                        content=f"Failed to get response: {str(e)}",
                        status=StatusType.FAILED,
                        role="assistant",
                        data={"error": str(e)}
                    )
                    self.dispatcher.dispatch(error_event)
                    
                    # Add error message to the conversation as assistant message
                    error_msg = "I encountered an error while processing your request. Please try again or check your connection."
                    self.message_processor.add_message("assistant", error_msg)
                    
                    # Create completion event to signal end of processing
                    complete_event = StatusEvent(
                        type=EventType.INFO,
                        content="",
                        status=StatusType.SUCCESS,
                        component="query"
                    )
                    self.dispatcher.dispatch(complete_event)
                    
                    # Re-raise the error to be caught by the higher-level handler
                    raise

                # Add message to processor
                self.message_processor.add_message("assistant", response.get("message", {}).get("content", ""))
                
                # Extract tool calls
                tool_calls = (response or {}).get("message", {}).get("tool_calls", [])
                if not tool_calls:
                    break

                # Create and dispatch info event for tool execution
                tool_info_event = StatusEvent(
                    type=EventType.INFO,
                    content=f"Executing tools iter {current_iteration}",
                    status=StatusType.IN_PROGRESS,
                    component="tools",
                    data={"count": len(tool_calls)}
                )
                self.dispatcher.dispatch(tool_info_event)

                # Execute tools
                await self._execute_tool_calls(tool_calls)

                # Create and dispatch completion event for tool execution
                tool_complete_event = StatusEvent( 
                    type=EventType.INFO,
                    content=f"Executed tools iter {current_iteration}",
                    status=StatusType.SUCCESS,
                    component="tools"
                )
                self.dispatcher.dispatch(tool_complete_event)

                # Prepare for potential next iteration
                messages = self.message_processor.get_formatted_messages()

            # Create and dispatch completion event
            complete_event = StatusEvent(
                type=EventType.INFO,
                content="",
                status=StatusType.SUCCESS,
                component="query"
            )
            self.dispatcher.dispatch(complete_event)

            logger.info("--- Query Processing Complete ---")
            
        except LogOnlyError as e:
            # This is already handled above and has proper UI messaging
            logger.error(f"Error during streaming: {e}")
            raise
        except Exception as e:
            # Handle unexpected errors by dispatching an error event
            error_event = MessageEvent(
                type=EventType.ERROR,
                content=f"Unexpected error: {str(e)}",
                status=StatusType.FAILED,
                role="assistant",
                data={"error": str(e)}
            )
            self.dispatcher.dispatch(error_event)
            
            # Also dispatch completion event to signal end of processing
            complete_event = StatusEvent(
                type=EventType.INFO,
                content="",
                status=StatusType.SUCCESS, 
                component="query"
            )
            self.dispatcher.dispatch(complete_event)
            
            # Log the error
            logger.error(f"Unexpected error in process_query: {e}", exc_info=True)
            raise

    async def cleanup(self):
        """Clean up resources used by the client."""
        logger.info("Starting MCP client cleanup")
        
        # Cancel all running tasks first
        self._cancel_all_running_tasks()
        
        # If we have a process, terminate it
        if hasattr(self, "_proc") and self._proc:
            try:
                logger.info("Terminating MCP server process")
                # Send SIGTERM to allow graceful shutdown
                if sys.platform == "win32":
                    # Windows doesn't have SIGTERM
                    self._proc.terminate()
                else:
                    os.kill(self._proc.pid, signal.SIGTERM)
                
                # Wait a bit for the process to exit
                try:
                    await asyncio.wait_for(self._proc.wait(), timeout=2.0)
                except asyncio.TimeoutError:
                    logger.warning("MCP server process didn't terminate, forcing kill")
                    if sys.platform == "win32":
                        self._proc.kill()
                    else:
                        os.kill(self._proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                # Process is already gone
                logger.info("MCP server process already terminated")
            except Exception as e:
                logger.error(f"Error terminating MCP server process: {e}", exc_info=True)
            finally:
                self._proc = None
        else:
            logger.debug("No server process to terminate")

        # Now safely close the exit stack
        if hasattr(self, "_exit_stack") and self._exit_stack:
            await self._safe_aclose_exit_stack()
            self._exit_stack = None
        
        logger.info("MCP client cleanup completed")

    def _cancel_all_running_tasks(self):
        """Cancel all running tasks safely."""
        logger.info("Cancelling all MCP client tasks")
        
        try:
            # Get all tasks in the current event loop
            for task in asyncio.all_tasks():
                # Skip the current task (cleanup)
                if task is asyncio.current_task():
                    continue
                
                # Only cancel tasks that belong to our client
                task_name = task.get_name()
                if "mcp_client" in task_name.lower():
                    logger.info(f"Cancelling task: {task_name}")
                    task.cancel()
                    
            logger.info("All MCP client tasks cancelled")
        except Exception as e:
            logger.error(f"Error cancelling tasks: {e}", exc_info=True)

    async def _safe_aclose_exit_stack(self):
        """Safely close the exit stack with error handling."""
        logger.info("Closing MCP client exit stack")
        
        if not self._exit_stack:
            return
            
        try:
            # Set a timeout for closing the exit stack
            with concurrent.futures.ThreadPoolExecutor() as executor:
                # Create a future that will close the exit stack
                future = executor.submit(lambda: asyncio.run_coroutine_threadsafe(
                    self._exit_stack.aclose(), asyncio.get_event_loop()))
                
                # Wait for the future to complete with a timeout
                try:
                    future.result(timeout=3.0)
                    logger.info("Exit stack closed successfully")
                except concurrent.futures.TimeoutError:
                    logger.warning("Timeout while closing exit stack")
                except Exception as e:
                    logger.error(f"Error closing exit stack: {e}", exc_info=True)
        except Exception as e:
            logger.error(f"Critical error during exit stack closure: {e}", exc_info=True)
            # Log the full traceback for debugging
            logger.error(traceback.format_exc())
