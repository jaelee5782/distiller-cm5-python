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
    property bool scrollModeActive: false // Track if scroll mode is active
    // Expose scroll animation for FocusManager but with zero duration
    property alias scrollAnimation: smoothScrollAnimation

    // Signal to notify when scroll mode changes
    signal scrollModeChanged(bool active)

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
        // Use a timer with a small delay to ensure it happens after layout updates

        var wasAtBottom = atBottom;
        model = newModel;
        // Always scroll to bottom during response or if we were already at the bottom
        if (responseInProgress || wasAtBottom)
            scrollTimer.start();
    }

    objectName: "conversationView"
    // Add keyboard focus handling
    focus: isActiveItem
    // Observe changes to scroll mode from FocusManager
    onScrollModeActiveChanged: {
        // Force UI update
        activeScrollModeInstructions.visible = scrollModeActive;
    }
    clip: true
    spacing: ThemeManager.spacingSmall
    // Always enable interaction
    interactive: true
    // Track when view is at the bottom
    onContentYChanged: {
        // Clamp contentY to valid bounds
        if (contentY < 0)
            contentY = 0;
        else if (contentHeight > height && contentY > contentHeight - height)
            contentY = Math.max(0, contentHeight - height);
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
        // Only apply if there's enough content to scroll

        // If contentY is beyond bounds, clamp it
        if (contentY < 0)
            contentY = 0;
        else if (contentHeight > height && contentY > contentHeight - height)
            contentY = Math.max(0, contentHeight - height);
        // Always scroll to bottom when response is in progress
        // or if we were already at the bottom, or this is the first content
        if (responseInProgress || atBottom || lastContentHeight === 0)
            scrollTimer.start();

        lastContentHeight = contentHeight;
    }
    // When model changes, we also want to scroll to bottom if appropriate
    onModelChanged: {
        if (responseInProgress || atBottom || count === 0)
            scrollTimer.start();
    }
    // Add keyboard handling for scroll mode
    Keys.onPressed: function (event) {
        if (scrollModeActive) {
            var scrollAmount = 50; // Pixels to scroll per key press
            if (event.key === Qt.Key_Down) {
                // Calculate the maximum valid contentY value (content height minus view height)
                var maxY = Math.max(0, contentHeight - height);
                // Prevent scrolling beyond the end of content
                contentY = Math.min(contentY + scrollAmount, maxY);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                // Prevent scrolling beyond the start of content
                contentY = Math.max(contentY - scrollAmount, 0);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // Exit scroll mode
                FocusManager.exitScrollMode();
                scrollModeChanged(false);
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            // Enter scroll mode
            if (contentHeight > height) {
                FocusManager.enterScrollMode();
                scrollModeChanged(true);
                event.accepted = true;
            }
        }
    }
    // Override the flick function to enforce bounds (this prevents bounce-back effects)
    boundsBehavior: Flickable.StopAtBounds

    // Animation with zero duration for compatibility with code expecting the animation
    NumberAnimation {
        id: smoothScrollAnimation

        target: conversationView
        property: "contentY"
        duration: 0 // No animation for e-ink
        easing.type: Easing.Linear
    }

    // Visual instruction when in focus but not in scroll mode
    Rectangle {
        id: scrollModeInstructions

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: ThemeManager.spacingNormal
        height: scrollModeText.height + ThemeManager.spacingLarge
        width: scrollModeText.width + ThemeManager.spacingSmall * 3
        color: ThemeManager.textColor
        border.width: ThemeManager.borderWidth
        border.color: ThemeManager.white
        radius: ThemeManager.borderRadius
        visible: isActiveItem && !scrollModeActive && conversationView.contentHeight > conversationView.height
        z: 2

        Text {
            id: scrollModeText

            anchors.centerIn: parent
            text: "Press Enter to enable scroll mode"
            color: ThemeManager.backgroundColor
            font: FontManager.small
        }
    }

    // Visual instruction when in scroll mode
    Rectangle {
        id: activeScrollModeInstructions

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: ThemeManager.spacingNormal
        height: activeScrollModeText.height + ThemeManager.spacingSmall * 2
        width: activeScrollModeText.width + ThemeManager.spacingNormal * 2
        color: ThemeManager.textColor
        border.width: ThemeManager.borderWidth
        border.color: ThemeManager.textColor
        radius: ThemeManager.borderRadius
        visible: false // Start invisible and let the binding update it
        z: 2
        // Make sure the visibility is bound to the scrollModeActive property
        Component.onCompleted: {
            activeScrollModeInstructions.visible = Qt.binding(function () {
                return scrollModeActive;
            });
        }

        Text {
            id: activeScrollModeText

            anchors.centerIn: parent
            text: "Use ↑/↓ to scroll, Enter to exit"
            color: ThemeManager.backgroundColor
            font: FontManager.small
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

    // Delegate for message items
    delegate: MessageItem {
        width: ListView.view.width
        messageText: typeof modelData === "string" ? modelData : ""
        isLastMessage: index === conversationView.count - 1
        isResponding: conversationView.responseInProgress && index === conversationView.count - 1
    }
}
