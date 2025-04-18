import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: cardContainer

    property string serverName: ""
    property string serverDescription: ""
    property string serverPath: ""

    signal cardClicked(string path)

    width: 200
    height: 200

    // Drop shadow effect (subtle for e-ink displays)
    Rectangle {
        id: shadow
        anchors.fill: card
        anchors.margins: -2
        radius: card.radius + 2
        color: "transparent"
        border.color: ThemeManager.subtleColor
        border.width: 2
        z: 0
    }

    // Main card rectangle
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 12 // More rounded corners
        color: ThemeManager.backgroundColor
        border.color: ThemeManager.borderColor
        border.width: ThemeManager.borderWidth
        z: 1

        // Highlight effect on hover/press
        Rectangle {
            id: hoverIndicator
            anchors.fill: parent
            radius: parent.radius
            color: ThemeManager.buttonColor
            opacity: 0

            Behavior on opacity {
                NumberAnimation {
                    duration: ThemeManager.animationDuration / 2
                }
            }
        }

        // Card content
        Item {
            id: cardContent
            anchors.fill: parent
            anchors.margins: ThemeManager.spacingNormal / 2

            // Center content to ensure server name visibility
            ColumnLayout {
                id: contentLayout
                anchors.fill: parent
                spacing: 0  // Removed spacing

                // Server name container with guaranteed spacing
                Rectangle {
                    id: nameContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 0  // Removed margins
                    color: "transparent" // No background

                    // Background rectangle for server name
                    Rectangle {
                        id: nameBackground
                        anchors.fill: parent
                        color: ThemeManager.darkMode ? ThemeManager.buttonColor : ThemeManager.highlightColor
                        radius: ThemeManager.borderRadius
                        border.width: 0
                    }

                    // Server name text with improved visibility
                    Text {
                        id: nameText
                        anchors.centerIn: parent
                        width: parent.width - (ThemeManager.spacingSmall * 2) // Reduced margins on sides
                        height: parent.height - (ThemeManager.spacingSmall * 2) // Allow more vertical space
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: cardContainer.serverName.toUpperCase()
                        font {
                            pixelSize: FontManager.fontSizeNormal
                            family: FontManager.primaryFontFamily
                            weight: FontManager.fontWeightBold
                        }
                        color: ThemeManager.textColor
                        elide: Text.ElideNone // Prevent truncation
                        maximumLineCount: 5 // Increased max lines for longer names
                        wrapMode: Text.Wrap // Better handling of long words
                        // Scale down text if needed
                        fontSizeMode: Text.Fit // Changed to Fit to scale in both directions
                        minimumPixelSize: 8 // Slightly lower minimum size to fit more text
                    }
                }
            }
        }
    }

    // Use AppDialog for server description
    AppDialog {
        id: serverDescriptionDialog
        dialogTitle: cardContainer.serverName ? cardContainer.serverName.toUpperCase() : "SERVER DETAILS"
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        // Center the dialog on the screen
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        
        // Size constraints
        width: Math.min(400, cardContainer.parent ? cardContainer.parent.width * 0.9 : 400)
        height: Math.min(400, cardContainer.parent ? cardContainer.parent.height * 0.8 : 400)
        
        // Configure buttons to show only one centered button
        standardButtonTypes: DialogButtonBox.Ok
        okButtonText: "Close"
        showSecondaryAction: false  // Make sure no other buttons are shown
        
        // Custom content for scrollable description
        customContent: Item {
            id: descriptionContentContainer
            width: serverDescriptionDialog.width - ThemeManager.spacingLarge * 2
            height: 200 // This will be resized by the dialog
            
            ScrollView {
                id: descTextScroll
                anchors.fill: parent
                clip: true
                
                TextArea {
                    id: descriptionTextArea
                    text: cardContainer.serverDescription || "No description available"
                    font: FontManager.normal
                    color: ThemeManager.textColor
                    wrapMode: Text.WordWrap
                    readOnly: true
                    background: null
                    leftPadding: 0
                    rightPadding: 0
                    width: descTextScroll.width
                    textFormat: TextEdit.PlainText
                }
            }
        }
    }

    // Info button positioned over the card at bottom right
    Rectangle {
        id: infoButton
        anchors.right: card.right
        anchors.bottom: card.bottom
        anchors.rightMargin: ThemeManager.spacingSmall
        anchors.bottomMargin: ThemeManager.spacingSmall
        width: 24
        height: 24
        radius: width / 2
        color: infoMouseArea.containsMouse ? ThemeManager.pressedColor : ThemeManager.buttonColor
        border.color: ThemeManager.borderColor
        border.width: ThemeManager.borderWidth
        z: 10

        Text {
            id: infoIcon
            anchors.centerIn: parent
            text: "i"
            font.pixelSize: FontManager.fontSizeNormal
            font.family: FontManager.primaryFontFamily
            font.bold: true
            color: ThemeManager.textColor
        }
    }

    // Separate MouseArea just for the info button
    MouseArea {
        id: infoMouseArea
        anchors.fill: infoButton
        hoverEnabled: true
        z: 11

        onClicked: {
            serverDescriptionDialog.open();
        }
    }

    // Click and hover behavior for the card (but not the info button)
    MouseArea {
        id: cardMouseArea
        anchors.fill: parent
        hoverEnabled: true
        z: 2

        onEntered: {
            hoverIndicator.opacity = 0.2;
        }

        onExited: {
            hoverIndicator.opacity = 0;
        }

        onPressed: {
            // Don't show pressed state if clicking the info button area
            var mouseOverInfoButton = mouseX >= (infoButton.x - card.x) && mouseX <= (infoButton.x - card.x + infoButton.width) && mouseY >= (infoButton.y - card.y) && mouseY <= (infoButton.y - card.y + infoButton.height);

            if (!mouseOverInfoButton) {
                hoverIndicator.opacity = 0.4;
            }
        }

        onReleased: {
            hoverIndicator.opacity = 0.2;
        }

        onClicked: {
            // Calculate if click is over the info button
            var mouseOverInfoButton = mouseX >= (infoButton.x - card.x) && mouseX <= (infoButton.x - card.x + infoButton.width) && mouseY >= (infoButton.y - card.y) && mouseY <= (infoButton.y - card.y + infoButton.height);

            if (!mouseOverInfoButton) {
                clickTimer.start();
            }
        }
    }

    // Timer to allow visual feedback before triggering the action
    Timer {
        id: clickTimer
        interval: 200
        repeat: false
        onTriggered: {
            cardContainer.cardClicked(cardContainer.serverPath);
        }
    }
}
