from datetime import datetime


class ConversationManager:
    """
    Manages the conversation history for the MCPClientBridge.

    Handles message storage, formatting, and streaming message tracking.
    """

    def __init__(self, bridge):
        """Initialize the conversation manager.

        Args:
            bridge: The parent MCPClientBridge instance
        """
        self._bridge = bridge
        self._conversation = []
        self.current_streaming_message: dict[str, str] | None = None

    def add_message(self, message):
        """Add a message to the conversation history and emit the signal.

        Args:
            message: A message dict with timestamp and content keys
        """
        self._conversation.append(message)
        self._bridge.conversationChanged.emit()

    def clear(self):
        """Clear the conversation history."""
        self._conversation = []
        self._bridge.conversationChanged.emit()

    def get_messages(self):
        """Get the raw conversation messages list.

        Returns:
            The internal conversation list
        """
        return self._conversation

    def get_messages_copy(self):
        """Get a copy of the conversation messages.

        Returns:
            A copy of the internal conversation list
        """
        return self._conversation.copy()

    def set_messages(self, messages):
        """Set the conversation messages list.

        Args:
            messages: The new conversation list to use
        """
        self._conversation = messages
        self._bridge.conversationChanged.emit()

    def get_formatted_messages(self):
        """Format the conversation messages for display in the UI.

        Returns:
            A list of formatted message strings
        """
        formatted_messages = []
        for message in self._conversation:
            timestamp = message.get("timestamp", "")
            content = message.get("content", "")
            # Format message as expected by MessageItem: "[timestamp] sender: content"
            # If content starts with "You: ", it's a user message, otherwise it's an assistant message
            if content.startswith("You: "):
                formatted_messages.append(f"[{timestamp}] {content}")
            else:
                formatted_messages.append(f"[{timestamp}] Assistant: {content}")
        return formatted_messages

    def get_timestamp(self):
        """Get the current timestamp for a message.

        Returns:
            A formatted timestamp string
        """
        return datetime.now().strftime("%H:%M:%S")

    def reset_streaming_message(self):
        """Reset the current streaming message reference.
        
        This should be called whenever starting a fresh message stream.
        """
        self.current_streaming_message = None
