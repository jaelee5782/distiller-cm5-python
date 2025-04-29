import logging
import sys
from typing import Optional, IO

# Define the standard log format
DEFAULT_LOG_FORMAT = '%(asctime)s - %(name)s - %(module)s.%(funcName)s - %(levelname)s - %(message)s'

def setup_logging(log_level: int = logging.INFO, stream: IO = sys.stdout):
    """Setup root logging configuration.

    Args:
        log_level: The logging level to use (e.g., logging.DEBUG, logging.INFO).
                   Defaults to logging.INFO.
        stream: The output stream to use (e.g., sys.stdout, sys.stderr).
                Defaults to sys.stdout.
    """
    # Create a formatter
    formatter = logging.Formatter(DEFAULT_LOG_FORMAT)

    # Setup stream handler
    stream_handler = logging.StreamHandler(stream)
    stream_handler.setFormatter(formatter)

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)

    # Remove existing handlers to avoid duplicates if setup_logging is called multiple times
    # (though it should ideally be called only once at the application start)
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)

    # Add our handler
    root_logger.addHandler(stream_handler)

    # Optionally quiet overly verbose libraries
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("asyncio").setLevel(logging.WARNING)

# Removed the module-level call: logger = setup_logging()
# Logging configuration should now be explicitly called by application entry points.
# Example usage in an entry point:
# import logging
# from utils.logger import setup_logging
# import sys
#
# if __name__ == "__main__":
#     # Configure logging to INFO level, outputting to stderr
#     setup_logging(log_level=logging.INFO, stream=sys.stderr) 
#
#     # Modules should get their own logger
#     logger = logging.getLogger(__name__) 
#     logger.info("Application started.") 