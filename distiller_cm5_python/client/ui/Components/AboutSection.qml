import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

AppSection {
    id: aboutSection

    title: "About"

    ColumnLayout {
        width: parent.width
        spacing: ThemeManager.spacingNormal

        // App logo image that changes based on theme
        OptimizedImage {
            id: logoImage

            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 100
            Layout.preferredHeight: 100
            Layout.topMargin: ThemeManager.spacingNormal
            Layout.bottomMargin: ThemeManager.spacingNormal

            source: ThemeManager.darkMode ? "../images/pamir_logo_white.png" : "../images/pamir_logo.png"
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 200
            sourceSize.height: 200

            // Set fadeInDuration to match the theme animation duration
            fadeInDuration: ThemeManager.animationDuration

            // Add a smooth transition when theme changes
            Behavior on source {
                PropertyAnimation {
                    target: logoImage
                    property: "opacity"
                    from: 0.8
                    to: 1.0
                    duration: ThemeManager.animationDuration
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: ThemeManager.spacingSmall

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: AppInfo.appName.split(" ")[0]
                color: ThemeManager.textColor
                font.pixelSize: FontManager.fontSizeXLarge
                font.bold: true
                font.family: FontManager.primaryFontFamily
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: AppInfo.appName.split(" ").slice(1).join(" ")
                color: ThemeManager.secondaryTextColor
                font.pixelSize: FontManager.fontSizeMedium
                font.family: FontManager.primaryFontFamily
            }

            // Version information
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: AppInfo.shortVersionString
                color: ThemeManager.tertiaryTextColor
                font.pixelSize: FontManager.fontSizeSmall
                font.family: FontManager.primaryFontFamily
                topPadding: 4
            }
        }
    }
}
