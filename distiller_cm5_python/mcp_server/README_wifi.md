# WiFi Management MCP Server

This MCP (Multi-modal Conversation Protocol) server implementation provides WiFi management capabilities for the Distiller CM5 system. The server allows voice assistants to control and monitor WiFi connections.

## Features

- WiFi network scanning and connection
- Network status monitoring
- Password management for WiFi networks
- Signal strength reporting
- MAC address retrieval
- Clean prompt design for voice interactions

## Getting Started

### Prerequisites

Ensure you have the Distiller CM5 Python environment set up with all dependencies installed. This server requires the MCP package and networking libraries specified in the main project requirements.

### Running the Server

```bash
# From the project root directory:
python -m distiller_cm5_python.mcp_server.wifi_server

# With debug logging:
python -m distiller_cm5_python.mcp_server.wifi_server --debug
```

### Connecting from the Distiller CM5 Client

1. Launch the main client with the server script path:

```bash
python main.py --gui --server-script /path/to/distiller_cm5_python/mcp_server/wifi_server.py
```

2. Or connect from the client UI by selecting the WiFi server from the server selection dialog.

## Available Prompts

The server provides several prompts for WiFi management:

1. **wifi_connect**: Guides the assistant to help connect to a WiFi network
2. **wifi_list**: Helps the assistant list available WiFi networks
3. **wifi_status**: Shows the current WiFi connection status

## Available Tools

### scan_networks

Scans for available WiFi networks in range.

**Parameters**: None

### list_saved_networks

Lists previously saved WiFi networks.

**Parameters**: None

### get_connection_status

Returns the current WiFi connection status.

**Parameters**: None

### connect_to_network

Connects to a specified WiFi network.

**Parameters**:
- `ssid` (string, required): The name of the WiFi network
- `password` (string, optional): The password for the network (if required)

### get_wifi_ip

Retrieves the current IP address of the WiFi connection.

**Parameters**: None

### get_wifi_mac

Retrieves the MAC address of the WiFi interface.

**Parameters**: None

### get_signal_strength

Retrieves the signal strength of the current WiFi connection.

**Parameters**: None

## Platform Support

The WiFi server works on various platforms with different implementation details:

- **Linux**: Uses NetworkManager for WiFi management
- **Raspberry Pi**: Uses system-specific utilities for WiFi control
- **Windows/Mac**: Limited functionality, primarily for testing purposes

## Extending the Server

You can extend this server by:

1. Adding more WiFi-related tools in the `handle_call_tool()` method
2. Supporting additional platforms in the platform-specific handlers
3. Enhancing the existing prompts with more examples and instructions

## Related Servers

- **talk_server.py**: Provides text-to-speech capabilities
- **conversation_server.py**: Handles general voice conversations 