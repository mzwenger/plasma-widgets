// Desplegable de temperaturas: un gráfico con una línea por sensor, último minuto.
// La barra sigue usando la cara de barras (chartFace = barchart).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.faces as Faces
import org.kde.ksysguard.formatter as Formatter
import org.kde.quickcharts as Charts
import org.kde.quickcharts.controls as ChartsControls

Item {
    id: root

    readonly property int sampleMs: 2000
    readonly property int historySeconds: 60

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    Layout.minimumHeight: Kirigami.Units.gridUnit * 16
    Layout.preferredHeight: Kirigami.Units.gridUnit * 20

    function colorOf(value) {
        const text = String(value ?? "")
        if (text.startsWith("#") || text.startsWith("rgb"))
            return text
        const parts = text.split(",")
        if (parts.length >= 3) {
            return Qt.rgba(parseInt(parts[0], 10) / 255, parseInt(parts[1], 10) / 255, parseInt(parts[2], 10) / 255, 1)
        }
        return text || "#888888"
    }

    readonly property var colorMap: {
        const src = Plasmoid.faceController ? Plasmoid.faceController.sensorColors : {}
        const out = {}
        if (src) {
            for (const key in src)
                out[key] = colorOf(src[key])
        }
        return out
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 3
            Layout.fillWidth: true
            text: (Plasmoid.faceController && Plasmoid.faceController.title) ? Plasmoid.faceController.title : "Temperaturas"
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 8

            ChartsControls.AxisLabels {
                visible: true
                Layout.fillHeight: true
                constrainToBounds: false
                direction: ChartsControls.AxisLabels.VerticalBottomTop
                delegate: QQC2.Label {
                    anchors.right: parent.right
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    text: Formatter.Formatter.formatValueShowNull(ChartsControls.AxisLabels.label, sensorsModel.unit)
                }
                source: Charts.ChartAxisSource {
                    chart: plot
                    axis: Charts.ChartAxisSource.YAxis
                    itemCount: 5
                }
            }

            Charts.LineChart {
                id: plot
                Layout.fillWidth: true
                Layout.fillHeight: true
                direction: Charts.XYChart.ZeroAtEnd
                fillOpacity: 0
                stacked: false
                interpolate: true

                yRange {
                    from: 0
                    to: 100
                    automatic: false
                }

                Sensors.SensorDataModel {
                    id: sensorsModel
                    sensors: Plasmoid.faceController ? Plasmoid.faceController.highPrioritySensorIds : []
                    sensorLabels: Plasmoid.faceController ? Plasmoid.faceController.sensorLabels : ({})
                    updateRateLimit: root.sampleMs
                    property int unit: (sensorsModel.ready && sensorsModel.headerData(0, Qt.Horizontal, Sensors.SensorDataModel.Unit)) ?? Formatter.Units.UnitInvalid
                }

                Instantiator {
                    model: sensorsModel.sensors
                    delegate: Charts.HistoryProxySource {
                        source: Charts.ModelSource {
                            model: sensorsModel
                            column: index
                            roleName: "Value"
                        }
                        interval: root.sampleMs
                        maximumHistory: (root.historySeconds * 1000) / interval
                        fillMode: Charts.HistoryProxySource.FillFromEnd
                    }
                    onObjectAdded: (index, object) => plot.insertValueSource(index, object)
                    onObjectRemoved: (index, object) => plot.removeValueSource(object)
                }

                colorSource: Charts.MapProxySource {
                    source: Charts.ArraySource {
                        array: Plasmoid.faceController ? Plasmoid.faceController.highPrioritySensorIds : []
                    }
                    map: root.colorMap
                }
                nameSource: Charts.ModelSource {
                    roleName: "Name"
                    model: sensorsModel
                    indexColumns: true
                }
                shortNameSource: Charts.ModelSource {
                    roleName: "ShortName"
                    model: sensorsModel
                    indexColumns: true
                }

                ChartsControls.GridLines {
                    anchors.fill: plot
                    z: plot.z - 1
                    chart: plot
                    direction: ChartsControls.GridLines.Vertical
                    major.count: 3
                    major.lineWidth: 1
                    major.color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.18)
                    minor.visible: false
                }
            }
        }

        Faces.ExtendedLegend {
            Layout.fillWidth: true
            chart: plot
            sourceModel: sensorsModel
            updateRateLimit: root.sampleMs
        }
    }
}
