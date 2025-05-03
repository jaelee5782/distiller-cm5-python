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

    // Layout for header components
    RowLayout {
        id: headerLayout
        anchors.fill: parent
        anchors.leftMargin: ThemeManager.spacingTiny * 2
        anchors.rightMargin: ThemeManager.spacingTiny
        spacing: ThemeManager.spacingTiny

        // Server selection button
        AppButton {
            id: serverSelectBtn
            Layout.preferredWidth: 160
            Layout.preferredHeight: 44
            Layout.alignment: Qt.AlignVCenter
            navigable: true
            isFlat: false
            text: "" // Set empty text since we're using custom content
            onClicked: header.serverSelectClicked()
            
            // Add custom styling to ensure black border
            Rectangle {
                parent: serverSelectBtn
                anchors.fill: parent
                color: ThemeManager.transparentColor
                border.width: ThemeManager.borderWidth
                border.color: ThemeManager.black 
                radius: ThemeManager.borderRadius
                z: -1 // Behind the text
            }

            // Custom content using a child Column instead of contentItem
            Column {
                anchors.fill: parent
                anchors.leftMargin: ThemeManager.spacingTiny * 2
                anchors.rightMargin: ThemeManager.spacingTiny
                anchors.topMargin: ThemeManager.spacingTiny
                anchors.bottomMargin: ThemeManager.spacingTiny
                spacing: 1

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
                    font.pixelSize: FontManager.fontSizeSmall - 2
                    font.family: FontManager.primaryFontFamily
                    color: serverSelectBtn.visualFocus ? ThemeManager.backgroundColor : ThemeManager.textColor
                    elide: Text.ElideRight
                }
            }
        }

        // Item {
        //     Layout.fillWidth: false
        // }
    }
    
    // System stats display - positioned directly in header instead of in RowLayout
    Rectangle {
        id: statsDisplay
        width: 30
        height: 40
        anchors.right: parent.right
        anchors.rightMargin: ThemeManager.spacingNormal * 2  // Double the normal spacing
        anchors.verticalCenter: parent.verticalCenter
        Layout.alignment: Qt.AlignVCenter
        color: ThemeManager.transparentColor
        visible: showSystemStats
        
        // Add border for visibility
        Rectangle {
            anchors.fill: parent
            color: ThemeManager.transparentColor
            radius: ThemeManager.borderRadius / 3
        }
        
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
                font.pixelSize: 9
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
                font.pixelSize: 9
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
                font.pixelSize: 9
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
                font.pixelSize: 9
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.textColor
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // Dark mode button - commented out
    /*
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
            color: ThemeManager.darkMode ? "black" : "white" // Solid color

            // High contrast highlight for e-ink when focused
            Rectangle {
                visible: darkModeBtn.visualFocus || darkModeBtn.pressed || true // Always visible
                anchors.fill: parent
                radius: width / 2
                color: darkModeBtn.visualFocus ? "black" : (ThemeManager.darkMode ? "black" : "white")
                border.width: ThemeManager.borderWidth
                border.color: "black"
                opacity: 1.0
                antialiasing: true
            }

            Text {
                text: ThemeManager.darkMode ? "󰖨" : "" // Dark mode icon
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
    */

    // Keep the signal handler but make it do nothing to prevent runtime errors
    onDarkModeClicked: {
        /* Commented out
        // Toggle dark mode
        ThemeManager.toggleTheme();
        if (bridge && bridge.ready) {
            bridge.setConfigValue("display", "dark_mode", ThemeManager.darkMode.toString());
        }
        */
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
    
    // Timer to update system stats periodically
    Timer {
        interval: 3000
        running: showSystemStats
        repeat: true
        onTriggered: {
            updateSystemStats();
        }
    }
}
