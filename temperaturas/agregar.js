// Agrega a la barra el monitor de temperaturas (widget "Monitor del sistema" de KDE configurado).
// Uso: ./temperaturas/instalar.sh
var panel = panels()[0];
var w = panel.addWidget("org.kde.plasma.systemmonitor");

function set(group, values) {
    w.currentConfigGroup = group;
    for (var k in values) w.writeConfig(k, values[k]);
}

set([], { CurrentPreset: "org.kde.plasma.systemmonitor", popupHeight: 380, popupWidth: 440 });
// Las barras de la barra salen de esta cara. El desplegable lo reemplaza la copia local del applet.
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

// Sensores: id -> [etiqueta, color RGB]. Los ids "lmsensors/..." dependen del hardware de este equipo.
var sensors = [
    ["cpu/all/maximumTemperature",       "CPU",                 "231,76,60"],
    ["lmsensors/nct6795-isa-0a20/temp3", "VRM",                 "243,156,18"],
    ["gpu/gpu1/temperature",             "GPU",                 "46,204,113"],
    ["lmsensors/nvme-pci-2500/temp1",    "Disco Linux (ADATA)", "200,200,200"],
    ["lmsensors/nvme-pci-0100/temp1",    "Disco XPG (Windows)", "200,200,200"]
];
var labels = {}, colors = {}, ids = [];
sensors.forEach(function (s) { ids.push(s[0]); labels[s[0]] = s[1]; colors[s[0]] = s[2]; });
set(["SensorLabels"], labels);
set(["SensorColors"], colors);
set(["Sensors"], { highPrioritySensorIds: JSON.stringify(ids), lowPrioritySensorIds: "[]", totalSensors: "[]" });

print("Monitor de temperaturas agregado (id " + w.id + ")");
