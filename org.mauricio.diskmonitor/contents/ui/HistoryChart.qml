import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Gráfico del último minuto. valuesA y valuesB van de más viejo a más nuevo.
ColumnLayout {
    id: chart

    property var valuesA: []
    property var valuesB: []
    property bool showB: false
    property color colorA: "#3daee9"
    property color colorB: "#e67e22"
    property string nameA: ""
    property string nameB: ""
    property string textA: ""
    property string textB: ""
    property real yMax: 0
    property real floor: 0
    property int samples: 30
    property string unit: ""

    readonly property real scale: {
        if (yMax > 0)
            return yMax
        let peak = 0
        const a = valuesA || []
        const b = showB ? (valuesB || []) : []
        for (let i = 0; i < a.length; i++)
            peak = Math.max(peak, a[i])
        for (let i = 0; i < b.length; i++)
            peak = Math.max(peak, b[i])
        return Math.max(peak, floor)
    }

    function scaleText() {
        if (unit === "%")
            return Math.round(scale) + "%"
        const n = scale >= 10 ? String(Math.round(scale)) : scale.toFixed(1)
        return unit ? n + " " + unit : n
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents.Label {
            text: chart.nameA + (chart.textA ? "  " + chart.textA : "")
            color: chart.colorA
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }
        PlasmaComponents.Label {
            visible: chart.showB
            text: chart.nameB + (chart.textB ? "  " + chart.textB : "")
            color: chart.colorB
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }
        Item { Layout.fillWidth: true }
        PlasmaComponents.Label {
            text: chart.scaleText()
            opacity: 0.55
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }
    }

    Canvas {
        id: plot
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        function paintSeries(ctx, values, color, bottom, top, left, width) {
            const n = chart.samples
            const len = values.length
            if (len < 1 || chart.scale <= 0)
                return
            function xOf(i) {
                const slot = n - len + i
                return left + (n <= 1 ? width : slot / (n - 1) * width)
            }
            function yOf(v) {
                const t = Math.max(0, Math.min(1, v / chart.scale))
                return bottom - t * (bottom - top)
            }
            ctx.beginPath()
            ctx.moveTo(xOf(0), bottom)
            for (let i = 0; i < len; i++)
                ctx.lineTo(xOf(i), yOf(values[i]))
            ctx.lineTo(xOf(len - 1), bottom)
            ctx.closePath()
            ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.28)
            ctx.fill()
            ctx.beginPath()
            for (let i = 0; i < len; i++) {
                const x = xOf(i)
                const y = yOf(values[i])
                if (i === 0)
                    ctx.moveTo(x, y)
                else
                    ctx.lineTo(x, y)
            }
            ctx.strokeStyle = color
            ctx.lineWidth = 1.5
            ctx.stroke()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const top = 2
            const bottom = height - 2
            ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(0, bottom)
            ctx.lineTo(width, bottom)
            ctx.stroke()
            paintSeries(ctx, chart.valuesA || [], chart.colorA, bottom, top, 0, width)
            if (chart.showB)
                paintSeries(ctx, chart.valuesB || [], chart.colorB, bottom, top, 0, width)
        }
    }

    onValuesAChanged: plot.requestPaint()
    onValuesBChanged: plot.requestPaint()
    onScaleChanged: plot.requestPaint()
    onShowBChanged: plot.requestPaint()
}
