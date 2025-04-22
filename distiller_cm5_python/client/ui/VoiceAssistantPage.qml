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
    property string statusText: conversationView && conversationView.scrollModeActive ? 
                             "Scroll Mode (↑↓ to scroll)" : _statusText
    property string _statusText: "Tap to Talk"
    property var focusableItems: []
    property var previousFocusedItem: null
    property string transcribedText: ""
    property bool transcriptionInProgress: false
    property bool conversationScrollMode: false  // Track if conversation is in scroll mode
    property bool showStatusInBothPlaces: true  // Set to true to show status in voice area instead of header

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
            // First add the voice button
            if (voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable) {
                focusableItems.push(voiceInputArea.voiceButton)
            }
            
            // Then add the reset button
            let resetButton = findChild(voiceInputArea, "resetButton")
            if (resetButton && resetButton.navigable) {
                focusableItems.push(resetButton)
            }
            
            // Finally add the settings button
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
            
            // Reinitialize focus when the bridge signals it's ready (including after restart)
            Qt.callLater(resetFocusState);
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
                
                // Update to thinking state
                if (voiceInputArea.setThinkingState) {
                    voiceInputArea.setThinkingState();
                }
            } else {
                // Handle empty transcription the same way as short audio error
                console.log("Empty transcription detected, treating as error");
                
                // Reset all states on empty transcription
                isProcessing = false;
                isListening = false;
                stateResetTimer.toolExecutionActive = false; // Clear tool execution flag
                
                // Show error state and message
                messageToast.showMessage("Error: Empty voice message", 3000);
                
                // Show error state briefly before returning to idle
                if (voiceInputArea && voiceInputArea.setErrorState) {
                    voiceInputArea.setErrorState();
                } else {
                    // Fallback if setErrorState is not available
                    updateStatusText("Tap to Talk");
                    if (voiceInputArea && voiceInputArea.resetState) {
                        voiceInputArea.resetState();
                    }
                }
                
                // Reset conversation view state
                conversationView.setResponseInProgress(false);
            }
            transcriptionInProgress = false;
        }

        function onRecordingStateChanged(is_recording) {
            isListening = is_recording;
            if (is_recording) {
                updateStatusText("Listening...");
                transcribedText = "";
                voiceInputArea.transcribedText = "";
            } else {
                // Always show Processing when recording stops
                updateStatusText("Processing...");
                isProcessing = true;
                
                // Make sure voiceInputArea shows processing state as well
                if (voiceInputArea.setAppState) {
                    voiceInputArea.setAppState("processing");
                }
            }
        }

        function onStatusChanged(newStatus) {
            // Always show consistent status in the UI, regardless of internal state
            if (newStatus.toLowerCase().includes("thinking") || 
                newStatus.toLowerCase().includes("tool") || 
                newStatus.toLowerCase().includes("executing")) {
                // Use a unified "Processing..." status for all processing-related states
                updateStatusText("Processing...");
                
                // Set appropriate internal state
                if (newStatus.toLowerCase().includes("thinking")) {
                    if (voiceInputArea.setThinkingState) {
                        voiceInputArea.setThinkingState();
                    }
                    stateResetTimer.toolExecutionActive = false;
                } else {
                    // Tool execution or other processing
                    if (voiceInputArea.setToolExecutionState) {
                        voiceInputArea.setToolExecutionState();
                    }
                    stateResetTimer.toolExecutionActive = true; // Flag tool execution as active
                }
                
                // Always restart the timer when status changes to ensure we don't get stuck
                stateResetTimer.restart();
                
                // Ensure conversation view is updated to show any potential errors
                if (bridge && bridge.ready) {
                    conversationView.updateModel(bridge.get_conversation());
                }
            } else if (newStatus === "Ready") {
                console.log("StatusChanged: Detected Ready status, resetting isProcessing to false");
                isProcessing = false;
                isListening = false;
                stateResetTimer.toolExecutionActive = false; // Clear tool execution flag
                
                // Reset input area state
                if (voiceInputArea.resetState) {
                    voiceInputArea.resetState();
                }
                
                // Update status text
                updateStatusText("Tap to Talk");
                
                // Ensure conversation view is updated
                conversationView.setResponseInProgress(false);
                conversationView.scrollToBottom();
            } else {
                // For any other status, just update the text
                updateStatusText(newStatus);
            }
        }

        function onRecordingError(errorMessage) {
            console.log("Recording Error: " + errorMessage);
            messageToast.showMessage("Error: " + errorMessage, 3000);
            
            // Reset all states on recording error
            isProcessing = false;
            isListening = false;
            stateResetTimer.toolExecutionActive = false; // Clear tool execution flag
            
            // Show error state briefly before returning to idle
            if (voiceInputArea && voiceInputArea.setErrorState) {
                voiceInputArea.setErrorState();
            } else {
                // Fallback if setErrorState is not available
                updateStatusText("Tap to Talk");
                if (voiceInputArea && voiceInputArea.resetState) {
                    voiceInputArea.resetState();
                }
            }
            
            // Reset conversation view state
            conversationView.setResponseInProgress(false);
            
            console.log("RecordingError: Reset all UI states due to error: " + errorMessage);
        }

        function onErrorOccurred(errorMessage) {
            var displayDuration = Math.max(3000, Math.min(errorMessage.length * 75, 8000));
            messageToast.showMessage("Error: " + errorMessage, displayDuration);
            
            // Make sure to reset all states on error
            isProcessing = false;
            isListening = false;
            stateResetTimer.toolExecutionActive = false; // Clear tool execution flag
            updateStatusText("Tap to Talk");
            
            conversationView.setResponseInProgress(false);
            
            // Force conversation view to update - ensure the error is displayed
            if (bridge && bridge.ready) {
                conversationView.updateModel(bridge.get_conversation());
                conversationView.scrollToBottom();
            }
            
            if (errorMessage.toLowerCase().includes("connect") || 
                errorMessage.toLowerCase().includes("server") ||
                errorMessage.toLowerCase().includes("timeout")) {
                reconnectionTimer.start();
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
                // Show error for empty message
                console.log("Empty transcription in timer, showing error state");
                
                // Show error state and message
                messageToast.showMessage("Error: Empty voice message", 3000);
                
                // Reset all states
                isProcessing = false;
                isListening = false;
                
                // Show error state briefly before returning to idle
                if (voiceInputArea && voiceInputArea.setErrorState) {
                    voiceInputArea.setErrorState();
                } else {
                    // Fallback if setErrorState is not available
                    updateStatusText("Tap to Talk");
                    if (voiceInputArea && voiceInputArea.resetState) {
                        voiceInputArea.resetState();
                    }
                }
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
        showStatusText: false // Hide status text in header
        
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
                stateResetTimer.toolExecutionActive = false; // Clear tool execution flag
                updateStatusText("Tap to Talk");
                
                // Turn off response mode immediately
                conversationView.setResponseInProgress(false);
                // Ensure we scroll to the bottom
                conversationView.scrollToBottom();
                
                // Log the state reset
                console.log("MessageReceived: Reset isProcessing to false");
                
                // Start failsafe timer to ensure state is reset
                stateResetTimer.stop(); // Stop the timer since we're already resetting
            }
            
            function onListeningStarted() {
                isListening = true;
                updateStatusText("Listening...");
                transcribedText = "";
                voiceInputArea.transcribedText = "";
            }
            
            function onListeningStopped() {
                isListening = false;
                updateStatusText("Processing...");
                isProcessing = true;
                conversationView.setResponseInProgress(true);
            }
            
            function onErrorOccurred(errorMessage) {
                var displayDuration = Math.max(3000, Math.min(errorMessage.length * 75, 8000));
                messageToast.showMessage("Error: " + errorMessage, displayDuration);
                
                // Make sure to reset all states on error
                isProcessing = false;
                isListening = false;
                stateResetTimer.toolExecutionActive = false; // Clear tool execution flag
                updateStatusText("Tap to Talk");
                
                conversationView.setResponseInProgress(false);
                
                // Force conversation view to update - ensure the error is displayed
                if (bridge && bridge.ready) {
                    conversationView.updateModel(bridge.get_conversation());
                    conversationView.scrollToBottom();
                }
                
                if (errorMessage.toLowerCase().includes("connect") || 
                    errorMessage.toLowerCase().includes("server") ||
                    errorMessage.toLowerCase().includes("timeout")) {
                    reconnectionTimer.start();
                }
            }
        }

        function onScrollModeChanged(active) {
            console.log("Scroll mode changed to: " + active);
            conversationScrollMode = active;
            
            // When entering scroll mode, we need to make sure the focus stays
            if (active) {
                FocusManager.lockFocus = true;
            } else {
                FocusManager.lockFocus = false;
                updateStatusText();  // Restore status when exiting scroll mode
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
        showStatusHint: true // Always show status hint in voice area
        
        // Connect to our new state changed signal
        onStateChanged: function(newState) {
            console.log("VoiceInputArea state changed to: " + newState);
            
            // Update parent state variables for compatibility
            if (newState === "listening") {
                voiceAssistantPage.isListening = true;
                voiceAssistantPage.isProcessing = false;
                updateStatusText("Listening...");
            } else if (newState === "processing") {
                voiceAssistantPage.isListening = false;
                voiceAssistantPage.isProcessing = true;
                updateStatusText("Processing...");
            } else if (newState === "thinking") {
                voiceAssistantPage.isListening = false;
                voiceAssistantPage.isProcessing = true;
                updateStatusText("Thinking...");
            } else if (newState === "executing_tool") {
                voiceAssistantPage.isListening = false;
                voiceAssistantPage.isProcessing = true;
                updateStatusText("Executing tool...");
            } else if (newState === "error") {
                voiceAssistantPage.isListening = false;
                voiceAssistantPage.isProcessing = false;
                updateStatusText("Error occurred");
            } else if (newState === "idle") {
                voiceAssistantPage.isListening = false;
                voiceAssistantPage.isProcessing = false;
                updateStatusText("Tap to Talk");
            }
        }
        
        onVoiceToggled: function(listening) {
            if (bridge && bridge.ready && bridge.isConnected && !isProcessing) {
                if (listening) {
                    bridge.startRecording();
                } else {
                    bridge.stopAndTranscribe();
                }
            }
        }
        
        onVoicePressed: function() {
            if (bridge && bridge.ready && bridge.isConnected && !isProcessing) {
                bridge.startRecording();
            }
        }
        
        onVoiceReleased: function() {
            if (bridge && bridge.ready && bridge.isConnected && isListening) {
                bridge.stopAndTranscribe();
            }
        }
        
        onSettingsClicked: {
            if (mainWindow && typeof mainWindow.pushSettingsPage === "function") {
                mainWindow.pushSettingsPage();
            }
        }
        
        onResetClicked: {
            // Show confirmation dialog
            restartConfirmDialog.open();
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
        interval: 15000  // Increase timeout to 15 seconds to accommodate longer tool operations
        repeat: false
        running: false
        
        property bool toolExecutionActive: false
        
        onTriggered: {
            if (isProcessing && !toolExecutionActive) {
                console.log("StateResetTimer: Force resetting isProcessing from", isProcessing, "to false");
                isProcessing = false;
                isListening = false;
                updateStatusText("Tap to Talk");
                conversationView.setResponseInProgress(false);
                
                // Reset input area state
                if (voiceInputArea.resetState) {
                    voiceInputArea.resetState();
                }
            } else if (toolExecutionActive) {
                console.log("StateResetTimer: Not resetting state because tool execution is active");
                // Show processing state for any active operation
                updateStatusText("Processing...");
                if (voiceInputArea.setAppState) {
                    voiceInputArea.setAppState("processing");
                }
                // Restart the timer to check again later, but with a shorter interval to avoid long waits
                interval = 5000; // Reduce the interval for subsequent checks to 5 seconds
                stateResetTimer.restart();
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
                updateStatusText("Tap to Talk");
                conversationView.setResponseInProgress(false);
                
                // Reset input area state
                if (voiceInputArea.resetState) {
                    voiceInputArea.resetState();
                }
                
                // Force conversation view to update - ensure any errors are displayed
                if (bridge && bridge.ready) {
                    conversationView.updateModel(bridge.get_conversation());
                    conversationView.scrollToBottom();
                }
            }
        }
    }
    
    // Reset the action timestamp whenever user interacts or state changes
    onIsProcessingChanged: {
        stateCheckTimer.lastActionTimestamp = Date.now();
        if (!conversationScrollMode) {
            _statusText = isProcessing ? "Processing..." : "Tap to Talk";
            updateStatusText();
        }
    }
    
    onIsListeningChanged: {
        stateCheckTimer.lastActionTimestamp = Date.now();
        if (!conversationScrollMode) {
            _statusText = isListening ? "Listening..." : (_statusText === "Listening..." ? "Processing..." : _statusText);
            updateStatusText();
        }
    }

    // Update status text based on app state
    function updateStatusText(newStatus) {
        if (conversationView && conversationView.scrollModeActive) return; // Don't update status in scroll mode
        
        if (newStatus) {
            if (newStatus === "Ready") {
                _statusText = "Tap to Talk";
            } else if (newStatus.toLowerCase().includes("executing") || 
                      newStatus.toLowerCase().includes("thinking") || 
                      newStatus.toLowerCase().includes("processing") || 
                      newStatus.toLowerCase().includes("tool")) {
                // Use a consistent "Processing..." status for all processing-related states
                _statusText = "Processing...";
            } else if (newStatus.toLowerCase().includes("listening")) {
                _statusText = "Listening...";
            } else if (newStatus.toLowerCase().includes("error")) {
                _statusText = "Error Occurred";
            } else {
                _statusText = newStatus;
            }
        } else if (isListening) {
            _statusText = "Listening...";
        } else if (isProcessing) {
            _statusText = "Processing...";
        } else {
            _statusText = "Tap to Talk";
        }
    }

    // App restart confirmation dialog
    AppDialog {
        id: restartConfirmDialog

        dialogTitle: "Reset Application"
        message: "Are you sure you want to reset the application?\nThis will clear your conversation and reconnect to the server."
        
        standardButtonTypes: DialogButtonBox.Yes | DialogButtonBox.No
        
        yesButtonText: "Reset"
        noButtonText: "Cancel"
        
        acceptButtonColor: ThemeManager.backgroundColor
        
        onAccepted: {
            // Reset the application
            restartApplication();
        }
    }
    
    // Function to reset focus state
    function resetFocusState() {
        console.log("Resetting focus state after restart");
        // First clear any existing focus
        FocusManager.clearFocus();
        FocusManager.currentFocusItems = [];
        FocusManager.currentFocusIndex = -1;
        FocusManager.lockFocus = false;
        
        // Re-collect focus items
        collectFocusItems();
        
        // Set focus to voice button if available
        if (voiceInputArea && voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable) {
            FocusManager.setFocusToItem(voiceInputArea.voiceButton);
        } else if (focusableItems.length > 0) {
            FocusManager.setFocusToItem(focusableItems[0]);
        }
    }

    // Function to restart the application
    function restartApplication() {
        console.log("Restarting application...");
        
        // Use the dedicated restart method
        if (bridge && bridge.ready) {
            // Use the dedicated restart method
            if (typeof bridge.restartApplication === "function") {
                // Reset focus state immediately to clear any stuck state
                FocusManager.clearFocus();
                FocusManager.lockFocus = false;
                
                bridge.restartApplication();
                messageToast.showMessage("Restarting application...", 2000);
            } else {
                // Fallback if the method isn't available
                messageToast.showMessage("Unable to restart - bridge method not available", 3000);
            }
        } else {
            // Fallback if bridge is not available
            messageToast.showMessage("Unable to restart - bridge not ready", 3000);
        }
    }
}

