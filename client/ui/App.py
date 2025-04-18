# pyright: reportArgumentType=false
from PyQt6.QtCore import QUrl
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtWidgets import QApplication
from client.ui.AppInfoManager import AppInfoManager
from client.ui.bridge.MCPClientBridge import MCPClientBridge
from contextlib import AsyncExitStack
from qasync import QEventLoop
from utils.logger import logger
import asyncio
import os
import sys


class App:
    def __init__(self):
        """Initialize the Qt application and QML engine."""
        self.app = QApplication(sys.argv)
        self.app.setApplicationName("PamirAI Assistant")
        self.app.setOrganizationName("PamirAI Inc")

        # Set up the event loop
        self.loop = QEventLoop(self.app)
        asyncio.set_event_loop(self.loop)

        # Create QML engine
        self.engine = QQmlApplicationEngine()

        # Create the MCP client bridge and app info manager
        self.bridge = MCPClientBridge()
        self.app_info = AppInfoManager()

        # Connect signal to handle application quit
        self.app.aboutToQuit.connect(self.handle_quit)

    async def initialize(self):
        """Initialize the application."""
        # Register the bridge object with QML
        root_context = self.engine.rootContext()
        if root_context is None:
            logger.error("Failed to get QML root context")
            raise RuntimeError("Failed to get QML root context")

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

        # Create source URL from file path
        url = QUrl.fromLocalFile(qml_file)

        # Make sure Qt can find its resources
        qt_conf_path = os.path.join(current_dir, "qt.conf")
        if not os.path.exists(qt_conf_path):
            # Create a minimal qt.conf if it doesn't exist
            with open(qt_conf_path, "w") as f:
                f.write("[Paths]\nPrefix=.\n")

        # Load the QML file
        self.engine.load(url)

        # Wait for the QML to load
        await asyncio.sleep(0.1)

        # Check if the QML was loaded successfully
        if not self.engine.rootObjects():
            logger.error("Failed to load QML")
            raise RuntimeError("Failed to load QML")

        # Initialize the bridge
        await self.bridge.initialize()

        logger.info("Application initialized successfully")

    async def run(self):
        """Run the application with async event loop."""
        try:
            # Initialize the application
            await self.initialize()

            # Use AsyncExitStack for resource management
            async with AsyncExitStack() as exit_stack:
                # Register cleanup callbacks if needed
                exit_stack.push_async_callback(self._cleanup_resources)

                # Schedule application execution
                run_app_task = asyncio.create_task(self.loop.run_forever())

                # Wait for the application to exit
                try:
                    await run_app_task
                except asyncio.CancelledError:
                    logger.info("Application task cancelled")

                # The AsyncExitStack's context manager will handle cleanup
        except Exception as e:
            logger.error(f"Error running application: {e}", exc_info=True)
            raise
        finally:
            # Ensure we exit cleanly
            if hasattr(self, "app") and self.app:
                self.app.quit()

            # Return exit code
            logger.info("Application exited")
            return 0

    async def _cleanup_resources(self):
        """Cleanup resources registered with exit_stack."""
        logger.info("Cleaning up resources from exit stack")
        try:
            # Ensure the bridge is cleaned up
            if hasattr(self, "bridge"):
                await self.bridge.cleanup()
        except Exception as e:
            logger.error(f"Error during resource cleanup: {e}", exc_info=True)
        finally:
            # Close the event loop if it exists and is open
            if hasattr(self, "loop") and self.loop and not self.loop.is_closed():
                self.loop.close()

    def handle_quit(self):
        """Handle application quit event."""
        logger.info("Application quit requested")

        # Schedule bridge shutdown
        try:
            self.bridge.shutdown()
        except Exception as e:
            logger.error(f"Error during shutdown: {e}", exc_info=True)
