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
    property bool showStatusHint: true // New property to control visibility of status hint
    // State management - define possible states
    property string appState: "idle"
    // Possible values: "idle", "listening", "processing", "thinking", "executing_tool", "error"
    property string stateHint: getStateHint()
    // Expose button as property
    property alias settingsButton: settingsButton
    property alias voiceButton: voiceButton
    property alias resetButton: resetButton

    // Signals
    signal voiceToggled(bool listening)
    signal voicePressed()
    signal voiceReleased()
    signal settingsClicked()
    signal resetClicked() // New signal for reset button

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
        }
    }

    // Functions to manage state
    function resetState() {
        setAppState("idle");
        transcribedText = "";
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

    // Hint text that's always visible
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
        // Hide static hint when any button has focus - prevents conflict with button hints
        // Also hide if showStatusHint is false
        visible: showStatusHint && !(resetButton.isActiveItem || settingsButton.isActiveItem)

        // Add a background for e-ink contrast
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -6
            color: ThemeManager.backgroundColor
            border.width: ThemeManager.borderWidth
            border.color: ThemeManager.borderColor
            radius: 3
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
            RoundButton {
                // This allows the binding to checked: voiceInputArea.isListening to work
                // We don't force the checked state here to let the binding handle it

                id: voiceButton

                property bool navigable: isConnected // Only navigable when connected
                property bool isActiveItem: false

                // Activate when Enter is pressed via FocusManager
                function activate() {
                    // Only allow activation when connected
                    if (!isConnected)
                        return ;

                    // Toggle the checked state
                    var newState = !checked;
                    // Log what's happening
                    console.log("VoiceButton.activate() called, current state: " + checked + ", new state: " + newState);
                    // This will force the checked state directly
                    // instead of relying on the binding which may get confused
                    checked = newState;
                    // Trigger the voice toggle with the new state
                    voiceInputArea.voiceToggled(newState);
                }

                width: ThemeManager.buttonHeight
                height: ThemeManager.buttonHeight
                flat: true
                checkable: true
                checked: voiceInputArea.isListening
                enabled: isConnected // Disable button when not connected
                onClicked: {
                    // Only allow interaction when connected
                    if (!isConnected)
                        return ;

                    // This is called for mouse clicks, not keyboard
                    // Keep consistent with the activate method
                    console.log("VoiceButton.onClicked(), current state: " + checked);
                    // Toggle state - invert current state
                    var newState = !checked;
                    // Trigger the voice toggle with the new state
                    voiceInputArea.voiceToggled(newState);
                }
                onPressed: {
                    // Only allow interaction when connected
                    if (!isConnected)
                        return ;

                    voiceInputArea.voicePressed();
                    // Start listening when button is pressed
                    setAppState("listening");
                }
                onReleased: {
                    voiceInputArea.voiceReleased();
                    // Go to processing state when button is released
                    setAppState("processing");
                }
                // Add direct key handling for Enter/Return
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        event.accepted = true;
                        activate();
                    }
                }

                background: Rectangle {
                    color: {
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
                    antialiasing: true
                    border.width: buttonRow.borderWidth
                    border.color: voiceInputArea.appState === "error" ? ThemeManager.borderColor : (voiceButton.checked ? ThemeManager.borderColor : "transparent")

                    // Clear border for focus state (e-ink optimized)
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: voiceButton.isActiveItem ? 0 : -buttonRow.borderWidth
                        color: "transparent"
                        radius: width / 2
                        antialiasing: true
                        opacity: voiceButton.isActiveItem ? 1 : 0

                        border {
                            width: voiceButton.isActiveItem ? buttonRow.borderWidth : 0
                            color: ThemeManager.accentColor
                        }

                    }

                }

                contentItem: Item {
                    anchors.fill: parent

                    // High contrast highlight for e-ink
                    Rectangle {
                        visible: voiceButton.isActiveItem || voiceButton.hovered || voiceButton.pressed
                        anchors.fill: parent
                        radius: width / 2
                        color: voiceButton.isActiveItem ? ThemeManager.subtleColor : "transparent"
                        border.width: ThemeManager.borderWidth
                        border.color: ThemeManager.borderColor
                        opacity: voiceButton.isActiveItem ? 0.3 : 0.1
                        antialiasing: true
                    }

                    Text {
                        // Idle

                        id: micIcon

                        text: {
                            // Disconnected/disabled icon

                            // If not connected, show "disabled" icon
                            if (!isConnected)
                                return "";

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
                        font.pixelSize: parent.width * 0.45 // Slightly smaller for cleaner look
                        color: isConnected ? ThemeManager.textColor : ThemeManager.secondaryTextColor // Dimmed when not connected
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        opacity: isConnected ? 1 : 0.7 // Slightly dimmed when not connected
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
            RoundButton {
                id: resetButton

                property bool navigable: true
                property bool isActiveItem: false

                objectName: "resetButton"
                width: ThemeManager.buttonHeight
                height: ThemeManager.buttonHeight
                flat: true
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

                background: Rectangle {
                    color: "transparent"
                    antialiasing: true

                    // Clear border for focus state (e-ink optimized)
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: resetButton.isActiveItem ? 0 : -buttonRow.borderWidth
                        color: "transparent"
                        radius: width / 2
                        antialiasing: true
                        opacity: resetButton.isActiveItem ? 1 : 0

                        border {
                            width: resetButton.isActiveItem ? buttonRow.borderWidth : 0
                            color: ThemeManager.accentColor
                        }

                    }

                }

                contentItem: Item {
                    anchors.fill: parent

                    // High contrast highlight for e-ink
                    Rectangle {
                        visible: resetButton.isActiveItem || resetButton.hovered || resetButton.pressed
                        anchors.fill: parent
                        radius: width / 2
                        color: resetButton.isActiveItem ? ThemeManager.subtleColor : "transparent"
                        border.width: ThemeManager.borderWidth
                        border.color: ThemeManager.borderColor
                        opacity: resetButton.isActiveItem ? 0.3 : 0.1
                        antialiasing: true
                    }

                    Text {
                        text: "↻" // Reset icon as text
                        font.pixelSize: parent.width * 0.5
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        opacity: 1 // Always full opacity for better e-ink visibility
                    }

                }

            }

            // 3rd button: Settings button
            RoundButton {
                id: settingsButton

                property bool navigable: true
                property bool isActiveItem: false

                objectName: "settingsButton"
                width: ThemeManager.buttonHeight
                height: ThemeManager.buttonHeight
                flat: true
                onClicked: voiceInputArea.settingsClicked()

                // Add hint for settings button
                Rectangle {
                    id: settingsButtonHint

                    visible: settingsButton.isActiveItem
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 8
                    height: settingsHintText.contentHeight + 10
                    width: settingsHintText.contentWidth + 16
                    color: ThemeManager.backgroundColor
                    border.width: ThemeManager.borderWidth
                    border.color: ThemeManager.borderColor
                    radius: 4
                    z: 100

                    Text {
                        id: settingsHintText

                        anchors.centerIn: parent
                        text: "Settings"
                        font.pixelSize: FontManager.fontSizeSmall
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                    }

                }

                background: Rectangle {
                    color: "transparent"
                    antialiasing: true

                    // Clear border for focus state (e-ink optimized)
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: settingsButton.isActiveItem ? 0 : -buttonRow.borderWidth
                        color: "transparent"
                        radius: width / 2
                        antialiasing: true
                        opacity: settingsButton.isActiveItem ? 1 : 0

                        border {
                            width: settingsButton.isActiveItem ? buttonRow.borderWidth : 0
                            color: ThemeManager.accentColor
                        }

                    }

                }

                contentItem: Item {
                    anchors.fill: parent

                    // High contrast highlight for e-ink
                    Rectangle {
                        visible: settingsButton.isActiveItem || settingsButton.hovered || settingsButton.pressed
                        anchors.fill: parent
                        radius: width / 2
                        color: settingsButton.isActiveItem ? ThemeManager.subtleColor : "transparent"
                        border.width: ThemeManager.borderWidth
                        border.color: ThemeManager.borderColor
                        opacity: settingsButton.isActiveItem ? 0.3 : 0.1
                        antialiasing: true
                    }

                    Text {
                        text: "⚙" // Gear icon as text
                        font.pixelSize: parent.width * 0.45 // Slightly smaller for cleaner look
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        opacity: 1 // Always full opacity for better e-ink visibility
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
