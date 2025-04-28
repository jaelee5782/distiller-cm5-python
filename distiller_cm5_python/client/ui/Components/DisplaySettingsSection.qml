import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

AppSection {
    id: displaySettingsSection

    property alias darkTheme: darkThemeItem.toggleValue
    property bool isDirty: false

    signal darkThemeToggled(bool enabled)
    signal configChanged()

    // Function to get all navigable controls in this section
    function getNavigableControls() {
        var controls = [];
        if (darkThemeItem && darkThemeItem.visible) {
            // Get the toggle inside the setting item
            var toggle = darkThemeItem.getToggle();
            if (toggle && toggle.navigable)
                controls.push(toggle);

        }
        return controls;
    }

    function updateFromBridge() {
        if (bridge && bridge.ready) {
            // Try to use cached theme from ThemeManager first
            if (ThemeManager.themeCached) {
                darkTheme = ThemeManager.darkMode;
            } else {
                // Fall back to direct bridge call if needed
                var savedTheme = bridge.getConfigValue("display", "dark_mode");
                if (savedTheme !== "")
                    darkTheme = (savedTheme === "true" || savedTheme === "True");

                // Update ThemeManager's cache
                ThemeManager.themeCached = true;
            }
            isDirty = false;
        }
    }

    function getConfig() {
        return {
            "dark_mode": darkTheme.toString()
        };
    }

    title: "DISPLAY SETTINGS"
    navigable: true
    // Keyboard navigation within the section
    Keys.onReturnPressed: {
        if (darkThemeItem) {
            var toggle = darkThemeItem.getToggle();
            if (toggle)
                toggle.forceActiveFocus();

        }
    }

    ColumnLayout {
        width: parent.width
        spacing: ThemeManager.spacingLarge

        // Description text for e-ink optimization
        Text {
            text: "Choose a theme optimized for e-ink display"
            font.pixelSize: FontManager.fontSizeNormal
            font.family: FontManager.primaryFontFamily
            color: ThemeManager.secondaryTextColor
            Layout.fillWidth: true
            Layout.bottomMargin: ThemeManager.spacingNormal
            wrapMode: Text.WordWrap
        }

        // Dark theme toggle
        SettingItem {
            id: darkThemeItem

            // Function to expose the toggle for navigation
            function getToggle() {
                // Access internal toggle by ID
                return toggle;
            }

            label: "DARK THEME"
            toggleValue: darkTheme
            onUserToggled: function(newValue) {
                displaySettingsSection.darkThemeToggled(newValue);
                displaySettingsSection.isDirty = true;
                displaySettingsSection.configChanged();
            }
        }

    }

}
