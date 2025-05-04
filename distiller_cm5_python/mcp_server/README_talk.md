# Text-to-Speech MCP Server

This MCP (Multi-modal Conversation Protocol) server implementation provides text-to-speech capabilities for the Distiller CM5 system. The server enables voice assistants to generate high-quality speech output from text.

## Features

- High-quality text-to-speech conversion
- Multiple voice options and customization
- Voice speed and pitch control
- Emotion and emphasis support
- Queued speech playback
- Clean prompt design for natural voice interactions

## Getting Started

### Prerequisites

Ensure you have the Distiller CM5 Python environment set up with all dependencies installed. This server requires the MCP package and audio libraries specified in the main project requirements.

### Running the Server

```bash
# From the project root directory:
python -m distiller_cm5_python.mcp_server.talk_server

# With debug logging:
python -m distiller_cm5_python.mcp_server.talk_server --debug
```

### Connecting from the Distiller CM5 Client

1. Launch the main client with the server script path:

```bash
python main.py --gui --server-script /path/to/distiller_cm5_python/mcp_server/talk_server.py
```

2. Or connect from the client UI by selecting the Talk server from the server selection dialog.

## Available Prompts

The server provides several prompts for text-to-speech functionality:

1. **speak_text**: Guides the assistant to speak text with natural intonation
2. **speak_with_emotion**: Helps the assistant express text with specific emotions
3. **speak_system_notification**: Format for speaking system notifications

## Available Tools

### speak

Converts text to speech and plays it through the audio output.

**Parameters**:
- `text` (string, required): The text to be spoken
- `voice` (string, optional): The voice to use (default is system default)
- `speed` (float, optional): Speech rate multiplier (0.5-2.0, default is 1.0)
- `pitch` (float, optional): Pitch adjustment (-1.0 to 1.0, default is 0.0)

### get_available_voices

Lists all available voice options for text-to-speech.

**Parameters**: None

### stop_speaking

Stops any currently playing speech.

**Parameters**: None

### set_volume

Sets the volume for speech output.

**Parameters**:
- `level` (float, required): Volume level (0.0-1.0)

### queue_speech

Adds text to the speech queue to be spoken after current speech finishes.

**Parameters**:
- `text` (string, required): The text to be queued for speaking
- `voice` (string, optional): The voice to use
- `priority` (integer, optional): Priority level (higher numbers get priority)

## Voice Customization

The talk server supports various voice customization options:

- **Emotions**: Happy, sad, angry, surprised
- **Emphasis**: Regular, strong, reduced
- **Languages**: Multiple language support depending on installed voices
- **Gender**: Male and female voice options

## Platform Support

The talk server works on various platforms with different TTS backends:

- **Linux**: Uses eSpeak or Festival
- **Raspberry Pi**: Uses Piper TTS for offline operation
- **Windows/Mac**: Uses system TTS engines

## Extending the Server

You can extend this server by:

1. Adding more TTS-related tools in the `handle_call_tool()` method
2. Adding support for new TTS engines and voices
3. Enhancing the existing prompts with more examples and instructions

## Related Servers

- **wifi_server.py**: Provides WiFi management capabilities
- **conversation_server.py**: Handles general voice conversations 