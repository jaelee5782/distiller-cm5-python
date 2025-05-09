# MCP Server Implementations

This directory contains various example implementations of servers adhering to the Model Context Protocal (MCP). Each server typically exposes a specific set of tools or resources related to a particular domain or device.

These servers are designed to be launched independently and communicated with by an MCP client (like the one in the `../client` directory), often via standard input/output (stdio).

## TODO for next release: Use uv env control to manage server


## Included Example Servers

- **`talk_server.py`**: An MCP server offering a tool (`speak_text`) to perform Text-to-Speech using the `piper` library. Allows the assistant to speak provided text aloud.
- **`wifi_server.py`**: An MCP server for interacting with WiFi networks on **Linux systems** using `nmcli`. Provides tools for listing networks, checking status, connecting to a network, and showing SSH instructions. *Note: Requires `nmcli` and appropriate permissions (e.g., `sudo`) for some operations.*

## Usage

Each server script can typically be run directly using Python:

```bash
# Example for talk server
python distiller_cm5_python/mcp_server/talk_server.py

# Example for wifi server
python distiller_cm5_python/mcp_server/wifi_server.py
```

An MCP client (like the one started via `main.py --server-script /path/to/server.py`) can then connect to the launched server process using the stdio transport mechanism provided by the `mcp` library.

## Dependencies

- `mcp` library (likely installed from the parent project or a central location).
- `distiller_cm5_sdk` (specifically `piper` for `talk_server.py`).
- Specific system utilities depending on the server's functionality (e.g., `nmcli` for `wifi_server.py` on Linux).
- `nest_asyncio` (used by both servers). 