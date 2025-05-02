import QtQuick 2.15
pragma Singleton

QtObject {
    // Subtle overlay for hover effects
    // No animations for e-ink display
    // Standard button height
    // Text on accent background: Black/White
    // Lighter version of accent color

    id: themeManager

    // Theme mode property - controls which theme to use
    property bool darkMode: false
    // Theme caching to reduce bridge calls
    property bool themeCached: false
    
    // Linear color palette arrays from white to black and vice versa
    readonly property var lightPalette: [
        "#FFFFFF", // 0: Pure white
        "#F0F0F0", // 1
        "#E1E1E1", // 2
        "#D2D2D2", // 3
        "#C3C3C3", // 4
        "#B4B4B4", // 5
        "#A5A5A5", // 6
        "#969696", // 7
        "#878787", // 8
        "#787878", // 9
        "#696969", // 10
        "#5A5A5A", // 11
        "#4B4B4B", // 12
        "#3C3C3C", // 13
        "#1a1a1a", // 14
        "#000000"  // 15: Pure black
    ]
    
    readonly property var darkPalette: [
        "#000000", // 0: Pure black
        "#1a1a1a", // 1
        "#3C3C3C", // 2
        "#4B4B4B", // 3
        "#5A5A5A", // 4
        "#696969", // 5
        "#787878", // 6
        "#878787", // 7
        "#969696", // 8
        "#A5A5A5", // 9
        "#B4B4B4", // 10
        "#C3C3C3", // 11
        "#D2D2D2", // 12
        "#E1E1E1", // 13
        "#F0F0F0", // 14
        "#FFFFFF"  // 15: Pure white
    ]
    
    // Main color properties using palette
    readonly property color backgroundColor: darkMode ? darkPalette[0] : lightPalette[0]  // Background: black/white
    readonly property color textColor: darkMode ? darkPalette[15] : lightPalette[15]  // Text: white/black
    readonly property color buttonColor: darkMode ? darkPalette[2] : lightPalette[2]  // Buttons: dark gray/light gray
    readonly property color accentColor: darkMode ? darkPalette[14] : lightPalette[12]  // Accent: near-white in dark mode, darker gray in light
    readonly property color borderColor: darkMode ? darkPalette[14] : lightPalette[12]  // Borders: medium gray
    readonly property color placeholderTextColor: darkMode ? darkPalette[10] : lightPalette[10]  // Placeholders: medium gray
    readonly property color headerColor: darkMode ? darkPalette[1] : lightPalette[1]  // Headers: near-black/near-white
    readonly property color secondaryTextColor: darkMode ? darkPalette[12] : lightPalette[12]  // Secondary text: lighter gray/darker gray
    readonly property color tertiaryTextColor: darkMode ? darkPalette[8] : lightPalette[8]  // Tertiary text: medium gray
    readonly property color pressedColor: darkMode ? darkPalette[3] : lightPalette[3]  // Pressed state: dark gray/light gray
    readonly property color highlightColor: darkMode ? darkPalette[2] : lightPalette[2]  // Highlight: dark gray/light gray
    readonly property color subtleColor: darkMode ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.05)  // Subtle overlay
    
    // Additional color properties for focus states and button variants
    readonly property color focusBackgroundColor: darkMode ? darkPalette[13] : lightPalette[13]  // Background for focused items
    readonly property color focusBorderColor: darkMode ? darkPalette[15] : lightPalette[15]  // Border for focused items
    readonly property color focusTextColor: darkMode ? darkPalette[0] : lightPalette[0]  // Text for focused items
    readonly property color textOnAccentColor: darkMode ? darkPalette[0] : lightPalette[0]  // Text on accent background
    
    // Transparent and utility colors
    readonly property color transparentColor: "transparent"  // Transparent color for backgrounds
    readonly property color shadowColor: darkMode ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0, 0, 0, 0.1)  // Shadow color for subtle effects
    readonly property color borderShadowColor: darkMode ? Qt.rgba(0, 0, 0, 0.2) : Qt.rgba(0, 0, 0, 0.05)  // Very subtle shadow for borders
    
    // Derived colors
    readonly property color lightShadeColor: darkMode ? Qt.lighter(backgroundColor, 1.2) : Qt.darker(backgroundColor, 1.02)  // Slight shade for background variation
    readonly property color darkAccentColor: Qt.darker(accentColor, 1.3)  // Darker version of accent color
    readonly property color lightAccentColor: Qt.lighter(accentColor, 1.5)  // Lighter version of accent color
    
    // Sizes and metrics
    readonly property real borderRadius: 6  // Border radius for rectangles
    readonly property real borderWidth: 2  // Border width
    readonly property real animationDuration: 0  // No animations for e-ink
    
    // Padding
    readonly property real paddingSmall: 4
    readonly property real paddingNormal: 8
    readonly property real paddingLarge: 12
    
    // Spacing
    readonly property real spacingSmall: 8
    readonly property real spacingNormal: 16
    readonly property real spacingLarge: 20
    readonly property real spacingTiny: 4
    
    // Component specific properties
    readonly property real buttonHeight: 36
    
    // Icon management - using more defined paths
    readonly property string basePath: "../../images/icons/"
    readonly property string lightIconPath: basePath
    readonly property string darkIconPath: basePath + "dark/"

    // Initialize theme from bridge settings
    function initializeTheme() {
        if (!themeCached && bridge && bridge.ready) {
            var savedTheme = bridge.getConfigValue("display", "dark_mode");
            if (savedTheme !== "")
                setDarkMode(savedTheme === "true" || savedTheme === "True");

            themeCached = true;
            return true;
        }
        return false;
    }

    // Helper function to get theme-appropriate icon path
    function getIconPath(iconName) {
        if (darkMode)
            return darkIconPath + iconName;

        return lightIconPath + iconName;
    }

    // Function to toggle theme
    function toggleTheme() {
        darkMode = !darkMode;
    }

    // Function to set theme explicitly
    function setDarkMode(isDark) {
        darkMode = isDark;
    }

    // Function to get a color from the current palette by index
    function getPaletteColor(index) {
        if (index < 0 || index > 15) {
            console.error("Invalid palette index: " + index + ". Must be between 0-15.");
            return darkMode ? darkPalette[0] : lightPalette[0];
        }
        
        return darkMode ? darkPalette[index] : lightPalette[index];
    }
}
