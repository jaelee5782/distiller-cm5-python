// import QtGraphicalEffects 1.15  // Commented out in case it's not available

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Components 1.0

Rectangle {
    // No borders on the main rectangle

    id: inputArea

    // Simplified height since there's no text input
    height: 90 // Increased height to accommodate hint text
    property bool isListening: false
    property bool isProcessing: false // Keep this for visual feedback on voice button?
    property bool compact: true // Keep or remove based on visual needs

    // State management - define possible states
    property string appState: "idle" // Possible values: "idle", "listening", "processing", "thinking", "executing_tool", "error"
    property string stateHint: getStateHint() // Dynamic hint text based on state
    
    // Signal for state changes - can be connected to from parent to update status bar
    signal stateChanged(string newState)
    
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
            console.log("InputArea: State changing from " + appState + " to " + newState);
            appState = newState;
            stateHint = getStateHint();
            stateChanged(newState);
            
            // Update legacy state properties for backward compatibility
            isListening = (newState === "listening");
            isProcessing = (newState === "processing" || newState === "thinking" || newState === "executing_tool");
        }
    }

    // Expose only remaining buttons
    property alias settingsButton: settingsButton
    property alias voiceButton: voiceButton
    // property alias sendButton: sendButton // Removed

    // signal textSubmitted(string text) // Removed
    signal settingsClicked()
    // Add signals for press/release
    signal voicePressed()
    signal voiceReleased()

    // Reset state might still be useful for voice button
    function resetState() {
        setAppState("idle");
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
    z: 10 // Ensure this is always on top

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
        text: inputArea.stateHint
        font.pixelSize: FontManager.fontSizeSmall
        font.family: FontManager.primaryFontFamily
        color: ThemeManager.secondaryTextColor
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.9
        z: 20 // Make sure it appears above everything
    }

    // Simple Row layout for the remaining buttons
    RowLayout {
        id: buttonRowLayout

        anchors.fill: parent
        anchors.topMargin: staticHintText.height + 15 // Position below the hint text
        anchors.bottomMargin: 8
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 12

        // Consistent button size
        property int buttonSize: 40
        property int borderWidth: 2

        // Settings button (kept)
        RoundButton {
            id: settingsButton
            Layout.preferredWidth: buttonRowLayout.buttonSize
            Layout.preferredHeight: buttonRowLayout.buttonSize
            flat: true
            property bool navigable: true
            property bool isActiveItem: false
            onClicked: inputArea.settingsClicked()

            background: Rectangle {
                color: "transparent"
                antialiasing: true
                
                // Crisp focus border
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: settingsButton.isActiveItem ? 0 : -buttonRowLayout.borderWidth
                    color: "transparent"
                    border {
                        width: settingsButton.isActiveItem ? buttonRowLayout.borderWidth : 0
                        color: ThemeManager.accentColor
                    }
                    radius: width / 2
                    antialiasing: true
                    opacity: settingsButton.isActiveItem ? 1.0 : 0
                }
            }

            contentItem: Item {
                anchors.fill: parent
                
                // Simple hover highlight
                Rectangle {
                    visible: settingsButton.hovered || settingsButton.pressed
                    anchors.fill: parent
                    radius: width / 2
                    color: ThemeManager.buttonColor
                    opacity: 0.15
                    antialiasing: true
                }

                Text {
                    text: "⚙"  // Gear icon as text
                    font.pixelSize: parent.width / 2
                    font.family: FontManager.primaryFontFamily
                    color: ThemeManager.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    anchors.centerIn: parent
                    opacity: settingsButton.isActiveItem ? 1.0 : (settingsButton.hovered ? 1 : 0.7)
                }
            }
        }

        // Spacer to push voice button towards center/right
        Item {
           Layout.fillWidth: true
        }

        // Voice button
        RoundButton {
            id: voiceButton
            Layout.preferredWidth: buttonRowLayout.buttonSize
            Layout.preferredHeight: buttonRowLayout.buttonSize
            flat: true
            property bool navigable: true
            property bool isActiveItem: false
            // checkable: true // Now handled differently
            // checked: inputArea.isListening // State handled by parent page signal
            // onClicked: { inputArea.voiceToggled(checked); } // Handled differently

            // Connect the button's own signals to the InputArea signals
            onPressed: {
                inputArea.voicePressed();
                // Start listening when button is pressed
                setAppState("listening");
            }
            onReleased: {
                inputArea.voiceReleased();
                // Go to processing state when button is released
                setAppState("processing");
            }

            background: Rectangle {
                color: {
                    // Use the new state system for determining color
                    switch(inputArea.appState) {
                        case "listening": return ThemeManager.subtleColor;
                        case "processing": 
                        case "thinking": 
                        case "executing_tool": 
                            return ThemeManager.buttonColor;
                        default: return "transparent";
                    }
                }
                antialiasing: true
                
                // Crisp focus border
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: voiceButton.isActiveItem ? 0 : -buttonRowLayout.borderWidth
                    color: "transparent"
                    border {
                        width: voiceButton.isActiveItem ? buttonRowLayout.borderWidth : 0
                        color: ThemeManager.accentColor
                    }
                    radius: width / 2
                    antialiasing: true
                    opacity: voiceButton.isActiveItem ? 1.0 : 0
                }
            }

            contentItem: Item {
                anchors.fill: parent
                
                // Simple hover highlight
                Rectangle {
                    visible: voiceButton.hovered || voiceButton.pressed
                    anchors.fill: parent
                    radius: width / 2
                    color: ThemeManager.buttonColor
                    opacity: 0.15
                    antialiasing: true
                }

                OptimizedImage {
                    id: micIcon
                    source: {
                        // Use the new state system for determining icon
                        switch(inputArea.appState) {
                            case "listening": 
                                return ThemeManager.darkMode ? "../images/icons/dark/microphone-half.svg" : "../images/icons/microphone-half.svg";
                            case "processing":
                            case "thinking":
                            case "executing_tool":
                                return ThemeManager.darkMode ? "../images/icons/dark/microphone-filled.svg" : "../images/icons/microphone-filled.svg";
                            case "error":
                                return ThemeManager.darkMode ? "../images/icons/dark/microphone-error.svg" : "../images/icons/microphone-error.svg";
                            default: // idle
                                return ThemeManager.darkMode ? "../images/icons/dark/microphone-empty.svg" : "../images/icons/microphone-empty.svg";
                        }
                    }
                    sourceSize.width: 22
                    sourceSize.height: 22
                    width: 22
                    height: 22
                    anchors.centerIn: parent
                    fillMode: Image.PreserveAspectFit
                    opacity: voiceButton.hovered ? 1 : 0.8 // Improved opacity
                    fadeInDuration: 0
                    showPlaceholder: false
                }

                // Simple indicator for active states
                Rectangle {
                    visible: inputArea.appState !== "idle" && inputArea.appState !== "error"
                    anchors.centerIn: parent
                    width: parent.width - 4
                    height: parent.height - 4
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: inputArea.appState === "listening" ? ThemeManager.accentColor : 
                                 (inputArea.appState === "processing" || 
                                  inputArea.appState === "thinking" || 
                                  inputArea.appState === "executing_tool") ? ThemeManager.buttonColor : "transparent"
                    opacity: 0.5
                    antialiasing: true
                }
            }
        }
        
        // Spacer
        Item { 
            Layout.fillWidth: true
        }
        
        // Send Button Removed
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
