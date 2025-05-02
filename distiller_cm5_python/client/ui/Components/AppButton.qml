import QtQuick 2.15
import QtQuick.Controls 2.15

NavigableItem {
    id: root

    property bool isFlat: false
    property bool useFixedHeight: true
    property string text: ""
    property color backgroundColor: getBackgroundColor()
    property color textColor: root.visualFocus ? ThemeManager.focusTextColor : ThemeManager.textColor
    property color borderColor: "black"
    property int fontSize: FontManager.fontSizeNormal
    property int buttonRadius: ThemeManager.borderRadius
    // Define standalone pressed property for visual states
    property bool pressed: false

    function getBackgroundColor() {
        if (root.visualFocus)
            return ThemeManager.accentColor;

        return isFlat ? (ThemeManager.darkMode ? "black" : "white") : ThemeManager.buttonColor;
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

            return isFlat ? (ThemeManager.darkMode ? "black" : "white") : ThemeManager.buttonColor;
        }

        function getBorderColor() {
            if (root.visualFocus)
                return "black";

            // Always use black border for visibility on E-Ink
            return "black";
        }

        anchors.fill: parent
        color: root.backgroundColor
        border.color: getBorderColor()
        border.width: root.visualFocus ? 2 : 1 // Always show border for better visibility on E-Ink
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
