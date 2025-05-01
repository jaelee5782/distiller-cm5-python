import Components 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    // Dynamic hint text based on state
    // Any external components connecting to stateChanged can now connect to onAppStateChanged

    id: voiceInputArea

    // Properties
    property bool isListening: false
    property bool isProcessing: false
    property bool isConnected: true // Add new property for connection status
    property string transcribedText: ""
    property bool showStatusHint: true // Enable status hint by default
    // State management - define possible states
    property string appState: "idle"
    // Possible values: "idle", "listening", "processing", "thinking", "executing_tool", "error"
    property string stateHint: getStateHint()
    // Expose button as property
    property alias voiceButton: voiceButton
    property alias resetButton: resetButton
    property alias wifiButton: wifiButton
    property alias darkModeButton: darkModeButton
    // WiFi status properties
    property bool wifiConnected: false
    property string ipAddress: ""

    // Signals
    signal voiceToggled(bool listening)
    signal voicePressed()
    signal voiceReleased()
    signal resetClicked() // New signal for reset button
    signal wifiClicked() // New signal for WiFi button
    signal darkModeClicked() // New signal for dark mode button

    // Get appropriate hint text for current state
    function getStateHint() {
        if (!isConnected)
            return "Not connected";

        switch (appState) {
        case "idle":
            return "Tap to speak";
        case "listening":
            return "Listening...";
        case "processing":
            return "Processing audio...";
        case "thinking":
            return "Thinking...";
        case "executing_tool":
            return "Executing tool...";
        case "error":
            return "Error - try again";
        default:
            return "Ready";
        }
    }

    // Set the app state and emit signal
    function setAppState(newState) {
        if (appState !== newState) {
            console.log("VoiceInputArea: State changing from " + appState + " to " + newState);
            appState = newState;
            stateHint = getStateHint();
            // Update legacy state properties for backward compatibility
            isListening = (newState === "listening");
            isProcessing = (newState === "processing" || newState === "thinking" || newState === "executing_tool");
            
            // If transitioning to idle, ensure button is enabled
            if (newState === "idle" && voiceButton) {
                voiceButton.enabled = isConnected;
                voiceButton.checked = false;
            }
        }
    }

    // Functions to manage state
    function resetState() {
        console.log("VoiceInputArea: Resetting state");
        setAppState("idle");
        transcribedText = "";
        // Reset button states
        if (voiceButton) {
            voiceButton.checked = false;
            voiceButton.enabled = isConnected;
        }
        // Force status update
        stateHint = getStateHint();
    }

    // Move to thinking state (for external calls)
    function setThinkingState() {
        setAppState("thinking");
    }

    // Move to tool execution state (for external calls)
    function setToolExecutionState() {
        setAppState("executing_tool");
    }

    // Set error state (for external calls)
    function setErrorState() {
        setAppState("error");
        // Automatically reset to idle after showing error briefly
        errorResetTimer.start();
    }

    // Connect to the automatically generated property change signal
    onAppStateChanged: {
        console.log("App state changed to: " + appState);
    }
    color: ThemeManager.backgroundColor
    height: transcribedText.trim().length > 0 ? 120 : 90 // Ensure enough height for hint text and buttons
    z: 10 // Ensure this is always on top
    // Watch for changes to legacy properties and update state accordingly (for backward compatibility)
    onIsListeningChanged: {
        if (isListening && appState !== "listening")
            setAppState("listening");
        else if (!isListening && appState === "listening")
            setAppState("idle");
    }
    onIsProcessingChanged: {
        if (isProcessing && appState === "idle")
            setAppState("processing");
        else if (!isProcessing && (appState === "processing" || appState === "thinking" || appState === "executing_tool"))
            setAppState("idle");
    }
    onVoiceReleased: function() {
        if (bridge && bridge.ready && bridge.isConnected && isListening) {
            // First set state to processing explicitly
            setAppState("processing");
            // Then call the bridge method
            bridge.stopAndTranscribe();
        }
    }

    // Timer to automatically reset from error state to idle
    Timer {
        id: errorResetTimer

        interval: 2000 // Show error state for 2 seconds
        repeat: false
        running: false
        onTriggered: {
            resetState();
        }
    }

    // Hint text that shows when microphone is in focus
    Text {
        id: staticHintText

        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        text: voiceInputArea.stateHint
        font.pixelSize: FontManager.fontSizeSmall
        font.family: FontManager.primaryFontFamily
        color: ThemeManager.secondaryTextColor
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.9
        z: 20 // Make sure it appears above everything
        // Visibility is controlled by the voiceButton's onIsActiveItemChanged handler
        visible: false

        // Add a background for e-ink contrast
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -6
            color: ThemeManager.backgroundColor
            border.width: ThemeManager.borderWidth
            border.color: ThemeManager.borderColor
            radius: ThemeManager.borderRadius / 2
            visible: true // Always show background for better visibility
        }

    }

    // Transcribed text display
    Rectangle {
        id: transcribedTextDisplay

        visible: transcribedText.trim().length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: staticHintText.bottom
        anchors.topMargin: 10
        anchors.margins: 8
        height: transcribedTextLabel.contentHeight + 12
        color: ThemeManager.backgroundColor
        border.width: ThemeManager.borderWidth
        border.color: ThemeManager.borderColor
        radius: 4

        Text {
            id: transcribedTextLabel

            anchors.fill: parent
            anchors.margins: 6
            text: transcribedText
            font.pixelSize: FontManager.fontSizeNormal
            font.family: FontManager.primaryFontFamily
            color: ThemeManager.textColor
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 1
        }

    }

    // Button layout
    Item {
        id: buttonRow

        // Consistent button size - smaller for better layout
        property int borderWidth: ThemeManager.borderWidth

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        height: ThemeManager.buttonHeight

        Row {
            anchors.centerIn: parent
            spacing: ThemeManager.spacingLarge

            // 1st button: Voice/Mic button in the center position
            AppButton {
                // This allows the binding to checked: voiceInputArea.isListening to work
                // We don't force the checked state here to let the binding handle it

                id: voiceButton

                property bool navigable: isConnected // Only navigable when connected
                property bool isActiveItem: false
                property bool checked: voiceInputArea.isListening

                // Activate when Enter is pressed via FocusManager
                function activate() {
                    // Only allow activation when connected and not processing
                    if (!isConnected || voiceInputArea.appState === "processing" || 
                        voiceInputArea.appState === "thinking" || 
                        voiceInputArea.appState === "executing_tool")
                        return;

                    // When activating with Enter key
                    if (!isListening) {
                        // Start listening
                        console.log("VoiceButton.activate(): Starting listening");
                        voiceInputArea.voicePressed();
                        setAppState("listening");
                    } else {
                        // Stop listening
                        console.log("VoiceButton.activate(): Stopping listening");
                        voiceInputArea.voiceReleased();
                        setAppState("processing");
                    }
                }

                width: ThemeManager.buttonHeight
                height: ThemeManager.buttonHeight
                isFlat: true
                // Disable button when not connected or when processing/thinking/executing
                enabled: isConnected && 
                         voiceInputArea.appState !== "processing" && 
                         voiceInputArea.appState !== "thinking" && 
                         voiceInputArea.appState !== "executing_tool"
                
                onClicked: {
                    // Only allow interaction when connected and not processing
                    if (!isConnected || voiceInputArea.appState === "processing" || 
                        voiceInputArea.appState === "thinking" || 
                        voiceInputArea.appState === "executing_tool")
                        return;

                    // Toggle listening state
                    console.log("VoiceButton.onClicked(), current state: " + checked);
                    
                    if (!isListening) {
                        // Start listening
                        voiceInputArea.voicePressed();
                        setAppState("listening");
                    } else {
                        // Stop listening
                        voiceInputArea.voiceReleased();
                        setAppState("processing");
                    }
                }
                
                // Handle key press/release for Enter/Return
                Keys.onPressed: function(event) {
                    // Check if we're processing before handling key
                    if (!isConnected || voiceInputArea.appState === "processing" || 
                        voiceInputArea.appState === "thinking" || 
                        voiceInputArea.appState === "executing_tool") {
                        event.accepted = true;
                        return;
                    }
                        
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        event.accepted = true;
                        if (!isListening) {
                            // Start listening
                            voiceInputArea.voicePressed();
                            setAppState("listening");
                        }
                    }
                }
                
                Keys.onReleased: function(event) {
                    // Check if we're processing before handling key
                    if (!isConnected || (voiceInputArea.appState !== "listening" && 
                        voiceInputArea.appState !== "idle")) {
                        event.accepted = true;
                        return;
                    }
                    
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (isListening) {
                            // Stop listening
                            voiceInputArea.voiceReleased();
                            setAppState("processing");
                        }
                    }
                }

                backgroundColor: {
                    // Use the new state system for determining color
                    switch (voiceInputArea.appState) {
                    case "listening":
                        return ThemeManager.subtleColor;
                    case "processing":
                    case "thinking":
                    case "executing_tool":
                        return ThemeManager.buttonColor;
                    case "error":
                        return ThemeManager.backgroundColor; // Use background color for error (black/white only)
                    default:
                        return "transparent";
                    }
                }
                buttonRadius: width / 2

                // For visual feedback for focus state
                onIsActiveItemChanged: {
                    // Only update hint visibility if showStatusHint is enabled
                    if (isActiveItem && showStatusHint) {
                        // Show hint when mic button is active and connected
                        staticHintText.visible = isConnected;
                    } else if (!isActiveItem) {
                        // Hide hint when mic button loses focus
                        staticHintText.visible = false;
                    }
                }

                // Voice icon content needs custom handling
                Rectangle {
                    // Clear custom styling from AppButton
                    parent: voiceButton
                    anchors.fill: parent
                    color: "transparent"
                    
                    // High contrast highlight for e-ink when focused
                    Rectangle {
                        visible: voiceButton.isActiveItem || voiceButton.pressed
                        anchors.fill: parent
                        radius: width / 2
                        color: voiceButton.isActiveItem ? ThemeManager.accentColor : "transparent"
                        border.width: ThemeManager.borderWidth
                        border.color: ThemeManager.borderColor
                        opacity: voiceButton.isActiveItem ? 1.0 : 0.1
                        antialiasing: true
                    }
                    
                    Text {
                        id: micIcon
                        text: {
                            // If not connected, show "disabled" icon
                            if (!isConnected)
                                return "󱙱"; // Disabled microphone icon

                            // Use the new state system for determining icon
                            switch (voiceInputArea.appState) {
                            case "listening":
                                return "󰍬"; // Listening
                            case "processing":
                            case "thinking":
                            case "executing_tool":
                                return "󰍯"; // Processing
                            case "error":
                                return "󱦉"; // Error symbol (warning icon)
                            default:
                                // idle
                                return "󰍭";
                            }
                        }
                        anchors.centerIn: parent
                        font.pixelSize: parent.width * 0.45 // Slightly smaller for cleaner look
                        // Color based on connection state and focus state
                        color: voiceButton.isActiveItem ? 
                               ThemeManager.textOnAccentColor : 
                               ((isConnected && 
                               voiceInputArea.appState !== "processing" && 
                               voiceInputArea.appState !== "thinking" && 
                               voiceInputArea.appState !== "executing_tool") ? 
                               ThemeManager.textColor : ThemeManager.secondaryTextColor)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        // More dimmed when disabled
                        opacity: voiceButton.isActiveItem ? 1.0 :
                                ((isConnected && 
                                voiceInputArea.appState !== "processing" && 
                                voiceInputArea.appState !== "thinking" && 
                                voiceInputArea.appState !== "executing_tool") ? 1 : 0.5)
                    }

                    // Simple indicator for active states
                    Rectangle {
                        visible: voiceInputArea.appState !== "idle" && voiceInputArea.appState !== "error"
                        anchors.centerIn: parent
                        width: parent.width - 4
                        height: parent.height - 4
                        radius: width / 2
                        color: "transparent"
                        border.width: ThemeManager.borderWidth
                        border.color: voiceInputArea.appState === "listening" ? ThemeManager.accentColor : (voiceInputArea.appState === "processing" || voiceInputArea.appState === "thinking" || voiceInputArea.appState === "executing_tool") ? ThemeManager.buttonColor : "transparent"
                        opacity: 0.7
                        antialiasing: true
                    }
                }
            }

            // 2nd button: Reset button
            AppButton {
                id: resetButton

                property bool navigable: true
                property bool isActiveItem: false

                objectName: "resetButton"
                width: ThemeManager.buttonHeight
                height: ThemeManager.buttonHeight
                isFlat: true
                buttonRadius: width / 2
                onClicked: voiceInputArea.resetClicked()

                // Hint text that appears when button has focus
                Rectangle {
                    id: resetButtonHint

                    visible: resetButton.isActiveItem
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 8
                    height: resetHintText.contentHeight + 10
                    width: resetHintText.contentWidth + 16
                    color: ThemeManager.backgroundColor
                    border.width: ThemeManager.borderWidth
                    border.color: ThemeManager.borderColor
                    radius: 4
                    z: 100

                    Text {
                        id: resetHintText

                        anchors.centerIn: parent
                        text: "Reset App"
                        font.pixelSize: FontManager.fontSizeSmall
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                    }
                }

                // Reset icon content needs custom handling
                Rectangle {
                    // Clear custom styling from AppButton
                    parent: resetButton
                    anchors.fill: parent
                    color: "transparent"
                    
                    // High contrast highlight for e-ink when focused
                    Rectangle {
                        visible: resetButton.isActiveItem || resetButton.pressed
                        anchors.fill: parent
                        radius: width / 2
                        color: resetButton.isActiveItem ? ThemeManager.accentColor : "transparent"
                        border.width: ThemeManager.borderWidth
                        border.color: ThemeManager.borderColor
                        opacity: resetButton.isActiveItem ? 1.0 : 0.1
                        antialiasing: true
                    }

                    Text {
                        text: "↻" // Reset icon as text
                        font.pixelSize: parent.width * 0.5
                        font.family: FontManager.primaryFontFamily
                        color: resetButton.isActiveItem ? ThemeManager.textOnAccentColor : ThemeManager.textColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        opacity: 1 // Always full opacity for better e-ink visibility
                    }
                }
            }
            
            // 3rd button: WiFi status button
            AppButton {
                id: wifiButton
                
                property bool navigable: true
                property bool isActiveItem: false
                
                width: ThemeManager.buttonHeight
                height: ThemeManager.buttonHeight
                isFlat: true
                buttonRadius: width / 2
                onClicked: {
                    // Refresh WiFi info when clicked
                    if (bridge && bridge.ready) {
                        bridge.getWifiIpAddress(); // This forces a refresh
                    }
                    voiceInputArea.wifiClicked();
                }
                
                // Hint text that appears when button has focus
                Rectangle {
                    id: wifiButtonHint

                    visible: wifiButton.isActiveItem
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 8
                    height: wifiHintText.contentHeight + 10
                    width: wifiHintText.contentWidth + 16
                    color: ThemeManager.backgroundColor
                    border.width: ThemeManager.borderWidth
                    border.color: ThemeManager.borderColor
                    radius: 4
                    z: 100

                    Text {
                        id: wifiHintText

                        anchors.centerIn: parent
                        text: "WiFi Status"
                        font.pixelSize: FontManager.fontSizeSmall
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                    }
                }
                
                // WiFi icon content needs custom handling
                Rectangle {
                    // Clear custom styling from AppButton
                    parent: wifiButton
                    anchors.fill: parent
                    color: "transparent"
                    
                    // High contrast highlight for e-ink when focused
                    Rectangle {
                        visible: wifiButton.isActiveItem || wifiButton.pressed
                        anchors.fill: parent
                        radius: width / 2
                        color: wifiButton.isActiveItem ? ThemeManager.accentColor : "transparent"
                        border.width: ThemeManager.borderWidth
                        border.color: ThemeManager.borderColor
                        opacity: wifiButton.isActiveItem ? 1.0 : 0.1
                        antialiasing: true
                    }
                    
                    Text {
                        text: "" // WiFi icon
                        font.pixelSize: parent.width * 0.3
                        font.family: FontManager.primaryFontFamily
                        color: wifiButton.isActiveItem ? ThemeManager.textOnAccentColor : ThemeManager.textColor
                        width: parent.width
                        height: parent.height
                        rightPadding: 6
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        opacity: 1
                    }
                }
            }
            
            // 4th button: Dark mode button
            AppButton {
                id: darkModeButton
                
                property bool navigable: true
                property bool isActiveItem: false
                
                width: ThemeManager.buttonHeight
                height: ThemeManager.buttonHeight
                isFlat: true
                buttonRadius: width / 2
                onClicked: voiceInputArea.darkModeClicked()
                
                // Dark mode icon content needs custom handling
                Rectangle {
                    // Clear custom styling from AppButton
                    parent: darkModeButton
                    anchors.fill: parent
                    color: "transparent"
                    
                    // High contrast highlight for e-ink when focused
                    Rectangle {
                        visible: darkModeButton.isActiveItem || darkModeButton.pressed
                        anchors.fill: parent
                        radius: width / 2
                        color: darkModeButton.isActiveItem ? ThemeManager.accentColor : "transparent"
                        border.width: ThemeManager.borderWidth
                        border.color: ThemeManager.borderColor
                        opacity: darkModeButton.isActiveItem ? 1.0 : 0.1
                        antialiasing: true
                    }
                    
                    Text {
                        text: ThemeManager.darkMode ? "󰖨" : "" // Dark mode icon
                        font.pixelSize: parent.width * 0.3
                        font.family: FontManager.primaryFontFamily
                        color: darkModeButton.isActiveItem ? ThemeManager.textOnAccentColor : ThemeManager.textColor
                        rightPadding: ThemeManager.darkMode ? 3 : 0
                        width: parent.width
                        height: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        opacity: 1
                    }
                }
            }

        }

    }

    Behavior on height {
        NumberAnimation {
            duration: 100
        }
    }
}
