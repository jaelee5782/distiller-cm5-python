import asyncio
import sys
import argparse
import logging
from typing import Any, Dict, List, Optional
import nest_asyncio

# MCP imports
from mcp.server import NotificationOptions, Server
from mcp.server.models import InitializationOptions
import mcp.types as types
import mcp.server.stdio

# --- Setup Logging ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],
)
logger = logging.getLogger(__name__)

# Enable nested event loops (needed for some environments)
nest_asyncio.apply()

# Parse command line arguments
parser = argparse.ArgumentParser(description="Simple Voice Conversation MCP Server")
parser.add_argument("--debug", action="store_true", help="Enable debug logging")
args = parser.parse_args()

if args.debug:
    logging.getLogger().setLevel(logging.DEBUG)

# Initialize server
server = Server("conversation")


@server.list_prompts()
async def list_prompts() -> list[types.Prompt]:
    """List available prompts for the conversation server."""
    return [
        types.Prompt(
            name="general_conversation",
            description="General conversation prompt for voice interactions",
            arguments=[],
        ),
        types.Prompt(
            name="help_prompt",
            description="Help documentation for using this conversation server",
            arguments=[],
        ),
    ]


def create_general_conversation_prompt() -> str:
    """Create the prompt for general conversation."""
    return """
You are a helpful voice assistant. Respond to user queries directly and concisely.
Keep your responses conversational but efficient, as they will be spoken aloud.

Here are some helpful guidelines:
1. Be concise - voice responses should be brief
2. Format information clearly for spoken delivery
3. Offer to summarize long explanations
4. When giving instructions, break them into clear steps
5. Use markdown for formatting when helpful

<example conversation>
user: What's the weather today?
assistant: I don't have access to real-time weather data. To check today's weather, you can use a weather app, visit a weather website, or ask another assistant with internet access.

user: Tell me about quantum computing
assistant: Quantum computing uses quantum mechanics to perform calculations differently than classical computers. 

Instead of regular bits (0 or 1), quantum computers use quantum bits or "qubits" that can exist in multiple states simultaneously. This potentially allows quantum computers to solve certain problems much faster than traditional computers.

Current quantum computers are still experimental and limited, but they show promise for fields like cryptography, material science, and complex system modeling.
</example conversation>
"""


def create_help_prompt() -> str:
    """Create the help documentation prompt."""
    return """
You are a helpful voice assistant providing information about the capabilities of this system.

This is a simple general conversation MCP server that handles basic voice interactions.
The server does not have specialized tools for tasks like searching the web, accessing files,
or controlling smart home devices.

Please explain the following to the user in a helpful way:
1. This is a basic voice assistant for general conversation
2. The system does not have internet access or specialized tools
3. The assistant can engage in text-based conversation and provide general knowledge
4. For more advanced features, specialized MCP servers would need to be implemented

<example conversation>
user: What can you do?
assistant: I'm a basic voice assistant designed for general conversation. I can chat with you and answer questions based on my training knowledge.

I don't have access to the internet, your files, or specialized tools. I can't perform web searches, control smart home devices, or access real-time information like weather or news.

I'm happy to discuss a wide range of topics, provide explanations, or just have a friendly conversation.

user: How do I add more capabilities?
assistant: To add more capabilities to this system, you would need to implement specialized MCP (Multi-modal Conversation Protocol) servers that provide specific tools.

For example:
- A web search server could provide internet access
- A file management server could handle document operations
- A smart home server could control compatible devices

These specialized servers would need to be developed and integrated with the main system. Each would expose specific tools that I could then use to perform those tasks when requested.
</example conversation>
"""


def create_messages(
    prompt_name: str, arguments: dict[str, str] | None = None
) -> list[types.PromptMessage]:
    """Create messages based on the prompt name and arguments."""

    if prompt_name == "general_conversation":
        prompt_text = create_general_conversation_prompt()
    elif prompt_name == "help_prompt":
        prompt_text = create_help_prompt()
    else:
        prompt_text = "Unknown prompt requested."

    return [
        types.PromptMessage(
            role="user",
            content=types.TextContent(type="text", text=prompt_text),
        )
    ]


@server.get_prompt()
async def get_prompt(
    name: str, arguments: dict[str, str] | None = None
) -> types.GetPromptResult:
    """Get the specified prompt with given arguments."""
    logger.info(f"Retrieving prompt: {name}")

    return types.GetPromptResult(
        messages=create_messages(name, arguments), description=f"Prompt for {name}"
    )


@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    """List available tools for the conversation server."""
    return [
        types.Tool(
            name="echo_message",
            description="Simple tool that echoes the provided message back to the client",
            inputSchema={
                "type": "object",
                "properties": {
                    "message": {
                        "type": "string",
                        "description": "The message to echo back",
                    },
                },
                "required": ["message"],
            },
        ),
        types.Tool(
            name="format_text",
            description="Format text with markdown styling for better display",
            inputSchema={
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "The text content to format",
                    },
                    "style": {
                        "type": "string",
                        "description": "The style to apply (bold, italic, heading, code)",
                        "enum": ["bold", "italic", "heading", "code"],
                    },
                },
                "required": ["text", "style"],
            },
        ),
    ]


@server.call_tool()
async def handle_call_tool(
    name: str, arguments: dict | None
) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
    """Handle tool execution requests."""
    # Log tool call
    logger.info(f"Handling tool call: '{name}' with arguments: {arguments}")

    if not arguments:
        arguments = {}

    if name == "echo_message":
        message = arguments.get("message", "No message provided")
        return [types.TextContent(type="text", text=f"Echo: {message}")]
    elif name == "format_text":
        text = arguments.get("text", "")
        style = arguments.get("style", "bold")

        formatted_text = text
        if style == "bold":
            formatted_text = f"**{text}**"
        elif style == "italic":
            formatted_text = f"*{text}*"
        elif style == "heading":
            formatted_text = f"# {text}"
        elif style == "code":
            formatted_text = f"```\n{text}\n```"

        return [
            types.TextContent(type="text", text=f"Formatted text: {formatted_text}")
        ]
    else:
        raise ValueError(f"Unknown tool: {name}")


async def run():
    """Run the MCP server."""
    logger.info("Starting Simple Voice Conversation MCP Server")

    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="conversation",
                server_version="1.0.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


if __name__ == "__main__":
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Error running server: {e}", exc_info=True)
        sys.exit(1)
