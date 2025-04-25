import Components 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

ApplicationWindow {
    id: mainWindow

    // Navigation function
    function pushSettingsPage() {
        stackView.push(settingsPageComponent);
    }

    visible: true
    width: 256
    height: 384
    title: AppInfo.appName
    font: FontManager.normal
    
    // Dedicated key handler that stays on top of everything
    FocusScope {
        id: keyHandler
        
        anchors.fill: parent
        focus: true
        z: 2000 // Make sure it's above everything else
        
        // Use this Item to capture all key events
        Item {
            anchors.fill: parent
            focus: true
            
            Keys.onPressed: function(event) {
                // Only handle navigation keys - UP, DOWN, and ENTER
                if (event.key === Qt.Key_Down) {
                    event.accepted = true;
                    FocusManager.moveFocusDown();
                } else if (event.key === Qt.Key_Up) {
                    event.accepted = true;
                    FocusManager.moveFocusUp();
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    event.accepted = true;
                    // If in scroll mode, exit it with ENTER key
                    if (FocusManager.scrollModeActive) {
                        FocusManager.exitScrollMode();
                        if (FocusManager.scrollTargetItem) {
                            // Force update the property first
                            FocusManager.scrollTargetItem.scrollModeActive = false;
                            
                            // Then trigger the signal if available
                            if (FocusManager.scrollTargetItem.scrollModeChanged) {
                                FocusManager.scrollTargetItem.scrollModeChanged(false);
                            }
                            
                            // Force a UI update by using a short timer
                            exitScrollModeTimer.start();
                        }
                    } else {
                        // Normal enter key handling
                        FocusManager.handleEnterKey();
                    }
                }
            }
            
            // Explicitly grab focus whenever anything else tries to take it
            onActiveFocusChanged: {
                if (!activeFocus) {
                    forceActiveFocus();
                }
            }
        }
        
        Component.onCompleted: {
            console.log("Key handler initialized");
            forceActiveFocus();
        }
        
        // More efficient timer for focus management
        Timer {
            interval: 500  // Increased from 200ms to 500ms to reduce CPU usage
            running: true
            repeat: true
            onTriggered: {
                if (!keyHandler.activeFocus) {
                    keyHandler.forceActiveFocus();
                }
            }
        }
    }
    
    // Timer to ensure the UI is updated when exiting scroll mode
    Timer {
        id: exitScrollModeTimer
        interval: 10
        repeat: false
        onTriggered: {
            // Force additional update for any target that might still be in scroll mode
            if (FocusManager.scrollTargetItem) {
                FocusManager.scrollTargetItem.scrollModeActive = false;
                console.log("Forced update of scroll mode state");
            }
        }
    }
    
    // Cache for theme setting to avoid repeated bridge calls
    property bool themeCached: false
    property bool cachedDarkMode: false
    
    // Connect to the bridge ready signal
    Connections {
        target: bridge
        
        function onBridgeReady() {
            // Use the ThemeManager's centralized theme caching
            ThemeManager.initializeTheme();
        }
    }
    
    // Update the FontManager primaryFontFamily when the app loads
    Component.onCompleted: {
        if (jetBrainsMono.status == FontLoader.Ready) {
            // Use the loaded font in the components
            FontManager.primaryFontFamily = jetBrainsMono.name;
        }
        
        // Set initial focus to key handler
        keyHandler.forceActiveFocus();
    }
    
    // Handle application shutdown
    onClosing: function(closeEvent) {
        closeEvent.accepted = false;
        if (bridge && bridge.ready) {
            bridge.shutdownApplication(false);
        } else {
            // No bridge available or not ready, just accept the close event
            closeEvent.accepted = true;
        }
    }
    
    // Function to handle application restart
    function restartApp() {
        if (bridge && bridge.ready) {
            // First disconnect from any server
            if (bridge.isConnected) {
                bridge.disconnectFromServer();
            }
            
            // Then shutdown with restart flag
            bridge.shutdownApplication(true);
        }
    }

    // Custom font
    FontLoader {
        id: jetBrainsMono

        source: "fonts/JetBrainsMonoNerdFont-Regular.ttf"
        onStatusChanged: {
            if (status == FontLoader.Ready)
                console.log("JetBrains Mono font loaded successfully");
        }
    }

    // Main content area - full width since we removed the navigation buttons
    StackView {
        id: stackView

        anchors.fill: parent
        initialItem: serverSelectionComponent
        
        // Monitor current page to handle transitions and focus resets
        onCurrentItemChanged: {
            // Ensure key handler has focus whenever the page changes
            keyHandler.forceActiveFocus();
            
            // If returning to VoiceAssistantPage, reset focus state
            if (currentItem && currentItem.resetFocusState) {
                // Delay to ensure components are fully loaded
                resetFocusStateTimer.start();
            }
        }
        
        // Timer to ensure components are loaded before resetting focus
        Timer {
            id: resetFocusStateTimer
            interval: 100
            repeat: false
            running: false
            
            onTriggered: {
                if (stackView.currentItem && stackView.currentItem.resetFocusState) {
                    stackView.currentItem.resetFocusState();
                    console.log("Focus state reset on page transition");
                }
            }
        }

        // Server Selection Page
        Component {
            id: serverSelectionComponent

            ServerSelectionPage {
                // Initialize focus items when component is loaded
                Component.onCompleted: {
                    if (typeof collectFocusItems === "function") {
                        collectFocusItems();
                    }
                    // Ensure key handler has focus
                    keyHandler.forceActiveFocus();
                }
                
                onServerSelected: function(serverPath) {
                    if (!bridge.ready) {
                        console.error("Bridge not ready, cannot connect to server");
                        // Display an error message to the user
                        globalToast.showMessage("Error: Application not fully initialized. Please restart.", 5000);
                        return;
                    }
                    
                    // Set the selected server and connect to it
                    bridge.setServerPath(serverPath);
                    
                    // This returns an error message if connection fails, or empty string on success
                    var connectionResult = bridge.connectToServer();
                    
                    if (connectionResult) {
                        // Connection failed, show error message
                        console.error("Connection failed: " + connectionResult);
                        globalToast.showMessage("Connection failed: " + connectionResult, 5000);
                        return;
                    }
                    
                    console.log("Connecting to server...");
                    
                    // Push the voice assistant page with a placeholder name
                    var voiceAssistantPage = stackView.push(voiceAssistantComponent);
                    
                    // Create and start the server name update timer
                    var serverNameUpdateTimer = serverNameUpdateTimerComponent.createObject(voiceAssistantPage, {
                        "targetPage": voiceAssistantPage
                    });
                    serverNameUpdateTimer.start();
                }
            }
        }
        
        // Timer component for updating server name
        Component {
            id: serverNameUpdateTimerComponent
            
            Timer {
                property var targetPage
                
                interval: 1000
                repeat: false
                running: false
                
                onTriggered: {
                    if (!bridge.ready) {
                        console.error("Bridge not ready in timer, cannot update server name");
                        destroy();
                        return;
                    }
                    
                    // Get the status message which should now contain the correct server name
                    var status = bridge.get_status();
                    console.log("Current status: " + status);
                    if (status.indexOf("Connected to") === 0) {
                        var extractedName = status.substring("Connected to ".length).trim();
                        if (extractedName) {
                            console.log("Setting server name to: " + extractedName);
                            targetPage.serverName = extractedName;
                        }
                    }
                    
                    // Destroy the timer after use
                    destroy();
                }
            }
        }

        // Voice Assistant Page
        Component {
            id: voiceAssistantComponent

            VoiceAssistantPage {
                // Initialize focus items when component is loaded
                Component.onCompleted: {
                    if (typeof collectFocusItems === "function") {
                        collectFocusItems();
                    }
                    // Ensure key handler has focus
                    keyHandler.forceActiveFocus();
                }
                
                onSelectNewServer: {
                    // Replace the current view with the server selection page
                    stackView.replace(serverSelectionComponent);
                    // Request servers again to refresh the list
                    if (bridge.ready) {
                        bridge.getAvailableServers();
                    }
                }
            }
        }

        // Settings Page
        Component {
            id: settingsPageComponent

            SettingsPage {
                // Initialize focus items when component is loaded
                Component.onCompleted: {
                    if (typeof collectFocusItems === "function") {
                        collectFocusItems();
                    }
                    // Ensure key handler has focus
                    keyHandler.forceActiveFocus();
                }
                
                onBackClicked: {
                    stackView.pop();
                }
            }
        }

        // No transitions for e-ink display
        pushEnter: null
        pushExit: null
        popEnter: null
        popExit: null
    }

    // E-ink optimized splash screen without animations
    Rectangle {
        id: splashScreen

        anchors.fill: parent
        color: ThemeManager.backgroundColor
        z: 1000

        // Create a container for better positioning
        Rectangle {
            id: splashContainer

            anchors.centerIn: parent
            width: parent.width * 0.8
            height: contentColumn.height
            color: "transparent"

            // Column layout for vertical alignment
            Column {
                id: contentColumn

                width: parent.width
                spacing: ThemeManager.spacingLarge

                // Logo with reduced size and nested in a nicely bordered container
                Rectangle {
                    id: logoContainer

                    width: 154
                    height: 154
                    color: ThemeManager.backgroundColor
                    border.color: ThemeManager.borderColor
                    border.width: ThemeManager.borderWidth
                    radius: width / 2
                    anchors.horizontalCenter: parent.horizontalCenter

                    OptimizedImage {
                        id: logoImage

                        source: ThemeManager.darkMode ? "images/pamir_logo_white.png" : "images/pamir_logo.png"
                        width: 150
                        height: 150
                        anchors.centerIn: parent
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 300
                        sourceSize.height: 300
                        fadeInDuration: 0 // No fade in animation
                    }
                }

                // Improved typography
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: ThemeManager.spacingSmall

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: AppInfo.appName.split(" ")[0]
                        color: ThemeManager.textColor
                        font.pixelSize: FontManager.fontSizeXLarge
                        font.bold: true
                        font.family: FontManager.primaryFontFamily
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: AppInfo.appName.split(" ").slice(1).join(" ")
                        color: ThemeManager.secondaryTextColor
                        font.pixelSize: FontManager.fontSizeMedium
                        font.family: FontManager.primaryFontFamily
                    }

                    // Version information
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: AppInfo.shortVersionString
                        color: ThemeManager.tertiaryTextColor
                        font.pixelSize: FontManager.fontSizeSmall
                        font.family: FontManager.primaryFontFamily
                        topPadding: 4
                    }
                }
            }
        }

        // Show splash for fixed time without animation
        Timer {
            interval: 1000
            running: true
            onTriggered: {
                splashScreen.visible = false;
            }
        }
    }

    // Background
    background: Rectangle {
        color: ThemeManager.backgroundColor
    }

    // Global toast message for application-wide errors
    MessageToast {
        id: globalToast
        
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        z: 1001 // Above everything, including the splash screen
    }
    
    // Handle global bridge errors
    Connections {
        target: bridge
        
        function onErrorOccurred(errorMessage) {
            // Show global error messages only for severe errors
            if (errorMessage.toLowerCase().includes("critical") || 
                errorMessage.toLowerCase().includes("fatal") ||
                errorMessage.toLowerCase().includes("restart")) {
                globalToast.showMessage("Error: " + errorMessage, 5000);
            }
        }
    }
}

