import Components 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

ApplicationWindow {
    id: mainWindow

    // Cache for theme setting to avoid repeated bridge calls
    property bool themeCached: false
    property bool cachedDarkMode: false

    visible: true
    width: 240
    height: 416
    title: AppInfo.appName
    font: FontManager.normal
    
    // Update the FontManager primaryFontFamily when the app loads
    Component.onCompleted: {
        // Use the loaded font in the components
        if (jetBrainsMono.status == FontLoader.Ready)
            FontManager.primaryFontFamily = jetBrainsMono.name;

        // Set initial focus to key handler
        keyHandler.forceActiveFocus();
    }
    
    // Handle application shutdown
    onClosing: function(closeEvent) {
        // No bridge available or not ready, just accept the close event
        closeEvent.accepted = false;
        if (bridge && bridge.ready)
            bridge.shutdownApplication(false);
        else
            closeEvent.accepted = true;
    }

    // Dedicated key handler that stays on top of everything
    FocusScope {
        id: keyHandler

        anchors.fill: parent
        focus: true
        z: 2000 // Make sure it's above everything else
        Component.onCompleted: {
            forceActiveFocus();
        }

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
                            if (FocusManager.scrollTargetItem.scrollModeChanged)
                                FocusManager.scrollTargetItem.scrollModeChanged(false);

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
                if (!activeFocus)
                    forceActiveFocus();
            }
        }

        // Timer for focus management
        Timer {
            interval: 500
            running: true
            repeat: true
            onTriggered: {
                if (!keyHandler.activeFocus)
                    keyHandler.forceActiveFocus();
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
            if (FocusManager.scrollTargetItem)
                FocusManager.scrollTargetItem.scrollModeActive = false;
        }
    }

    // Connect to the bridge ready signal
    Connections {
        function onBridgeReady() {
            // Use the ThemeManager's centralized theme caching
            ThemeManager.initializeTheme();
        }

        target: bridge
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

    // Main content - single VoiceAssistantPage
    VoiceAssistantPage {
        id: voiceAssistantPage
        anchors.fill: parent
        
        Component.onCompleted: {
            if (typeof collectFocusItems === "function")
                collectFocusItems();
                
            // Ensure key handler has focus
            keyHandler.forceActiveFocus();
        }
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
                        topPadding: ThemeManager.paddingSmall
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
        function onErrorOccurred(errorMessage) {
            // Show global error messages only for severe errors
            if (errorMessage.toLowerCase().includes("critical") || errorMessage.toLowerCase().includes("fatal") || errorMessage.toLowerCase().includes("restart"))
                globalToast.showMessage("Error: " + errorMessage, 5000);
        }

        target: bridge
    }

    // Background
    background: Rectangle {
        color: ThemeManager.backgroundColor
    }
}
