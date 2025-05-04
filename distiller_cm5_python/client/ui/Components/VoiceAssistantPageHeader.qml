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
    // Keep the alias but point to a dummy item to prevent runtime errors
    property alias darkModeButton: dummyDarkModeBtn
    property alias closeButton: closeBtn
    
    // System stats properties
    property bool showSystemStats: bridge && bridge.ready ? bridge.getShowSystemStats() : true
    property var systemStats: {"cpu": "N/A", "ram": "N/A", "temp": "N/A", "llm": "Local"}

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
    
    // Update system stats from bridge
    function updateSystemStats() {
        if (bridge && bridge.ready && showSystemStats) {
            systemStats = bridge.getSystemStats();
        }
    }

    signal serverSelectClicked
    // Keep the signal to prevent errors
    signal darkModeClicked
    signal closeAppClicked

    color: ThemeManager.backgroundColor
    Component.onCompleted: {
        updateWifiStatus();
        updateSystemStats();
    }

    // Dummy invisible item to satisfy the darkModeButton alias
    Item {
        id: dummyDarkModeBtn
        visible: false
        property bool navigable: false
    }

    // Shadow effect for the header
    Rectangle {
        anchors.top: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: ThemeManager.black 
    }

    // System stats display
    Rectangle {
        id: statsDisplay
        width: 30
        height: 40
        anchors.left: parent.left
        anchors.leftMargin: ThemeManager.spacingSmall
        anchors.verticalCenter: parent.verticalCenter
        color: ThemeManager.transparentColor
        visible: showSystemStats
        
        // Stats content
        Column {
            anchors.fill: parent
            anchors.margins: 2
            spacing: 0
            
            // CPU usage
            Text {
                width: parent.width
                height: 10
                text: "CPU: " + systemStats.cpu
                font.pixelSize: FontManager.fontSizeTiny
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.textColor
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }
            
            // RAM usage
            Text {
                width: parent.width
                height: 10
                text: "MEM: " + systemStats.ram
                font.pixelSize: FontManager.fontSizeTiny
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.textColor
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }
            
            // Temperature
            Text {
                width: parent.width
                height: 10
                text: "TEMP: " + systemStats.temp
                font.pixelSize: FontManager.fontSizeTiny
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.textColor
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }

             // LLM model
            Text {
                width: parent.width
                height: 10
                text: "LLM: " + systemStats.llm
                font.pixelSize: FontManager.fontSizeTiny
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.textColor
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // Server selection button - centered with reduced width
    AppButton {
        id: serverSelectBtn
        width: 120
        height: 44
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        navigable: true
        isFlat: false
        text: "" // Set empty text since we're using custom content
        onClicked: header.serverSelectClicked()
        
        // Custom content using a child Column instead of contentItem
        Column {
            anchors.fill: parent
            anchors.leftMargin: ThemeManager.spacingSmall
            anchors.rightMargin: ThemeManager.spacingSmall
            anchors.topMargin: ThemeManager.spacingSmall
            anchors.bottomMargin: ThemeManager.spacingTiny
            spacing: ThemeManager.spacingTiny / 4

            // Server name - left aligned
            Text {
                width: parent.width
                height: parent.height / 2
                horizontalAlignment: Text.AlignLeft
                text: isConnected && serverName && serverName !== "NO SERVER" ? serverName : "SELECT SERVER"
                font: FontManager.small
                color: serverSelectBtn.visualFocus ? ThemeManager.backgroundColor : ThemeManager.textColor
                elide: Text.ElideRight
            }

            // Status text - left aligned, smaller font
            Text {
                width: parent.width
                height: parent.height / 2
                horizontalAlignment: Text.AlignLeft
                text: statusText
                // visible: isConnected && serverName && serverName !== "NO SERVER"
                font.pixelSize: FontManager.fontSizeTiny
                font.family: FontManager.primaryFontFamily
                color: serverSelectBtn.visualFocus ? ThemeManager.backgroundColor : ThemeManager.textColor
                elide: Text.ElideRight
            }
        }
    }

    // Close app button - positioned at top right
    AppButton {
        id: closeBtn
        width: 36
        height: 36
        anchors.right: parent.right
        anchors.rightMargin: ThemeManager.spacingSmall
        anchors.verticalCenter: parent.verticalCenter
        navigable: true
        isFlat: true
        buttonRadius: width / 2
        onClicked: {
            closeConfirmDialog.open();
        }
        
        // Close button icon
        Rectangle {
            parent: closeBtn
            anchors.fill: parent
            color: ThemeManager.backgroundColor
            
            // High contrast highlight for e-ink when focused
            Rectangle {
                visible: closeBtn.visualFocus || closeBtn.pressed || true
                anchors.fill: parent
                radius: width / 2
                color: closeBtn.visualFocus ? ThemeManager.textColor : ThemeManager.backgroundColor
                border.width: ThemeManager.borderWidth
                border.color: ThemeManager.black
                antialiasing: true
            }
            
            Text {
                text: "✕" // Close icon
                font.pixelSize: parent.width * 0.4
                font.family: FontManager.primaryFontFamily
                color: closeBtn.visualFocus ? ThemeManager.backgroundColor : ThemeManager.textColor
                anchors.centerIn: parent
            }
        }
    }
    
    // Close confirmation dialog
    AppDialog {
        id: closeConfirmDialog
        dialogTitle: "Close Application"
        message: "Are you sure you want to close the application?"
        standardButtonTypes: DialogButtonBox.Yes | DialogButtonBox.No
        yesButtonText: "Proceed"
        noButtonText: "Cancel"
        acceptButtonColor: ThemeManager.backgroundColor
        
        onAccepted: {
            header.closeAppClicked();
            if (bridge && bridge.ready && typeof bridge.closeApplication === "function") {
                bridge.closeApplication();
            } else {
                console.log("Unable to close application - bridge method not available");
            }
        }
    }
}
