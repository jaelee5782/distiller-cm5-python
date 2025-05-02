import QtQuick 2.15
import QtQuick.Controls 2.15

// Simple debug panel to show information about the image loading
Rectangle {
    id: debugPanel
    
    // Default properties
    width: parent.width * 0.9
    height: 60
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: 10
    color: "#80000000"  // Semi-transparent black
    visible: true
    radius: 5
    z: 1000  // Above everything else
    
    // Debug text
    Text {
        id: debugText
        anchors.fill: parent
        anchors.margins: 5
        color: "white"
        font.pixelSize: 10
        wrapMode: Text.Wrap
        text: "Debug: Loading..."
    }
    
    // Method to update debug info
    function setDebugInfo(info) {
        debugText.text = info;
    }
    
    // Timer to hide after a while
    Timer {
        interval: 10000  // 10 seconds
        running: debugPanel.visible
        repeat: false
        onTriggered: {
            debugPanel.visible = false;
        }
    }
} 