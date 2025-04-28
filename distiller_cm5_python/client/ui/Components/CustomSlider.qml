import QtQuick 2.15
import QtQuick.Layouts 1.15

// Reusable custom slider component that works with three-button navigation
NavigableItem {
    id: customSlider

    // Configurable properties
    property real value: 0.5
    property real from: 0
    property real to: 1
    property real stepSize: 0.05
    property bool pressed: false // Set directly
    property real visualPosition: (value - from) / (to - from)
    property string label: ""
    property string valueFormat: ""
    property bool showLabel: true

    // Signal emitted when value changes
    signal valueAdjusted(real newValue)

    // Override the base methods for Up/Down value adjustment
    function increaseValue() {
        adjustValue(stepSize);
    }

    function decreaseValue() {
        adjustValue(-stepSize);
    }

    // Helper function to adjust value
    function adjustValue(delta) {
        var newValue = value + delta;
        // Clamp to range
        newValue = Math.max(from, Math.min(to, newValue));
        // Update if changed
        if (value !== newValue) {
            value = newValue;
            valueAdjusted(newValue);
        }
    }

    // Navigation properties
    isAdjustable: true
    adjustmentStep: stepSize
    Layout.fillWidth: true
    height: showLabel ? labelText.height + sliderItem.height + 8 : sliderItem.height
    // Enter key behavior
    Keys.onReturnPressed: function() {
        // Enter slider adjustment mode
        // Exit slider adjustment mode

        if (!FocusManager.currentMode === FocusManager.sliderMode)
            FocusManager.enterSliderMode();
        else
            FocusManager.exitSpecialMode();
    }

    // Label text if enabled
    Text {
        id: labelText

        visible: showLabel
        text: label + (valueFormat !== "" ? " (" + valueFormat + ")" : "")
        font.pixelSize: FontManager.fontSizeNormal
        font.family: FontManager.primaryFontFamily
        color: customSlider.visualFocus ? ThemeManager.accentColor : ThemeManager.secondaryTextColor
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
    }

    // Slider implementation
    Item {
        id: sliderItem

        anchors.top: showLabel ? labelText.bottom : parent.top
        anchors.topMargin: showLabel ? 8 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        height: 40

        // Background track
        Rectangle {
            id: sliderBackground

            x: 0
            y: (parent.height - height) / 2
            width: parent.width
            height: 6
            radius: 3
            color: ThemeManager.buttonColor
            border.color: customSlider.visualFocus ? ThemeManager.accentColor : ThemeManager.borderColor
            border.width: customSlider.visualFocus ? 2 : ThemeManager.borderWidth

            // Filled portion
            Rectangle {
                width: customSlider.visualPosition * parent.width
                height: parent.height
                color: ThemeManager.accentColor
                radius: 3
            }

        }

        // Handle
        Rectangle {
            id: sliderHandle

            x: customSlider.visualPosition * (parent.width - width)
            y: (parent.height - height) / 2
            width: 20
            height: 20
            radius: 10
            color: customSlider.visualFocus ? ThemeManager.accentColor : ThemeManager.backgroundColor
            border.color: customSlider.visualFocus ? ThemeManager.accentColor : ThemeManager.borderColor
            border.width: customSlider.visualFocus ? 2 : ThemeManager.borderWidth
        }

    }

}
