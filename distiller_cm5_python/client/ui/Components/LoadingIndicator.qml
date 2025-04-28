import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: busyIndicator

    property bool isLoading: true

    width: 80
    height: 80
    radius: 40
    color: ThemeManager.backgroundColor
    border.color: ThemeManager.borderColor
    border.width: ThemeManager.borderWidth
    visible: isLoading

    Text {
        id: loadingText

        anchors.centerIn: parent
        text: "Loading"
        font: FontManager.heading
        color: ThemeManager.textColor
    }

}
