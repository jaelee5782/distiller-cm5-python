import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: header

    property string serverName: "NO SERVER"
    property string statusText: "Ready"
    property bool isConnected: false
    property bool showStatusText: false
    property bool wifiConnected: false
    property string ipAddress: ""
    property alias serverSelectButton: serverSelectBtn
    property alias darkModeButton: darkModeBtn

    // Update WiFi status from bridge
    function updateWifiStatus() {
        if (bridge && bridge.ready) {
            var ipAddr = bridge.getWifiIpAddress();
            wifiConnected = ipAddr && ipAddr !== "No network IP found" && !ipAddr.includes("Error");
            ipAddress = wifiConnected ? ipAddr : "";
        } else {
            wifiConnected = false;
            ipAddress = "";
        }
    }

    signal serverSelectClicked
    signal darkModeClicked

    color: ThemeManager.headerColor
    Component.onCompleted: {
        updateWifiStatus();
    }

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

        // Server selection button
        AppButton {
            id: serverSelectBtn
            Layout.preferredWidth: 140
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignVCenter
            text: isConnected && serverName && serverName !== "NO SERVER" ? serverName : "SELECT SERVER"
            fontSize: FontManager.fontSizeSmall
            navigable: true
            isFlat: true
            onClicked: header.serverSelectClicked()

            // Connection indicator removed as requested
        }

        Item {
            Layout.fillWidth: true
        }

        // Dark mode button
        AppButton {
            id: darkModeBtn
            Layout.preferredWidth: ThemeManager.buttonHeight
            Layout.preferredHeight: ThemeManager.buttonHeight
            Layout.alignment: Qt.AlignVCenter
            isFlat: true
            navigable: true
            buttonRadius: width / 2
            onClicked: header.darkModeClicked()

            // Dark mode icon content
            Rectangle {
            	parent: darkModeBtn
                anchors.fill: parent
                color: "transparent"

                // High contrast highlight for e-ink when focused
                Rectangle {
                    visible: darkModeBtn.visualFocus || darkModeBtn.pressed
                    anchors.fill: parent
                    radius: width / 2
                    color: darkModeBtn.visualFocus ? ThemeManager.accentColor : "transparent"
                    border.width: ThemeManager.borderWidth
                    border.color: ThemeManager.borderColor
                    opacity: darkModeBtn.visualFocus ? 1.0 : 0.1
                    antialiasing: true
                }

                Text {
                    text: ThemeManager.darkMode ? "󰖨" : "" // Dark mode icon
                    font.pixelSize: parent.width * 0.3
                    font.family: FontManager.primaryFontFamily
                    color: darkModeBtn.visualFocus ? ThemeManager.backgroundColor : ThemeManager.textColor
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

    onDarkModeClicked: {
        // Toggle dark mode
        ThemeManager.toggleTheme();
        if (bridge && bridge.ready) {
            bridge.setConfigValue("display", "dark_mode", ThemeManager.darkMode.toString());
        }
    }

    // Timer to update WiFi status periodically
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            updateWifiStatus();
        }
    }
}
