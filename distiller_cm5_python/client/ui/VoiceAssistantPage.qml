import "Components"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

PageBase {
    id: voiceAssistantPage

    property string _serverName: ""
    property string serverName: _serverName
    property bool isListening: false
    property bool isProcessing: false
    property bool isServerConnected: bridge && bridge.ready ? bridge.isConnected : false
    property string statusText: conversationView && conversationView.scrollModeActive ? "Scroll Mode (↑↓ to scroll)" : _statusText
    property string _statusText: isServerConnected ? "Tap to Talk" : "Not connected"
    property var focusableItems: []
    property var previousFocusedItem: null
    property string transcribedText: ""
    property bool transcriptionInProgress: false
    property bool conversationScrollMode: false // Track if conversation is in scroll mode
    property bool showStatusInBothPlaces: true // Set to true to show status in voice area instead of header

    function findChild(parent, objectName) {
        if (!parent)
            return null;

        for (var i = 0; i < parent.children.length; i++) {
            var child = parent.children[i];
            if (child.objectName === objectName)
                return child;

            var found = findChild(child, objectName);
            if (found)
                return found;

        }
        return null;
    }

    function collectFocusItems() {
        focusableItems = [];
        
        // Add server select button first (highest priority)
        if (header && header.serverSelectButton && header.serverSelectButton.navigable)
            focusableItems.push(header.serverSelectButton);
        
        // Add conversation view for keyboard scrolling
        if (conversationView && conversationView.navigable)
            focusableItems.push(conversationView);

        // Add voice input area buttons only if we have a server connection
        if (voiceInputArea) {
            // Add the voice button if server is connected
            if (voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable)
                focusableItems.push(voiceInputArea.voiceButton);

            // Then add the reset button
            let resetButton = findChild(voiceInputArea, "resetButton");
            if (resetButton && resetButton.navigable)
                focusableItems.push(resetButton);
                
            // Add WiFi button
            if (voiceInputArea.wifiButton && voiceInputArea.wifiButton.navigable)
                focusableItems.push(voiceInputArea.wifiButton);
                
            // Add dark mode button
            if (voiceInputArea.darkModeButton && voiceInputArea.darkModeButton.navigable)
                focusableItems.push(voiceInputArea.darkModeButton);
        }
        
        // Initialize focus manager with proper activation handling
        FocusManager.initializeFocusItems(focusableItems, conversationView);
    }

    function ensureFocusableItemsHaveFocus() {
        if (FocusManager.currentFocusIndex < 0 || FocusManager.currentFocusItems.length === 0) {
            collectFocusItems();
            if (voiceInputArea && voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable)
                FocusManager.setFocusToItem(voiceInputArea.voiceButton);
            else if (focusableItems.length > 0)
                FocusManager.setFocusToItem(focusableItems[0]);
        }
    }

    // Update status text based on app state
    function updateStatusText(newStatus) {
        if (conversationView && conversationView.scrollModeActive)
            return ;

        // Don't update status in scroll mode
        if (!isServerConnected) {
            _statusText = "Not connected";
            return ;
        }
        if (newStatus) {
            // Use a consistent "Processing..." status for all processing-related states

            if (newStatus === "Ready")
                _statusText = "Tap to Talk";
            else if (newStatus.toLowerCase().includes("executing") || newStatus.toLowerCase().includes("thinking") || newStatus.toLowerCase().includes("processing") || newStatus.toLowerCase().includes("tool"))
                _statusText = "Processing...";
            else if (newStatus.toLowerCase().includes("listening"))
                _statusText = "Listening...";
            else if (newStatus.toLowerCase().includes("error"))
                _statusText = "Error Occurred";
            else
                _statusText = newStatus;
        } else if (isListening)
            _statusText = "Listening...";
        else if (isProcessing)
            _statusText = "Processing...";
        else
            _statusText = "Tap to Talk";
    }

    // Function to reset focus state
    function resetFocusState() {
        console.log("Resetting focus state after restart");
        // First clear any existing focus
        FocusManager.clearFocus();
        FocusManager.currentFocusItems = [];
        FocusManager.currentFocusIndex = -1;
        FocusManager.lockFocus = false;
        
        // Immediately collect focus items to ensure they're available
        collectFocusItems();
        
        // Then start the timer to ensure UI elements are ready
        focusResetTimer.start();
        
        // Force a check immediately after resetting focus
        Qt.callLater(function() {
            if (FocusManager.currentFocusItems.length === 0) {
                console.log("No focus items available after reset, forcing recollection");
                collectFocusItems();
                if (voiceInputArea && voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable) {
                    FocusManager.setFocusToItem(voiceInputArea.voiceButton);
                } else if (focusableItems.length > 0) {
                    FocusManager.setFocusToItem(focusableItems[0]);
                }
            }
        });
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

    // Safety check to ensure focus is restored properly after dialogs
    Timer {
        id: focusSafetyCheckTimer
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            // If there are no focusable items, recollect them
            if (FocusManager.currentFocusItems.length === 0 || 
                FocusManager.currentFocusIndex < 0 || 
                FocusManager.currentFocusIndex >= FocusManager.currentFocusItems.length) {
                console.log("Focus safety check: Restoring focus items");
                collectFocusItems();
                if (voiceInputArea && voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable) {
                    FocusManager.setFocusToItem(voiceInputArea.voiceButton);
                } else if (focusableItems.length > 0) {
                    FocusManager.setFocusToItem(focusableItems[0]);
                }
            }
        }
    }

    pageName: "Voice Assistant"
    onServerNameChanged: {
        _serverName = serverName;
    }
    Component.onCompleted: {
        collectFocusItems();
        
        // Explicitly disable conversationView navigability initially to prevent it from capturing focus
        if (conversationView) {
            conversationView.navigable = false;
        }
        
        // Force focus to server select button
        if (header && header.serverSelectButton && header.serverSelectButton.navigable) {
            console.log("Setting initial focus to server select button");
            FocusManager.setFocusToItem(header.serverSelectButton);
            
            // Delay enabling of conversationView navigability
            Qt.callLater(function() {
                if (conversationView) {
                    conversationView.navigable = true;
                }
            });
        } else if (voiceInputArea && voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable) {
            // Fall back to voice button if server select button isn't available
            FocusManager.setFocusToItem(voiceInputArea.voiceButton);
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

    Connections {
        function onBridgeReady() {
            if (conversationView)
                conversationView.updateModel(bridge.get_conversation());

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
                if (voiceInputArea.setThinkingState)
                    voiceInputArea.setThinkingState();

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
                    if (voiceInputArea && voiceInputArea.resetState)
                        voiceInputArea.resetState();

                }
                // Reset conversation view state
                conversationView.setResponseInProgress(false);
            }
            transcriptionInProgress = false;
        }

        // Handler for SSH information events
        function onSshInfoReceived(content, eventId, timestamp) {
            console.log("SSH Info received: " + content);
            // Add to conversation if not empty
            if (content && content.trim().length > 0) {
                // Update the UI to show SSH connection info
                if (conversationView)
                    conversationView.updateModel(bridge.get_conversation());

                // Show a toast notification for the SSH info
                messageToast.showMessage("SSH Connection Info: " + content, 5000);
            }
        }

        // Handler for function events
        function onFunctionReceived(content, eventId, timestamp) {
            console.log("Function info received: " + content);
            // Add the function information to the conversation view
            if (conversationView)
                conversationView.updateModel(bridge.get_conversation());

        }

        // Handler for observation events
        function onObservationReceived(content, eventId, timestamp) {
            console.log("Observation received: " + content);
            // Add the observation to the conversation view
            if (conversationView)
                conversationView.updateModel(bridge.get_conversation());

        }

        // Handler for plan events
        function onPlanReceived(content, eventId, timestamp) {
            console.log("Plan received: " + content);
            // Add the plan to the conversation view
            if (conversationView)
                conversationView.updateModel(bridge.get_conversation());

        }

        // Handler for raw message schema objects
        function onMessageSchemaReceived(messageData) {
            // console.log("Message schema received: " + JSON.stringify(messageData));
            // Update conversation view with latest messages
            if (conversationView)
                conversationView.updateModel(bridge.get_conversation());

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
                if (voiceInputArea.setAppState)
                    voiceInputArea.setAppState("processing");

            }
        }

        function onStatusChanged(newStatus) {
            console.log("QML: Status changed to:", newStatus);
            // Always show consistent status in the UI, regardless of internal state
            if (newStatus.toLowerCase().includes("thinking") || newStatus.toLowerCase().includes("tool") || newStatus.toLowerCase().includes("executing")) {
                // Use a unified "Processing..." status for all processing-related states
                updateStatusText("Processing...");
                // Set appropriate internal state
                if (newStatus.toLowerCase().includes("thinking")) {
                    if (voiceInputArea.setThinkingState)
                        voiceInputArea.setThinkingState();
                    stateResetTimer.toolExecutionActive = false;
                } else {
                    // Tool execution or other processing
                    if (voiceInputArea.setToolExecutionState)
                        voiceInputArea.setToolExecutionState();
                    stateResetTimer.toolExecutionActive = true; // Flag tool execution as active
                }
                // Always restart the timer when status changes to ensure we don't get stuck
                stateResetTimer.restart();
            } else if (newStatus === "idle" || newStatus === "Ready") {
                console.log("QML: Detected idle/ready status, resetting all states");
                isProcessing = false;
                isListening = false;
                stateResetTimer.toolExecutionActive = false; // Clear tool execution flag
                // Reset input area state
                if (voiceInputArea && voiceInputArea.resetState) {
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
                if (voiceInputArea && voiceInputArea.resetState)
                    voiceInputArea.resetState();

            }
            // Reset conversation view state
            conversationView.setResponseInProgress(false);
            console.log("RecordingError: Reset all UI states due to error: " + errorMessage);
        }

        function onErrorReceived(content, eventId, timestamp) {
            console.log("Error event received: " + content);
            // Reset all UI states on error
            isProcessing = false;
            isListening = false;
            stateResetTimer.toolExecutionActive = false;
            // Force error state
            if (voiceInputArea && voiceInputArea.setErrorState)
                voiceInputArea.setErrorState();

            // Update status text
            updateStatusText("Error occurred");
            // Reset conversation view response state
            conversationView.setResponseInProgress(false);
            // Update the conversation and show message toast
            if (bridge && bridge.ready) {
                conversationView.updateModel(bridge.get_conversation());
                conversationView.scrollToBottom();
                messageToast.showMessage("Error: " + content, 5000);
            }
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
            if (errorMessage.toLowerCase().includes("connect") || errorMessage.toLowerCase().includes("server") || errorMessage.toLowerCase().includes("timeout"))
                reconnectionTimer.start();

        }

        function onIsConnectedChanged(connected) {
            isServerConnected = connected;
            updateStatusText();
        }

        target: bridge
    }

    Timer {
        id: transcriptionTimer

        interval: 750
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
                    if (voiceInputArea && voiceInputArea.resetState)
                        voiceInputArea.resetState();

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
        
        // Update WiFi status initially and whenever bridge is ready
        Component.onCompleted: {
            // Add high contrast border for visibility
            var headerRect = findChild(header, "headerBackground");
            if (headerRect) {
                headerRect.border.width = 1;
                headerRect.border.color = ThemeManager.borderColor;
            }
            
            // Ensure WiFi status is updated
            if (bridge && bridge.ready) {
                updateWifiStatus();
            }
        }
        
        onServerSelectClicked: {
            previousFocusedItem = FocusManager.currentFocusItems[FocusManager.currentFocusIndex];
            // Show server list dialog instead of confirmation
            serverListDialog.open();
        }
    }

    // Server list dialog
    ServerListDialog {
        id: serverListDialog
        
        // Ensure dialog is drawn above all other UI elements
        z: 1000
        
        Component.onCompleted: {
            // Keep a reference to the dialog in the FocusManager
            FocusManager.serverListDialog = this;
        }
        
        onServerSelected: function(serverPath, serverName) {
            if (bridge && bridge.ready) {
                // Set the selected server and connect to it
                bridge.setServerPath(serverPath);
                
                // This returns an error message if connection fails, or empty string on success
                var connectionResult = bridge.connectToServer();
                if (connectionResult) {
                    // Connection failed, show error message
                    console.error("Connection failed: " + connectionResult);
                    messageToast.showMessage("Connection failed: " + connectionResult, 5000);
                } else {
                    // Connection successful, update server name
                    _serverName = serverName;
                    
                    // Get conversation if available
                    if (conversationView) {
                        conversationView.updateModel(bridge.get_conversation());
                    }
                }
            }
            
            // Restore focus after dialog closes
            restoreFocusTimer.start();
        }
        
        onDialogClosed: {
            // Restore focus after dialog closes
            restoreFocusTimer.start();
        }
    }

    ConversationView {
        id: conversationView

        function onScrollModeChanged(active) {
            console.log("Scroll mode changed to: " + active);
            conversationScrollMode = active;
            // When entering scroll mode, we need to make sure the focus stays
            if (active) {
                FocusManager.lockFocus = true;
            } else {
                FocusManager.lockFocus = false;
                updateStatusText(); // Restore status when exiting scroll mode
            }
        }

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: voiceInputArea.top
        anchors.bottomMargin: 4
        anchors.margins: ThemeManager.spacingNormal
        Component.onCompleted: {
            if (bridge && bridge.ready)
                updateModel(bridge.get_conversation());
            else
                updateModel([]);
            // Disable scrolling animations for smoother experience
            if (scrollAnimation)
                scrollAnimation.duration = 0;

        }

        Connections {
            // For streaming chunks, keep the response in progress
            // and update the conversation model with the new chunk

            function onConversationChanged() {
                conversationView.updateModel(bridge.get_conversation());
                // Ensure we scroll to the bottom after model updates
                conversationView.scrollToBottom();
            }

            function onMessageReceived(message, eventId, timestamp, status) {
                console.log("QML onMessageReceived:", status, eventId, message.substring(0, 50));
                if (status === "in_progress") {
                    // Get current conversation
                    var conversation = bridge.get_conversation();
                    // If this is the first chunk of a new message
                    if (conversation.length === 0 || !conversation[conversation.length - 1].includes(message)) {
                        // Add as a new message
                        conversation.push("[" + timestamp + "] Assistant: " + message);
                    } else {
                        // Update the last message by appending the new chunk
                        var lastMsg = conversation[conversation.length - 1];
                        var timestampPart = lastMsg.substring(0, lastMsg.indexOf("]") + 1);
                        var senderPart = "Assistant: ";
                        var existingContent = lastMsg.substring(lastMsg.indexOf(senderPart) + senderPart.length);
                        // Replace the last message with updated content
                        conversation[conversation.length - 1] = timestampPart + " " + senderPart + existingContent + message;
                    }
                    // Update the model and keep response in progress
                    conversationView.updateModel(conversation);
                    conversationView.setResponseInProgress(true);
                    conversationView.scrollToBottom();
                } else if (status === "success") {
                    console.log("QML: Message complete, resetting UI state");
                    // Final message or end of streaming
                    // Reset UI state now that the response is complete
                    isProcessing = false;
                    isListening = false;
                    stateResetTimer.toolExecutionActive = false; // Clear tool execution flag
                    updateStatusText("Tap to Talk");
                    // Turn off response mode
                    conversationView.setResponseInProgress(false);
                    conversationView.scrollToBottom();
                    // Reset voice input area state
                    if (voiceInputArea && voiceInputArea.resetState) {
                        voiceInputArea.resetState();
                    }
                    // Log the state reset
                    console.log("MessageReceived: Reset isProcessing to false (complete message)");
                    // Stop failsafe timer
                    stateResetTimer.stop();
                }
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
                if (errorMessage.toLowerCase().includes("connect") || errorMessage.toLowerCase().includes("server") || errorMessage.toLowerCase().includes("timeout"))
                    reconnectionTimer.start();

            }

            target: bridge && bridge.ready ? bridge : null
        }

    }

    MessageToast {
        id: messageToast

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: voiceInputArea.top
        anchors.bottomMargin: ThemeManager.spacingNormal
        Component.onCompleted: {
            // Improve contrast for visibility
            var toastRect = findChild(messageToast, "toastBackground");
            if (toastRect) {
                toastRect.border.width = 1;
                toastRect.border.color = ThemeManager.borderColor;
                toastRect.color = ThemeManager.backgroundColor;
            }
        }
    }

    VoiceInputArea {
        id: voiceInputArea

        property string transcribedText: ""

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        isListening: voiceAssistantPage.isListening
        isProcessing: voiceAssistantPage.isProcessing
        isConnected: voiceAssistantPage.isServerConnected && serverName && serverName.length > 0 && serverName !== "No Server"
        showStatusHint: true // Use a simple boolean value for now as getConfigBoolValue isn't available
        // Set WiFi properties
        wifiConnected: header.wifiConnected
        ipAddress: header.ipAddress
        
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
                if (listening)
                    bridge.startRecording();
                else
                    bridge.stopAndTranscribe();
            }
        }
        onVoicePressed: function() {
            if (bridge && bridge.ready && bridge.isConnected && !isProcessing)
                bridge.startRecording();
        }
        onVoiceReleased: function() {
            if (bridge && bridge.ready && bridge.isConnected && isListening)
                bridge.stopAndTranscribe();
        }
        onResetClicked: {
            // Show confirmation dialog
            restartConfirmDialog.open();
        }
        onWifiClicked: {
            // Show WiFi status in a toast message instead of dialog
            if (bridge && bridge.ready) {
                var ipAddr = bridge.getWifiIpAddress();
                var macAddr = bridge.getWifiMacAddress ? bridge.getWifiMacAddress() : "";
                var signalStr = bridge.getWifiSignalStrength ? bridge.getWifiSignalStrength() : "";
                
                var wifiConnected = ipAddr && ipAddr !== "No network IP found" && !ipAddr.includes("Error");
                
                var statusMsg = wifiConnected ? 
                    "WiFi: Connected\nIP: " + ipAddr : 
                    "WiFi: Disconnected";
                    
                if (wifiConnected && macAddr) {
                    statusMsg += "\nMAC: " + macAddr;
                }
                
                if (wifiConnected && signalStr) {
                    statusMsg += "\nSignal: " + signalStr;
                }
                
                messageToast.showMessage(statusMsg, 5000);
            } else {
                messageToast.showMessage("Error: Bridge not ready", 3000);
            }
        }
        onDarkModeClicked: {
            // Toggle dark mode
            ThemeManager.toggleTheme();
            if (bridge && bridge.ready) {
                bridge.setConfigValue("display", "dark_mode", ThemeManager.darkMode.toString());
            }
        }
    }

    Timer {
        id: reconnectionTimer

        interval: 750 // Increased from 500ms to 750ms
        repeat: false
        running: false
        onTriggered: {
            previousFocusedItem = FocusManager.currentFocusItems[FocusManager.currentFocusIndex];
            confirmServerChangeDialog.open();
        }
    }

    Timer {
        id: responseEndTimer

        interval: 500 // Increased from 300ms to 500ms
        repeat: false
        running: false
        onTriggered: {
            conversationView.setResponseInProgress(false);
        }
    }

    Timer {
        id: restoreFocusTimer

        interval: 300 // Increased from 100ms to 300ms
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
            // Directly ensure focus here instead of starting another timer
            ensureFocusableItemsHaveFocus();
        }
    }

    // Failsafe timer to ensure processing state is properly reset
    Timer {
        id: stateResetTimer

        property bool toolExecutionActive: false

        interval: 20000 // 20 seconds timeout
        repeat: false
        running: false
        onTriggered: {
            if (isProcessing) {
                console.log("StateResetTimer triggered: Forcing state reset from stuck state");
                isProcessing = false;
                isListening = false;
                updateStatusText("Tap to Talk");
                conversationView.setResponseInProgress(false);
                // Reset input area state
                if (voiceInputArea.resetState)
                    voiceInputArea.resetState();

                // Ensure any errors are displayed in the conversation
                if (bridge && bridge.ready) {
                    conversationView.updateModel(bridge.get_conversation());
                    conversationView.scrollToBottom();
                }
            }
        }
    }

    // Periodic state check to ensure we don't get stuck in processing state
    Timer {
        id: stateCheckTimer

        property real lastActionTimestamp: Date.now()

        interval: 10000 // Increased from 5000ms to 10000ms
        repeat: true
        running: true
        onTriggered: {
            // Increased timeout check from 10s to 15s
            if (isProcessing && (Date.now() - lastActionTimestamp > 15000)) {
                isProcessing = false;
                isListening = false;
                updateStatusText("Tap to Talk");
                conversationView.setResponseInProgress(false);
                // Reset input area state
                if (voiceInputArea.resetState)
                    voiceInputArea.resetState();

                // Force conversation view to update - ensure any errors are displayed
                if (bridge && bridge.ready) {
                    conversationView.updateModel(bridge.get_conversation());
                    conversationView.scrollToBottom();
                }
            }
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

    // Timer to ensure proper focus reset
    Timer {
        id: focusResetTimer

        interval: 200
        repeat: false
        running: false
        onTriggered: {
            // Re-collect focus items
            collectFocusItems();
            // Set focus to voice button if available
            if (voiceInputArea && voiceInputArea.voiceButton && voiceInputArea.voiceButton.navigable) {
                FocusManager.setFocusToItem(voiceInputArea.voiceButton);
                console.log("Focus reset to voice button");
            } else if (focusableItems.length > 0) {
                FocusManager.setFocusToItem(focusableItems[0]);
                console.log("Focus reset to first focusable item");
            }
            // Force focus to keyHandler in main window to ensure key navigation works
            if (mainWindow && mainWindow.keyHandler) {
                mainWindow.keyHandler.forceActiveFocus();
                console.log("Focus forced to key handler");
            }
        }
    }

    // Move to thinking state (for external calls)
    function setThinkingState() {
        setAppState("thinking");
        // Ensure state reset timer is started
        stateResetTimer.restart();
    }

    // Move to tool execution state (for external calls)
    function setToolExecutionState() {
        setAppState("executing_tool");
        // Ensure state reset timer is started
        stateResetTimer.restart();
    }

}
