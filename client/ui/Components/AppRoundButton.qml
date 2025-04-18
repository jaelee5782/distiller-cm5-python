import QtQuick 2.15
import QtQuick.Controls 2.15

RoundButton {
    id: root
    
    property string iconText: ""
    property real iconOpacity: 0.7
    property real hoverOpacity: 1.0
    property bool useHoverEffect: true
    property bool showBorder: false
    
    width: 36
    height: 36
    flat: true
    
    background: Rectangle {
        color: root.checked ? ThemeManager.subtleColor 
             : root.pressed ? ThemeManager.pressedColor 
             : "transparent"
        border.width: showBorder ? ThemeManager.borderWidth : 0
        border.color: showBorder ? ThemeManager.borderColor : "transparent"
        radius: width / 2
    }
    
    contentItem: Text {
        text: root.iconText
        font: FontManager.heading
        color: ThemeManager.textColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: (useHoverEffect && root.hovered) ? hoverOpacity : iconOpacity
        
        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }
    }
} 