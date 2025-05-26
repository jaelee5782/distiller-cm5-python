#!/usr/bin/env python3
import asyncio
import logging
import sys
import nest_asyncio
import requests
from typing import Dict, Optional, List

# Core MCP components
from mcp.server import Server, NotificationOptions
from mcp.server.models import InitializationOptions
import mcp.types as types
import mcp.server.stdio
from distiller_cm5_sdk.piper import Piper

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
logger = logging.getLogger("Caddy3Server")

# Server Instance
server = Server("Caddy3Server-InternalID")

# Initialize services
green_coordinates = GreenCoordinates()
piper = Piper()

def _speak_text(text: str, volume: int = 50):
    """Speak text using Piper TTS and return success status."""
    try:
        piper.speak_stream(text, volume, "snd_rpi_pamir_ai_soundcard")
        return True
    except Exception as e:
        logger.error(f"Error in TTS: {str(e)}")
        return False

def create_response(
    display_text: str,
    speech_text: Optional[str] = None,
    volume: int = 50
) -> List[types.TextContent]:
    """
    Create a response that will be both displayed and spoken.
    Args:
        display_text: Text to display to the user
        speech_text: Text to speak (if different from display_text)
        volume: Volume level for speech
    """
    # If no specific speech text is provided, use the display text
    text_to_speak = speech_text if speech_text is not None else display_text
    
    # Always speak the response
    if _speak_text(text_to_speak, volume):
        return [types.TextContent(type="text", text=display_text)]
    else:
        error_msg = f"{display_text}\n\nError: Could not speak the response."
        return [types.TextContent(type="text", text=error_msg)]

# Tool Definition
@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    """Lists all tools provided by this server."""
    tools = [
        types.Tool(
            name="get_coordinates",
            description="Get and speak the GPS coordinates for a specific hole.",
            inputSchema={
                "type": "object",
                "properties": {
                    "hole_number": {
                        "type": "integer",
                        "description": "The hole number to get coordinates for"
                    },
                    "volume": {
                        "type": "integer",
                        "description": "Volume level for speech (0-100)",
                        "default": 25
                    }
                },
                "required": ["hole_number"]
            }
        )
    ]
    
    # Speak the available tools
    tools_speech = "Available tools include: " + ", ".join(tool.name for tool in tools)
    return create_response("Available Tools:\n" + "\n".join(tool.name for tool in tools), tools_speech)

# Tool Implementation
@server.call_tool()
async def handle_call_tool(
    name: str,
    arguments: dict | None
) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
    """Handles incoming tool calls by dispatching to the correct logic."""
    if not arguments:
        arguments = {}

    volume = arguments.get('volume', 50)
    logger.info(f"Executing tool '{name}' with arguments: {arguments}")

    try:
        if name == "get_coordinates":
            hole_number = arguments.get('hole_number')
            coordinates = green_coordinates.get_green_coordinates(hole_number)
            
            if coordinates:
                # Create a natural speech response
                speech_text = f"Here are the coordinates for hole {hole_number}. "
                
                # Also prepare a text display version
                display_text = f"Hole {hole_number} Green Coordinates:\n\n"
                
                for position, coords in coordinates.items():
                    if coords:
                        # Add to display text
                        display_text += f"{position.capitalize()} of green:\n"
                        display_text += f"  Latitude:  {coords['latitude']}\n"
                        display_text += f"  Longitude: {coords['longitude']}\n\n"
                        
                        # Add to speech in a more conversational way
                        speech_text += f"For the {position} of the green, "
                        speech_text += f"you'll find latitude {coords['latitude']:.6f}, "
                        speech_text += f"and longitude {coords['longitude']:.6f}. "
                    else:
                        display_text += f"{position.capitalize()} of green: Coordinates not available\n\n"
                        speech_text += f"I don't have coordinates for the {position} of the green. "
                
                return create_response(display_text, speech_text, volume)
            else:
                speech_text = f"I'm sorry, I couldn't get the coordinates for hole {hole_number}."
                display_text = f"Could not retrieve green coordinates for hole {hole_number}"
                return create_response(display_text, speech_text, volume)

        else:
            error_msg = f"Unknown tool called: {name}"
            speech_text = f"I'm sorry, but I don't know how to handle the tool called {name}."
            return create_response(error_msg, speech_text, volume)

    except Exception as e:
        error_message = f"Error executing tool '{name}': {str(e)}"
        speech_text = f"I encountered an error while trying to help you. {str(e)}"
        return create_response(error_message, speech_text, volume)

# Server Execution
async def run():
    """Sets up and runs the MCP server using stdio."""
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        logger.info(f"Starting Caddy3Server via stdio...")
        startup_msg = "Caddy server is ready to help you with course coordinates."
        _speak_text(startup_msg)
        
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="Caddy3Server",
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
        shutdown_msg = "Shutting down caddy server. Goodbye!"
        _speak_text(shutdown_msg)
        logger.info("Server stopped by user.") 