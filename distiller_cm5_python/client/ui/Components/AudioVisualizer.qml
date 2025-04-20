import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: audioVisualizer

    property bool isActive: false
    property int barCount: 5
    
    width: parent.width
    height: parent.height
    color: "transparent"
    
    // Container for visualizer and text
    Item {
        anchors.centerIn: parent
        width: parent.width * 0.9
        height: parent.height * 0.8

        // Use Canvas for better e-ink performance with static visualization
        Canvas {
            id: canvas

            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var barWidth = width / (barCount * 2 - 1);
                var spacing = barWidth;
                
                // Draw static bars with varying heights for audio visualization
                ctx.fillStyle = ThemeManager.darkMode ? "#FFFFFF" : "#000000";
                for (let i = 0; i < barCount; i++) {
                    // Use fixed pattern that indicates recording state
                    var barHeight;
                    if (isActive) {
                        // When active, show middle bar tallest with alternating heights
                        if (i === 2) {
                            barHeight = height * 0.6; // Middle bar is tallest
                        } else if (i % 2 === 0) {
                            barHeight = height * 0.5; // Even bars tall
                        } else {
                            barHeight = height * 0.3; // Odd bars short
                        }
                    } else {
                        // When inactive, show all bars at same small height
                        barHeight = height * 0.2;
                    }
                    
                    var x = i * (barWidth + spacing);
                    var y = (height - barHeight) / 2;
                    
                    // Draw rounded rectangles for bars
                    ctx.beginPath();
                    var radius = 3;
                    ctx.moveTo(x + radius, y);
                    ctx.lineTo(x + barWidth - radius, y);
                    ctx.arcTo(x + barWidth, y, x + barWidth, y + radius, radius);
                    ctx.lineTo(x + barWidth, y + barHeight - radius);
                    ctx.arcTo(x + barWidth, y + barHeight, x + barWidth - radius, y + barHeight, radius);
                    ctx.lineTo(x + radius, y + barHeight);
                    ctx.arcTo(x, y + barHeight, x, y + barHeight - radius, radius);
                    ctx.lineTo(x, y + radius);
                    ctx.arcTo(x, y, x + radius, y, radius);
                    ctx.fill();
                }
            }
        }
        
        // Redraw when active state changes
        onVisibleChanged: canvas.requestPaint()
    }
    
    // Update the canvas when active state changes
    onIsActiveChanged: {
        canvas.requestPaint();
    }
}
