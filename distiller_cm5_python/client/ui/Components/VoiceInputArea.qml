import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Components 1.0

Rectangle {
    id: voiceInputArea

    // Properties
    property bool isListening: false
    property bool isProcessing: false
    
    // Expose button as property
    property alias voiceButton: voiceButton

    // Signals
    signal voiceToggled(bool listening)
    signal settingsClicked()

    // Functions
    function resetState() {
        isProcessing = false;
    }

    color: ThemeManager.backgroundColor
    height: 60 // Reduced height for smaller buttons
    z: 10 // Ensure this is always on top

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

        anchors.fill: parent
        anchors.margins: 8

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
                onClicked: {
                    voiceInputArea.voiceToggled(checked);
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