# pyright: reportArgumentType=false
from PyQt6.QtCore import QUrl, QTimer, Qt, QObject, pyqtSignal, pyqtSlot
from PyQt6.QtGui import QKeyEvent
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtWidgets import QApplication
from contextlib import AsyncExitStack
import logging # Import standard logging
import sys # Import sys
from distiller_cm5_python.client.ui.display_config import config
from distiller_cm5_python.client.ui.AppInfoManager import AppInfoManager
from distiller_cm5_python.client.ui.bridge.MCPClientBridge import MCPClientBridge
from distiller_cm5_python.utils.config import LOGGING_LEVEL # Import LOGGING_LEVEL
from distiller_cm5_sdk.whisper import Whisper # Assuming whisper.py is in this path
from qasync import QEventLoop
import asyncio
import os
import signal
from concurrent.futures import ThreadPoolExecutor
import atexit
import threading # Add threading import
import errno # Add errno import
import select # Add standard select import

# Try importing evdev
try:
    import evdev
    from evdev import InputDevice, categorize, ecodes, util
    EVDEV_AVAILABLE = True
except ImportError:
    EVDEV_AVAILABLE = False
    print("WARNING: python-evdev library not found. Hardware button input will not work.")
    print("Install it using: pip install python-evdev")

# --- Setup Logging EARLY ---
logger = logging.getLogger(__name__)


if config["display"]["eink_enabled"]:
    from distiller_cm5_python.client.ui.bridge.EInkRenderer import EInkRenderer
    from distiller_cm5_python.client.ui.bridge.EInkRendererBridge import EInkRendererBridge
    # Remove evdev import
    # import evdev


class App(QObject): # Inherit from QObject to support signals/slots
    # --- Signals ---
    transcriptionUpdate = pyqtSignal(str, arguments=['transcription'])
    transcriptionComplete = pyqtSignal(str, arguments=['full_text'])
    recordingStateChanged = pyqtSignal(bool, arguments=['is_recording'])
    recordingError = pyqtSignal(str, arguments=['error_message']) # New signal for errors
    # --- End Signals ---

    def __init__(self):
        QObject.__init__(self)
        """Initialize the Qt application and QML engine."""
        # Register a global exit handler at process exit
        atexit.register(self._emergency_exit_handler)

        # Set platform to offscreen before creating QApplication if E-Ink is enabled
        # TODO: Make this conditional based on configuration
        if config["display"]["eink_enabled"]:
            # Import E-Ink Renderer and Bridge
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
       
        # Shutdown control
        self._shutdown_in_progress = False
        self._shutdown_timeout = 5000  # milliseconds
        self._shutdown_timer = QTimer(self.app)
        self._shutdown_timer.setSingleShot(True)
        self._shutdown_timer.timeout.connect(self._force_quit)
        
        # Exit stack for managed resource cleanup
        self.exit_stack = AsyncExitStack()
        
        self._eink_initialized = False
        # Remove evdev task handle
        # self._input_monitor_task = None # Task handle for input monitoring

        # Connect signal to handle application quit
        self.app.aboutToQuit.connect(self._on_about_to_quit)
        
        # Set up signal handlers for graceful shutdown on system signals
        self._setup_signal_handlers()

        # --- Whisper Initialization ---
        # TODO: Load model path/size from config if needed
        self.whisper = Whisper() 
        self._is_actively_recording = False # Separate state for UI feedback
        self._transcription_task = None
        # --- End Whisper Initialization ---

        # Add main_window attribute initialization
        self.main_window = None

        # --- Input Device Monitoring ---
        self._input_device_path = "/dev/input/event1" # TODO: Make configurable?
        self._input_thread = None
        self._stop_input_thread = threading.Event()
        # --- End Input Device Monitoring ---

    def _find_input_device_path(self, device_name: str) -> str | None:
        """Find the event device path for a given device name."""
        if not EVDEV_AVAILABLE:
            logger.error("evdev library not available, cannot search for input devices.")
            return None

        devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
        for device in devices:
            logger.debug(f"Checking device: {device.path}, Name: {device.name}")
            if device.name == device_name:
                logger.info(f"Found device '{device_name}' at path: {device.path}")
                return device.path
        
        logger.warning(f"Could not find input device with name: '{device_name}'")
        return None

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
        
        # Set a reference to this App instance in the bridge
        self.bridge.set_app_instance(self)
        
        logger.info("Bridge initialized successfully")
        
        # Now register the initialized bridge with QML
        root_context.setContextProperty("bridge", self.bridge)
        root_context.setContextProperty("AppInfo", self.app_info)
        # Expose App instance to QML for signals/slots
        root_context.setContextProperty("AppController", self) 

        # Set display dimensions from config
        self._set_display_dimensions()

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
                f.write("[Paths]\\nPrefix=.\\n")

        # Signal to QML that the bridge is ready
        self.bridge.setReady(True)
        
        # Load the QML file
        url = QUrl.fromLocalFile(qml_file)
        self.engine.load(url)

        # Wait for the QML to load
        await asyncio.sleep(0.1)

        # Check if the QML was loaded successfully and get the main window
        root_objects = self.engine.rootObjects()
        if not root_objects:
            logger.error("Failed to load QML or find root objects")
            raise RuntimeError("Failed to load QML")
        else:
             self.main_window = root_objects[0] # Assign main_window HERE
             logger.info(f"QML loaded successfully. Main window: {self.main_window}")

        if config.get("display").get("eink_enabled"):
            # Apply fixed size constraints to the root window after loading
            self._apply_window_constraints()
            # E-Ink Initialization Call
            self._init_eink_renderer()
            self._eink_initialized = True
            
            # --- Start Input Device Monitor ---
            # Add a small delay to allow QML/FocusManager to potentially settle
            await asyncio.sleep(0.2) # Wait 200ms
            logger.info("Proceeding to start input monitor after short delay.")
            
            if EVDEV_AVAILABLE and self.main_window:
                self._start_input_monitor()
            elif not EVDEV_AVAILABLE:
                logger.warning("evdev library not available, cannot monitor input device.")
            elif not self.main_window:
                logger.error("Cannot start input monitor: Main window not available.")
            # --- End Input Device Monitor ---

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

    def _cleanup_eink(self):
        """Cleanup E-Ink resources."""

        try:
            # Stop the E-Ink renderer if active
            if self.eink_renderer:
                self.eink_renderer.stop()
                logger.info("E-Ink renderer stopped.")
                self.eink_renderer = None

            # Clean up e-ink bridge if active
            if self.eink_bridge:
                self.eink_bridge.cleanup()
                logger.info("E-Ink bridge cleaned up.")
                self.eink_bridge = None

            self._eink_initialized = False
        except Exception as e:
            logger.error(f"Error during E-Ink cleanup: {e}", exc_info=True)
            # Ensure we clean up even if an error occurs
            if self.eink_bridge:
                self.eink_bridge.cleanup()
                self.eink_bridge = None
            self.eink_renderer = None

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

            # E-Ink Cleanup
            if config.get("display").get("eink_enabled"):
                self._cleanup_eink()

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
            # --- Stop Input Monitor ---
            self._stop_input_monitor()
            # --- End Stop Input Monitor ---
            
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

    def handle_quit(self):
        """Handle application quit signal."""
        logger.info("Application quit requested")
        # Stop the asyncio event loop when the Qt application quits
        if hasattr(self, "loop") and self.loop.is_running():
            self.loop.stop()

        # Clean up the E-Ink renderer if it exists
        if config.get("display").get("eink_enabled"):
            self._cleanup_eink()
            
        # Disconnect SAM
        if self.sam:
            self.sam.disconnect()
            self.sam = None

        # Schedule bridge shutdown
        try:
            self.bridge.shutdown()
        except Exception as e:
            logger.error(f"Error during shutdown: {e}", exc_info=True)

    def _set_display_dimensions(self):
        """Set display dimensions from the config file as context properties for QML."""
        # Get width and height from config or use defaults
        width = int(config.get("display").get("width") or 240)
        height = int(config.get("display").get("height") or 416)
        
        # Set as context properties for QML
        rc = self.engine.rootContext()
        rc.setContextProperty("configWidth", width)
        rc.setContextProperty("configHeight", height)
        
        logger.info(f"Set display dimensions from config: {width}x{height}")


    def _apply_window_constraints(self):
        """Apply fixed size constraints to the main window after QML is loaded."""
        # Get display dimensions from config
        width = int(config.get("display").get("width") or 240)
        height = int(config.get("display").get("height") or 416)
        
        # Find the root window object - use self.main_window if already assigned
        main_window = self.main_window
        if not main_window:
            root_objects = self.engine.rootObjects()
            if not root_objects:
                logger.error("No root objects found to apply size constraints")
                return
            main_window = root_objects[0] # Assign here if not already done

        if not main_window:
            logger.error("Main window object is still None, cannot apply constraints")
            return
            
        try:
            # Set fixed size - use QML properties for ApplicationWindow
            main_window.setProperty("width", width)
            main_window.setProperty("height", height)
            
            # These may or may not be available, depending on the window type
            try:
                main_window.setProperty("minimumWidth", width)
                main_window.setProperty("maximumWidth", width)
                main_window.setProperty("minimumHeight", height)
                main_window.setProperty("maximumHeight", height)
                
                # For ApplicationWindow, we set the flag in QML directly
                # So we don't need to do main_window.setFlags() here
            except Exception as e:
                logger.warning(f"Could not set all window constraints: {e}")
                
            logger.info(f"Applied fixed size constraints: {width}x{height}")
        except Exception as e:
            logger.error(f"Error applying window constraints: {e}", exc_info=True)
    

    # E-Ink Methods
    def _init_eink_renderer(self):
        """Initialize the E-Ink renderer."""
        # logger.info(f"config: {config}")

        if not config.get("display").get("eink_enabled"):
            logger.warning("E-Ink display mode disabled in configuration")
            return 

        # Check if e-ink mode is enabled in config
        eink_enabled = config.get("display").get("eink_enabled")
        
        if not eink_enabled:
            logger.warning("E-Ink display mode disabled in configuration")
            return

        logger.info("E-Ink display mode enabled")

        # Get configuration for e-ink renderer with optimized defaults
        capture_interval = config.get("display").get("eink_refresh_interval", 1000)  # Default to 1000ms
        buffer_size = config.get("display").get("eink_buffer_size", 1)  # Default to 1 for memory optimization
        dithering_enabled = config.get("display").get("eink_dithering_enabled", True)
        dithering_method = config.get("display").get("eink_dithering_method", 1)  # 1=Floyd-Steinberg, 2=Ordered
        adaptive_capture = config.get("display").get("eink_adaptive_capture", True)  # Enable adaptive refresh
        threshold = config.get("display").get("eink_threshold", 128)  # Threshold for black/white conversion
        
        # Get B&W conversion details
        bw_config = config.get("display").get("eink_bw_conversion", {})
        bw_method = bw_config.get("method", 1)
        bw_method_name = "Simple Threshold" if bw_method == 1 else "Adaptive Threshold"
        use_gamma = bw_config.get("use_gamma", False)
        gamma_value = bw_config.get("gamma_value", 0.7) if use_gamma else None

        try:
            # First initialize the e-ink bridge that connects to the hardware
            self.eink_bridge = EInkRendererBridge(parent=self.app)
            init_success = self.eink_bridge.initialize()

            if not init_success:
                logger.error("Failed to initialize e-ink bridge")
                self.eink_bridge = None
                return False

            # Configure dithering with method
            self.eink_bridge.set_dithering(dithering_enabled, dithering_method)

            # Create the renderer instance with optimized settings
            self.eink_renderer = EInkRenderer(
                parent=self.app,
                capture_interval=capture_interval,
                buffer_size=buffer_size
            )
            
            # Set adaptive capture mode
            self.eink_renderer.set_adaptive_capture(adaptive_capture)

            # Connect the signal to an async lambda that schedules the handler
            # Use asyncio.create_task to run the async handler without blocking the signal emission
            self.eink_renderer.frameReady.connect(
                lambda data, w, h: asyncio.create_task(self._handle_eink_frame(data, w, h))
            )
            
            # Start capturing frames
            self.eink_renderer.start()
            logger.info(f"E-Ink renderer initialized with {capture_interval}ms interval, "
                       f"buffer_size={buffer_size}, dithering={'enabled' if dithering_enabled else 'disabled'} "
                       f"(method={dithering_method}), threshold={threshold}, "
                       f"B&W method={bw_method_name}" + 
                       (f" with gamma={gamma_value}" if use_gamma else "") +
                       f", adaptive_capture={'enabled' if adaptive_capture else 'disabled'}")

            self._eink_initialized = True
            return True

        except Exception as e:
            logger.error(f"Error initializing E-Ink renderer: {e}", exc_info=True)
            # Clean up resources on failure
            if self.eink_bridge:
                self.eink_bridge.cleanup()
                self.eink_bridge = None
            self.eink_renderer = None
            return False


    async def _handle_eink_frame(self, frame_data, width, height):
        """
        Handle a new frame from the E-Ink renderer asynchronously.
        This method forwards the frame to the e-ink bridge for display in a separate thread.
        
        Args:
            frame_data: The binary data for the frame
            width: The width of the frame
            height: The height of the frame
        """
        logger.debug(f"E-Ink frame received: {width}x{height}, {len(frame_data)} bytes. Offloading to bridge.")
        
        # Forward the frame to the e-ink bridge if available, using a separate thread
        if self.eink_bridge and self.eink_bridge.initialized:
            try:
                # Run the potentially blocking bridge call in a separate thread
                await asyncio.to_thread(
                    self.eink_bridge.handle_frame, frame_data, width, height
                )
                logger.debug("E-Ink frame successfully handled by bridge.")
            except Exception as e:
                 logger.error(f"Error calling eink_bridge.handle_frame in thread: {e}", exc_info=True)
        else:
            logger.warning("E-Ink bridge not available or not initialized, skipping frame handling.")

    def _emergency_exit_handler(self):
        """Emergency exit handler registered with atexit.
        This ensures we exit even if all other mechanisms fail."""
        logger.warning("Emergency exit handler called - forcing process exit")
        try:
            # Disconnect SAM if possible
            if self.sam:
                self.sam.disconnect()
        except Exception:
            pass # Ignore errors during emergency exit
        try:
            # Make one final attempt to flush logs
            import logging
            logging.shutdown()
        except:
            pass
        
        # Force exit at the process level
        os._exit(0)

    # --- Whisper Slots ---
    @pyqtSlot()
    def startRecording(self):
        if self._is_actively_recording:
            logger.warning("Already recording.")
            return
        if self.whisper.start_recording():
            self._is_actively_recording = True
            self.recordingStateChanged.emit(True)
            # Also forward to the bridge if it exists
            if hasattr(self, "bridge") and self.bridge:
                self.bridge.recordingStateChanged.emit(True)
            logger.info("UI Recording Started")
        else:
            logger.error("Failed to start Whisper recording")

    MIN_AUDIO_BYTES_THRESHOLD = 16000 # Approx 0.5 seconds at 16kHz/16bit/mono

    @pyqtSlot()
    def stopAndTranscribe(self):
        if not self._is_actively_recording:
            logger.warning("Not recording.")
            return

        audio_data = self.whisper.stop_recording()
        self._is_actively_recording = False
        self.recordingStateChanged.emit(False)
        # Also forward to the bridge if it exists
        if hasattr(self, "bridge") and self.bridge:
            self.bridge.recordingStateChanged.emit(False)
        logger.info("UI Recording Stopped")

        # Check if audio data is long enough
        if not audio_data or len(audio_data) < self.MIN_AUDIO_BYTES_THRESHOLD:
            logger.warning(f"Audio data too short ({len(audio_data) if audio_data else 0} bytes). Minimum required: {self.MIN_AUDIO_BYTES_THRESHOLD}. Skipping transcription.")
            self.recordingError.emit("Audio too short") # Emit error signal
            # Also forward to the bridge if it exists
            if hasattr(self, "bridge") and self.bridge:
                self.bridge.recordingError.emit("Audio too short")
            return # Stop processing here

        # If audio is long enough, proceed with transcription
        logger.info("Scheduling transcription...")
        # Run transcription in a separate thread to avoid blocking UI
        if self._transcription_task and not self._transcription_task.done():
                logger.warning("Previous transcription task still running. Skipping new one.")
                return

        self._transcription_task = asyncio.create_task(self._transcribe_audio_async(audio_data))


    async def _transcribe_audio_async(self, audio_data):
        """Run transcription in a separate thread and emit signals."""
        try:
            logger.info("Transcription task started.")
            # Use asyncio.to_thread for blocking I/O or CPU-bound tasks
            transcription_generator = await asyncio.to_thread(
                self.whisper.transcribe_buffer, audio_data
            )

            full_transcription = []
            for segment in transcription_generator:
                self.transcriptionUpdate.emit(segment)
                # Also forward to the bridge if it exists
                if hasattr(self, "bridge") and self.bridge:
                    self.bridge.transcriptionUpdate.emit(segment)
                full_transcription.append(segment)
                await asyncio.sleep(0) # Yield control briefly

            complete_text = " ".join(full_transcription)
            self.transcriptionComplete.emit(complete_text)
            # Also forward to the bridge if it exists
            if hasattr(self, "bridge") and self.bridge:
                self.bridge.transcriptionComplete.emit(complete_text)
            logger.info(f"Transcription task finished. Full text: {complete_text}")

        except Exception as e:
            logger.error(f"Error during transcription: {e}", exc_info=True)
            self.recordingError.emit("[Transcription Error]") # Use the new error signal
            # Also forward to the bridge if it exists
            if hasattr(self, "bridge") and self.bridge:
                self.bridge.recordingError.emit("[Transcription Error]") # Forward error signal
        finally:
            self._transcription_task = None # Clear task handle

    # --- E-Ink Trigger Slot ---
    @pyqtSlot()
    def triggerEinkUpdate(self):
        """Slot callable from QML to force an e-ink render update."""
        if self.eink_renderer and self._eink_initialized:
            logger.debug("QML triggered E-Ink update")
            self.eink_renderer.force_render_update()
        else:
            logger.warning("Attempted to trigger E-Ink update, but renderer is not ready.")
            
    # --- Input Device Monitoring Thread ---
    def _start_input_monitor(self):
        """Finds the input device and starts the monitoring thread."""
        if not EVDEV_AVAILABLE:
            logger.error("Cannot start input monitor: evdev library not available.")
            return
        if self._input_thread and self._input_thread.is_alive():
            logger.warning("Input monitor thread already running.")
            return

        # Find the device path dynamically
        target_device_name = "RP2040 Key Input" # Or make this configurable
        device_path = self._find_input_device_path(target_device_name)

        if not device_path:
            logger.error(f"Failed to find input device '{target_device_name}'. Cannot start monitor.")
            return
            
        self._stop_input_thread.clear()
        self._input_thread = threading.Thread(
            target=self._monitor_input_device,
            args=(device_path, self.main_window), # Pass the found path
            daemon=True # Allow app to exit even if this thread is stuck
        )
        self._input_thread.start()
        logger.info(f"Started input device monitor thread for {device_path}")

    def _monitor_input_device(self, device_path, target_window):
        """Monitors the specified input device and posts key events to the target window."""
        dev = None
        try:
            logger.info(f"Attempting to open input device: {device_path}")
            dev = InputDevice(device_path)
            # dev.grab() # Grab the device to prevent events going elsewhere
            logger.info(f"Successfully opened and grabbed input device: {dev.name}")
            
            key_map = {
                ecodes.KEY_UP: Qt.Key.Key_Up,
                ecodes.KEY_DOWN: Qt.Key.Key_Down,
                ecodes.KEY_ENTER: Qt.Key.Key_Enter, # Or Qt.Key_Return if needed
            }

            logger.info("Starting event read loop...")
            while not self._stop_input_thread.is_set():
                # Use blocking read with a timeout to allow checking the stop flag
                # Use standard select module on the device's file descriptor
                try:
                    r, w, x = select.select([dev.fd], [], [], 0.1) # 100ms timeout
                except select.error as e:
                    # Handle interrupted system call, e.g., by signals
                    if e.args[0] == errno.EINTR:
                        continue
                    else:
                        logger.error(f"Select error on input device {device_path}: {e}", exc_info=True)
                        break # Exit loop on other select errors
                
                if not r: # Timeout occurred, check stop flag and continue
                    continue
                    
                # Check if the file descriptor is the one we are waiting for
                if dev.fd in r:
                    try:
                        for event in dev.read(): # Read available events
                            if event.type == ecodes.EV_KEY:
                                # Only process key down events (value=1) for simplicity
                                # Or handle both press (1) and release (0) if needed
                                if event.value == 1: # Key press
                                    qt_key = key_map.get(event.code)
                                    if qt_key and target_window:
                                        logger.debug(f"Input Event: Code={event.code}, Mapped Qt Key={qt_key}")
                                        press_event = QKeyEvent(
                                            QKeyEvent.Type.KeyPress, 
                                            qt_key, 
                                            Qt.KeyboardModifier.NoModifier
                                        )
                                        QApplication.postEvent(target_window, press_event)
                                        logger.debug(f"Posted KeyPress {qt_key} to {target_window}")
                                        # If you need release events too:
                                        # release_event = QKeyEvent(
                                        #     QKeyEvent.Type.KeyRelease, 
                                        #     qt_key, 
                                        #     Qt.KeyboardModifier.NoModifier
                                        # )
                                        # QApplication.postEvent(target_window, release_event)
                                        # logger.debug(f"Posted KeyRelease {qt_key} to {target_window}")
                    except BlockingIOError:
                        # This can happen if select() returns but read() has no data yet
                        continue 
                    except OSError as e:
                        if e.errno == errno.ENODEV:
                            logger.error(f"Input device {device_path} disconnected. Stopping monitor.")
                            break # Exit the loop if device disconnects
                        else:
                            logger.error(f"Error reading from input device {device_path}: {e}", exc_info=True)
                            # Optionally add a delay before retrying
                            self._stop_input_thread.wait(1.0)
                    except Exception as e:
                         logger.error(f"Unexpected error in input monitor loop: {e}", exc_info=True)
                         # Add a delay before retrying to avoid tight loops on errors
                         self._stop_input_thread.wait(1.0)
                     
        except FileNotFoundError:
            logger.error(f"Input device not found: {device_path}")
        except PermissionError:
            logger.error(f"Permission denied for input device: {device_path}. Ensure user is in 'input' group.")
        except Exception as e:
            logger.error(f"Failed to initialize or monitor input device {device_path}: {e}", exc_info=True)
        finally:
            if dev:
                try:
                    dev.ungrab() # Release the device
                    dev.close()
                    logger.info(f"Ungrabbed and closed input device: {device_path}")
                except Exception as e:
                    logger.error(f"Error closing input device {device_path}: {e}")
            logger.info("Input device monitor thread finished.")
    # --- End Input Device Monitoring Thread ---

    def _stop_input_monitor(self):
        """Signals the input monitoring thread to stop and waits for it."""
        if self._input_thread and self._input_thread.is_alive():
            logger.info("Stopping input device monitor thread...")
            self._stop_input_thread.set()
            try:
                # Wait for the thread to finish, with a timeout
                self._input_thread.join(timeout=1.0)
                if self._input_thread.is_alive():
                    logger.warning("Input monitor thread did not stop gracefully within timeout.")
                else:
                    logger.info("Input monitor thread stopped.")
            except Exception as e:
                logger.error(f"Error stopping input monitor thread: {e}", exc_info=True)
        self._input_thread = None
        self._stop_input_thread.clear() # Reset event for potential restarts


if __name__ == "__main__":
    # Add a failsafe to ensure the application exits after a maximum runtime
    # This will force quit even if all other mechanisms fail
    import threading
    threading.Timer(3600, lambda: os._exit(0)).start()  # Force exit after 1 hour max
    
    # Add signal handler for more immediate termination
    def force_exit_handler(signum):
        logger.warning(f"Received signal {signum}, forcing immediate exit")
        os._exit(0)
    
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
