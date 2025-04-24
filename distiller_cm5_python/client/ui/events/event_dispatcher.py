import json
from distiller_cm5_python.utils.logger import logger
from PyQt6.QtCore import QObject, pyqtSignal

class EventDispatcher(QObject):
    """Dispatches UIEvent objects to listeners, optionally logging to file in debug mode."""
    event_dispatched = pyqtSignal(object)  # Emits UIEvent instance

    def __init__(self, debug: bool=False, log_path: str=None):
        super().__init__()
        self.debug = debug
        self.log_path = log_path
        self._file = open(log_path, "a") if (debug and log_path) else None

    def dispatch(self, evt):
        # Convert event to dict for logging
        payload = evt.to_dict()
        if self._file:
            self._file.write(json.dumps(payload) + "\n")
            self._file.flush()
        logger.debug(f"[UIEvent] {payload}")
        # Emit the UIEvent object to listeners
        self.event_dispatched.emit(evt)

    def close(self):
        if self._file:
            self._file.close()
