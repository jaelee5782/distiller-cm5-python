import QtQuick 2.15
import QtQuick.Controls 2.15

NavigableItem {
    id: root

    property bool isFlat: false
    property bool useFixedHeight: true
    property string text: ""
    property color backgroundColor: getBackgroundColor()
    property color textColor: root.visualFocus ? ThemeManager.focusTextColor : ThemeManager.textColor
    property int fontSize: FontManager.fontSizeNormal
    property int buttonRadius: ThemeManager.borderRadius
    // Define standalone pressed property for visual states
    property bool pressed: false

    function getBackgroundColor() {
        if (root.visualFocus)
            return ThemeManager.accentColor;

        return isFlat ? "transparent" : ThemeManager.buttonColor;
    }

    width: parent ? parent.width : implicitWidth
    height: useFixedHeight ? ThemeManager.buttonHeight : implicitHeight
    // Add keyboard handling for Enter/Return
    Keys.onReturnPressed: function() {
        clicked();
    }

    // Style properties
    Rectangle {
        id: backgroundRect

        function getBackgroundColor() {
            if (root.visualFocus)
                return ThemeManager.accentColor;

            return isFlat ? "transparent" : ThemeManager.buttonColor;
        }

        function getBorderColor() {
            if (root.visualFocus)
                return ThemeManager.accentColor;

            return isFlat ? "transparent" : ThemeManager.borderColor;
        }

        anchors.fill: parent
        color: root.backgroundColor
        border.color: getBorderColor()
        border.width: root.visualFocus ? 2 : (isFlat ? 0 : ThemeManager.borderWidth)
        radius: buttonRadius
    }

    Text {
        anchors.centerIn: parent
        text: root.text
        color: root.textColor
        font.pixelSize: root.fontSize
        font.family: FontManager.primaryFontFamily
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

}
