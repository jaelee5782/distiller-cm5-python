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

    signal serverSelectClicked()

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
