import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: serverListDialog
    
    property var availableServers: []
    property bool isLoading: false
    property int selectedIndex: -1
    property var focusableItems: []
    
    signal serverSelected(string serverPath, string serverName)
    signal dialogClosed()
    
    function collectFocusItems() {
        focusableItems = [];
        
        // Add refresh button first
        if (refreshButton && refreshButton.navigable) {
            refreshButton.objectName = "RefreshButton";
            focusableItems.push(refreshButton);
        }
        
        // Add close button
        if (closeButton && closeButton.navigable) {
            closeButton.objectName = "CloseButton";
            focusableItems.push(closeButton);
        }
        
        // Add list items if available
        if (serverList && serverList.count > 0) {
            var listItems = serverList.contentItem.children;
            for (var i = 0; i < listItems.length; i++) {
                var item = listItems[i];
                if (item && item.navigable) {
                    item.objectName = "ServerItem_" + i;
                    focusableItems.push(item);
                }
            }
        }
        
        // Initialize focus with our FocusManager
        FocusManager.initializeFocusItems(focusableItems);
        
        // Set focus to first item if available
        if (focusableItems.length > 0) {
            FocusManager.setFocusToItem(focusableItems[0]);
        }
    }
    
    // Connect to FocusManager to handle focus changes
    Connections {
        target: FocusManager
        
        function onCurrentFocusIndexChanged() {
            // Ensure the focused item is visible if it's a server list item
            if (FocusManager.currentFocusIndex >= 0 && 
                FocusManager.currentFocusItems.length > 0) {
                
                var item = FocusManager.currentFocusItems[FocusManager.currentFocusIndex];
                if (item && item.objectName && item.objectName.startsWith("ServerItem_")) {
                    // Extract index from the object name
                    var idx = parseInt(item.objectName.split("_")[1]);
                    if (!isNaN(idx) && idx >= 0) {
                        serverList.positionViewAtIndex(idx, ListView.Contain);
                    }
                }
            }
        }
    }
    
    // Open the dialog
    function open() {
        visible = true;
        isLoading = true;
        
        // Request servers
        if (bridge && bridge.ready) {
            bridge.getAvailableServers();
        } else {
            isLoading = false;
            messageToast.showMessage("Error: Application not fully initialized", 3000);
        }
    }
    
    // Close the dialog
    function close() {
        visible = false;
        // Notify parent about dialog closing so it can restore its focus items
        dialogClosed();
        
        // Force the parent to reinitialize its focus items
        if (parent && typeof parent.collectFocusItems === "function") {
            Qt.callLater(parent.collectFocusItems);
        }
    }
    
    // Set focus to the first server item
    function focusFirstServerItem() {
        if (serverList && serverList.count > 0) {
            // Ensure the ListView has created all items
            var listItems = serverList.contentItem.children;
            for (var i = 0; i < listItems.length; i++) {
                var item = listItems[i];
                if (item && item.navigable) {
                    FocusManager.setFocusToItem(item);
                    return true;
                }
            }
        }
        return false;
    }
    
    anchors.fill: parent
    color: ThemeManager.subtleColor
    visible: false
    z: 1000 // Set a very high z value to appear above all other content
    
    // Connections for bridge events
    Connections {
        target: bridge
        
        function onAvailableServersChanged(servers) {
            availableServers = servers;
            isLoading = false;
            
            if (servers.length === 0) {
                messageToast.showMessage("No servers found", 3000);
            } else {
                // Use a small delay to ensure all list items are created
                focusCollectionTimer.restart();
            }
        }
        
        function onErrorOccurred(errorMessage) {
            if (errorMessage.toLowerCase().includes("server") || 
                errorMessage.toLowerCase().includes("discover")) {
                messageToast.showMessage("Error: " + errorMessage, 3000);
            }
            isLoading = false;
        }
    }
    
    // Timer to collect focus items after server list changes
    Timer {
        id: focusCollectionTimer
        interval: 100
        repeat: false
        onTriggered: {
            collectFocusItems();
            // Try to focus the first server item
            if (!focusFirstServerItem()) {
                // If no server items, focus refresh button as fallback
                if (refreshButton && refreshButton.navigable) {
                    FocusManager.setFocusToItem(refreshButton);
                }
            }
        }
    }
    
    Component.onCompleted: {
        // Initialize the focus manager
        collectFocusItems();
    }
    
    // Dialog content
    Rectangle {
        id: dialogContent
        width: parent.width
        height: parent.height
        anchors.centerIn: parent
        color: ThemeManager.backgroundColor
        // border.width: ThemeManager.borderWidth
        // border.color: ThemeManager.borderColor
        // radius: ThemeManager.borderRadius
        
        // Dialog header
        Rectangle {
            id: dialogHeader
            width: parent.width
            height: 60
            color: ThemeManager.headerColor
            radius: ThemeManager.borderRadius
            
            // Refresh button - now positioned at top-left corner
            AppButton {
                id: refreshButton
                width: ThemeManager.buttonHeight
                height: ThemeManager.buttonHeight
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: ThemeManager.spacingSmall
                text: "↻"
                fontSize: FontManager.fontSizeMedium
                navigable: true
                isFlat: true
                buttonRadius: width / 2
                z: 10 // Ensure it's above other content
                onClicked: {
                    if (bridge && bridge.ready) {
                        isLoading = true;
                        bridge.getAvailableServers();
                    } else {
                        messageToast.showMessage("Error: Application not fully initialized", 3000);
                    }
                }
            }
            
            // Header title - centered between buttons with width constraint
            Text {
                anchors.centerIn: parent
                width: parent.width - refreshButton.width - closeButton.width - 40 // Allow space on both sides
                horizontalAlignment: Text.AlignHCenter
                text: "SELECT SERVER"
                font.pixelSize: FontManager.fontSizeNormal
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.textColor
                elide: Text.ElideRight
            }
            
            // Close button - positioned at top-right corner
            AppButton {
                id: closeButton
                width: ThemeManager.buttonHeight
                height: ThemeManager.buttonHeight
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: ThemeManager.spacingSmall
                text: "×"
                fontSize: FontManager.fontSizeMedium
                navigable: true
                isFlat: true
                buttonRadius: width / 2
                z: 10 // Ensure it's above other content
                onClicked: serverListDialog.close()
            }
            
            // Add a shadow effect
            // Rectangle {
            //     anchors.top: parent.bottom
            //     anchors.left: parent.left
            //     anchors.right: parent.right
            //     height: 1
            //     color: ThemeManager.borderColor
            //     opacity: 0.5
            // }
        }
        
        // Loading indicator
        LoadingIndicator {
            anchors.fill: parent
            isLoading: serverListDialog.isLoading
            z: 5
        }
        
        // Server list
        ListView {
            id: serverList
            anchors.top: dialogHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footerArea.top
            anchors.margins: ThemeManager.spacingSmall
            spacing: ThemeManager.spacingSmall
            model: availableServers
            clip: true
            visible: !isLoading
            // Add highlight to the current item
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 0 // Disable animation for e-ink display
            
            // Empty state message
            Text {
                anchors.centerIn: parent
                visible: availableServers.length === 0 && !serverListDialog.isLoading
                text: "No servers found"
                font.pixelSize: FontManager.fontSizeMedium
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.textColor
            }
            
            delegate: NavigableItem {
                id: serverItem
                width: serverList.width
                // get height based on the number of servers
                height: Math.min(100, serverList.height / availableServers.length)
                navigable: true
                
                onClicked: {
                    // Emit signal first, then close dialog
                    // This ensures proper signal handling before UI changes
                    serverListDialog.serverSelected(modelData.path, modelData.name);
                    
                    // Close the dialog with a slight delay to allow signal processing
                    Qt.callLater(function() {
                        serverListDialog.close();
                    });
                }
                
                // Ensure the item scrolls into view when it receives focus
                onIsActiveItemChanged: {
                    if (isActiveItem) {
                        serverList.positionViewAtIndex(index, ListView.Contain);
                    }
                }
                
                Rectangle {
                    anchors.fill: parent
                    color: parent.isActiveItem ? ThemeManager.accentColor : ThemeManager.transparentColor
                    border.width: ThemeManager.borderWidth
                    border.color: ThemeManager.borderColor
                    radius: ThemeManager.borderRadius
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: ThemeManager.spacingSmall
                        spacing: ThemeManager.spacingSmall
                        
                        // Server details
                        Column {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: ThemeManager.spacingTiny
                            
                            Text {
                                text: modelData.name || ""
                                width: parent.width
                                font.pixelSize: FontManager.fontSizeNormal
                                font.family: FontManager.primaryFontFamily
                                color: serverItem.isActiveItem ? 
                                    ThemeManager.textOnAccentColor : ThemeManager.textColor
                                elide: Text.ElideRight
                            }
                            
                            Text {
                                // Description functionality will be added later
                                // visible: modelData.description && modelData.description.length > 0
                                visible: false
                                text: modelData.description || ""
                                width: parent.width
                                font.pixelSize: FontManager.fontSizeSmall
                                font.family: FontManager.primaryFontFamily
                                color: serverItem.isActiveItem ? 
                                    ThemeManager.textOnAccentColor : ThemeManager.secondaryTextColor
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
        
        // Footer area - now just a small area for spacing at the bottom
        Rectangle {
            id: footerArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: ThemeManager.spacingLarge
            color: ThemeManager.backgroundColor
            
            // Add a subtle top border
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: ThemeManager.borderColor
                opacity: 0.5
            }
        }
    }
    
    // Toast message
    MessageToast {
        id: messageToast
        anchors.centerIn: parent
        z: 100
    }
} 
