"""
Processing layer for MCP client.
This file combines message, tool and prompt processors into a single module.
"""

import time
import json
import logging
from mcp import ClientSession
from datetime import datetime
from typing import List, Dict, Any, Union, Optional, Coroutine

from distiller_cm5_python.utils.logger import logger
from distiller_cm5_python.utils.config import MAX_MESSAGES_LENGTH, DEFAULT_SYSTEM_PROMPT
from distiller_cm5_python.utils.distiller_exception import UserVisibleError, LogOnlyError
from distiller_cm5_python.client.ui.events.event_types import UIEvent


def timestamp_to_time(timestamp):
    dt_object = datetime.fromtimestamp(timestamp)
    formatted_time = dt_object.strftime('%Y-%m-%d %H:%M:%S')
    return formatted_time


class MessageProcessor:
    """Processor for managing conversation history and formatting messages for LLM providers."""
    
    def __init__(self):
        """Initialize the message processor"""
        super().__init__()  # No verbose parameter needed
        
        self.message_history = []
        self.session_start_time = timestamp_to_time(time.time()).replace(":","-")

        # Debug message traffic tracking - only active when logger is in debug mode
        self.is_debug_mode = logger.isEnabledFor(logging.DEBUG)
        self.debug_history_file = f"debug_message_traffic_{self.session_start_time}.json"
        
        # Initialize standardized message cache
        self.standardized_messages = []
        
        logger.debug(f"MessageProcessor.__init__: Initialized with {"DEBUG" if self.is_debug_mode else "INFO"} mode")

    def add_message(self, role: str, content: str, metadata: Dict[str, Any] = None, tool_calls: List[Dict[str, Any]] = None) -> None:
        """Add a message to the conversation history
        
        Args:
            role: The role of the message sender (user, assistant, system, tool)
            content: The content of the message
            metadata: Optional metadata for the message
        """

        # Control message length
        if len(self.message_history) >= MAX_MESSAGES_LENGTH:
            logger.warning(f"MessageProcessor.add_message: Message history is full. Removing oldest message.")
            # Traverse the list from the beginning, find the first message that is not of the 'system' role
            for i, msg in enumerate(self.message_history):
                if msg["role"] != "system":
                    # Delete the first non-system role message
                    del self.message_history[i]
                    break

        metadata = metadata or {}
        
        message = {
            "role": role,
            "content": content,
            "time": timestamp_to_time(time.time()),
            "metadata": metadata
        }
        if tool_calls:
            message["tool_calls"] = tool_calls

        # Add to normal message history
        self.message_history.append(message)
        
        # Create standardized message schema
        from distiller_cm5_python.client.ui.events.event_types import MessageSchema, EventType, StatusType, MessageEvent
        
        # Determine event type based on role
        event_type = EventType.MESSAGE
        if role == "system":
            event_type = EventType.INFO
        elif role == "tool":
            event_type = EventType.ACTION
            
        # Create a standardized message
        std_message = MessageEvent(
            type=event_type,
            content=content,
            status=StatusType.SUCCESS,
            role=role,
            data={
                "metadata": metadata,
                "tool_calls": tool_calls
            }
        )
        
        # Add to standardized messages
        self.standardized_messages.append(std_message)
        
        # If in debug mode, track detailed message traffic with message type
        if self.is_debug_mode:
            self._save_debug_traffic()

        logger.info(f"MessageProcessor.add_message: One {role} message added, now total {len(self.message_history)} messages")
        
        return std_message

    def set_system_message(self, content: str, metadata: Dict[str, Any] = None) -> None:
        """Set or replace the system message in the conversation history
        
        This method removes any existing system messages and adds a new one.
        
        Args:
            content: The content of the system message
            metadata: Optional metadata for the message
        """
        # Remove any existing system messages
        self.message_history = [msg for msg in self.message_history if msg["role"] != "system"]
        
        # Add the new system message
        metadata = metadata or {}
        if self.is_debug_mode:
            metadata["message_type"] = "system_message_set"
        
        self.add_message("system", content, metadata)
        
        logger.debug(f"MessageProcessor.set_system_message: System message set: {content[:50]}...")
    

    def add_tool_call(self, tool_call: Dict[str, Any]):
        """Add a tool call to the conversation history and return a UIEvent"""
        tool_name = tool_call.get("function", {}).get("name", "") if "function" in tool_call else tool_call.get("name", "")
        tool_args = tool_call.get("function", {}).get("arguments", {}) if "function" in tool_call else tool_call.get("arguments", {})
        tool_call_id = tool_call.get("id", tool_name)

        assistant_message = self.message_history[-1] # last message is assistant message

        if assistant_message.get("tool_calls", None) is None:
            assistant_message["tool_calls"] = []
        
        assistant_message["tool_calls"].append({
            "id": tool_call_id,
            "type": "function",
            "function": {
                "name": tool_name,
                "arguments": tool_args
            }
        })

        self.message_history[-1] = assistant_message

        # Create standardized message for tool call
        from distiller_cm5_python.client.ui.events.event_types import ActionEvent, EventType, StatusType
        
        std_message = ActionEvent(
            type=EventType.ACTION,
            content=f"Calling {tool_name}",
            status=StatusType.IN_PROGRESS,
            tool_name=tool_name,
            tool_args=tool_args,
            data={"tool_call": tool_call}
        )
        
        # Add to standardized messages
        self.standardized_messages.append(std_message)

        logger.info(f"Tool call added: {tool_name}")
        if self.is_debug_mode:
            self._save_debug_traffic()
            
        # Return UIEvent for backward compatibility
        from distiller_cm5_python.client.ui.events.event_types import UIEvent
        return UIEvent.tool_call(tool_call)

    def add_tool_result(self, tool_call: Dict[str, Any], result: str) -> None:
        """Add a tool result to the conversation history and return a UIEvent"""

        tool_name = tool_call.get("function", {}).get("name", "") if "function" in tool_call else tool_call.get("name", "")
        tool_args = tool_call.get("function", {}).get("arguments", {}) if "function" in tool_call else tool_call.get("arguments", {})
        tool_call_id = tool_call.get("id", tool_name)

        metadata = {
            "tool_name": tool_name,
            "tool_call_id": tool_call_id,
            "tool_args": tool_args,
            "is_tool_result": True,
            "message_type": "tool_result"
        }

        self.add_message("tool", result, metadata)

        # Create standardized message for tool result
        from distiller_cm5_python.client.ui.events.event_types import ActionEvent, EventType, StatusType
        
        std_message = ActionEvent(
            type=EventType.ACTION,
            content=f"Result for {tool_name}",
            status=StatusType.SUCCESS,
            tool_name=tool_name,
            tool_args=tool_args,
            data={"tool_call": tool_call, "result": result}
        )
        
        # Add to standardized messages
        self.standardized_messages.append(std_message)

        # If in debug mode, track detailed message traffic
        if self.is_debug_mode:
            self._save_debug_traffic()

        logger.debug(f"MessageProcessor.add_tool_result: {tool_name} and it's result({result}) are added into message history")
        
        # Return UIEvent for backward compatibility
        from distiller_cm5_python.client.ui.events.event_types import UIEvent
        return UIEvent.tool_result(tool_call, result)


    def get_formatted_messages(self) -> List[Dict[str, Union[str, List[Dict[str, Any]]]]]:
        """Get the message history formatted for LLM API
        
        Returns:
            List of formatted messages
        """

        formatted_messages = []
        
        for message in self.message_history:
            role = message["role"]
            content = message["content"]
            tool_calls = message.get("tool_calls", [])
            metadata = message.get("metadata", {})
            
            # Handle tool results with special formatting
            if role == "tool" and metadata.get("is_tool_result", False):
                tool_name = metadata.get("tool_name", "unknown_tool")
                tool_call_id = metadata.get("tool_call_id", tool_name)
                formatted_messages.append({
                    "role": "tool",
                    "type": "function_call_output",
                    "tool_call_id": tool_call_id,
                    "content": content
                })
                
            elif role in ["user", "system"] or (role == "assistant" and len(tool_calls) == 0):
                formatted_messages.append({
                    "role": role,
                    "content": content
                    })
            elif role == "assistant":
                # Standard message formatting
                formatted_messages.append({
                    "role": role,
                    "content": content,
                    "tool_calls": tool_calls
                })

        logger.debug(f"MessageProcessor.get_formatted_messages: {len(formatted_messages)} messages returned")
        return formatted_messages

    def _save_debug_traffic(self) -> None:
        """Save the debug message traffic to a JSON file"""
        if not self.is_debug_mode:
            return
            
        try:
            with open(self.debug_history_file, "w", encoding="utf-8") as f:
                json.dump({
                    "session_start": self.session_start_time,
                    "debug_traffic": self.get_formatted_messages()
                }, f, indent=2)
                
            logger.debug(f"MessageProcessor._save_debug_traffic: Debug traffic saved to {self.debug_history_file}")
        except Exception as e:
            logger.error(f"MessageProcessor._save_debug_traffic: Failed to save debug traffic: {e}")
    
    def process(self, messages: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Process messages and return formatted messages for LLM API
        Args:
            messages: A list of messages to process
        Returns:
            Formatted messages for LLM API
        """
        for message in messages:
            role = message.get("role", "user")
            content = message.get("content", "")
            metadata = message.get("metadata", {})
            self.add_message(role, content, metadata)

        return self.get_formatted_messages()


class ToolProcessor:
    """Manages tool execution and formatting for LLM providers"""
    
    def __init__(self, session: Optional[ClientSession] = None):
        """Initialize the tool processor
        
        Args:
            session: MCP client session
        """
        self.session = session
        self.tools = []
        
        logger.debug(f"ToolProcessor.__init__: Initialized with session: {session is not None}")

    async def refresh_capabilities(self) -> None:
        """Refresh available tools from the MCP server"""
        if not self.session:
            logger.error("ToolProcessor.refresh_capabilities: No session available")
            raise UserVisibleError("No connected Mcp server session available, please check Mcp server connection")

        logger.debug(f"ToolProcessor.refresh_capabilities: Refreshing tools")
            
        # Get available tools
        try:
            tools_response = await self.session.list_tools()
            self.tools = tools_response.tools

            logger.debug(f"ToolProcessor.refresh_capabilities: Got {len(self.tools)} tools")
            for tool in self.tools:
                logger.debug(f"ToolProcessor.refresh_capabilities: Tool: {tool.name}")
        
        except Exception as e:
            logger.error(f"ToolProcessor.refresh_capabilities: Failed to refresh tools: {e}")
            self.tools = []

    def format_tools(self) -> List[Dict[str, Any]]:
        """Format all available tools from server into the shape expected by LLM models"""
        if not self.session or not hasattr(self, 'tools') or not self.tools:
            return []

        formatted_tools = []
        
        # Create standard tool info events for UI
        from distiller_cm5_python.client.ui.events.event_types import FunctionEvent, EventType, StatusType
        
        function_events = []
        
        for tool in self.tools:
            # Check if tool is a dictionary or an object with attributes
            if isinstance(tool, dict):
                name = tool.get("name", "")
                description = tool.get("description", "")
                parameters = tool.get("inputSchema", {})
            else:
                # Assume it's an object with attributes
                name = getattr(tool, "name", "")
                description = getattr(tool, "description", "")
                parameters = getattr(tool, "inputSchema", {})

            formatted_tool = {
                "type": "function",
                "function": {
                    "name": name,
                    "description": description,
                    "parameters": parameters
                }
            }
            formatted_tools.append(formatted_tool)
            
            # Create a FunctionEvent for each tool
            function_event = FunctionEvent(
                type=EventType.FUNCTION,
                content=f"Function: {name}",
                status=StatusType.SUCCESS,
                name=name,
                description=description,
                parameters=parameters 
            )
            function_events.append(function_event)

        # Store the function events for later use
        self.function_events = function_events
        
        logger.debug(f"ToolProcessor.format_tools: Return {len(formatted_tools)} formatted tools")
        return formatted_tools

    async def execute_tool_call_async(self, tool_call: Dict[str, Any]) -> str:
        """Execute the tool call asynchronously

        Args:
            tool_call: The tool call to execute

        Returns:
            The result of the tool execution
        """
        if not self.session:
            raise LogOnlyError("ToolProcessor.execute_tool_call_async: No MCP session available")

        tool_name = tool_call.get("function", {}).get("name", "")
        args = tool_call.get("function", {}).get("arguments", {})
        
        # Extract arguments; could be string (JSON) or dict
        if isinstance(args, str):
            try:
                # Try to parse as JSON if it's a string
                import json
                args = json.loads(args.strip())
            except:
                # If fails, use as is - will likely cause issues, 
                # but better than failing entirely
                pass
        
        logger.debug(f"ToolProcessor.execute_tool_call_async: Executing {tool_name} with args: {args}")
        
        try:
            # Call the tool via the MCP session
            result = await self.session.call_tool(tool_name, args) if args else await self.session.call_tool(tool_name, None)

            # Check if any SSH info is contained in the tool result
            ssh_info = self._extract_ssh_info(result, tool_name, args)
            if ssh_info:
                # Dispatch the SSH info event
                from distiller_cm5_python.client.ui.events.event_types import SSHInfoEvent, EventType, StatusType
                from distiller_cm5_python.client.ui.events.event_dispatcher import EventDispatcher
                
                ssh_event = SSHInfoEvent(
                    type=EventType.SSH_INFO,
                    content=f"SSH: {ssh_info['username']}@{ssh_info['ip_address']}:{ssh_info['port']}",
                    status=StatusType.SUCCESS,
                    ip_address=ssh_info['ip_address'],
                    username=ssh_info['username'],
                    port=ssh_info['port']
                )
                
                # We need to access the event dispatcher to dispatch this event
                # This relies on the MCPClient instance having a dispatcher attribute
                try:
                    # Find a way to access the event dispatcher
                    # This is a bit of a hack, but it allows for SSH info to be displayed
                    # Alternative would be to return special format and have MCPClient handle
                    from distiller_cm5_python.client.ui import App
                    if hasattr(App, "current_dispatcher"):
                        App.current_dispatcher.dispatch(ssh_event)
                except Exception as e:
                    logger.warning(f"Could not dispatch SSH info event: {e}")
            
            # Format the result for display
            formatted_result = self._format_tool_result(result)
            return formatted_result
        
        except Exception as e:
            error_msg = f"Error executing tool {tool_name}: {e}"
            logger.error(error_msg)
            return error_msg

    def _extract_ssh_info(self, result, tool_name: str, args: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Extract SSH connection information from a tool result if present.
        
        Args:
            result: The raw result from the tool call
            tool_name: The name of the tool that was called
            args: The arguments that were passed to the tool
            
        Returns:
            Dictionary with SSH info (username, ip_address, port) or None if not found
        """
        # Check if tool name is related to SSH
        ssh_related_tools = ["show_ssh_instructions", "ssh_info", "get_ssh_info", "get_connection_info"]
        
        if tool_name in ssh_related_tools:
            # For explicit SSH info tools
            try:
                # Extract from result content if it's a structured message
                if isinstance(result, list):
                    for item in result:
                        content = item.get("content", "")
                        # Look for IP address patterns in content
                        import re
                        ip_match = re.search(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', content)
                        if ip_match:
                            ip_address = ip_match.group(1)
                            # Try to find username and port
                            username = args.get("username", "user")
                            port = args.get("port", 22)
                            
                            return {
                                "ip_address": ip_address,
                                "username": username,
                                "port": port
                            }
            
                # If we have direct ip_address in args
                if "ip_address" in args:
                    return {
                        "ip_address": args["ip_address"],
                        "username": args.get("username", "user"),
                        "port": args.get("port", 22)
                    }
            except Exception as e:
                logger.warning(f"Error extracting SSH info: {e}")
        
        return None

    def _format_tool_result(self, result) -> str:
        """Format a tool result into a string representation.
        
        Args:
            result: The result object returned from the MCP server
            
        Returns:
            A string representation of the result
        """
        # Handle different result types
        if isinstance(result, list):
            # Handle list of content (common MCP server response format)
            result_text = []
            for item in result:
                if isinstance(item, dict):
                    # Handle content object
                    content_type = item.get("type", "unknown")
                    
                    if content_type == "text":
                        # Extract text content
                        text = item.get("text", "")
                        result_text.append(text)
                    elif "content" in item:
                        # Extract generic content
                        result_text.append(str(item["content"]))
                    else:
                        # Just extract whole item as string
                        result_text.append(str(item))
                else:
                    # Just add as string
                    result_text.append(str(item))
            
            # Join text items with newlines
            return "\n".join(result_text)
        elif isinstance(result, dict):
            # Try to extract content from dict
            if "text" in result:
                return result["text"]
            elif "content" in result:
                return str(result["content"])
            else:
                # Format as JSON
                import json
                try:
                    return json.dumps(result, indent=2)
                except:
                    return str(result)
        else:
            # Return as string
            return str(result)


class PromptProcessor:
    """Processor for generating system prompts with optional tool information."""
    
    def __init__(self):
        """Initialize the prompt processor"""

        # Default user system prompt
        self.default_user_prompt = (
            DEFAULT_SYSTEM_PROMPT
        )
        
        logger.debug(f"PromptProcessor.__init__: Initialized with default system prompt, {self.default_user_prompt}")

    async def format_prompts(self, session):
        """Format the prompts for the MCP server"""
        prompts = []
        available_prompts = await session.list_prompts()
        logger.debug(f"PromptProcessor.format_prompts: Available prompts: {available_prompts}")
        for prompt in available_prompts.prompts:
            prompt_result = await session.get_prompt(prompt.name, prompt.arguments if prompt.arguments else {})
            formatted_prompt = {
                "name": prompt.name,
                "description": prompt_result.description,
                "messages": [{
                    "role": msg.role,
                    "content": msg.content.text
                } for msg in prompt_result.messages]
            }
            prompts.append(formatted_prompt)
        return prompts

    def generate_system_prompt(self, additional_prompt: Optional[str] = None) -> str:
        """Generate a complete system prompt
        
        Args:
            additional_prompt: Optional custom user prompt to add to the default system prompt
            
        Returns:
            A formatted system prompt
        """
        prompt = self.default_user_prompt
        if additional_prompt: prompt += "\n\n" + additional_prompt
        
        logger.info(f"PromptProcessor.generate_system_prompt: Generated system prompt with {len(prompt)} characters")
        logger.debug(f"PromptProcessor.generate_system_prompt: Generated system prompt: {prompt}")
        return prompt


# Export the classes for easy importing
__all__ = ['MessageProcessor', 'ToolProcessor', 'PromptProcessor'] 