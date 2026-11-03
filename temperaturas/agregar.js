// Agrega a la barra el monitor de temperaturas (widget "Monitor del sistema" de KDE configurado).
// Uso: ./temperaturas/instalar.sh
var panel = panels()[0];
var w = panel.addWidget("org.kde.plasma.systemmonitor");

function set(group, values) {
    w.currentConfigGroup = group;
    for (var k in values) w.writeConfig(k, values[k]);
}

set([], { CurrentPreset: "org.kde.plasma.systemmonitor", popupHeight: 380, popupWidth: 440 });
// El panel lo dibuja CompactRepresentation.qml (una barra por highPrioritySensorIds).
// chartFace queda en barchart para no romper Ajustes; el desplegable es FullRepresentation.qml.
set(["Appearance"], { chartFace: "org.kde.ksysguard.barchart", title: "Temperaturas" });
set(["FaceConfig"], { rangeAuto: false, rangeFrom: 0, rangeTo: 100 });
set(["org.kde.ksysguard.linechart", "General"], {
    historyAmount: 60,
    rangeAutoY: false,
    rangeFromY: 0,
    rangeToY: 100,
    rangeFromYMultiplier: 1,
    rangeToYMultiplier: 1,
    lineChartStacked: false,
    lineChartSmooth: true,
    lineChartFillOpacity: 20,
    showLegend: true,
    showGridLines: true,
    showYAxisLabels: true
});

// Sensores: id -> [etiqueta, color RGB]. Los ids "lmsensors/..." y gpu/gpu0 dependen de este equipo.
// GPU es gpu/gpu0 (RTX 3090). gpu/gpu1 no existe y dejaba la barra vacía.
// Discos: pci-0100 = Linux (Samsung 990 PRO), pci-2500 = Windows (XPG). El panel
// compacto muestra una barra por NVMe (LIN y WIN).
var sensors = [
    ["cpu/all/maximumTemperature",       "CPU",                   "231,76,60"],
    ["gpu/gpu0/temperature",             "GPU",                   "46,204,113"],
    ["lmsensors/nct6795-isa-0a20/temp3", "VRM",                   "243,156,18"],
    ["lmsensors/nvme-pci-0100/temp1",    "Linux (Samsung)",       "189,195,199"],
    ["lmsensors/nvme-pci-2500/temp1",    "Windows (XPG)",         "127,140,141"]
];
var labels = {}, colors = {}, ids = [];
sensors.forEach(function (s) { ids.push(s[0]); labels[s[0]] = s[1]; colors[s[0]] = s[2]; });
set(["SensorLabels"], labels);
set(["SensorColors"], colors);
set(["Sensors"], { highPrioritySensorIds: JSON.stringify(ids), lowPrioritySensorIds: "[]", totalSensors: "[]" });

print("Monitor de temperaturas agregado (id " + w.id + ")");

