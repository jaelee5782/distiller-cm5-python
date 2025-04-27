from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Any, Dict, List, Optional, Union
import uuid
import time
import json
from pydantic import BaseModel, Field, validator, root_validator


# Status values for UI events
class StatusType(str, Enum):
    """Status types for event messages following the architecture diagram"""
    IN_PROGRESS = "in_progress"
    SUCCESS = "success"
    FAILED = "failed"


class EventType(str, Enum):
    """Standard event types for UI communication"""
    INFO = "Info"
    MESSAGE = "Message"
    ACTION = "Action"
    OBSERVATION = "Observation"
    PLAN = "Plan"
    WARNING = "Warning"
    ERROR = "Error"
    SSH_INFO = "SSHInfo"  # New event type for SSH information
    STATUS = "Status"     # New event type for status updates
    FUNCTION = "Function" # New event type for function calls (MCP)


class MessageSchema(BaseModel):
    """Standardized message schema following the architecture diagram"""
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    type: EventType
    content: Any
    status: StatusType 
    data: Optional[Dict[str, Any]] = None
    timestamp: float = Field(default_factory=time.time)
    
    class Config:
        use_enum_values = True
        json_encoders = {
            uuid.UUID: lambda v: str(v)
        }
    
    def to_json(self) -> str:
        """Convert message to JSON string"""
        return json.dumps(self.dict())
    
    @classmethod
    def from_json(cls, json_str: str) -> 'MessageSchema':
        """Create message from JSON string"""
        data = json.loads(json_str)
        return cls(**data)


# For backward compatibility
@dataclass
class UIEvent:
    """Standard event message for UI communication"""
    id: str
    type: EventType
    content: Any
    status: StatusType
    data: Optional[Any] = None
    timestamp: Optional[float] = None

    @staticmethod
    def new(type: EventType, content: Any, status: StatusType, data: Optional[Any] = None, timestamp: Optional[float] = None) -> 'UIEvent':
        """Helper to create a new event with unique id"""
        return UIEvent(
            id=str(uuid.uuid4()),
            type=type,
            content=content,
            status=status,
            data=data,
            timestamp=timestamp or time.time()
        )

    def to_dict(self):
        """Convert event to dictionary format"""
        return {
            "id": self.id,
            "type": self.type.value,
            "content": self.content,
            "status": self.status.value,
            "data": self.data,
            "timestamp": self.timestamp
        }
        
    def to_message_schema(self) -> MessageSchema:
        """Convert UIEvent to MessageSchema"""
        return MessageSchema(
            id=self.id,
            type=self.type,
            content=self.content,
            status=self.status,
            data=self.data,
            timestamp=self.timestamp or time.time()
        )
    
    @classmethod
    def from_message_schema(cls, message: MessageSchema) -> 'UIEvent':
        """Create UIEvent from MessageSchema"""
        return cls(
            id=message.id,
            type=message.type,
            content=message.content,
            status=message.status,
            data=message.data,
            timestamp=message.timestamp
        )

    @classmethod
    def thinking(cls):
        import uuid, time
        
        # Create a MessageSchema first, then convert to UIEvent for backward compatibility
        message = MessageSchema(
            id=str(uuid.uuid4()),
            type=EventType.INFO,
            content="Thinking...",
            status=StatusType.IN_PROGRESS,
            timestamp=time.time()
        )
        
        # Convert to UIEvent for backward compatibility
        return cls.from_message_schema(message)

    @classmethod
    def tool_call(cls, tool_call: dict):
        import uuid, time
        tool_name = tool_call.get("function", {}).get("name", tool_call.get("name", ""))
        
        # Create a MessageSchema first, then convert to UIEvent for backward compatibility
        message = MessageSchema(
            id=str(uuid.uuid4()),
            type=EventType.ACTION,
            content=f"Calling {tool_name}",
            status=StatusType.IN_PROGRESS,
            data=tool_call,
            timestamp=time.time()
        )
        
        # Convert to UIEvent for backward compatibility
        return cls.from_message_schema(message)

    @classmethod
    def tool_result(cls, tool_call: dict, result: str):
        import uuid, time
        tool_name = tool_call.get("function", {}).get("name", tool_call.get("name", ""))
        
        # Create a MessageSchema first, then convert to UIEvent for backward compatibility
        message = MessageSchema(
            id=str(uuid.uuid4()),
            type=EventType.ACTION,
            content=f"Result for {tool_name}",
            status=StatusType.SUCCESS,
            data={"tool_call": tool_call, "result": result},
            timestamp=time.time()
        )
        
        # Convert to UIEvent for backward compatibility
        return cls.from_message_schema(message)

    @classmethod
    def message_chunk(cls, chunk: str, event_id: str):
        import time
        
        # Create a MessageSchema first, then convert to UIEvent for backward compatibility
        message = MessageSchema(
            id=event_id,
            type=EventType.MESSAGE,
            content=chunk,
            status=StatusType.IN_PROGRESS,
            timestamp=time.time()
        )
        
        # Convert to UIEvent for backward compatibility
        return cls.from_message_schema(message)

    @classmethod
    def message_complete(cls, event_id: str, content: str):
        import time
        
        # Create a MessageSchema first, then convert to UIEvent for backward compatibility
        message = MessageSchema(
            id=event_id,
            type=EventType.MESSAGE,
            content=content,
            status=StatusType.SUCCESS,
            timestamp=time.time()
        )
        
        # Convert to UIEvent for backward compatibility
        return cls.from_message_schema(message)

    @classmethod
    def ssh_info(cls, ip_address: str, username: str = "user", port: int = 22):
        """Create SSH info event with connection details"""
        import uuid, time
        
        # Create a MessageSchema first, then convert to UIEvent for backward compatibility
        message = MessageSchema(
            id=str(uuid.uuid4()),
            type=EventType.SSH_INFO,
            content=f"SSH: {username}@{ip_address}:{port}",
            status=StatusType.SUCCESS,
            data={"ip": ip_address, "username": username, "port": port},
            timestamp=time.time()
        )
        
        # Convert to UIEvent for backward compatibility
        return cls.from_message_schema(message)

    @classmethod
    def function_info(cls, name: str, description: str, params: dict = None):
        """Create function info event with details about available functions"""
        import uuid, time
        
        # Create a MessageSchema first, then convert to UIEvent for backward compatibility
        message = MessageSchema(
            id=str(uuid.uuid4()),
            type=EventType.FUNCTION,
            content=f"Function: {name}",
            status=StatusType.SUCCESS,
            data={"name": name, "description": description, "params": params or {}},
            timestamp=time.time()
        )
        
        # Convert to UIEvent for backward compatibility
        return cls.from_message_schema(message)


# Specialized message schemas for different event types
class MessageEvent(MessageSchema):
    """Message from assistant or user"""
    type: EventType = EventType.MESSAGE
    role: Optional[str] = "assistant"  # 'user' or 'assistant'
    
    class Config:
        use_enum_values = True


class ActionEvent(MessageSchema):
    """Action being performed"""
    type: EventType = EventType.ACTION
    tool_name: Optional[str] = None
    tool_args: Optional[Dict[str, Any]] = None
    
    class Config:
        use_enum_values = True


class ObservationEvent(MessageSchema):
    """Observation about environment or system state"""
    type: EventType = EventType.OBSERVATION
    source: Optional[str] = None
    
    class Config:
        use_enum_values = True


class PlanEvent(MessageSchema):
    """Plan for executing a task"""
    type: EventType = EventType.PLAN
    steps: Optional[List[str]] = None
    
    class Config:
        use_enum_values = True


class SSHInfoEvent(MessageSchema):
    """SSH connection information"""
    type: EventType = EventType.SSH_INFO
    ip_address: str
    username: str = "user"
    port: int = 22
    
    class Config:
        use_enum_values = True


class FunctionEvent(MessageSchema):
    """Function capabilities info"""
    type: EventType = EventType.FUNCTION
    name: str
    description: Optional[str] = None
    parameters: Optional[Dict[str, Any]] = None
    
    class Config:
        use_enum_values = True


class StatusEvent(MessageSchema):
    """System status information"""
    type: EventType = EventType.STATUS
    component: Optional[str] = None
    
    class Config:
        use_enum_values = True
