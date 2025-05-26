#!/usr/bin/env python3
import asyncio
import logging
import sys
import nest_asyncio
import requests
from typing import Dict, Optional

# Core MCP components
from mcp.server import Server, NotificationOptions
from mcp.server.models import InitializationOptions
import mcp.types as types
import mcp.server.stdio

# Golf API Configuration
API_KEY = "a86ff919-bdc4-4759-b05e-ffb7e2b0bc4e"
COURSE_ID = "012141520658891108829"

class GreenCoordinates:
    def __init__(self):
        self.course_data = None
        self.coordinates_cache = {}
        self._fetch_course_data()

    def _fetch_course_data(self):
        """Fetch course coordinate data from the API"""
        url = f"https://www.golfapi.io/api/v2.3/coordinates/{COURSE_ID}"
        headers = {
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json"
        }
        
        try:
            response = requests.get(url, headers=headers)
            response.raise_for_status()
            self.course_data = response.json()
            logger.info("Successfully fetched course coordinate data")
        except Exception as e:
            logger.error(f"Failed to fetch course coordinate data: {str(e)}")
            self.course_data = None

    def get_green_coordinates(self, hole_number: int) -> Optional[Dict]:
        """Get coordinates for front, middle, and back of green for a specific hole"""
        if not self.course_data:
            return None

        # Check if we already have this hole's data cached
        if hole_number in self.coordinates_cache:
            return self.coordinates_cache[hole_number]

        # poi = 1 means green; location 1 = front, 2 = middle, 3 = back
        green_coords = {
            1: None,  # front
            2: None,  # middle
            3: None   # back
        }

        for coord in self.course_data["coordinates"]:
            if coord["hole"] == hole_number and coord["poi"] == 1:
                loc = coord["location"]
                if loc in green_coords:
                    green_coords[loc] = {
                        "latitude": coord["latitude"],
                        "longitude": coord["longitude"]
                    }

        coordinates = {
            "front": green_coords[1],
            "middle": green_coords[2],
            "back": green_coords[3]
        }

        self.coordinates_cache[hole_number] = coordinates
        return coordinates

# Apply nest_asyncio
nest_asyncio.apply()

# Setup basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("Caddy2Server")

# Server Instance
server = Server("Caddy2Server-InternalID")

# Initialize GreenCoordinates
green_coordinates = GreenCoordinates()

# Tool Definition
@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    """Lists all tools provided by this server."""
    return [
        types.Tool(
            name="get_hole_coordinates",
            description="Get the GPS coordinates for the front, middle, and back of the green for a specific hole.",
            inputSchema={
                "type": "object",
                "properties": {
                    "hole_number": {
                        "type": "integer",
                        "description": "The hole number to get coordinates for"
                    }
                },
                "required": ["hole_number"]
            }
        )
    ]

# Tool Implementation
@server.call_tool()
async def handle_call_tool(
    name: str,
    arguments: dict | None
) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
    """Handles incoming tool calls by dispatching to the correct logic."""
    if not arguments:
        arguments = {}

    logger.info(f"Executing tool '{name}' with arguments: {arguments}")

    try:
        if name == "get_hole_coordinates":
            hole_number = arguments.get('hole_number')
            coordinates = green_coordinates.get_green_coordinates(hole_number)
            
            if coordinates:
                # Format coordinates nicely
                result_text = f"Hole {hole_number} Green Coordinates:\n\n"
                
                for position, coords in coordinates.items():
                    if coords:
                        result_text += f"{position.capitalize()} of green:\n"
                        result_text += f"  Latitude:  {coords['latitude']}\n"
                        result_text += f"  Longitude: {coords['longitude']}\n\n"
                    else:
                        result_text += f"{position.capitalize()} of green: Coordinates not available\n\n"
            else:
                result_text = f"Could not retrieve green coordinates for hole {hole_number}"
            
            return [types.TextContent(type="text", text=result_text)]
        else:
            logger.error(f"Unknown tool called: {name}")
            raise ValueError(f"unknown tool: {name}")

    except Exception as e:
        error_message = f"Error executing tool '{name}': {str(e)}"
        logger.error(error_message, exc_info=True)
        return [types.TextContent(type="text", text=error_message)]

# Server Execution
async def run():
    """Sets up and runs the MCP server using stdio."""
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        logger.info(f"Starting Caddy2Server via stdio...")
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="Caddy2Server",
                server_version="0.1.0",
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
        logger.info("Server stopped by user.") 