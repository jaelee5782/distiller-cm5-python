import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: header

    property string serverName: "MCP Server"
    property string statusText: "Ready"
    property bool isConnected: false
    property alias serverSelectButton: backButton
    property bool showStatusText: false

    signal serverSelectClicked()

    color: ThemeManager.headerColor

    // Shadow effect for the header
    Rectangle {
        anchors.top: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: ThemeManager.borderColor
        opacity: 0.5
    }

    // Layout for header components
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: ThemeManager.spacingNormal
        anchors.rightMargin: ThemeManager.spacingNormal
        spacing: ThemeManager.spacingNormal

        // Back button (server select)
        AppButton {
            id: backButton

            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignVCenter
            text: "←"
            fontSize: FontManager.fontSizeLarge
            navigable: true
            buttonRadius: parent.width
            isFlat: true
            onClicked: header.serverSelectClicked()
        }

        // Server name and status column
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: ThemeManager.spacingSmall / 4

            RowLayout {
                spacing: ThemeManager.spacingSmall / 2
                Layout.fillWidth: true

                Text {
                    text: serverName.toUpperCase()
                    font: FontManager.normal
                    color: ThemeManager.textColor
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                ServerStatusIndicator {
                    Layout.alignment: Qt.AlignVCenter
                    isConnected: header.isConnected
                    width: 12
                    height: 12
                }

            }

            Text {
                id: statusTextItem

                text: statusText
                font: FontManager.small
                color: ThemeManager.secondaryTextColor
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
                clip: true
                visible: showStatusText
            }

        }

    }

}
