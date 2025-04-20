import "Components"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

PageBase {
    id: voiceAssistantPage
    
    pageName: "Voice Assistant"

    property string _serverName: "MCP Server"
    property string serverName: _serverName
    property bool isListening: false
    property bool isProcessing: false
    property string statusText: "Ready"
    property var focusableItems: []
    property var previousFocusedItem: null
    property string transcribedText: ""
    property bool transcriptionInProgress: false

    signal selectNewServer()

    onServerNameChanged: {
        _serverName = serverName;
    }
    
    function findChild(parent, objectName) {
        if (!parent) return null;
        
        for (var i = 0; i < parent.children.length; i++) {
            var child = parent.children[i];
            if (child.objectName === objectName) {
                return child;
            }
            
            var found = findChild(child, objectName);
            if (found) return found;
        }
        
        return null;
    }
    
    function collectFocusItems() {
        focusableItems = []
        
        // Add conversation view for keyboard scrolling
        if (conversationView && conversationView.navigable) {
            focusableItems.push(conversationView)
        }
        
        if (voiceInputArea) {
            if (voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable) {
                focusableItems.push(voiceInputArea.voiceButton)
            }
            
            let settingsButton = findChild(voiceInputArea, "settingsButton")
            if (settingsButton && settingsButton.navigable) {
                focusableItems.push(settingsButton)
            }
        }
        
        if (header && header.serverSelectButton && header.serverSelectButton.navigable) {
            focusableItems.push(header.serverSelectButton)
        }
        
        // Initialize focus manager with proper activation handling
        FocusManager.initializeFocusItems(focusableItems, conversationView)
    }
    
    function ensureFocusableItemsHaveFocus() {
        if (FocusManager.currentFocusIndex < 0 || FocusManager.currentFocusItems.length === 0) {
            collectFocusItems();
            
            if (voiceInputArea && voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable) {
                FocusManager.setFocusToItem(voiceInputArea.voiceButton);
            } else if (focusableItems.length > 0) {
                FocusManager.setFocusToItem(focusableItems[0]);
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(collectFocusItems);
    }

    Timer {
        id: focusInitTimer
        interval: 500
        running: true
        repeat: false
        onTriggered: {
            collectFocusItems();
            
            if (voiceInputArea && voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable) {
                FocusManager.setFocusToItem(voiceInputArea.voiceButton);
            }
        }
    }

    Connections {
        target: bridge
        
        function onBridgeReady() {
            if (conversationView) {
                conversationView.updateModel(bridge.get_conversation());
            }
        }

        function onTranscriptionUpdate(transcription) {
            transcribedText += transcription + " ";
            voiceInputArea.transcribedText = transcribedText;
            transcriptionInProgress = true;
        }

        function onTranscriptionComplete(full_text) {
            if (full_text && full_text.trim().length > 0) {
                transcribedText = full_text;
                voiceInputArea.transcribedText = transcribedText;
                
                // Submit the transcribed text to the server after a short delay
                transcriptionTimer.start();
            }
            transcriptionInProgress = false;
        }

        function onRecordingStateChanged(is_recording) {
            isListening = is_recording;
            if (is_recording) {
                statusText = "Listening...";
                transcribedText = "";
                voiceInputArea.transcribedText = "";
            } else if (!transcriptionInProgress) {
                statusText = "Processing...";
                isProcessing = true;
            }
        }

        function onStatusChanged(newStatus) {
            statusText = newStatus;
            
            // Reset processing state when we get a "Ready" status
            if (newStatus === "Ready" && isProcessing) {
                console.log("StatusChanged: Detected Ready status, resetting isProcessing to false");
                isProcessing = false;
                isListening = false;
                
                // Ensure conversation view is updated
                conversationView.setResponseInProgress(false);
                conversationView.scrollToBottom();
            }
        }
    }

    Timer {
        id: transcriptionTimer
        interval: 500
        repeat: false
        running: false
        onTriggered: {
            if (transcribedText && transcribedText.trim().length > 0 && bridge && bridge.ready) {
                bridge.submit_query(transcribedText.trim());
                transcribedText = "";
                voiceInputArea.transcribedText = "";
                
                // Start the state reset timer as a failsafe
                stateResetTimer.start();
            } else {
                // If no text to submit, make sure we reset the state
                isProcessing = false;
                isListening = false;
                statusText = "Ready";
            }
        }
    }

    VoiceAssistantPageHeader {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 60
        serverName: _serverName
        statusText: voiceAssistantPage.statusText
        isConnected: bridge && bridge.ready ? bridge.isConnected : false
        
        Component.onCompleted: {
            // Add high contrast border for visibility
            var headerRect = findChild(header, "headerBackground")
            if (headerRect) {
                headerRect.border.width = 1
                headerRect.border.color = ThemeManager.borderColor
            }
        }
        
        onServerSelectClicked: {
            previousFocusedItem = FocusManager.currentFocusItems[FocusManager.currentFocusIndex];
            confirmServerChangeDialog.open();
        }
    }

    AppDialog {
        id: confirmServerChangeDialog

        dialogTitle: "Change Server"
        message: "Are you sure you want to change servers? Current conversation will be lost."
        
        standardButtonTypes: DialogButtonBox.Yes | DialogButtonBox.No
        
        yesButtonText: "Proceed"
        noButtonText: "Cancel"
        
        acceptButtonColor: ThemeManager.backgroundColor
        
        onAccepted: {
            if (bridge && bridge.ready) {
                bridge.disconnectFromServer();
            }
            voiceAssistantPage.selectNewServer();
        }
        
        onRejected: {
            restoreFocusTimer.start();
        }
        
        onClosed: {
            if (!visible && !accepted) {
                restoreFocusTimer.start();
            }
        }
    }

    ConversationView {
        id: conversationView

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: voiceInputArea.top
        anchors.bottomMargin: 4
        anchors.margins: ThemeManager.spacingNormal
        
        Component.onCompleted: {
            if (bridge && bridge.ready) {
                updateModel(bridge.get_conversation());
            } else {
                updateModel([]);
            }
            
            // Disable scrolling animations for smoother experience
            if (scrollAnimation) {
                scrollAnimation.duration = 0;
            }
        }

        Connections {
            target: bridge && bridge.ready ? bridge : null
            
            function onConversationChanged() {
                conversationView.updateModel(bridge.get_conversation());
                // Ensure we scroll to the bottom after model updates
                conversationView.scrollToBottom();
            }
            
            function onMessageReceived(message, timestamp) {
                // Ensure processing state is fully reset
                isProcessing = false;
                isListening = false;
                statusText = "Ready";
                
                // Turn off response mode immediately
                conversationView.setResponseInProgress(false);
                // Ensure we scroll to the bottom
                conversationView.scrollToBottom();
                
                // Log the state reset
                console.log("MessageReceived: Reset isProcessing to false");
                
                // Start failsafe timer to ensure state is reset
                stateResetTimer.start();
            }
            
            function onListeningStarted() {
                isListening = true;
                statusText = "Listening...";
                transcribedText = "";
                voiceInputArea.transcribedText = "";
            }
            
            function onListeningStopped() {
                isListening = false;
                statusText = "Processing...";
                isProcessing = true;
                conversationView.setResponseInProgress(true);
            }
            
            function onErrorOccurred(errorMessage) {
                var displayDuration = Math.max(3000, Math.min(errorMessage.length * 75, 8000));
                messageToast.showMessage("Error: " + errorMessage, displayDuration);
                
                // Make sure to reset all states on error
                isProcessing = false;
                isListening = false;
                statusText = "Ready";
                
                conversationView.setResponseInProgress(false);
                
                if (errorMessage.toLowerCase().includes("connect") || 
                    errorMessage.toLowerCase().includes("server") ||
                    errorMessage.toLowerCase().includes("timeout")) {
                    reconnectionTimer.start();
                }
            }
        }
    }

    MessageToast {
        id: messageToast

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: voiceInputArea.top
        anchors.bottomMargin: ThemeManager.spacingNormal
        
        Component.onCompleted: {
            // Improve contrast for visibility
            var toastRect = findChild(messageToast, "toastBackground")
            if (toastRect) {
                toastRect.border.width = 1
                toastRect.border.color = ThemeManager.borderColor
                toastRect.color = ThemeManager.backgroundColor
            }
        }
    }

    VoiceInputArea {
        id: voiceInputArea
        
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        
        isListening: voiceAssistantPage.isListening
        isProcessing: voiceAssistantPage.isProcessing
        property string transcribedText: ""
        
        onVoiceToggled: function(listening) {
            if (bridge && bridge.ready && bridge.isConnected && !isProcessing) {
                if (listening) {
                    bridge.startRecording();
                } else {
                    bridge.stopAndTranscribe();
                }
            }
        }
        
        onSettingsClicked: {
            if (mainWindow && typeof mainWindow.pushSettingsPage === "function") {
                mainWindow.pushSettingsPage();
            }
        }
    }
    
    Timer {
        id: reconnectionTimer
        
        interval: 500
        repeat: false
        running: false
        
        onTriggered: {
            previousFocusedItem = FocusManager.currentFocusItems[FocusManager.currentFocusIndex];
            confirmServerChangeDialog.open();
        }
    }
    
    Timer {
        id: responseEndTimer
        
        interval: 300
        repeat: false
        running: false
        
        onTriggered: {
            conversationView.setResponseInProgress(false);
        }
    }

    Timer {
        id: restoreFocusTimer
        interval: 100
        repeat: false
        running: false
        
        onTriggered: {
            collectFocusItems();
            
            if (previousFocusedItem && previousFocusedItem.navigable) {
                FocusManager.setFocusToItem(previousFocusedItem);
            } else if (voiceInputArea && voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable) {
                FocusManager.setFocusToItem(voiceInputArea.voiceButton);
            } else if (focusableItems.length > 0) {
                for (var i = 0; i < focusableItems.length; i++) {
                    if (focusableItems[i] !== header.serverSelectButton) {
                        FocusManager.setFocusToItem(focusableItems[i]);
                        break;
                    }
                }
            }
            
            focusCheckTimer.start();
        }
    }
    
    Timer {
        id: focusCheckTimer
        interval: 200
        repeat: false
        running: false
        onTriggered: {
            ensureFocusableItemsHaveFocus();
        }
    }

    // Failsafe timer to ensure processing state is properly reset
    Timer {
        id: stateResetTimer
        interval: 1000
        repeat: false
        running: false
        onTriggered: {
            if (isProcessing) {
                console.log("StateResetTimer: Force resetting isProcessing from", isProcessing, "to false");
                isProcessing = false;
                isListening = false;
                statusText = "Ready";
                conversationView.setResponseInProgress(false);
            }
        }
    }

    // Periodic state check to ensure we don't get stuck in processing state
    Timer {
        id: stateCheckTimer
        interval: 5000  // Check every 5 seconds
        repeat: true
        running: true
        
        property real lastActionTimestamp: Date.now()
        
        onTriggered: {
            // If we've been in processing state for more than 10 seconds, reset it
            if (isProcessing && (Date.now() - lastActionTimestamp > 10000)) {
                console.log("StateCheckTimer: Detected stuck processing state, resetting");
                isProcessing = false;
                isListening = false;
                statusText = "Ready";
                conversationView.setResponseInProgress(false);
            }
        }
    }
    
    // Reset the action timestamp whenever user interacts or state changes
    onIsProcessingChanged: {
        stateCheckTimer.lastActionTimestamp = Date.now();
    }
    
    onIsListeningChanged: {
        stateCheckTimer.lastActionTimestamp = Date.now();
    }
}

