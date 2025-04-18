import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

AppSection {
    id: audioSettingsSection

    property alias volume: volumeSlider.value

    signal volumeAdjusted(real value)

    title: "AUDIO SETTINGS"
    compact: true

    ColumnLayout {
        width: parent.width
        spacing: ThemeManager.spacingNormal

        // Volume slider
        ColumnLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingNormal

            CustomSlider {
                id: volumeSlider
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                from: 0.0
                to: 1.0
                stepSize: 0.05
                value: 0.5
                label: "VOLUME"
                valueFormat: Math.round(value * 100) + "%"
                
                onValueAdjusted: function(newValue) {
                    audioSettingsSection.volumeAdjusted(newValue)
                }
            }
        }
    }
}
