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
    
    // Expose button as property
    property alias settingsButton: settingsButton
    property alias voiceButton: voiceButton
    property alias resetButton: resetButton

    // Signals
    signal voiceToggled(bool listening)
    signal settingsClicked()
    signal resetClicked()  // New signal for reset button

    // Functions
    function resetState() {
        isProcessing = false;
        transcribedText = "";
    }

    color: ThemeManager.backgroundColor
    height: transcribedText.trim().length > 0 ? 90 : 60 // Increase height when text is visible
    z: 10 // Ensure this is always on top

    Behavior on height {
        NumberAnimation { duration: 100 }
    }

    // Transcribed text display
    Rectangle {
        id: transcribedTextDisplay
        
        visible: transcribedText.trim().length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
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

    // Listening hint that appears during microphone input
    Text {
        id: listeningHint

        visible: isListening
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: buttonRow.top
        anchors.bottomMargin: 8
        text: "Listening..."
        font.pixelSize: FontManager.fontSizeNormal
        font.family: FontManager.primaryFontFamily
        color: ThemeManager.textColor
        opacity: 0.9

        // Add a background for e-ink contrast
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -6
            color: ThemeManager.backgroundColor
            border.width: 1
            border.color: ThemeManager.borderColor
            radius: 3
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

            // Settings button (on the left)
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
            }
            
            // Reset button
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
            }

            // Center microphone button - now same size as settings button
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
                
                // Add direct key handling for Enter/Return
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        event.accepted = true;
                        activate();
                    }
                }

                background: Rectangle {
                    color: voiceButton.checked ? ThemeManager.subtleColor : "transparent" // Light background when active for e-ink
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
                            if (!voiceButton.enabled)
                                return "󰍭"; // Idle
                                
                            if (voiceInputArea.isProcessing)
                                return "󰍯"; // Processing
                            
                            if (voiceButton.checked)
                                return "󰍬"; // Listening
                                
                            return "󰍭"; // Idle
                        }
                        font.pixelSize: parent.width * 0.45 // Slightly smaller for cleaner look
                        font.family: "Symbols Nerd Font"
                        color: ThemeManager.textColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        opacity: 1.0 // Always full opacity for better e-ink visibility
                    }

                    // Simple indicator for listening state (e-ink optimized)
                    Rectangle {
                        visible: voiceButton.checked && !voiceInputArea.isProcessing
                        anchors.centerIn: parent
                        width: parent.width - 4
                        height: parent.height - 4
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: ThemeManager.accentColor
                        opacity: 0.7
                        antialiasing: true
                        
                        // Remove animations for e-ink display
                    }
                }
            }
        }
    }
} 
