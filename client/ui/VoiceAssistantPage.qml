import "Components"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

PageBase {
    id: voiceAssistantPage
    
    pageName: "Voice Assistant"

    // Use property setter pattern to ensure component updates
    property string _serverName: "MCP Server"
    property string serverName: _serverName
    property bool isListening: false
    property bool isProcessing: false
    property string statusText: "Ready"

    signal selectNewServer()

    onServerNameChanged: {
        _serverName = serverName;
    }

    // Header area with server name and status
    VoiceAssistantPageHeader {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 70 // Increased height to accommodate wrapping status text
        serverName: _serverName
        statusText: voiceAssistantPage.statusText
        isConnected: bridge.isConnected
        onServerSelectClicked: {
            confirmServerChangeDialog.open();
        }
    }

    // Confirmation dialog for server change 
    AppDialog {
        id: confirmServerChangeDialog

        dialogTitle: "Change Server"
        message: "Are you sure you want to change servers? Current conversation will be lost."
        
        // Configure the standard buttons 
        standardButtonTypes: DialogButtonBox.Yes | DialogButtonBox.No
        
        // Button text customization
        yesButtonText: "Proceed"
        noButtonText: "Cancel"
        
        // Hide secondary action
        showSecondaryAction: false
        
        // Use accent color for the positive button
        positiveButtonColor: ThemeManager.accentColor
        
        onAccepted: {
            // Disconnect from current server
            bridge.disconnectFromServer();
            // Go back to server selection
            voiceAssistantPage.selectNewServer();
        }
    }

    // Conversation display area
    ConversationView {
        id: conversationView

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: inputArea.top
        anchors.bottomMargin: 4 // Add a gap between conversation and input area
        anchors.margins: ThemeManager.spacingNormal

        // Force model refresh when conversation changes
        Component.onCompleted: {
            updateModel(bridge.get_conversation());
        }

        Connections {
            target: bridge
            
            function onConversationChanged() {
                conversationView.updateModel(bridge.get_conversation());
            }
            
            function onMessageReceived(message, timestamp) {
                isProcessing = false;
                isListening = false;
                statusText = "Ready";
                // Delay turning off response mode slightly to ensure the final message is rendered
                responseEndTimer.start();
            }
            
            function onListeningStarted() {
                isListening = true;
                statusText = "Listening...";
                messageToast.showMessage("Listening...", 1500);
            }
            
            function onListeningStopped() {
                isListening = false;
                statusText = "Processing...";
                isProcessing = true;
                // Set response in progress to lock scrolling
                conversationView.setResponseInProgress(true);
            }
            
            function onErrorOccurred(errorMessage) {
                messageToast.showMessage("Error: " + errorMessage, 3000);
                isProcessing = false;
                isListening = false;
                statusText = "Ready";
                // Enable scrolling on error
                conversationView.setResponseInProgress(false);
            }
            
            function onStatusChanged(newStatus) {
                statusText = newStatus;
            }
        }
    }

    // Message toast
    MessageToast {
        id: messageToast

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: inputArea.top
        anchors.bottomMargin: ThemeManager.spacingNormal
    }

    // Input area
    InputArea {
        id: inputArea

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        z: 2 // Ensure input area is above other elements
        isListening: voiceAssistantPage.isListening
        isProcessing: voiceAssistantPage.isProcessing
        compact: false
        onTextSubmitted: function(messageText) {
            statusText = "Processing...";
            isProcessing = true;
            // Set response in progress to lock scrolling
            conversationView.setResponseInProgress(true);
            bridge.submit_query(messageText);
        }
        onVoiceToggled: function(listening) {
            if (listening) {
                isListening = true;
                statusText = "Listening...";
                bridge.start_listening();
            } else {
                isListening = false;
                statusText = "Processing...";
                isProcessing = true;
                // Set response in progress to lock scrolling
                conversationView.setResponseInProgress(true);
                bridge.stop_listening();
            }
        }
        onSettingsClicked: pushSettingsPage()
    }

    // Timer to delay disabling response mode to ensure UI is updated
    Timer {
        id: responseEndTimer

        interval: 500 // Half-second delay
        repeat: false
        onTriggered: {
            // Response complete, enable scrolling again
            conversationView.setResponseInProgress(false);
        }
    }
}
