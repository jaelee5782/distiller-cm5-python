# Voice Conversation MCP Server

This is a basic MCP (Multi-modal Conversation Protocol) server implementation for general voice conversations. The server provides a foundation for handling voice-based interactions without specialized tools.

## Features

- General conversation capabilities
- Simple text formatting tool
- Echo message tool for testing
- Clean prompt design for voice interactions
- Markdown support for formatted responses

## Getting Started

### Prerequisites

Ensure you have the Distiller CM5 Python environment set up with all dependencies installed. This server requires the MCP package and other dependencies specified in the main project requirements.

### Running the Server

```bash
# From the project root directory:
python -m distiller_cm5_python.mcp_server.conversation_server

# With debug logging:
python -m distiller_cm5_python.mcp_server.conversation_server --debug
```

### Connecting from the Distiller CM5 Client

1. Launch the main client with the server script path:

```bash
python main.py --gui --server-script /path/to/distiller_cm5_python/mcp_server/conversation_server.py
```

2. Or connect from the client UI by selecting the conversation server from the server selection dialog.

## Available Prompts

The server provides two main prompts:

1. **general_conversation**: Default prompt for general voice interactions
2. **help_prompt**: Documentation about the server's capabilities

## Available Tools

### echo_message

A simple tool that echoes the provided message back to the client.

**Parameters**:
- `message` (string, required): The message to echo back

### format_text

A tool that formats text with markdown styling for better display.

**Parameters**:
- `text` (string, required): The text content to format
- `style` (string, required): The style to apply (bold, italic, heading, code)

## Extending the Server

You can extend this server by:

1. Adding new prompts by creating new prompt functions and adding entries to the `list_prompts()` method
2. Adding new tools by implementing their functionality in the `handle_call_tool()` method and defining them in the `handle_list_tools()` method
3. Enhancing the existing prompts with more examples and instructions

## Limitations

- This is a basic server with limited functionality
- No external API integrations or advanced capabilities
- Designed for simple voice conversations only
- No web search, file access, or other specialized tools
