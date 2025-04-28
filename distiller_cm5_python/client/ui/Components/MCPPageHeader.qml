import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: headerArea

    property string title: "Title"
    property string subtitle: "Subtitle"

    implicitHeight: headerColumn.height

    // Fixed header to avoid recalculation during scrolling
    Column {
        id: headerColumn

        width: parent.width
        spacing: 0

        Text {
            width: parent.width
            text: title.toUpperCase()
            font: FontManager.title
            color: ThemeManager.textColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            padding: ThemeManager.paddingSmall
        }

        Text {
            width: parent.width
            text: subtitle
            font: FontManager.small
            color: ThemeManager.secondaryTextColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            padding: ThemeManager.paddingSmall
            bottomPadding: ThemeManager.paddingSmall
            visible: text.length > 0
        }

    }

}
