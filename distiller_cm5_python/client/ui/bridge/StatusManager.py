from PyQt6.QtCore import QObject, pyqtSignal
import logging

logger = logging.getLogger(__name__)

class StatusManager(QObject):
    """Manages the status system for the UI/client"""
    
    # Status constants
    STATUS_IDLE = "idle"
    STATUS_INITIALIZING = "initializing"
    STATUS_CONNECTING = "connecting"
    STATUS_CONNECTED = "connected"
    STATUS_PROCESSING = "processing"
    STATUS_READY = "ready"
    STATUS_ERROR = "error"
    STATUS_DISCONNECTED = "disconnected"
    STATUS_RESTARTING = "restarting"
    STATUS_SHUTTING_DOWN = "shutting_down"
    STATUS_CONFIG_APPLIED = "config_applied"
    
    # Signal to update UI with status changes
    statusChanged = pyqtSignal(str, str)  # status, details
    
    def __init__(self, parent=None):
        """Initialize the status manager"""
        super().__init__(parent)
        self._current_status = self.STATUS_IDLE
        self._status_details = ""
        logger.info("StatusManager initialized")
    
    def update_status(self, status, details="", **kwargs):
        """
        Update the current status and emit signals for UI
        
        Args:
            status: The new status string (use STATUS_* constants)
            details: Optional details about the status
            **kwargs: Additional keyword arguments, such as server_name
        """
        # Process additional kwargs if needed
        if 'server_name' in kwargs and not details:
            details = f"Connected to {kwargs['server_name']}"
            
        # Only update and emit signal if status actually changed
        status_changed = (self._current_status != status or self._status_details != details)
        
        if status_changed:
            self._current_status = status
            self._status_details = details
            logger.debug(f"Status updated: {status} - {details}")
            
            # Emit signal for UI components to update
            self.statusChanged.emit(status, details)
    
    def get_current_status(self):
        """
        Get the current status
        
        Returns:
            Tuple of (status, details)
        """
        return (self._current_status, self._status_details)
    
    @property
    def status(self):
        """Return the current status string."""
        return self._current_status
    
    def is_ready(self):
        """
        Check if the system is in ready state
        
        Returns:
            True if status is READY
        """
        return self._current_status == self.STATUS_READY
    
    def is_error(self):
        """
        Check if the system is in error state
        
        Returns:
            True if status is ERROR
        """
        return self._current_status == self.STATUS_ERROR
    
    def is_connected(self):
        """
        Check if the system is connected
        
        Returns:
            True if status is CONNECTED
        """
        return self._current_status == self.STATUS_CONNECTED
    
    def cleanup(self):
        """Clean up resources and reset status"""
        self.update_status(self.STATUS_IDLE)
        logger.info("StatusManager cleaned up")
