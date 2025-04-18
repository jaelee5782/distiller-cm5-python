import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

AppSection {
    id: llmSettingsSection

    property alias serverUrl: serverUrlInput.text
    property alias modelName: modelNameInput.text
    property alias providerTypeIndex: providerComboBox.currentIndex
    property alias apiKey: apiKeyInput.text
    property alias temperature: temperatureSlider.value
    property alias enableStreaming: streamingItem.toggleValue
    property alias maxTokens: maxTokensInput.text
    readonly property string providerTypeText: providerComboBox.currentText

    // Signal for when configuration changes are applied
    signal configChanged()

    // Helper function to convert provider type string to ComboBox index
    function getProviderTypeIndex(type) {
        switch(type) {
            case "llama-cpp": return 0;
            case "openrouter": return 1;
            default: return 0;
        }
    }

    // Helper function to safely get config values with fallbacks
    function safeGetConfigValue(section, key, fallback) {
        if (bridge && bridge.ready) {
            var value = bridge.getConfigValue(section, key);
            
            // For boolean values like streaming
            if (key === "streaming") {
                console.log("Raw streaming value from bridge: '" + value + "' (type: " + (typeof value) + ")");
                
                // Handle various forms of true/false values
                if (value === "true" || value === "True" || value === true || value === "1" || value === 1) {
                    return "true";
                } else if (value === "false" || value === "False" || value === false || value === "0" || value === 0) {
                    return "false";
                }
            }
            
            return value !== "" ? value : fallback;
        }
        return fallback;
    }

    // Function to refresh all settings from bridge
    function refresh() {
        if (bridge && bridge.ready) {
            serverUrl = safeGetConfigValue("llm", "server_url", "http://localhost:8000");
            providerTypeIndex = getProviderTypeIndex(safeGetConfigValue("llm", "provider_type", "llama-cpp"));
            modelName = safeGetConfigValue("llm", "model_name", "");
            apiKey = safeGetConfigValue("llm", "api_key", "");
            temperature = parseFloat(safeGetConfigValue("llm", "temperature", "0.7"));
            maxTokens = safeGetConfigValue("llm", "max_tokens", "4096");
            
            // Fix streaming setting initialization
            var streamingValue = safeGetConfigValue("llm", "streaming", "true");
            console.log("Streaming value from config: " + streamingValue);
            enableStreaming = (streamingValue === "true" || streamingValue === "True" || streamingValue === true);
        }
    }

    // Connect to bridge ready signal
    Connections {
        target: bridge
        
        function onBridgeReady() {
            // Refresh values when bridge becomes ready
            refresh();
        }
    }

    // Initialize with default values or from config
    Component.onCompleted: {
        refresh();
    }

    title: "LLM SETTINGS"
    compact: true

    ColumnLayout {
        width: parent.width
        spacing: ThemeManager.spacingLarge

        // Provider Type
        ColumnLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingNormal

            Text {
                text: "PROVIDER TYPE"
                font.pixelSize: FontManager.fontSizeNormal
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.secondaryTextColor
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: ThemeManager.borderRadius
                color: ThemeManager.backgroundColor
                border.color: ThemeManager.borderColor
                border.width: ThemeManager.borderWidth

                ComboBox {
                    id: providerComboBox
                    anchors.fill: parent
                    anchors.margins: 1
                    model: ["llama-cpp", "openrouter"]
                    
                    background: Rectangle {
                        color: "transparent"
                    }
                    
                    onCurrentTextChanged: {
                        if (bridge && bridge.ready) {
                            bridge.setConfigValue("llm", "provider_type", currentText);
                            
                            // Update server URL based on selected provider
                            var defaultServerUrl = currentText === "llama-cpp" ? 
                                "http://localhost:8000" : 
                                "https://openrouter.ai/api/v1";
                            
                            // Only set default if current URL is empty
                            if (!serverUrl) {
                                serverUrl = defaultServerUrl;
                                bridge.setConfigValue("llm", "server_url", serverUrl);
                            }
                            
                            configChanged();
                        }
                    }
                    
                    // Override text color
                    contentItem: Text {
                        leftPadding: 8
                        text: providerComboBox.displayText
                        font: FontManager.normal
                        color: ThemeManager.textColor
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    
                    // Override dropdown colors based on theme
                    popup: Popup {
                        y: providerComboBox.height
                        width: providerComboBox.width
                        
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: providerComboBox.popup.visible ? providerComboBox.delegateModel : null
                            
                            ScrollIndicator.vertical: ScrollIndicator {}
                        }
                        
                        background: Rectangle {
                            color: ThemeManager.backgroundColor
                            radius: ThemeManager.borderRadius
                            border.color: ThemeManager.borderColor
                            border.width: ThemeManager.borderWidth
                        }
                    }
                    
                    // Override dropdown item appearance
                    delegate: ItemDelegate {
                        width: providerComboBox.width
                        height: 40
                        
                        contentItem: Text {
                            text: modelData
                            font: FontManager.normal
                            color: ThemeManager.textColor
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignLeft
                            leftPadding: 8
                        }
                        
                        background: Rectangle {
                            color: highlighted ? ThemeManager.accentColor : "transparent"
                            opacity: highlighted ? 0.3 : 1.0
                        }
                        
                        highlighted: providerComboBox.highlightedIndex === index
                    }
                }
            }
        }

        // Server URL
        ColumnLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingNormal

            Text {
                text: "SERVER URL"
                font.pixelSize: FontManager.fontSizeNormal
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.secondaryTextColor
            }

            Rectangle {
                id: urlInputContainer
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(48, serverUrlInput.implicitHeight + 16)
                radius: ThemeManager.borderRadius
                color: ThemeManager.backgroundColor
                border.color: serverUrlInput.activeFocus ? ThemeManager.accentColor : ThemeManager.borderColor
                border.width: ThemeManager.borderWidth
                
                TextEdit {
                    id: serverUrlInput
                    anchors.fill: parent
                    anchors.margins: 8
                    font: FontManager.normal
                    color: ThemeManager.textColor
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    verticalAlignment: TextEdit.AlignVCenter
                    
                    onTextChanged: {
                        var contentHeight = serverUrlInput.contentHeight
                        urlInputContainer.height = Math.max(48, contentHeight + 16)
                        
                        if (bridge && bridge.ready) {
                            bridge.setConfigValue("llm", "server_url", text);
                            configChanged();
                        }
                    }
                }
            }
        }
        
        // Model Name
        ColumnLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingNormal

            Text {
                text: "MODEL NAME"
                font.pixelSize: FontManager.fontSizeNormal
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.secondaryTextColor
            }

            Rectangle {
                id: modelNameContainer
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(48, modelNameInput.implicitHeight + 16)
                radius: ThemeManager.borderRadius
                color: ThemeManager.backgroundColor
                border.color: modelNameInput.activeFocus ? ThemeManager.accentColor : ThemeManager.borderColor
                border.width: ThemeManager.borderWidth
                
                TextEdit {
                    id: modelNameInput
                    anchors.fill: parent
                    anchors.margins: 8
                    font: FontManager.normal
                    color: ThemeManager.textColor
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    verticalAlignment: TextEdit.AlignVCenter
                    
                    onTextChanged: {
                        var contentHeight = modelNameInput.contentHeight
                        modelNameContainer.height = Math.max(48, contentHeight + 16)
                        
                        if (bridge && bridge.ready) {
                            bridge.setConfigValue("llm", "model_name", text);
                            configChanged();
                        }
                    }
                }
            }
        }
        
        // API Key (hidden for llama-cpp)
        ColumnLayout {
            id: apiKeyLayout
            Layout.fillWidth: true
            spacing: ThemeManager.spacingNormal
            visible: providerComboBox.currentText !== "llama-cpp"

            Text {
                text: "API KEY"
                font.pixelSize: FontManager.fontSizeNormal
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.secondaryTextColor
            }

            Rectangle {
                id: apiKeyContainer
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(48, apiKeyInput.implicitHeight + 16)
                radius: ThemeManager.borderRadius
                color: ThemeManager.backgroundColor
                border.color: apiKeyInput.activeFocus ? ThemeManager.accentColor : ThemeManager.borderColor
                border.width: ThemeManager.borderWidth
                
                TextInput {
                    id: apiKeyInput
                    anchors.fill: parent
                    anchors.margins: 8
                    font: FontManager.normal
                    color: ThemeManager.textColor
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    echoMode: showPassword.checked ? TextInput.Normal : TextInput.Password
                    
                    onTextChanged: {
                        if (bridge && bridge.ready) {
                            bridge.setConfigValue("llm", "api_key", text);
                            configChanged();
                        }
                    }
                }
            }
            
            CheckBox {
                id: showPassword
                text: "Show API Key"
                checked: false
                contentItem: Text {
                    text: showPassword.text
                    font: FontManager.small
                    color: ThemeManager.secondaryTextColor
                    leftPadding: showPassword.indicator.width + showPassword.spacing
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
        
        // Temperature Slider
        ColumnLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingNormal

            RowLayout {
                Layout.fillWidth: true
                
                Text {
                    text: "TEMPERATURE"
                    font.pixelSize: FontManager.fontSizeNormal
                    font.family: FontManager.primaryFontFamily
                    color: ThemeManager.secondaryTextColor
                }
                
                Item { Layout.fillWidth: true }
                
                Text {
                    text: temperatureSlider.value.toFixed(1)
                    font.pixelSize: FontManager.fontSizeNormal
                    font.family: FontManager.primaryFontFamily
                    color: ThemeManager.secondaryTextColor
                }
            }

            CustomSlider {
                id: temperatureSlider
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                from: 0.0
                to: 1.0
                stepSize: 0.1
                value: 0.7
                showLabel: false
                
                onValueAdjusted: function(newValue) {
                    if (bridge && bridge.ready) {
                        bridge.setConfigValue("llm", "temperature", newValue.toString());
                        configChanged();
                    }
                }
            }
            
            // Helper text for temperature
            Text {
                text: "Lower values produce more focused output, higher values more creative"
                font.pixelSize: FontManager.fontSizeSmall
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.tertiaryTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
        
        // Max Tokens
        ColumnLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingNormal

            Text {
                text: "MAX TOKENS"
                font.pixelSize: FontManager.fontSizeNormal
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.secondaryTextColor
            }

            Rectangle {
                id: maxTokensContainer
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: ThemeManager.borderRadius
                color: ThemeManager.backgroundColor
                border.color: maxTokensInput.activeFocus ? ThemeManager.accentColor : ThemeManager.borderColor
                border.width: ThemeManager.borderWidth
                
                TextInput {
                    id: maxTokensInput
                    anchors.fill: parent
                    anchors.margins: 8
                    font: FontManager.normal
                    color: ThemeManager.textColor
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    validator: IntValidator { bottom: 10; top: 32768 }
                    
                    onTextChanged: {
                        if (bridge && bridge.ready) {
                            bridge.setConfigValue("llm", "max_tokens", text);
                            configChanged();
                        }
                    }
                }
            }
            
            // Helper text for max tokens
            Text {
                text: "Maximum number of tokens to generate"
                font.pixelSize: FontManager.fontSizeSmall
                font.family: FontManager.primaryFontFamily
                color: ThemeManager.tertiaryTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        // Streaming toggle
        SettingItem {
            id: streamingItem
            label: "ENABLE STREAMING"
            toggleValue: enableStreaming
            
            Component.onCompleted: {
                console.log("Streaming toggle initialized with value: " + toggleValue);
            }
            
            onToggleChanged: function(newValue) {
                console.log("Streaming toggle changed to: " + newValue);
                if (bridge && bridge.ready) {
                    // Update the configuration value
                    bridge.setConfigValue("llm", "streaming", newValue.toString());
                    
                    // Directly apply the streaming setting to the current client
                    if (bridge.isConnected()) {
                        console.log("Applying streaming setting to active client: " + newValue);
                        bridge.toggle_streaming(newValue);
                    } else {
                        console.log("Client not connected, cannot apply streaming setting immediately");
                    }
                    
                    configChanged();
                }
            }
        }
    }
}
