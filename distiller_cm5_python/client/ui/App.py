# pyright: reportArgumentType=false
from PyQt6.QtCore import QUrl, QTimer
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtWidgets import QApplication
from distiller_cm5_python.client.ui.AppInfoManager import AppInfoManager
from distiller_cm5_python.client.ui.bridge.MCPClientBridge import MCPClientBridge
from contextlib import AsyncExitStack
from qasync import QEventLoop
from distiller_cm5_python.utils.logger import logger
from distiller_cm5_python.utils.config import EINK_ENABLED, EINK_CAPTURE_INTERVAL, EINK_BUFFER_SIZE, EINK_DITHERING_ENABLED
import asyncio
import os
import sys
import signal
from concurrent.futures import ThreadPoolExecutor
import atexit


class App:
    def __init__(self):
        """Initialize the Qt application and QML engine."""
        # Register a global exit handler at process exit
        atexit.register(self._emergency_exit_handler)
        
        # Set platform to offscreen before creating QApplication if E-Ink is enabled
        if EINK_ENABLED:
            os.environ["QT_QPA_PLATFORM"] = "offscreen"
            
        self.app = QApplication(sys.argv)
        self.app.setApplicationName("PamirAI Assistant")
        self.app.setOrganizationName("PamirAI Inc")

        # Set up the event loop
        self.loop = QEventLoop(self.app)
        asyncio.set_event_loop(self.loop)
        
        # For executing blocking operations
        self.executor = ThreadPoolExecutor(max_workers=3)
        
        # Create QML engine
        self.engine = QQmlApplicationEngine()

        # Create the MCP client bridge and app info manager
        self.bridge = MCPClientBridge()
        self.app_info = AppInfoManager()

        # E-Ink Initialization
        self.eink_renderer = None
        self.eink_bridge = None
        self._eink_initialized = False
        
        # Shutdown control
        self._shutdown_in_progress = False
        self._shutdown_timeout = 5000  # milliseconds
        self._shutdown_timer = QTimer(self.app)
        self._shutdown_timer.setSingleShot(True)
        self._shutdown_timer.timeout.connect(self._force_quit)
        
        # Exit stack for managed resource cleanup
        self.exit_stack = AsyncExitStack()
        
        # Connect signal to handle application quit
        self.app.aboutToQuit.connect(self._on_about_to_quit)
        
        # Set up signal handlers for graceful shutdown on system signals
        self._setup_signal_handlers()

    async def initialize(self):
        """Initialize the application."""
        # Register the bridge object with QML
        root_context = self.engine.rootContext()
        if root_context is None:
            logger.error("Failed to get QML root context")
            raise RuntimeError("Failed to get QML root context")

        # Initialize the bridge first
        logger.info("Initializing bridge...")
        await self.bridge.initialize()
        logger.info("Bridge initialized successfully")

        # Now register the initialized bridge with QML
        root_context.setContextProperty("bridge", self.bridge)
        root_context.setContextProperty("AppInfo", self.app_info)

        # Get the directory containing the QML files
        current_dir = os.path.dirname(os.path.abspath(__file__))

        # Set import paths for QML modules
        qml_path = os.path.join(current_dir)
        self.engine.addImportPath(qml_path)

        # Find the main.qml file
        qml_file = os.path.join(current_dir, "main.qml")

        if not os.path.exists(qml_file):
            logger.error(f"QML file not found: {qml_file}")
            raise FileNotFoundError(f"QML file not found: {qml_file}")

        # Make sure Qt can find its resources
        qt_conf_path = os.path.join(current_dir, "qt.conf")
        if not os.path.exists(qt_conf_path):
            # Create a minimal qt.conf if it doesn't exist
            with open(qt_conf_path, "w") as f:
                f.write("[Paths]\nPrefix=.\n")

        # Signal to QML that the bridge is ready
        self.bridge.setReady(True)
        
        # Load the QML file
        url = QUrl.fromLocalFile(qml_file)
        self.engine.load(url)

        # Wait for the QML to load
        await asyncio.sleep(0.1)

        # Check if the QML was loaded successfully
        if not self.engine.rootObjects():
            logger.error("Failed to load QML")
            raise RuntimeError("Failed to load QML")

        if EINK_ENABLED:
            # E-Ink Initialization Call
            self._init_eink_renderer()

        logger.info("Application initialized successfully")

    async def run(self):
        """Run the application with async event loop."""
        try:
            # Initialize the application
            await self.initialize()

            # Prepare exit stack for resource management
            await self.exit_stack.enter_async_context(self)  # Use this class as an async context manager
            
            # Run the event loop
            return self.loop.run_forever()
            
        except Exception as e:
            logger.error(f"Error running application: {e}", exc_info=True)
            await self._cleanup()
            return 1  # Return error code
    
    async def __aenter__(self):
        """Enter the async context manager."""
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Exit the async context manager, ensuring cleanup."""
        await self._cleanup()
        return False  # Don't suppress exceptions
    
    def _setup_signal_handlers(self):
        """Set up signal handlers for graceful shutdown."""
        for sig in (signal.SIGINT, signal.SIGTERM):
            self.loop.add_signal_handler(
                sig, lambda sig=sig: asyncio.create_task(self._handle_signal(sig))
            )
        
    async def _handle_signal(self, sig):
        """Handle system signal gracefully."""
        logger.info(f"Received signal {sig.name}, shutting down gracefully")
        await self._initiate_shutdown()
        
    def _on_about_to_quit(self):
        """Handle Qt's aboutToQuit signal."""
        # Force quit immediately - this is the most reliable approach
        os._exit(0)

    async def _initiate_shutdown(self):
        """Initiate the shutdown sequence."""
        if self._shutdown_in_progress:
            logger.debug("Shutdown already in progress, ignoring additional request")
            return
            
        self._shutdown_in_progress = True
        logger.info("Initiating application shutdown")
        
        # Let the bridge know about the shutdown first
        try:
            if self.bridge:
                self.bridge.shutdown()
        except Exception as e:
            logger.error(f"Error during bridge shutdown notification: {e}", exc_info=True)
        
        # Start the full cleanup
        await self._cleanup()
        
        # Force application exit after cleanup
        # This is a guaranteed exit mechanism
        os._exit(0)

    async def _cleanup(self):
        """Clean up all resources."""
        if not hasattr(self, 'loop') or not self.loop:
            return  # Already cleaned up or not initialized
            
        logger.info("Performing application cleanup")
        
        try:
            # Clean up the bridge
            if self.bridge:
                try:
                    # Set a timeout for bridge cleanup
                    await asyncio.wait_for(self.bridge.cleanup(), timeout=3.0)
                except asyncio.TimeoutError:
                    logger.warning("Bridge cleanup timed out")
                except Exception as e:
                    logger.error(f"Error during bridge cleanup: {e}", exc_info=True)
            
            # Clean up E-Ink resources
            self._cleanup_eink()
                
            # Shut down the thread pool
            self.executor.shutdown(wait=False)
                
            # Cancel all running tasks
            tasks = [t for t in asyncio.all_tasks(self.loop) if t is not asyncio.current_task()]
            if tasks:
                logger.info(f"Cancelling {len(tasks)} pending tasks")
                for task in tasks:
                    task.cancel()
                
                # Wait for tasks to acknowledge cancellation
                try:
                    await asyncio.wait_for(asyncio.gather(*tasks, return_exceptions=True), timeout=2.0)
                except asyncio.TimeoutError:
                    logger.warning("Some tasks did not cancel in time")
                    
        except Exception as e:
            logger.error(f"Error during application cleanup: {e}", exc_info=True)
        finally:
            # Make sure we stop the force quit timer if it's running
            if self._shutdown_timer.isActive():
                self._shutdown_timer.stop()
                
            # Exit the application properly
            if self.app:
                # Use the executor to call quit() to avoid potential deadlocks
                try:
                    asyncio.run_coroutine_threadsafe(
                        self.loop.run_in_executor(None, self.app.quit),
                        self.loop
                    )
                except Exception:
                    # If that fails, try to quit directly
                    try:
                        self.app.quit()
                    except Exception as e:
                        logger.error(f"Error quitting application: {e}", exc_info=True)
            
            # Close the event loop if it exists and is open
            if self.loop and not self.loop.is_closed():
                try:
                    self.loop.close()
                except Exception as e:
                    logger.error(f"Error closing event loop: {e}", exc_info=True)
    
    def _force_quit(self):
        """Force quit the application if normal shutdown takes too long."""
        logger.warning("Shutdown timeout reached, forcing application to exit")
        # Try to do minimal cleanup
        try:
            self.executor.shutdown(wait=False)
        except Exception:
            pass
        
        # Force exit with no delay
        os._exit(0)

    def _cleanup_eink(self):
        """Clean up E-Ink resources safely."""
        if not self._eink_initialized:
            return

        try:
            # Stop the E-Ink renderer if active
            if self.eink_renderer:
                self.eink_renderer.stop()
                logger.info("E-Ink renderer stopped")
                self.eink_renderer = None

            # Clean up e-ink bridge if active
            if self.eink_bridge:
                self.eink_bridge.cleanup()
                logger.info("E-Ink bridge cleaned up")
                self.eink_bridge = None
                
            self._eink_initialized = False
        except Exception as e:
            logger.error(f"Error during E-Ink cleanup: {e}", exc_info=True)

    # E-Ink Methods
    def _init_eink_renderer(self):
        """Initialize the E-Ink renderer."""
        if not EINK_ENABLED:
            logger.info("E-Ink display mode disabled in configuration")
            return

        logger.info("E-Ink display mode enabled from configuration")

        try:
            # Import E-Ink related classes only when needed
            from distiller_cm5_python.client.ui.bridge.EInkRenderer import EInkRenderer
            from distiller_cm5_python.client.ui.bridge.EInkRendererBridge import EInkRendererBridge

            # Get configuration values 
            capture_interval = EINK_CAPTURE_INTERVAL
            buffer_size = EINK_BUFFER_SIZE
            dithering_enabled = EINK_DITHERING_ENABLED

            logger.debug(f"E-Ink config: interval={capture_interval}ms, buffer={buffer_size}, dithering={dithering_enabled}")

            # First initialize the e-ink bridge that connects to the hardware
            self.eink_bridge = EInkRendererBridge(parent=self.app)
            init_success = self.eink_bridge.initialize()

            if not init_success:
                logger.error("Failed to initialize e-ink bridge")
                self.eink_bridge = None
                return False

            # Configure dithering
            self.eink_bridge.set_dithering(dithering_enabled)

            # Create the renderer instance
            self.eink_renderer = EInkRenderer(
                parent=self.app,
                capture_interval=capture_interval,
                buffer_size=buffer_size
            )

            # Connect frameReady signal
            self.eink_renderer.frameReady.connect(self._handle_eink_frame)

            # Start capturing frames
            self.eink_renderer.start()
            logger.info(f"E-Ink renderer initialized with {capture_interval}ms interval")

            # Mark as successfully initialized
            self._eink_initialized = True
            return True

        except ImportError as e:
            logger.error(f"E-Ink modules not available: {e}")
            logger.warning("Continuing without E-Ink support - modules not available")
            return False
        except Exception as e:
            logger.error(f"Error initializing E-Ink renderer: {e}", exc_info=True)
            # Clean up resources on failure
            if self.eink_bridge:
                self.eink_bridge.cleanup()
                self.eink_bridge = None
            self.eink_renderer = None
            return False

    def _handle_eink_frame(self, frame_data, width, height):
        """
        Handle a new frame from the E-Ink renderer.
        Forwards the frame to the e-ink bridge for display.
        """
        # logger.debug(f"E-Ink frame ready: {width}x{height}, {len(frame_data)} bytes") # Potentially noisy

        # Only process if E-Ink is enabled and initialized
        if not EINK_ENABLED or not self._eink_initialized:
            return

        # Forward the frame to the e-ink bridge if available
        if self.eink_bridge and self.eink_bridge.initialized:
            self.eink_bridge.handle_frame(frame_data, width, height)
        # else: # Avoid logging warning spam if bridge is intentionally disabled/not ready
            # logger.warning("E-Ink bridge not available or not initialized")

    def _emergency_exit_handler(self):
        """Emergency exit handler registered with atexit.
        This ensures we exit even if all other mechanisms fail."""
        logger.warning("Emergency exit handler called - forcing process exit")
        try:
            # Make one final attempt to flush logs
            import logging
            logging.shutdown()
        except:
            pass
        
        # Force exit at the process level
        os._exit(0)


if __name__ == "__main__":
    # Add a failsafe to ensure the application exits after a maximum runtime
    # This will force quit even if all other mechanisms fail
    import threading
    threading.Timer(3600, lambda: os._exit(0)).start()  # Force exit after 1 hour max
    
    # Add signal handler for more immediate termination
    def force_exit_handler(signum):
        logger.warning(f"Received signal {signum}, forcing immediate exit")
        os._exit(0)
    
    import signal
    signal.signal(signal.SIGINT, force_exit_handler)
    signal.signal(signal.SIGTERM, force_exit_handler)
    
    try:
        app = App()
        exit_code = asyncio.run(app.run())
        # Ensure we exit with the right code
        sys.exit(exit_code)
    except Exception as e:
        logger.critical(f"Fatal error in app: {e}", exc_info=True)
        # Force exit on unhandled exceptions
        os._exit(1)
    finally:
        # Ultimate fallback - force exit if we somehow reach here
        os._exit(0)
