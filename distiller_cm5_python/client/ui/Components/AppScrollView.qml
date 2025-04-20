import QtQuick 2.15
import QtQuick.Controls 2.15

ScrollView {
    id: root
    
    property bool showEdgeEffects: false
    property bool showScrollIndicator: false
    property int wheelScrollLines: 3
    property int touchScrollSensitivity: 1
    property int keyNavigationSpeed: 40
    
    // Expose the scroll animation for external use but set duration to 0
    property alias scrollAnimation: scrollAnimation
    
    clip: true
    
    // Disable the internal keyboard handling since we'll handle it through FocusManager
    Keys.enabled: false
    
    ScrollBar.horizontal: ScrollBar {
        policy: ScrollBar.AlwaysOff
    }
    
    contentWidth: availableWidth
    
    // Improve scroll behavior for wheel events
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton // Don't steal clicks from children
        propagateComposedEvents: true // Allow events to pass through
        
        // Direct scrolling without animation for e-ink
        onWheel: function(wheel) {
            if (wheel.angleDelta.y !== 0) {
                var delta = wheel.angleDelta.y > 0 ? -wheelScrollLines * 20 : wheelScrollLines * 20;
                // Apply directly with no animation
                root.contentItem.contentY = Math.max(0, Math.min(root.contentHeight - root.height, root.contentItem.contentY + delta));
            }
            wheel.accepted = true;
        }
    }
    
    // Animation with zero duration for compatibility with code expecting the animation
    NumberAnimation {
        id: scrollAnimation
        target: root.contentItem
        property: "contentY"
        duration: 0
        easing.type: Easing.Linear
    }
    
    // Custom ScrollBar styling - simplified for e-ink
    ScrollBar.vertical: ScrollBar {
        id: verticalScrollBar
        anchors.right: parent.right
        anchors.rightMargin: 4
        policy: ScrollBar.AsNeeded
        
        // Static opacity for e-ink
        opacity: 0.6
        interactive: true
        
        // Make scrollbar wider for better touch targets
        implicitWidth: 8
        
        contentItem: Rectangle {
            implicitWidth: 8
            radius: width / 2
            color: ThemeManager.accentColor
        }
        
        background: Rectangle {
            implicitWidth: 6
            radius: width / 2
            color: ThemeManager.shadowColor
            opacity: 0.3
        }
    }
    
    // Keyboard navigation support - direct movement without animation
    Keys.onPressed: function(event) {
        var contentItem = root.contentItem;
        
        if (event.key === Qt.Key_PageDown) {
            contentItem.contentY = Math.min(contentItem.contentY + root.height * 0.9, contentItem.contentHeight - root.height);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageUp) {
            contentItem.contentY = Math.max(contentItem.contentY - root.height * 0.9, 0);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home) {
            contentItem.contentY = 0;
            event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            contentItem.contentY = contentItem.contentHeight - root.height;
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            contentItem.contentY = Math.min(contentItem.contentY + keyNavigationSpeed, contentItem.contentHeight - root.height);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            contentItem.contentY = Math.max(contentItem.contentY - keyNavigationSpeed, 0);
            event.accepted = true;
        }
    }
    
    // Edge indicators - simplified to static elements
    Rectangle {
        id: topEdgeIndicator
        
        visible: showEdgeEffects && root.contentItem && root.contentItem.contentY <= 0
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 2
        color: ThemeManager.accentColor
        opacity: 0.8
        z: 1
    }
    
    Rectangle {
        id: bottomEdgeIndicator
        
        visible: showEdgeEffects && root.contentItem && 
                root.contentItem.contentHeight > root.height &&
                (root.contentItem.contentY + root.height) >= root.contentItem.contentHeight
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 2
        color: ThemeManager.accentColor
        opacity: 0.8
        z: 1
    }
    
    // Scroll indicator - simplified for e-ink display
    Rectangle {
        id: scrollPositionIndicator
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        height: 40
        radius: width / 2
        color: ThemeManager.accentColor
        visible: root.showScrollIndicator && root.contentItem.contentHeight > root.height * 1.5
        opacity: 0.7
        z: 10
        
        Text {
            anchors.centerIn: parent
            text: Math.round((root.contentItem.contentY / (root.contentItem.contentHeight - root.height)) * 100) + "%"
            color: ThemeManager.textOnAccentColor
            font.pixelSize: 12
            font.bold: true
            visible: root.contentItem.contentHeight > root.height
        }
    }
}
