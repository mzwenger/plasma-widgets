import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Configuración: "letra|nombre|origen"
    readonly property var def: {
        const p = Plasmoid.configuration.disk.split("|").map(s => s.trim())
        return { letter: p[0] || "?", name: p[1] || p[0] || "Disco", source: p[2] || "/" }
    }
    readonly property bool isRawDevice: def.source.startsWith("/dev/")
    readonly property string quoted: "'" + def.source.replace(/'/g, "'\\''") + "'"

    // Espacio de la partición marcada (bytes). avail < 0 = sin dato
    property real size: 0
    property real avail: -1
    property string shownId: ""
    property string shownName: ""
    property string shownType: ""
    property string activityDev: ""
    // Actividad: % del tiempo en que la partición estuvo ocupada, y velocidades en bytes/s
    property real busy: 0
    property real readRate: 0
    property real writeRate: 0
    property var prev: null

    readonly property bool spaceKnown: size > 0 && avail >= 0
    readonly property real usedFraction: spaceKnown ? 1 - avail / size : 0
    readonly property real freePercent: spaceKnown ? 100 * avail / size : 0
    readonly property real totalRate: readRate + writeRate

    readonly property color okColor: "#2ecc71"
    readonly property color warnColor: "#f39c12"
    readonly property color busyWarnColor: "#f1c40f"
    readonly property color critColor: "#e74c3c"

    readonly property color spaceColor: !spaceKnown ? Kirigami.Theme.disabledTextColor
        : freePercent < Plasmoid.configuration.critPercent ? critColor
        : freePercent < Plasmoid.configuration.warnPercent ? warnColor
        : okColor
    readonly property color busyColor: busy > Plasmoid.configuration.busyCrit ? critColor
        : busy >= Plasmoid.configuration.busyWarn ? busyWarnColor
        : okColor

    readonly property string scriptFile: {
        let u = Qt.resolvedUrl("../code/disk-info.py").toString()
        if (u.startsWith("file://"))
            u = decodeURIComponent(u.substring(7))
        return u
    }

    Plasmoid.title: def.name
    toolTipMainText: def.name
    toolTipSubText: (shownName ? shownName + (shownType ? " · " + shownType : "") + "\n" : "")
        + "Actividad " + Math.round(busy) + "% · " + formatRate(totalRate) + "\n"
        + (spaceKnown ? formatBytes(avail) + " libres de " + formatBytes(size) : "Espacio sin datos")

    // Todas las particiones del disco, cada 60 s
    readonly property string listCommand: "/usr/bin/python3 " + shellQuote(scriptFile) + " " + quoted + " " + shellQuote(def.name)

    // Actividad de la partición marcada. Antes de la primera lista, la del origen.
    readonly property string activityCommand: activityDev
        ? "awk -v d=" + shellQuote(activityDev) + " '$3==d{print $6, $10, $13}' /proc/diskstats; cut -d' ' -f1 /proc/uptime"
        : "d=$(basename \"$(readlink -f " + (isRawDevice ? quoted : "\"$(findmnt -nvo SOURCE --target " + quoted + ")\"") + ")\"); "
          + "awk -v d=\"$d\" '$3==d{print $6, $10, $13}' /proc/diskstats; cut -d' ' -f1 /proc/uptime"

    ListModel { id: partModel }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            const out = data["stdout"] || ""
            if (source === root.listCommand) root.parseList(out)
            else if (source === root.activityCommand) root.parseActivity(out)
        }
    }

    function shellQuote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'"
    }

    function run(cmd) {
        if (executable.connectedSources.indexOf(cmd) < 0) executable.connectSource(cmd)
    }

    function parseList(out) {
        let data
        try {
            data = JSON.parse(out)
        } catch (e) {
            return
        }
        if (!data || !data.parts) return
        const incoming = data.parts
        let same = partModel.count === incoming.length
        if (same) {
            for (let i = 0; i < incoming.length; i++) {
                if (partModel.get(i).partId !== (incoming[i].id || "")) {
                    same = false
                    break
                }
            }
        }
        if (!same) partModel.clear()
        for (let i = 0; i < incoming.length; i++) {
            const p = incoming[i]
            const row = {
                partId: p.id || "",
                kname: p.kname || "",
                title: p.name || "",
                fsType: p.type || "",
                bytes: p.size || 0,
                freeBytes: (p.free === null || p.free === undefined) ? -1 : p.free,
                isDefault: !!p.isDefault
            }
            if (same) partModel.set(i, row)
            else partModel.append(row)
        }
        applySelection()
    }

    function selectedIndex() {
        const want = Plasmoid.configuration.graphPart || ""
        let fallback = -1
        for (let i = 0; i < partModel.count; i++) {
            const row = partModel.get(i)
            if (want && row.partId === want) return i
            if (row.isDefault) fallback = i
        }
        return fallback
    }

    function applySelection() {
        const idx = selectedIndex()
        if (idx < 0) {
            size = 0
            avail = -1
            shownId = ""
            shownName = ""
            shownType = ""
            return
        }
        const row = partModel.get(idx)
        size = row.bytes
        avail = row.freeBytes
        shownId = row.partId
        shownName = row.title
        shownType = row.fsType
        if (activityDev !== row.kname) {
            activityDev = row.kname
            prev = null
        }
    }

    function choose(partId) {
        if (!partId || Plasmoid.configuration.graphPart === partId) return
        Plasmoid.configuration.graphPart = partId
        applySelection()
    }

    function parseActivity(out) {
        const lines = out.trim().split("\n")
        if (lines.length < 2) return
        const c = lines[0].trim().split(/\s+/).map(Number)
        const now = { sr: c[0], sw: c[1], ticks: c[2], t: parseFloat(lines[1]) }
        if (prev && now.t > prev.t) {
            const dt = now.t - prev.t
            busy = Math.max(0, Math.min(100, (now.ticks - prev.ticks) / (dt * 10)))
            readRate = Math.max(0, (now.sr - prev.sr) * 512 / dt)
            writeRate = Math.max(0, (now.sw - prev.sw) * 512 / dt)
        }
        prev = now
    }

    // Unidades de 1024. Por debajo de 10, un decimal, para que 100 MB no salga como 0 GB.
    function formatBytes(b) {
        if (b < 0) return "—"
        const u = 1024
        if (b < u) return Math.round(b) + " B"
        const kb = b / u
        if (kb < u) return (kb < 10 ? kb.toFixed(1) : Math.round(kb)) + " KB"
        const mb = kb / u
        if (mb < u) return (mb < 10 ? mb.toFixed(1) : Math.round(mb)) + " MB"
        const gb = mb / u
        if (gb < 1000) return (gb < 10 ? gb.toFixed(1) : Math.round(gb)) + " GB"
        return (gb / u).toFixed(1) + " TB"
    }
    function formatRate(b) {
        const m = b / 1048576
        if (m >= 100) return Math.round(m) + " MB/s"
        if (m >= 0.1) return m.toFixed(1) + " MB/s"
        return "0 MB/s"
    }
    function spaceText(free, bytes) {
        if (!(bytes > 0)) return "—"
        if (free < 0) return "— libres de " + formatBytes(bytes)
        return formatBytes(free) + " libres de " + formatBytes(bytes)
    }
    function barColor(free, bytes) {
        if (!(bytes > 0) || free < 0) return Kirigami.Theme.disabledTextColor
        const pct = 100 * free / bytes
        if (pct < Plasmoid.configuration.critPercent) return critColor
        if (pct < Plasmoid.configuration.warnPercent) return warnColor
        return okColor
    }
    function barUsed(free, bytes) {
        if (!(bytes > 0) || free < 0) return 0
        return 1 - free / bytes
    }

    Timer {
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: true
        onTriggered: root.run(root.listCommand)
    }
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: true
        onTriggered: root.run(root.activityCommand)
    }
    onExpandedChanged: if (expanded) run(listCommand)

    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: height
        Layout.preferredWidth: height
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Canvas {
            id: ring
            anchors.fill: parent
            anchors.margins: Math.round(parent.height * 0.08)
            property real busy: root.busy
            property real used: root.usedFraction
            property color busyColor: root.busyColor
            property color spaceColor: root.spaceColor
            property color bg: Kirigami.Theme.textColor
            onBusyChanged: requestPaint()
            onUsedChanged: requestPaint()
            onBusyColorChanged: requestPaint()
            onSpaceColorChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const w = Math.min(width, height)
                const lw = Math.max(2, w * 0.09)
                const r = w / 2 - lw / 2
                const cx = width / 2, cy = height / 2

                ctx.lineWidth = lw
                ctx.strokeStyle = Qt.rgba(bg.r, bg.g, bg.b, 0.15)
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke()
                if (busy > 0) {
                    ctx.strokeStyle = busyColor
                    ctx.lineCap = "round"
                    const start = -Math.PI / 2
                    ctx.beginPath(); ctx.arc(cx, cy, r, start, start + 2 * Math.PI * busy / 100); ctx.stroke()
                }

                const ri = r - lw / 2 - Math.max(1, w * 0.05)
                ctx.fillStyle = Qt.rgba(bg.r, bg.g, bg.b, 0.06)
                ctx.beginPath(); ctx.arc(cx, cy, ri, 0, 2 * Math.PI); ctx.fill()
                if (used > 0) {
                    const h = 2 * ri * used
                    ctx.save()
                    ctx.beginPath(); ctx.arc(cx, cy, ri, 0, 2 * Math.PI); ctx.clip()
                    ctx.fillStyle = Qt.rgba(spaceColor.r, spaceColor.g, spaceColor.b, 0.55)
                    ctx.fillRect(0, cy + ri - h, width, h)
                    ctx.restore()
                }
            }
        }

        PlasmaComponents.Label {
            anchors.centerIn: parent
            text: Math.round(root.busy) + "%"
            font.pixelSize: Math.max(8, compact.height * 0.30)
            font.bold: true
            color: root.busy >= 1 ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
        }

        Rectangle {
            readonly property int d: Math.max(10, Math.round(compact.height * 0.36))
            width: d
            height: d
            radius: d / 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.5)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: root.def.letter
                font.pixelSize: Math.max(7, Math.round(parent.d * 0.62))
                font.bold: true
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 28
        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * (14 + Math.max(partModel.count, 1) * 3)
        Layout.minimumHeight: Kirigami.Units.gridUnit * (14 + Math.max(partModel.count, 1) * 3)

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    source: root.def.source === "/" ? "computer" : "drive-harddisk"
                }
                Kirigami.Heading {
                    level: 3
                    text: root.def.name
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    opacity: 0.8
                    text: Math.round(root.busy) + "% · " + root.formatRate(root.totalRate)
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing * 2
            spacing: Kirigami.Units.smallSpacing

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: Kirigami.Units.smallSpacing * 2
                rowSpacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label { text: "Actividad" }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 0.5
                    radius: height / 2
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width * root.busy / 100
                        radius: parent.radius
                        color: root.busyColor
                    }
                }
                PlasmaComponents.Label {
                    opacity: 0.8
                    text: Math.round(root.busy) + "% · " + root.formatRate(root.totalRate)
                }

                PlasmaComponents.Label { text: "Lectura" }
                PlasmaComponents.Label {
                    Layout.columnSpan: 2
                    opacity: 0.8
                    text: root.formatRate(root.readRate)
                }

                PlasmaComponents.Label { text: "Escritura" }
                PlasmaComponents.Label {
                    Layout.columnSpan: 2
                    opacity: 0.8
                    text: root.formatRate(root.writeRate)
                }
            }

            PlasmaComponents.Label {
                text: "Particiones"
                font.bold: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }

            Column {
                id: partList
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: partModel
                delegate: RowLayout {
                    width: partList.width
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.CheckBox {
                        checked: model.partId === root.shownId
                        onClicked: root.choose(model.partId)
                    }
                    PlasmaComponents.Label {
                        text: model.title
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                        elide: Text.ElideRight
                    }
                    PlasmaComponents.Label {
                        text: model.fsType
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                        opacity: 0.7
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.45
                        radius: height / 2
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * root.barUsed(model.freeBytes, model.bytes)
                            radius: parent.radius
                            color: root.barColor(model.freeBytes, model.bytes)
                        }
                    }
                    PlasmaComponents.Label {
                        text: root.spaceText(model.freeBytes, model.bytes)
                        opacity: 0.8
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                        elide: Text.ElideRight
                    }
                }
            }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
