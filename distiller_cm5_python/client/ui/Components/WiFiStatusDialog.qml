import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: wifiStatusDialog
    
    property bool wifiConnected: false
    property string ipAddress: ""
    property string macAddress: ""
    property string signalStrength: ""
    property var networkDetails: ({})
    
    signal dialogClosed()
    
    // Open the dialog and fetch updated WiFi info
    function open() {
        visible = true;
        updateWifiInfo();
    }
    
    // Close the dialog
    function close() {
        visible = false;
        dialogClosed();
    }
    
    // Update WiFi information
    function updateWifiInfo() {
        if (bridge && bridge.ready) {
            ipAddress = bridge.getWifiIpAddress() || "Not available";
            wifiConnected = ipAddress && ipAddress !== "No network IP found" && !ipAddress.includes("Error");
            
            // Get additional details if available
            try {
                // These are placeholder methods - implement these in your bridge if needed
                macAddress = bridge.getWifiMacAddress() || "Not available";
                signalStrength = bridge.getWifiSignalStrength() || "Not available";
                networkDetails = bridge.getNetworkDetails() || {};
            } catch (e) {
                console.error("Error fetching WiFi details:", e);
            }
        }
    }
    
    anchors.fill: parent
    color: ThemeManager.subtleColor
    visible: false
    
    // Dialog content
    Rectangle {
        id: dialogContent
        width: parent.width * 0.9
        height: parent.height * 0.6
        anchors.centerIn: parent
        color: ThemeManager.backgroundColor
        border.width: ThemeManager.borderWidth
        border.color: ThemeManager.borderColor
        radius: 4
        
        // Dialog header
        Rectangle {
            id: dialogHeader
            width: parent.width
            height: 60
            color: ThemeManager.headerColor
            radius: ThemeManager.borderRadius
            
            // Header title
            Text {
                anchors.centerIn: parent
                width: parent.width - closeButton.width - 40
                horizontalAlignment: Text.AlignHCenter
                text: "WIFI STATUS"
                font.pixelSize: FontManager.fontSizeMedium
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.textColor
                elide: Text.ElideRight
            }
            
            // Close button
            AppButton {
                id: closeButton
                width: 40
                height: 40
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                text: "×"
                fontSize: FontManager.fontSizeMedium
                navigable: true
                isFlat: true
                z: 10
                onClicked: wifiStatusDialog.close()
            }
            
            // Shadow effect
            Rectangle {
                anchors.top: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: ThemeManager.borderColor
                opacity: 0.5
            }
        }
        
        // WiFi status content
        Item {
            anchors.top: dialogHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: ThemeManager.spacingNormal
            
            ColumnLayout {
                anchors.fill: parent
                spacing: ThemeManager.spacingNormal
                
                // WiFi connection status
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingNormal
                    
                    Text {
                        text: "Status:"
                        font.pixelSize: FontManager.fontSizeNormal
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                        font.bold: true
                    }
                    
                    Text {
                        text: wifiConnected ? "Connected" : "Disconnected"
                        font.pixelSize: FontManager.fontSizeNormal
                        font.family: FontManager.primaryFontFamily
                        color: wifiConnected ? "green" : "red"
                    }
                    
                    // Status indicator
                    Rectangle {
                        width: 12
                        height: 12
                        radius: width / 2
                        color: wifiConnected ? "green" : "red"
                    }
                }
                
                // IP Address
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingNormal
                    
                    Text {
                        text: "IP Address:"
                        font.pixelSize: FontManager.fontSizeNormal
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                        font.bold: true
                    }
                    
                    Text {
                        text: ipAddress
                        font.pixelSize: FontManager.fontSizeNormal
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
                
                // MAC Address (if available)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingNormal
                    visible: macAddress && macAddress !== "Not available"
                    
                    Text {
                        text: "MAC Address:"
                        font.pixelSize: FontManager.fontSizeNormal
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                        font.bold: true
                    }
                    
                    Text {
                        text: macAddress
                        font.pixelSize: FontManager.fontSizeNormal
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                    }
                }
                
                // Signal Strength (if available)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingNormal
                    visible: signalStrength && signalStrength !== "Not available"
                    
                    Text {
                        text: "Signal Strength:"
                        font.pixelSize: FontManager.fontSizeNormal
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                        font.bold: true
                    }
                    
                    Text {
                        text: signalStrength
                        font.pixelSize: FontManager.fontSizeNormal
                        font.family: FontManager.primaryFontFamily
                        color: ThemeManager.textColor
                    }
                }
                
                // Spacer
                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
