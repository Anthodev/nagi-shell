pragma ComponentBehavior: Bound

import QtQuick

// Semantic compact weather glyph for the island.
//
// One symbolic line-art family drawn from Theme tokens; provider symbols
// never reach this component, only the adapter's normalized condition enum
// (clear, mostlyClear, partlyCloudy, cloudy, fog, rain, sleet, snow,
// thunderstorm, unknown) and dayPhase (day, night, polartwilight). Night
// variants use a crescent; polartwilight keeps the day sun. The Canvas
// repaints only when its inputs change, so settled idle rendering does no
// continuous work.
Item {
    id: glyph

    property string condition: "unknown"
    property string dayPhase: "day"
    property color tint: Theme.color.textSecondary

    implicitWidth: Theme.size.iconSizeSm
    implicitHeight: Theme.size.iconSizeSm

    // Weather is already conveyed by adjacent text; the glyph is decorative.
    Accessible.ignored: true

    onConditionChanged: canvas.requestPaint()
    onDayPhaseChanged: canvas.requestPaint()
    onTintChanged: canvas.requestPaint()

    function paint(context) {
        context.reset();
        context.lineWidth = 1.3;
        context.lineCap = "round";
        context.lineJoin = "round";
        context.strokeStyle = String(tint);
        context.fillStyle = String(tint);

        switch (condition) {
        case "clear":
            drawSky(context, true);
            break;
        case "mostlyClear":
            drawSunOrMoon(context, 6.2, 6.2, 1.9, false);
            drawMiniCloud(context);
            break;
        case "partlyCloudy":
            drawSunOrMoon(context, 6.0, 6.0, 2.1, true);
            drawCloud(context, 8.8, 9.4, 1.0);
            break;
        case "cloudy":
            drawCloud(context, 8.0, 8.4, 1.15);
            break;
        case "fog":
            drawCloud(context, 8.0, 7.4, 1.05);
            drawLine(context, 3.6, 12.4, 10.6);
            drawLine(context, 5.4, 14.2, 12.4);
            break;
        case "rain":
            drawPrecipitation(context, "rain");
            break;
        case "sleet":
            drawPrecipitation(context, "sleet");
            break;
        case "snow":
            drawPrecipitation(context, "snow");
            break;
        case "thunderstorm":
            drawCloud(context, 8.0, 7.2, 1.05);
            context.beginPath();
            context.moveTo(9.4, 9.8);
            context.lineTo(7.8, 12.4);
            context.lineTo(9.2, 12.4);
            context.lineTo(7.6, 15.0);
            context.stroke();
            break;
        default:
            context.setLineDash([2, 2]);
            context.beginPath();
            context.arc(8, 8, 4.2, 0, Math.PI * 2);
            context.stroke();
            context.setLineDash([]);
            break;
        }
    }

    function drawSky(context, withRays) {
        if (isNight() && !withRays) {
            return;
        }

        if (isNight()) {
            drawMoon(context);
            return;
        }

        context.beginPath();
        context.arc(8, 8, 2.5, 0, Math.PI * 2);
        context.stroke();
        if (!withRays) {
            return;
        }

        for (let index = 0; index < 8; index += 1) {
            const angle = Math.PI * index / 4;
            context.moveTo(8 + Math.cos(angle) * 3.7, 8 + Math.sin(angle) * 3.7);
            context.lineTo(8 + Math.cos(angle) * 5.2, 8 + Math.sin(angle) * 5.2);
        }
        context.stroke();
    }

    function drawSunOrMoon(context, centerX, centerY, radius, withRays) {
        if (isNight()) {
            drawMoonAt(context, centerX, centerY, radius);
            return;
        }

        context.beginPath();
        context.arc(centerX, centerY, radius, 0, Math.PI * 2);
        context.stroke();
        if (!withRays) {
            return;
        }

        for (let index = 0; index < 8; index += 1) {
            const angle = Math.PI * index / 4;
            context.moveTo(centerX + Math.cos(angle) * (radius + 1.0), centerY + Math.sin(angle) * (radius
                                                                                                    + 1.0));
            context.lineTo(centerX + Math.cos(angle) * (radius + 2.2), centerY + Math.sin(angle) * (radius
                                                                                                    + 2.2));
        }
        context.stroke();
    }

    function isNight() {
        return dayPhase === "night";
    }

    function drawMoon(context) {
        drawMoonAt(context, 8, 8, 4.0);
    }

    function drawMoonAt(context, centerX, centerY, radius) {
        context.save();
        context.beginPath();
        context.arc(centerX, centerY, radius, 0, Math.PI * 2);
        context.fill();
        context.globalCompositeOperation = "destination-out";
        context.beginPath();
        context.arc(centerX + radius * 0.55, centerY - radius * 0.55, radius * 0.85, 0, Math.PI
                    * 2);


        context.fill();
        context.restore();
    }

    // One soft cloud silhouette centered near (centerX, baseY); scale grows
    // upward from the flat bottom edge.
    function drawCloud(context, centerX, baseY, scale) {
        const smallRadius = 1.9 * scale;
        const largeRadius = 2.3 * scale;
        const leftCenterX = centerX - largeRadius * 1.05;
        const rightCenterX = centerX + largeRadius * 1.05;
        context.beginPath();
        context.moveTo(leftCenterX - smallRadius, baseY);
        context.arc(leftCenterX, baseY - smallRadius * 0.35, smallRadius, Math.PI * 0.85, Math.PI
                    * 1.65);
        context.arc(centerX, baseY - largeRadius * 0.75, largeRadius, Math.PI * 1.2, Math.PI
                    * 1.95);
        context.arc(rightCenterX, baseY - smallRadius * 0.45, smallRadius, Math.PI * 1.55, Math.PI
                    * 0.15);
        context.closePath();
        context.stroke();
    }

    function drawMiniCloud(context) {
        drawCloud(context, 10.6, 11.4, 0.62);
    }

    function drawLine(context, x, y, endX) {
        context.beginPath();
        context.moveTo(x, y);
        context.lineTo(endX, y);
        context.stroke();
    }

    function drawPrecipitation(context, kind) {
        drawCloud(context, 8.0, 7.6, 1.1);
        if (kind === "rain" || kind === "sleet") {
            context.beginPath();
            context.moveTo(5.6, 10.6);
            context.lineTo(4.9, 12.8);
            context.moveTo(8.2, 10.8);
            context.lineTo(7.5, 13.0);
            if (kind === "rain") {
                context.moveTo(10.8, 10.6);
                context.lineTo(10.1, 12.8);
            }
            context.stroke();
        }
        if (kind === "snow" || kind === "sleet") {
            const dots = kind === "snow" ? [5.2, 8.0, 10.8] : [10.6];
            context.beginPath();
            for (let index = 0; index < dots.length; index += 1) {
                context.moveTo(dots[index] + 0.8, 12.2);
                context.arc(dots[index], 12.2, 0.8, 0, Math.PI * 2);
            }
            context.fill();
        }
    }

    Canvas {
        id: canvas

        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = canvas.getContext("2d");
            if (ctx !== null && ctx !== undefined) {
                glyph.paint(ctx);
            }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }
}
