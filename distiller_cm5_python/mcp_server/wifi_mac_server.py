import asyncio
import subprocess
import sys
import platform
import argparse
import logging
import sys
from typing import Any
import nest_asyncio
from distiller_cm5_python.utils.logger import setup_logging
from mcp.server import NotificationOptions, Server
from mcp.server.models import InitializationOptions
import mcp.types as types
import mcp.server.stdio

# --- Setup Logging ---
setup_logging(log_level=logging.DEBUG, stream=sys.stderr)
# Get logger for this module after setup
logger = logging.getLogger(__name__)
# --- Logging is now configured ---

# Enable nested event loops (needed for some environments)
nest_asyncio.apply()

# Parse command line arguments
parser = argparse.ArgumentParser(description='Pamir Example : WiFi Management MCP Server')
args = parser.parse_args()

# Initialize server
server = Server("cli")

@server.list_prompts()
async def list_prompts() -> list[types.Prompt]:
    return  [types.Prompt(
                name="wifi_assistant",
                description="A prompt for WiFi management assistant with sample conversations",
                arguments=[],
            )]

def create_wifi_assistant_prompt() -> str:
    """Creates the WiFi assistant prompt content."""
    return """
Please help onboarding the user to the device. your goal is to help the user connect to the device via wifi and then ssh into it.
Below is an example conversation flow:

<START_OF_SAMPLE_CONVERSATION>
user: Hi, I'm not sure what Wi-Fi networks are available. Can you help?  
assistant: Sure! Let me check the available networks for you.  
<tool_call>
{"name": "get_wifi_networks", "arguments": {}}
</tool_call>

user: How do I SSH into you?  
assistant: You may not be on the same network as me. Let's check your Wi-Fi status first.  
<tool_call>
{"name": "get_wifi_status", "arguments": {}}
</tool_call>
assistant: under the same network you can ssh via the ip address <ip_address> 

user: how exactly do I do that?
assistant: <tool_call>
{"name": "show_ssh_instructions", "arguments": {"ip_address": "<ip_address>"}}
</tool_call>
<END_OF_SAMPLE_CONVERSATION>
"""

def create_messages(prompt_name: str, arguments: dict[str, str] | None = None) -> list[types.PromptMessage]:
    """Create messages based on the prompt name and arguments."""

    return [types.PromptMessage(role="user", content=types.TextContent(
        type="text",
        text=create_wifi_assistant_prompt()
    ))]

@server.get_prompt()
async def get_prompt(
    name: str, arguments: dict[str, str] | None = None
) -> types.GetPromptResult:
    """Generic prompt handler that uses create_messages to generate the prompt."""

    return types.GetPromptResult(
        messages=create_messages(name, arguments),
        description=None
    )

@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    """List available WiFi management tools."""
    
    return [
            types.Tool(
                name="get_wifi_networks",
                description="Get the available WiFi networks",
                inputSchema={}
            ),
            types.Tool(
                name="get_wifi_status",
                description="Get the status of the WiFi connection",
                inputSchema={}
            ),
            types.Tool(
                name="connect_to_wifi",
                description="Connect to a WiFi network",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "ssid": {"type": "string", "description": "The name of the WiFi network"},
                        "password": {"type": "string", "description": "The password for the WiFi network"}
                    },
                    "required": ["ssid", "password"]
                }
            ),
            types.Tool(
                name="show_ssh_instructions",
                description="Show the instructions for SSHing into the device",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "ip_address": {"type": "string", "description": "The IP address of the device"}
                    },
                    "required": ["ip_address"]
                }
            )
        ]

@server.call_tool()
async def handle_call_tool(
    name: str, 
    arguments: dict | None
) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
    """Handle tool execution requests."""
    # Log tool call entry - Log argument keys only for sensitivity
    arg_keys = list(arguments.keys()) if arguments else []
    logger.info(f"Handling tool call: '{name}' with argument keys: {arg_keys}")

    if not arguments:
        arguments = {}

    
    if name == "get_wifi_networks":
        command ="""system_profiler SPAirPortDataType | awk '
     /Local Wi-Fi Networks:/ { flag=1; next }
     /^[[:space:]]*$/ { flag=0 }
     flag && /^[[:space:]]+[^[:space:]]/ {
         sub(/^[[:space:]]+/, "", $0)
         gsub(":", "", $0)
         if ($0 ~ /^Channel/ ||
             $0 ~ /^Current/ ||
             $0 ~ /^MAC Address/ ||
             $0 ~ /^Network Type/ ||
             $0 ~ /^PHY Mode/ ||
             $0 ~ /^Security/ ||
             $0 ~ /^Signal \/ Noise/ ||
             $0 ~ /^Supported Channels/ ||
             $0 ~ /^awdl0/) next
         print $0
    }' | sort | uniq"""
        
        logger.debug(f"Running command for get_wifi_networks: {command[:100]}...") # Log truncated command
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        
        if result.returncode != 0:
            logger.error(f"Command failed for get_wifi_networks. Return code: {result.returncode}, Stderr: {result.stderr}")
            return [types.TextContent(
                type="text",
                text=f"Error getting WiFi networks: {result.stderr}" # Return only stderr
            )]
        else:
            logger.info("Successfully retrieved WiFi networks.")
            logger.debug(f"get_wifi_networks stdout: {result.stdout[:200]}...") # Log truncated output
            return [types.TextContent(
                type="text",
                text=f"Available WiFi networks are: {result.stdout}"
            )]
    
    elif name == "get_wifi_status":
        command_list = ["ipconfig", "getsummary", "en0"]
        logger.debug(f"Running command for get_wifi_status: {' '.join(command_list)}")
        result = subprocess.run(command_list, capture_output=True, text=True)
        
        if result.returncode != 0:
             logger.error(f"Command failed for get_wifi_status. Return code: {result.returncode}, Stderr: {result.stderr}")
             return [types.TextContent(
                type="text",
                text="Failed to get wifi status" # Simple error message
             )]
        else:
            # Process the output to get wifi status info
            status_lines = []
            for line in result.stdout.splitlines():                
                if any(key in line for key in ["InterfaceType", "LinkStatusActive", "NetworkID", "SSID", "Security"]):
                    status_lines.append(line.strip())
            status_output = chr(10).join(status_lines)
            logger.info("Successfully retrieved WiFi status.")
            logger.debug(f"get_wifi_status relevant output: {status_output}")
            return [types.TextContent(
                type="text",
                text=f"Wifi status is: {status_output}"
            )]
       
    
    elif name == "connect_to_wifi":
        ssid = arguments.get("ssid", "")
        password = arguments.get("password", "")
        
        if not ssid or not password:
             logger.warning("connect_to_wifi called with missing ssid or password.")
             return [types.TextContent(type="text", text="Error: SSID and password are required.")]
             
        try:
            # Turn on WiFi first
            power_command = ["networksetup", "-setairportpower", "en0", "on"]
            logger.debug(f"Running command to enable WiFi: {' '.join(power_command)}")
            power_result = subprocess.run(
                power_command,
                capture_output=True,
                text=True,
                shell=False,
                check=False # Don't raise exception on non-zero exit
            )
            if power_result.returncode != 0:
                logger.error(f"Failed to enable WiFi. Return code: {power_result.returncode}, Stderr: {power_result.stderr}")
                return [types.TextContent(
                    type="text",
                    text=f"Failed to enable WiFi: {power_result.stderr}"
                )]
            logger.info("WiFi power enabled successfully.")

            # Ensure password is a string
            password_str = str(password)
            
            # Connect to network
            connect_command = ["networksetup", "-setairportnetwork", "en0", str(ssid), password_str]
            # Mask password in log
            masked_command_str = f"networksetup -setairportnetwork en0 '{ssid}' ****"
            logger.debug(f"Running command to connect to WiFi: {masked_command_str}")
            
            connect_result = subprocess.run(
                connect_command,
                capture_output=True,
                text=True,
                shell=False,
                check=False # Don't raise exception on non-zero exit
            )
            
            if connect_result.returncode == 0:
                logger.info(f"Successfully initiated connection to WiFi network '{ssid}'.")
                # Note: Success here might just mean the command ran; actual connection might take time.
                return [types.TextContent(
                    type="text",
                    text=f"Successfully attempted to connect to the wifi network '{ssid}'"
                )]
            else:
                # Check for specific known error messages if needed
                error_message = connect_result.stderr.strip()
                logger.error(f"Failed to connect to WiFi network '{ssid}'. Return code: {connect_result.returncode}, Stderr: {error_message}")
                # Provide a cleaner error message if possible
                if "password" in error_message.lower():
                    user_error = "Failed to connect: Incorrect password?"
                elif "not find network" in error_message.lower():
                    user_error = f"Failed to connect: Network '{ssid}' not found?"
                else:
                    user_error = f"Failed to connect to the wifi network: {error_message}"
                
                return [types.TextContent(
                    type="text",
                    text=user_error
                )]
                
        except Exception as e:
            logger.error(f"Unexpected error connecting to WiFi '{ssid}': {e}", exc_info=True)
            return [types.TextContent(
                type="text",
                text=f"Error connecting to WiFi: {str(e)}"
            )]
    
    elif name == "show_ssh_instructions":
        ip_address = arguments.get("ip_address", "")
        logger.info(f"Returning SSH instructions for IP: {ip_address}")
        return [types.TextContent(
            type="text",
            text=f"""Open a terminal under the same network, use the following command: ssh distiller@{ip_address} , the password is just 'one', You can use Cursor to connect via SSH function as well"""
        )]
    else:
        logger.error(f"Received call for unknown tool: '{name}'")
        raise ValueError(f"unknown tool: {name}")

async def run():
    """Run the MCP server."""
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="cli",
                server_version="0.1.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )

if __name__ == "__main__":
    asyncio.run(run())