import asyncio
import subprocess
import argparse
import nest_asyncio
from mcp.server import NotificationOptions, Server
from mcp.server.models import InitializationOptions
import mcp.types as types
import mcp.server.stdio

# Enable nested event loops (needed for some environments)
nest_asyncio.apply()

# Parse command line arguments
parser = argparse.ArgumentParser(description='Pamir Example : AirConditioning Control Server')
args = parser.parse_args()

# Initialize server
server = Server("AirConditioning Control")

@server.list_prompts()
async def list_prompts() -> list[types.Prompt]:
    return [types.Prompt(
                name="AirConditioning Control",
                description="A prompt for control airconditioning",
                arguments=[],
            )]

def control_air_conditioning_prompt() -> str:
    """Creates the speak to user prompt content."""
    return """
[START_OF_SAMPLE_CONVERSATION]
user: please help to turn on the air conditioning?
assistant: Sure, I can do it for you. <tool_call>
{"name": "turn_on", "arguments": {}}
</tool_call>

user: Please adjust the temperature of the air conditioner to 23 degrees Celsius. ?
assistant: Sure, I can do it for you<tool_call>
{"name": "adjust_temperature", "arguments": {"temperature": 23}}
</tool_call>
[END_OF_SAMPLE_CONVERSATION]
"""

def create_messages(prompt_name: str, arguments: dict[str, str] | None = None) -> list[types.PromptMessage]:
    """Create messages based on the prompt name and arguments."""
    return [types.PromptMessage(role="user", content=types.TextContent(
        type="text",
        text=control_air_conditioning_prompt()
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
                name="turn_on",
                description="turn on the air conditioning",
                inputSchema={}
            ),
            types.Tool(
                name="turn_off",
                description="turn off the air conditioning",
                inputSchema={}
            ),
            types.Tool(
                name="adjust_temperature",
                description="adjust the temperature of the air conditioner",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "temperature": {"type": "number", "description": "The target temperature in degrees Celsius to set the air conditioner to."}
                    },
                    "required": ["temperature"]}
            )
        ]

@server.call_tool()
async def handle_call_tool(
    name: str, 
    arguments: dict | None
) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
    """Handle tool execution requests."""
    if not arguments:
        arguments = {}
    
    if name == "turn_on":
        return [types.TextContent(
            type="text",
            text="Successfully turn on the air conditioning."
        )]

    elif name == "turn_off":
        return [types.TextContent(
            type="text",
            text="Successfully turn off the air conditioning."
        )]
    elif name == "adjust_temperature":
        target_temperature = arguments.get("temperature", 23)
        return [types.TextContent(
            type="text",
            text=f"Successfully adjusted the temperature of the air conditioner to {target_temperature} degrees Celsius. "
        )]
    else:
        raise ValueError(f"unknown tool: {name}")

async def run():
    """Run the MCP server."""
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="AirConditioning Control",
                server_version="0.1.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )

if __name__ == "__main__":
    asyncio.run(run())