"""
Event handling component for the MCPClientBridge.
Handles receiving events from the event dispatcher and forwarding them to appropriate handlers.
"""

from typing import Protocol, Union, cast
import logging
import time
import uuid

from PyQt6.QtCore import QObject, pyqtSignal

from distiller_cm5_python.client.ui.events.event_types import (
    EventType, 
    StatusType, 
    MessageSchema
)
from distiller_cm5_python.client.ui.events.event_dispatcher import EventDispatcher
from distiller_cm5_python.client.ui.bridge.StatusManager import StatusManager

logger = logging.getLogger(__name__)

class BridgeEventSignals(Protocol):
    """Protocol defining the required signals for event handling"""
    messageReceived: pyqtSignal
    actionReceived: pyqtSignal
    infoReceived: pyqtSignal
    warningReceived: pyqtSignal
    errorReceived: pyqtSignal
    sshInfoReceived: pyqtSignal
    functionReceived: pyqtSignal
    observationReceived: pyqtSignal
    planReceived: pyqtSignal
    statusChanged: pyqtSignal
    messageSchemaReceived: pyqtSignal

class BridgeEventHandler:
    """
    Handles events from the dispatcher and forwards them to the appropriate handlers.
    Decouples event handling from the main bridge class.
    """

    def __init__(
        self, 
        dispatcher: EventDispatcher, 
        status_manager: StatusManager, 
        signal_source: Union[QObject, BridgeEventSignals],
        connected_property: 'property'
    ):
        """
        Initialize the event handler.
        
        Args:
            dispatcher: The event dispatcher to receive events from
            status_manager: The status manager to update based on events
            signal_source: The object that provides signals for event emission
            connected_property: A property that indicates if the bridge is connected
        """
        self.dispatcher = dispatcher
        self.status_manager = status_manager
        self.signals = cast(BridgeEventSignals, signal_source)
        self.is_connected = connected_property
        
        # Get conversation manager reference from bridge if possible
        if hasattr(signal_source, 'conversation_manager'):
            self.signals.conversation_manager = signal_source.conversation_manager
        else:
            self.signals.conversation_manager = None
        
        # Connect to the dispatcher
        self.dispatcher.message_dispatched.connect(self.handle_event)
    
    def handle_event(self, event: MessageSchema) -> None:
        """
        Handle events from the dispatcher.
        
        Args:
            event: The MessageSchema event to handle
        """
        try:
            # Handle new MessageSchema format
            if isinstance(event, MessageSchema):
                self._handle_message_schema(event)
            # REMOVED legacy UIEvent handling block
            # elif isinstance(event, UIEvent):
            #     self._handle_ui_event(event)
            else:
                # This case should ideally not be reached if dispatcher only sends MessageSchema
                logger.error(f"Invalid event type received: {type(event)}")
                return
        except Exception as e:
            logger.error(f"Error handling event: {e}", exc_info=True)

    def _handle_message_schema(self, event: MessageSchema) -> None:
        """
        Handle events in the MessageSchema format.
        
        Args:
            event: The MessageSchema event to handle
        """
        # Convert timestamp to string if it exists
        timestamp_str = str(event.timestamp) if event.timestamp else None
        
        # Emit the raw message schema event
        try:
            # Convert the MessageSchema to a dictionary for QML
            event_dict = event.dict()
            # Emit the messageSchemaReceived signal with the event data
            self.signals.messageSchemaReceived.emit(event_dict)
        except Exception as e:
            logger.error(f"Error converting MessageSchema to dict: {e}", exc_info=True)
        
        # Get conversation manager from the bridge if available
        conversation_manager = getattr(self.signals, 'conversation_manager', None)
        
        # Emit the appropriate signal based on event type
        if event.type == EventType.MESSAGE:
            # Pass status as string (.value from Enum) to the UI
            status_value = event.status.value if hasattr(event.status, 'value') else event.status
            self.signals.messageReceived.emit(event.content, str(event.id), timestamp_str, status_value)
            
            # Add message type metadata for complete messages
            if status_value == "success" and conversation_manager:
                message = {
                    "timestamp": self._get_formatted_timestamp(),
                    "content": f"{event.content}",
                    "type": "Message"
                }
                conversation_manager.add_message(message)
            
            # Update status when message is complete
            if status_value == "success" and self.is_connected:
                self.status_manager.update_status(StatusManager.STATUS_IDLE)
                
        elif event.type == EventType.ACTION:
            self.signals.actionReceived.emit(event.content, str(event.id), timestamp_str)
            
            # Set executing tool status for actions
            status_value = event.status.value if hasattr(event.status, 'value') else event.status
            if status_value == "in_progress":
                self.status_manager.update_status(StatusManager.STATUS_EXECUTING_TOOL)
                
            # Add message type metadata
            if conversation_manager:
                message = {
                    "timestamp": self._get_formatted_timestamp(),
                    "content": f"{event.content}",
                    "type": "Action"
                }
                conversation_manager.add_message(message)
                
        elif event.type == EventType.INFO:
            self.signals.infoReceived.emit(event.content, str(event.id), timestamp_str)
            
            # For thinking info events, update status
            if event.content and "Thinking" in event.content:
                self.status_manager.update_status(StatusManager.STATUS_THINKING)
                
            # Add message type metadata
            if conversation_manager:
                message = {
                    "timestamp": self._get_formatted_timestamp(),
                    "content": f"{event.content}",
                    "type": "Info"
                }
                conversation_manager.add_message(message)
                
        elif event.type == EventType.WARNING:
            self.signals.warningReceived.emit(event.content, str(event.id), timestamp_str)
            
            # Add message type metadata
            if conversation_manager:
                message = {
                    "timestamp": self._get_formatted_timestamp(),
                    "content": f"{event.content}",
                    "type": "Warning"
                }
                conversation_manager.add_message(message)
                
        elif event.type == EventType.ERROR:
            self.signals.errorReceived.emit(event.content, str(event.id), timestamp_str)
            
            # Add message type metadata
            if conversation_manager:
                message = {
                    "timestamp": self._get_formatted_timestamp(),
                    "content": f"{event.content}",
                    "type": "Error"
                }
                conversation_manager.add_message(message)
                
        elif event.type == EventType.SSH_INFO:
            # Add handling for SSH_INFO events
            if hasattr(self.signals, 'sshInfoReceived'):
                self.signals.sshInfoReceived.emit(event.content, str(event.id), timestamp_str)
            else:
                # Fall back to info message if no dedicated handler
                self.signals.infoReceived.emit(event.content, str(event.id), timestamp_str)
                
            # Add message type metadata
            if conversation_manager:
                message = {
                    "timestamp": self._get_formatted_timestamp(),
                    "content": f"{event.content}",
                    "type": "SSH Info"
                }
                conversation_manager.add_message(message)
       
        elif event.type == EventType.OBSERVATION:
            # Handle observation events
            if hasattr(self.signals, 'observationReceived'):
                self.signals.observationReceived.emit(event.content, str(event.id), timestamp_str)
            else:
                # Fall back to info message if no dedicated handler
                self.signals.infoReceived.emit(event.content, str(event.id), timestamp_str)
                
            # Add message type metadata
            if conversation_manager:
                message = {
                    "timestamp": self._get_formatted_timestamp(),
                    "content": f"{event.content}",
                    "type": "Observation"
                }
                conversation_manager.add_message(message)
                
        elif event.type == EventType.PLAN:
            # Handle plan events
            if hasattr(self.signals, 'planReceived'):
                self.signals.planReceived.emit(event.content, str(event.id), timestamp_str)
            else:
                # Fall back to info message if no dedicated handler
                self.signals.infoReceived.emit(event.content, str(event.id), timestamp_str)
                
            # Add message type metadata
            if conversation_manager:
                message = {
                    "timestamp": self._get_formatted_timestamp(),
                    "content": f"{event.content}",
                    "type": "Plan"
                }
                conversation_manager.add_message(message)
                
        elif event.type == EventType.STATUS:
            # Update status if STATUS event
            status_str = event.content
            self.status_manager.update_status(status_str)
            self.signals.statusChanged.emit(status_str)
            
        else:
            logger.warning(f"Unknown event type: {event.type}")

    def create_error_event(self, error_msg: str) -> MessageSchema:
        """
        Create an error event.
        
        Args:
            error_msg: The error message
            
        Returns:
            A MessageSchema representing the error
        """
        return MessageSchema(
            id=str(uuid.uuid4()),
            type=EventType.ERROR,
            content=error_msg,
            status=StatusType.FAILED,
            timestamp=time.time()
        ) 

    def _get_formatted_timestamp(self):
        """Get a formatted timestamp string for messages."""
        from datetime import datetime
        return datetime.now().strftime("%H:%M:%S") 
