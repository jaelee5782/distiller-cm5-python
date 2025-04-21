import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Components 1.0

Rectangle {
    id: voiceInputArea

    // Properties
    property bool isListening: false
    property bool isProcessing: false
    property string transcribedText: ""
    
    // State management - define possible states
    property string appState: "idle" // Possible values: "idle", "listening", "processing", "thinking", "executing_tool", "error"
    property string stateHint: getStateHint() // Dynamic hint text based on state
    
    // Get appropriate hint text for current state
    function getStateHint() {
        switch(appState) {
            case "idle": return "Tap to speak";
            case "listening": return "Listening...";
            case "processing": return "Processing audio...";
            case "thinking": return "Thinking...";
            case "executing_tool": return "Executing tool...";
            case "error": return "Error - try again";
            default: return "Ready";
        }
    }
    
    // Set the app state and emit signal
    function setAppState(newState) {
        if (appState !== newState) {
            console.log("VoiceInputArea: State changing from " + appState + " to " + newState);
            appState = newState;
            stateHint = getStateHint();
            stateChanged(newState);
            
            // Update legacy state properties for backward compatibility
            isListening = (newState === "listening");
            isProcessing = (newState === "processing" || newState === "thinking" || newState === "executing_tool");
        }
    }
    
    // Expose button as property
    property alias settingsButton: settingsButton
    property alias voiceButton: voiceButton
    property alias resetButton: resetButton

    // Signals
    signal voiceToggled(bool listening)
    signal voicePressed()
    signal voiceReleased()
    signal settingsClicked()
    signal resetClicked()  // New signal for reset button
    signal stateChanged(string newState)

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

    color: ThemeManager.backgroundColor
    height: transcribedText.trim().length > 0 ? 120 : 90 // Increase height for hint text
    z: 10 // Ensure this is always on top

    Behavior on height {
        NumberAnimation { duration: 100 }
    }
    
    // Watch for changes to legacy properties and update state accordingly (for backward compatibility)
    onIsListeningChanged: {
        if (isListening && appState !== "listening") {
            setAppState("listening");
        } else if (!isListening && appState === "listening") {
            setAppState("idle");
        }
    }
    
    onIsProcessingChanged: {
        if (isProcessing && appState === "idle") {
            setAppState("processing");
        } else if (!isProcessing && (appState === "processing" || appState === "thinking" || appState === "executing_tool")) {
            setAppState("idle");
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
        visible: !(resetButton.isActiveItem || settingsButton.isActiveItem)
        
        // Add a background for e-ink contrast
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -6
            color: ThemeManager.backgroundColor
            border.width: 1
            border.color: ThemeManager.borderColor
            radius: 3
            visible: voiceInputArea.appState !== "idle"
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
        border.width: 1
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

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        height: 44

        // Consistent button size - smaller for better layout
        property int buttonSize: 44
        property int borderWidth: 2

        Row {
            anchors.centerIn: parent
            spacing: 24 // Increased spacing for better touch targets

            // 1st button: Voice/Mic button in the center position
            RoundButton {
                id: voiceButton
                width: buttonRow.buttonSize
                height: buttonRow.buttonSize
                flat: true
                checkable: true
                property bool navigable: true
                property bool isActiveItem: false
                checked: voiceInputArea.isListening
                
                // Activate when Enter is pressed via FocusManager
                function activate() {
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
                
                onClicked: {
                    // This is called for mouse clicks, not keyboard
                    // Keep consistent with the activate method
                    console.log("VoiceButton.onClicked(), current state: " + checked);
                    
                    // Toggle state - invert current state 
                    var newState = !checked;
                    
                    // This allows the binding to checked: voiceInputArea.isListening to work
                    // We don't force the checked state here to let the binding handle it
                    
                    // Trigger the voice toggle with the new state
                    voiceInputArea.voiceToggled(newState);
                }
                
                onPressed: {
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
                        switch(voiceInputArea.appState) {
                            case "listening": return ThemeManager.subtleColor;
                            case "processing": 
                            case "thinking": 
                            case "executing_tool": 
                                return ThemeManager.buttonColor;
                            default: return "transparent";
                        }
                    }
                    antialiasing: true
                    border.width: 1
                    border.color: voiceButton.checked ? ThemeManager.borderColor : "transparent"
                    
                    // Clear border for focus state (e-ink optimized)
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: voiceButton.isActiveItem ? 0 : -buttonRow.borderWidth
                        color: "transparent"
                        border {
                            width: voiceButton.isActiveItem ? buttonRow.borderWidth : 0
                            color: ThemeManager.accentColor
                        }
                        radius: width / 2
                        antialiasing: true
                        opacity: voiceButton.isActiveItem ? 1.0 : 0
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
                        border.width: 1
                        border.color: ThemeManager.borderColor
                        opacity: voiceButton.isActiveItem ? 0.3 : 0.1
                        antialiasing: true
                    }

                    Text {
                        id: micIcon
                        text: {
                            // Use the new state system for determining icon
                            switch(voiceInputArea.appState) {
                                case "listening": 
                                    return "󰍬"; // Listening
                                case "processing":
                                case "thinking": 
                                case "executing_tool":
                                    return "󰍯"; // Processing
                                case "error":
                                    return "󰍭"; // Error (using idle for now)
                                default: // idle
                                    return "󰍭"; // Idle
                            }
                        }
                        font.pixelSize: parent.width * 0.45 // Slightly smaller for cleaner look
                        font.family: "Symbols Nerd Font"
                        color: ThemeManager.textColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        opacity: 1.0 // Always full opacity for better e-ink visibility
                    }

                    // Simple indicator for active states
                    Rectangle {
                        visible: voiceInputArea.appState !== "idle" && voiceInputArea.appState !== "error"
                        anchors.centerIn: parent
                        width: parent.width - 4
                        height: parent.height - 4
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: voiceInputArea.appState === "listening" ? ThemeManager.accentColor : 
                                  (voiceInputArea.appState === "processing" || 
                                   voiceInputArea.appState === "thinking" || 
                                   voiceInputArea.appState === "executing_tool") ? ThemeManager.buttonColor : "transparent"
                        opacity: 0.7
                        antialiasing: true
                    }
                }
            }
            
            // 2nd button: Reset button
            RoundButton {
                id: resetButton
                objectName: "resetButton"

                width: buttonRow.buttonSize
                height: buttonRow.buttonSize
                flat: true
                property bool navigable: true
                property bool isActiveItem: false
                onClicked: voiceInputArea.resetClicked()

                background: Rectangle {
                    color: "transparent"
                    antialiasing: true
                    
                    // Clear border for focus state (e-ink optimized)
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: resetButton.isActiveItem ? 0 : -buttonRow.borderWidth
                        color: "transparent"
                        border {
                            width: resetButton.isActiveItem ? buttonRow.borderWidth : 0
                            color: ThemeManager.accentColor
                        }
                        radius: width / 2
                        antialiasing: true
                        opacity: resetButton.isActiveItem ? 1.0 : 0
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
                        border.width: 1
                        border.color: ThemeManager.borderColor
                        opacity: resetButton.isActiveItem ? 0.3 : 0.1
                        antialiasing: true
                    }

                    Text {
                        text: "↻"  // Reset icon as text
                        font.pixelSize: parent.width * 0.5
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        opacity: 1.0 // Always full opacity for better e-ink visibility
                    }
                }
                
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
                    border.width: 1
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
            }

            // 3rd button: Settings button
            RoundButton {
                id: settingsButton
                objectName: "settingsButton"

                width: buttonRow.buttonSize
                height: buttonRow.buttonSize
                flat: true
                property bool navigable: true
                property bool isActiveItem: false
                onClicked: voiceInputArea.settingsClicked()

                background: Rectangle {
                    color: "transparent"
                    antialiasing: true
                    
                    // Clear border for focus state (e-ink optimized)
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: settingsButton.isActiveItem ? 0 : -buttonRow.borderWidth
                        color: "transparent"
                        border {
                            width: settingsButton.isActiveItem ? buttonRow.borderWidth : 0
                            color: ThemeManager.accentColor
                        }
                        radius: width / 2
                        antialiasing: true
                        opacity: settingsButton.isActiveItem ? 1.0 : 0
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
                        border.width: 1
                        border.color: ThemeManager.borderColor
                        opacity: settingsButton.isActiveItem ? 0.3 : 0.1
                        antialiasing: true
                    }

                    Text {
                        text: "⚙"  // Gear icon as text
                        font.pixelSize: parent.width * 0.45 // Slightly smaller for cleaner look
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        opacity: 1.0 // Always full opacity for better e-ink visibility
                    }
                }
                
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
                    border.width: 1
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
            }
        }
    }
    
    // State animation for hint text
    Behavior on stateHint {
        PropertyAnimation {
            target: staticHintText
            property: "opacity"
            from: 0.5
            to: 0.9
            duration: 200
        }
    }
} 
