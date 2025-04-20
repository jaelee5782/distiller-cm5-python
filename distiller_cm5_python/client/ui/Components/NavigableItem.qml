import QtQuick 2.15

// Base component for items that can be navigated with Up/Down/Enter keys
Item {
    id: navigableItem
    
    // Navigation properties
    property bool navigable: true        // Whether this item can be navigated to
    property bool isActiveItem: false    // Whether this is the currently active item
    property bool visualFocus: activeFocus || isActiveItem
    
    // Visual state
    property bool highlighted: visualFocus
    property color backgroundColor: highlighted ? 
                                  (ThemeManager.accentColor || "#000000") : 
                                  (ThemeManager.buttonColor || "#EEEEEE")
    property color textColor: highlighted ? 
                            (ThemeManager.darkMode ? "#000000" : "#FFFFFF") : 
                            (ThemeManager.textColor || "#000000")
    
    // Function that will be called when Enter is pressed on this item
    signal clicked()
    
    // For sliders and other value adjustments
    property bool isAdjustable: false
    property real adjustmentStep: 0.1
    
    // Support for value adjustment (for sliders, etc.)
    function increaseValue() {
        // Override in derived components
    }
    
    function decreaseValue() {
        // Override in derived components
    }
    
    // Static focus indicator optimized for e-ink
    Rectangle {
        id: focusIndicator
        anchors.fill: parent
        color: ThemeManager.transparentColor
        border.width: parent.visualFocus ? 3 : 0 // Increased border width
        border.color: ThemeManager.accentColor
        radius: 4
        visible: parent.visualFocus
        opacity: 1.0 // Fixed opacity for e-ink
        
        // Add a more visible background highlighting for better visibility
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            color: ThemeManager.accentColor
            opacity: 0.2 // Increased opacity
            radius: 3
            visible: parent.visible
        }
    }
    
    // Explicit key handling for this item
    Keys.onReturnPressed: function(event) {
        if (navigable) {
            console.log("NavigableItem: Return key pressed on item");
            clicked();
            event.accepted = true;
        }
    }
    
    Keys.onEnterPressed: function(event) {
        if (navigable) {
            console.log("NavigableItem: Enter key pressed on item");
            clicked();
            event.accepted = true;
        }
    }
    
    // Handle property changes
    onIsActiveItemChanged: {
        console.log("NavigableItem: isActiveItem changed to: " + isActiveItem + " for " + (parent ? parent.objectName || "unnamed" : "no parent"));
        if (isActiveItem) {
            console.log("NavigableItem: Forcing focus");
            forceActiveFocus();
        }
    }
    
    // Handle focused state
    onActiveFocusChanged: {
        console.log("NavigableItem: activeFocus changed to: " + activeFocus + " for " + (parent ? parent.objectName || "unnamed" : "no parent"));
        if (activeFocus && !isActiveItem) {
            isActiveItem = true;
        }
    }
    
    // Make the component ready for focus
    Component.onCompleted: {
        if (navigable) {
            console.log("NavigableItem: Initialized with navigable=true");
        }
    }
} 