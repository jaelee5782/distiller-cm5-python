import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

NavigableItem {
    id: delegateItem

    property bool isCurrentItem: false
    property string serverName: ""
    property string serverDescription: ""
    property string serverPath: ""
    property bool compact: true

    signal itemClicked(string path)

    width: parent.width
    height: contentLayout.height + ThemeManager.spacingSmall * 2
    
    // Override the base NavigableItem's clicked signal to emit itemClicked
    onClicked: {
        itemClicked(serverPath);
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: ThemeManager.borderRadius
        color: ThemeManager.backgroundColor
        border.color: delegateItem.visualFocus ? ThemeManager.accentColor : ThemeManager.borderColor
        border.width: delegateItem.visualFocus ? 2 : ThemeManager.borderWidth

        // Server selection indication - simpler for e-ink
        Rectangle {
            id: selectionIndicator
            anchors.fill: parent
            radius: ThemeManager.borderRadius
            color: ThemeManager.buttonColor
            opacity: delegateItem.isCurrentItem || delegateItem.visualFocus ? 0.5 : 0
        }
    }

    // Server display with proper padding
    RowLayout {
        id: contentLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: compact ? ThemeManager.spacingSmall : ThemeManager.spacingNormal
        spacing: ThemeManager.spacingSmall

        ColumnLayout {
            Layout.fillWidth: true
            spacing: compact ? 2 : ThemeManager.spacingSmall

            Text {
                text: serverName.toUpperCase()
                font: compact ? FontManager.normal : FontManager.heading
                color: ThemeManager.textColor
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                text: serverDescription || ""
                font: FontManager.small
                color: ThemeManager.secondaryTextColor
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: compact ? 1 : 2
                visible: text.length > 0
            }
        }

        // Use AppRoundButton instead of text
        AppRoundButton {
            iconText: "⏎" // Enter symbol
            Layout.alignment: Qt.AlignVCenter
            useHoverEffect: false
            onClicked: {
                delegateItem.itemClicked(serverPath);
            }
        }
    }

    // Add keyboard handling for Enter key
    Keys.onReturnPressed: {
        itemClicked(serverPath);
    }
}
