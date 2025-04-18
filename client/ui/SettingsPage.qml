import Components 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

PageBase {
    id: settingsPage
    
    pageName: "Settings"

    // Signal to navigate back to the previous page
    signal backClicked()

    // Helper function to safely get config values with fallbacks
    function safeGetConfigValue(section, key, fallback) {
        if (bridge && bridge.ready) {
            var value = bridge.getConfigValue(section, key);
            return value !== "" ? value : fallback;
        }
        return fallback;
    }
    
    // Connect to bridge ready signal
    Connections {
        target: bridge
        
        function onBridgeReady() {
            // Reset all components with updated config values when bridge becomes ready
            if (settingsPage.visible) {
                // Force update of all settings sections
                // This will cause them to read current values from the bridge
                settingsColumn.forceUpdate();
            }
        }
    }

    width: parent ? parent.width : 0
    height: parent ? parent.height : 0

    // White background for e-ink display
    Rectangle {
        anchors.fill: parent
        color: ThemeManager.backgroundColor
    }

    // Use the SettingsHeader component
    SettingsHeader {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 60 // Adjusted height without subtitle
        z: 2 // Ensure header stays above content
        showApplyButton: false // Hide the apply button from header
        onBackClicked: {
            settingsPage.backClicked();
        }
    }

    // Use AppScrollView instead of standard ScrollView
    AppScrollView {
        id: settingsScrollView
        
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 1 // Connect with header
        anchors.leftMargin: ThemeManager.spacingSmall // Reduced left margin
        anchors.rightMargin: ThemeManager.spacingSmall // Reduced right margin
        anchors.bottomMargin: applyButtonContainer.height + ThemeManager.spacingNormal // Make room for the floating button
        
        // Setting contentHeight explicitly for proper scrolling
        contentHeight: settingsColumn.height
        
        // Disable scroll position indicator
        showScrollIndicator: false
        
        // Content background for better visual clarity
        Rectangle {
            id: contentBackground
            width: settingsScrollView.width
            height: settingsColumn.height
            color: "transparent"
            
            // Light background shading for scrollable area
            Rectangle {
                anchors.fill: parent
                color: Qt.darker(ThemeManager.backgroundColor, 1.02) // Very subtle darkening
                visible: ThemeManager.darkMode ? false : true
                opacity: 0.5
            }
        }
        
        // Column of settings sections
        Column {
            id: settingsColumn
            // This ensures the column fills exactly the width of the ScrollView's content area
            width: settingsScrollView.width
            spacing: 0 // We're using the section's bottom margin for spacing
            
            // Function to force update of all children
            function forceUpdate() {
                for (var i = 0; i < children.length; i++) {
                    if (children[i].refresh) {
                        children[i].refresh();
                    }
                }
            }
            
            // Add top padding
            Item {
                width: parent.width
                height: ThemeManager.spacingNormal
            }
            
            // LLM Settings Section - make wider
            LlmSettingsSection {
                width: parent.width - ThemeManager.spacingSmall * 2 // Wider width
                anchors.horizontalCenter: parent.horizontalCenter
                bottomMargin: ThemeManager.spacingNormal
            }
            
            // Audio Settings Section
            AudioSettingsSection {
                width: parent.width - ThemeManager.spacingSmall * 2 // Wider width
                anchors.horizontalCenter: parent.horizontalCenter
                bottomMargin: ThemeManager.spacingNormal
                
                // Function to refresh settings from bridge
                function refresh() {
                    volume = parseFloat(safeGetConfigValue("audio", "volume", "0.5"));
                }
                
                volume: parseFloat(safeGetConfigValue("audio", "volume", "0.5"))
                onVolumeAdjusted: function(value) {
                    if (bridge && bridge.ready) bridge.setConfigValue("audio", "volume", value.toString());
                }
            }
            
            // Display Settings Section
            DisplaySettingsSection {
                width: parent.width - ThemeManager.spacingSmall * 2 // Wider width
                anchors.horizontalCenter: parent.horizontalCenter
                bottomMargin: ThemeManager.spacingNormal
                
                // Function to refresh settings from bridge
                function refresh() {
                    var savedTheme = safeGetConfigValue("display", "dark_mode", "");
                    if (savedTheme !== "") {
                        darkTheme = (savedTheme === "true" || savedTheme === "True");
                        ThemeManager.setDarkMode(darkTheme);
                    }
                }
                
                darkTheme: ThemeManager.darkMode
                Component.onCompleted: {
                    // Initialize from stored setting if available
                    refresh();
                }
                onDarkThemeToggled: function(enabled) {
                    ThemeManager.setDarkMode(enabled);
                    if (bridge && bridge.ready) bridge.setConfigValue("display", "dark_mode", enabled.toString());
                }
            }
            
            // Developer Settings Section
            DeveloperSettingsSection {
                width: parent.width - ThemeManager.spacingSmall * 2 // Wider width
                anchors.horizontalCenter: parent.horizontalCenter
                bottomMargin: ThemeManager.spacingNormal
                
                // Function to refresh settings from bridge
                function refresh() {
                    debugMode = safeGetConfigValue("logging", "level", "INFO") === "DEBUG";
                }
                
                debugMode: safeGetConfigValue("logging", "level", "INFO") === "DEBUG"
                onDebugModeToggled: function(enabled) {
                    if (bridge && bridge.ready) bridge.setConfigValue("logging", "level", enabled ? "DEBUG" : "INFO");
                }
            }
            
            // Network Information Section
            NetworkInfoSection {
                width: parent.width - ThemeManager.spacingSmall * 2 // Wider width
                anchors.horizontalCenter: parent.horizontalCenter
                bottomMargin: ThemeManager.spacingNormal
            }
            
            // About Section
            AboutSection {
                width: parent.width - ThemeManager.spacingSmall * 2 // Wider width
                anchors.horizontalCenter: parent.horizontalCenter
                bottomMargin: ThemeManager.spacingNormal
            }
            
            // Add some bottom padding
            Item {
                width: parent.width
                height: ThemeManager.spacingLarge
            }
        }
    }
    
    // Floating Apply button container
    Rectangle {
        id: applyButtonContainer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: ThemeManager.buttonHeight + ThemeManager.spacingNormal
        color: ThemeManager.backgroundColor
        z: 2 // Ensure it stays above content
        
        // Subtle top shadow
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: ThemeManager.borderColor
            opacity: 0.5
        }
        
        // Apply button
        AppButton {
            id: applyButton
            anchors.centerIn: parent
            width: 120 // Fixed width for consistency
            height: ThemeManager.buttonHeight * 0.7
            text: "Apply"
            useFixedHeight: false
            enabled: bridge && bridge.ready
            
            onClicked: {
                if (bridge && bridge.ready) {
                    bridge.saveConfigToFile();
                    bridge.applyConfig();
                }
            }
        }
    }
}
