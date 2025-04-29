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

    @staticmethod
    def thinking() -> 'StatusEvent':
        """Create a 'thinking' status event."""
        return StatusEvent(type=EventType.STATUS, content="Thinking...", status=StatusType.IN_PROGRESS)

    @staticmethod
    def tool_call(tool_call_dict: dict) -> 'ActionEvent':
        """Create an action event for a tool call."""
        tool_name = tool_call_dict.get("function", {}).get("name", tool_call_dict.get("name", ""))
        tool_args = tool_call_dict.get("function", {}).get("arguments", tool_call_dict.get("arguments", {}))
        # Ensure args are dict, not string
        if isinstance(tool_args, str):
            try:
                tool_args = json.loads(tool_args)
            except json.JSONDecodeError:
                tool_args = {"args_str": tool_args} # fallback
        
        return ActionEvent(
            type=EventType.ACTION, 
            content=f"Tool Call: {tool_name}", 
            status=StatusType.IN_PROGRESS, 
            tool_name=tool_name, 
            tool_args=tool_args,
            data=tool_call_dict # Keep original full call in data for context
        )

    @staticmethod
    def tool_result(tool_call: dict, result: str) -> 'ObservationEvent':
        """Create an observation event for a tool result."""
        tool_name = tool_call.get("function", {}).get("name", tool_call.get("name", ""))
        return ObservationEvent(
            type=EventType.OBSERVATION,
            content=f"Tool Result: {tool_name}",
            status=StatusType.SUCCESS,
            source=tool_name,
            data={'tool_call': tool_call, 'result': result}
        )

    @staticmethod
    def message_chunk(chunk: str, event_id: str) -> 'MessageEvent':
        """Create a message event for a streaming chunk."""
        return MessageEvent(
            id=event_id, # Reuse ID for chunks of the same message
            type=EventType.MESSAGE,
            content=chunk,
            status=StatusType.IN_PROGRESS,
            role='assistant'
        )

    @staticmethod
    def message_complete(event_id: str, content: str) -> 'MessageEvent':
        """Create a message event for a complete message."""
        return MessageEvent(
            id=event_id, # Reuse ID from chunks
            type=EventType.MESSAGE,
            content=content,
            status=StatusType.SUCCESS,
            role='assistant'
        )

    @staticmethod
    def ssh_info(ip_address: str, username: str = "user", port: int = 22) -> 'SSHInfoEvent':
        """Create an SSH info event."""
        return SSHInfoEvent(
            type=EventType.SSH_INFO,
            content=f"SSH: {username}@{ip_address}:{port}",
            status=StatusType.SUCCESS,
            ip_address=ip_address,
            username=username,
            port=port
        )

    @staticmethod
    def function_info(name: str, description: Optional[str] = None, params: Optional[dict] = None) -> 'FunctionEvent':
        """Create a function info event."""
        return FunctionEvent(
            type=EventType.FUNCTION,
            content=f"Function: {name}",
            status=StatusType.SUCCESS,
            name=name,
            description=description,
            parameters=params or {}
        )


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
