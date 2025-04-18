import "Components"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

PageBase {
    id: serverSelectionPage
    
    pageName: "Server Selection"

    property var availableServers: []
    property bool isLoading: true
    property real cardSize: 200
    property real gridSpacing: 16

    signal serverSelected(string serverPath)

    // Connect to bridge ready signal
    Connections {
        target: bridge
        
        function onBridgeReady() {
            // Request server list when bridge is ready
            if (serverSelectionPage.visible && serverSelectionPage.width > 0) {
                serverInitTimer.stop(); // Stop the pending timer if it was running
                bridge.getAvailableServers();
            }
        }
        
        function onAvailableServersChanged(servers) {
            console.log("Received servers: " + servers.length);
            availableServers = servers;
            isLoading = false;
        }
    }

    Component.onCompleted: {
        // Call parent's onCompleted first
        // Use a small delay to ensure the component is fully constructed before requesting servers
        serverInitTimer.start();
    }
    
    // Prevent operations when being destroyed
    Component.onDestruction: {
        console.log("Server selection page being destroyed");
        // Stop any pending operations
        if (serverInitTimer.running)
            serverInitTimer.stop();
    }

    // Timer to delay server loading to prevent component creation during destruction
    Timer {
        id: serverInitTimer

        interval: 100
        repeat: false
        running: false
        onTriggered: {
            if (serverSelectionPage.visible && serverSelectionPage.width > 0 && bridge && bridge.ready) {
                bridge.getAvailableServers();
            } else if (serverSelectionPage.visible && serverSelectionPage.width > 0) {
                console.error("Bridge not ready, cannot get servers");
                isLoading = false;
            }
        }
    }

    // Loading indicator simplified for e-ink
    LoadingIndicator {
        anchors.fill: parent
        isLoading: serverSelectionPage.isLoading
        z: 10 // Ensure it's above other content
    }

    // Top margin padding area
    Item {
        id: topMargin
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: ThemeManager.spacingLarge // Add substantial top margin
    }

    // Header area
    MCPPageHeader {
        id: headerArea
        
        anchors.top: topMargin.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: implicitHeight
        z: 2 // Ensure header stays above content
        
        title: "SELECT MCP SERVER"
        subtitle: "Choose a server to connect to"
        compact: true
    }

    // Use AppScrollView instead of standard ListView for consistent behavior with SettingsPage
    AppScrollView {
        id: serverScrollView
        
        anchors.top: headerArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footerArea.top
        anchors.topMargin: 1 // Connect with header
        anchors.leftMargin: ThemeManager.spacingSmall // Reduced left margin
        anchors.rightMargin: ThemeManager.spacingSmall // Reduced right margin
        anchors.bottomMargin: ThemeManager.spacingSmall
        
        // Add scrolling animations and behavior from SettingsPage
        contentHeight: contentColumn.height
        showScrollIndicator: false
        visible: !isLoading
        
        // Content background for better visual clarity
        Rectangle {
            id: contentBackground
            width: serverScrollView.width
            height: contentColumn.height
            color: "transparent"
            
            // Light background shading for scrollable area
            Rectangle {
                anchors.fill: parent
                color: Qt.darker(ThemeManager.backgroundColor, 1.02) // Very subtle darkening
                visible: ThemeManager.darkMode ? false : true
                opacity: 0.5
            }
        }
        
        // Main content column
        Column {
            id: contentColumn
            width: serverScrollView.width
            spacing: ThemeManager.spacingLarge
            
            // Add top padding
            Item {
                width: parent.width
                height: ThemeManager.spacingSmall
            }
            
            // Empty state message for no servers
            MCPPageEmptyState {
                width: parent.width
                height: serverScrollView.height - ThemeManager.spacingLarge * 2
                visible: !serverSelectionPage.isLoading && availableServers.length === 0
                title: "NO SERVERS FOUND"
                message: "Please ensure MCP servers are available\nin the mcp_server directory"
                compact: true
            }
            
            // Server grid container
            Item {
                id: gridContainer
                width: parent.width
                // Height will be determined by the grid
                implicitHeight: serverGrid.implicitHeight
                visible: availableServers.length > 0
                
                // Calculate optimal number of columns based on width
                property int optimalColumns: Math.floor((width - ThemeManager.spacingLarge) / (cardSize + gridSpacing))
                property int columns: Math.max(2, optimalColumns) // Minimum 2 columns
                property real availableWidth: width - ThemeManager.spacingLarge
                property real effectiveCardWidth: (availableWidth - (columns - 1) * gridSpacing) / columns
                
                // Server grid layout
                Grid {
                    id: serverGrid
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.availableWidth
                    columns: gridContainer.columns
                    spacing: gridSpacing
                    
                    // Server grid cards
                    Repeater {
                        model: availableServers
                        
                        ServerGridCard {
                            width: gridContainer.effectiveCardWidth
                            height: width
                            serverName: modelData.name
                            serverDescription: modelData.description || ""
                            serverPath: modelData.path
                            
                            onCardClicked: function(path) {
                                // Add a delay to allow e-ink display to refresh
                                clickTimer.serverPath = path
                                clickTimer.start()
                            }
                        }
                    }
                }
            }
            
            // Add bottom padding
            Item {
                width: parent.width
                height: ThemeManager.spacingSmall
            }
        }
    }

    // Footer area with refresh button and status text
    Rectangle {
        id: footerArea
        
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: footerLayout.height + ThemeManager.spacingNormal * 2
        color: ThemeManager.backgroundColor
        visible: !isLoading
        
        // Add a subtle top border
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: ThemeManager.borderColor
            opacity: 0.5
        }
        
        ColumnLayout {
            id: footerLayout
            
            anchors.centerIn: parent
            width: parent.width - ThemeManager.spacingLarge * 2
            spacing: ThemeManager.spacingSmall
            
            // Status text
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: serverSelectionPage.isLoading ? 
                      "Loading servers..." : 
                      (availableServers.length === 0 ? 
                      (bridge && bridge.ready ? "No servers found" : "Bridge not ready") : "")
                color: ThemeManager.secondaryTextColor
                font: FontManager.small
                visible: serverSelectionPage.isLoading || availableServers.length === 0 // Only show when loading or no servers
            }
            
            // Refresh button
            AppButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: parent.width / 2
                Layout.preferredHeight: ThemeManager.buttonHeight * 0.7
                text: "Refresh"
                useFixedHeight: false
                onClicked: {
                    if (bridge && bridge.ready) {
                        isLoading = true;
                        bridge.getAvailableServers();
                    } else {
                        console.error("Bridge not ready, cannot refresh servers");
                    }
                }
            }
        }
    }

    // Timer to allow e-ink display to refresh before navigation
    Timer {
        id: clickTimer

        property string serverPath: ""

        interval: 300
        repeat: false
        onTriggered: {
            console.log("Server selected: " + serverPath);
            serverSelected(serverPath);
        }
    }
}
