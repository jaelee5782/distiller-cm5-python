import QtQuick 2.15
import QtQuick.Controls 2.15

NavigableItem {
    id: root
    
    // Add signals
    signal pressed()
    signal released()

    property string iconText: ""
    property string text: ""
    property real iconOpacity: 0.7
    property bool useHoverEffect: false // Disabling hover effect since mouse is removed
    property bool showBorder: false
    property bool flat: true
    property bool checked: false
    
    // Define pressed property directly on root
    property bool pressed: false
    
    width: 36
    height: 36
    
    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        color: root.checked ? ThemeManager.subtleColor 
             : root.visualFocus ? ThemeManager.accentColor
             : "transparent"
        border.width: showBorder || root.visualFocus ? ThemeManager.borderWidth : 0
        border.color: root.visualFocus ? ThemeManager.accentColor : (showBorder ? ThemeManager.borderColor : "transparent")
        radius: width / 2
    }
    
    Text {
        id: textItem
        text: root.iconText || root.text
        font: FontManager.heading
        color: root.visualFocus ? 
               (ThemeManager.darkMode ? "#000000" : "#FFFFFF") : 
               ThemeManager.textColor
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: iconOpacity
    }
    
    // Add keyboard handling
    Keys.onReturnPressed: {
        clicked();
    }
} 