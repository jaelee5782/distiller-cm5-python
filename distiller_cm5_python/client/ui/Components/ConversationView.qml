import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ListView {
    id: conversationView

    // Properties to track user scrolling and state
    property bool userScrolling: false
    property bool atBottom: true
    property real lastContentY: 0
    property real lastContentHeight: 0
    property bool responseInProgress: false // Track if a response is being generated
    property bool navigable: true // Make focusable for keyboard navigation
    property bool isActiveItem: false // For focus management
    
    // Expose scroll animation for FocusManager but with zero duration
    property alias scrollAnimation: smoothScrollAnimation
    
    // Add keyboard focus handling
    focus: isActiveItem
    
    // Animation with zero duration for compatibility with code expecting the animation
    NumberAnimation {
        id: smoothScrollAnimation
        target: conversationView
        property: "contentY"
        duration: 0 // No animation for e-ink
        easing.type: Easing.Linear
    }
    
    // Handle key navigation
    Keys.onPressed: function(event) {
        if (isActiveItem) {
            if (event.key === Qt.Key_Up) {
                event.accepted = true;
                conversationView.contentY = Math.max(0, conversationView.contentY - 50);
                checkIfAtBottom();
            } else if (event.key === Qt.Key_Down) {
                event.accepted = true;
                var maxY = Math.max(0, conversationView.contentHeight - conversationView.height);
                conversationView.contentY = Math.min(maxY, conversationView.contentY + 50);
                checkIfAtBottom();
            } else if (event.key === Qt.Key_Home) {
                event.accepted = true;
                conversationView.positionViewAtBeginning();
                atBottom = false;
            } else if (event.key === Qt.Key_End) {
                event.accepted = true;
                conversationView.positionViewAtEnd();
                atBottom = true;
            }
        }
    }
    
    // Visual indicator for keyboard focus
    Rectangle {
        id: focusIndicator
        anchors.fill: parent
        color: "transparent"
        border.width: isActiveItem ? 2 : 0
        border.color: ThemeManager.accentColor
        visible: isActiveItem
        z: -1
    }

    // Update function for external callers
    function setResponseInProgress(inProgress) {
        responseInProgress = inProgress;
        if (inProgress) {
            // Force scroll to bottom when response starts
            positionViewAtEnd();
            atBottom = true;
        }
    }
    
    // Force scroll to bottom immediately
    function scrollToBottom() {
        positionViewAtEnd();
        atBottom = true;
    }

    // Function to determine if view is at the bottom
    function checkIfAtBottom() {
        // Consider at bottom if within 50 pixels of the end
        var viewEnd = contentY + height;
        var tolerance = 50;
        atBottom = (contentHeight - viewEnd) < tolerance;
    }

    // Method to update the model and scroll to bottom conditionally
    function updateModel(newModel) {
        var wasAtBottom = atBottom;
        model = newModel;
        // Always scroll to bottom during response or if we were already at the bottom
        if (responseInProgress || wasAtBottom) {
            // Use a timer with a small delay to ensure it happens after layout updates
            scrollTimer.start();
        }
    }
    
    // Timer to scroll to bottom with slight delay to ensure layout updates are complete
    Timer {
        id: scrollTimer
        interval: 10
        repeat: false
        onTriggered: {
            positionViewAtEnd();
            atBottom = true;
        }
    }

    clip: true
    spacing: ThemeManager.spacingSmall
    // Always enable interaction
    interactive: true
    // Track when view is at the bottom
    onContentYChanged: {
        // Only check when not user scrolling to avoid unnecessary calculations
        if (!userScrolling)
            checkIfAtBottom();
    }
    // Track when user is manually scrolling
    onMovementStarted: {
        // If response is in progress, force scroll to bottom
        if (responseInProgress) {
            positionViewAtEnd();
        } else {
            // Normal scrolling behavior
            userScrolling = true;
            lastContentY = contentY;
        }
    }
    onMovementEnded: {
        userScrolling = false;
        checkIfAtBottom();
    }
    // For auto-scrolling when content changes
    onContentHeightChanged: {
        // Always scroll to bottom when response is in progress
        // or if we were already at the bottom, or this is the first content
        if (responseInProgress || atBottom || lastContentHeight === 0) {
            scrollTimer.start();
        }

        lastContentHeight = contentHeight;
    }
    
    // When model changes, we also want to scroll to bottom if appropriate
    onModelChanged: {
        if (responseInProgress || atBottom || count === 0)
            scrollTimer.start();
    }

    // Add a scroll-to-bottom button with no animations
    AppRoundButton {
        id: scrollToBottomButton
        
        width: 32
        height: 32
        iconText: "↓"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: ThemeManager.spacingSmall
        visible: !atBottom && contentHeight > height && !responseInProgress
        z: 1 // Ensure it's above content
        
        onClicked: {
            conversationView.positionViewAtEnd();
            atBottom = true;
        }
    }

    // Delegate for message items
    delegate: MessageItem {
        width: ListView.view.width
        messageText: typeof modelData === "string" ? modelData : ""
        compact: true
        isLastMessage: index === conversationView.count - 1
        isResponding: conversationView.responseInProgress && index === conversationView.count - 1
    }
}
