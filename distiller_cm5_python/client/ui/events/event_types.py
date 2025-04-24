from dataclasses import dataclass
from enum import Enum
from typing import Any, Optional
import uuid

# Status values for UI events
class StatusType(Enum):
    IN_PROGRESS = "in_progress"
    SUCCESS = "success"
    FAILED = "failed"

class EventType(Enum):
    """Standard event types for UI communication"""
    INFO = "Info"
    MESSAGE = "Message"
    ACTION = "Action"
    OBSERVATION = "Observation"  # currently unsupported
    PLAN = "Plan"                # currently unsupported
    WARNING = "Warning"
    ERROR = "Error"

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
            timestamp=timestamp
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

    @classmethod
    def thinking(cls):
        import uuid, time
        return cls(str(uuid.uuid4()), EventType.INFO, "Thinking...", StatusType.IN_PROGRESS, timestamp=time.time())

    @classmethod
    def tool_call(cls, tool_call: dict):
        import uuid, time
        tool_name = tool_call.get("function", {}).get("name", tool_call.get("name", ""))
        return cls(str(uuid.uuid4()), EventType.ACTION, f"Calling {tool_name}", StatusType.IN_PROGRESS, data=tool_call, timestamp=time.time())

    @classmethod
    def tool_result(cls, tool_call: dict, result: str):
        import uuid, time
        tool_name = tool_call.get("function", {}).get("name", tool_call.get("name", ""))
        return cls(str(uuid.uuid4()), EventType.ACTION, f"Result for {tool_name}", StatusType.SUCCESS, data={"tool_call": tool_call, "result": result}, timestamp=time.time())

    @classmethod
    def message_chunk(cls, chunk: str, event_id: str):
        import time
        return cls(event_id, EventType.MESSAGE, chunk, StatusType.IN_PROGRESS, timestamp=time.time())

    @classmethod
    def message_complete(cls, event_id: str, content: str):
        import time
        return cls(event_id, EventType.MESSAGE, content, StatusType.SUCCESS, timestamp=time.time())
