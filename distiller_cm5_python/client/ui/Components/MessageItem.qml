import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: messageItem

    property string messageText: ""
    property bool isLastMessage: false
    property bool isResponding: false
    // Parse message components from string format "[timestamp] sender: content::type"
    readonly property string timestamp: messageText.indexOf("]") > 0 ? messageText.substring(1, messageText.indexOf("]")) : ""
    readonly property string remainder: messageText.indexOf("]") > 0 ? messageText.substring(messageText.indexOf("]") + 2) : messageText
    readonly property string sender: remainder.indexOf(":") > 0 ? remainder.substring(0, remainder.indexOf(":")) : ""
    // Extract message type if present (after ::)
    readonly property string contentWithType: remainder.indexOf(":") > 0 ? remainder.substring(remainder.indexOf(":") + 2) : remainder
    readonly property string messageType: contentWithType.lastIndexOf("::") > 0 ? contentWithType.substring(contentWithType.lastIndexOf("::") + 2) : "Message"
    readonly property string content: contentWithType.lastIndexOf("::") > 0 ? contentWithType.substring(0, contentWithType.lastIndexOf("::")) : contentWithType

    width: parent.width
    height: messageLayout.implicitHeight + ThemeManager.spacingNormal
    radius: ThemeManager.borderRadius
    color: Qt.rgba(ThemeManager.backgroundColor.r, ThemeManager.backgroundColor.g, ThemeManager.backgroundColor.b, 0.6) // Semi-transparent background
    border.color: ThemeManager.borderColor
    border.width: ThemeManager.borderWidth
    // Don't show the message if it's empty or only contains timestamp brackets
    visible: messageText !== "" && content.trim() !== ""

    // Subtle highlight effect for the latest message during response generation
    // Only applied to the actual message rectangle, not extending beyond it
    Rectangle {
        id: highlightEffect

        anchors.fill: parent
        radius: parent.radius
        color: isLastMessage && isResponding ? ThemeManager.highlightColor : "transparent"
        visible: isLastMessage && isResponding
        z: -1 // Behind text content
    }

    ColumnLayout {
        id: messageLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: ThemeManager.spacingSmall
        spacing: ThemeManager.spacingTiny

        Text {
            text: sender
            font: FontManager.small
            color: ThemeManager.textColor
            Layout.fillWidth: true
            visible: sender !== ""
        }

        Text {
            text: content
            font: FontManager.normal
            color: ThemeManager.textColor
            wrapMode: Text.WordWrap
            lineHeight: 1.1
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: ThemeManager.spacingTiny / 2

            // Display the message type at the bottom left
            Text {
                text: messageType
                color: ThemeManager.secondaryTextColor
                horizontalAlignment: Text.AlignLeft
                Layout.fillWidth: true
                visible: messageType !== ""

                font {
                    family: FontManager.small.family
                    pixelSize: FontManager.small.pixelSize
                    // Use bold for important message types
                    weight: {
                        switch (messageType.toLowerCase()) {
                        case "error":
                        case "warning":
                        case "ssh info":
                            return Font.Bold;
                        default:
                            return Font.Normal;
                        }
                    }
                    // Use italic for action-related types
                    italic: {
                        switch (messageType.toLowerCase()) {
                        case "action":
                        case "function":
                        case "observation":
                        case "plan":
                            return true;
                        default:
                            return false;
                        }
                    }
                }

            }

            // Display timestamp at the bottom right
            Text {
                text: timestamp
                font: FontManager.small
                color: ThemeManager.secondaryTextColor
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
                visible: timestamp !== ""
            }

        }

    }

}
