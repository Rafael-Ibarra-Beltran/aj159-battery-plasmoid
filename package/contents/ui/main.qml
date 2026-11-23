import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Estado de la última lectura
    property int level: -1          // 0-100, -1 = sin dato
    property bool charging: false
    property bool powered: false    // conectado a la corriente (cable o base)
    property bool connected: false
    property string status: "Leyendo…"
    property string lastRead: "—"

    readonly property int lowThreshold: 15
    readonly property string readCmd: "python3 '" + Qt.resolvedUrl("../code/aj159-battery").toString().replace("file://", "") + "'"
    readonly property bool isLow: connected && level >= 0 && level < lowThreshold && !charging
    // ⚡ = cargando de verdad; 🔌 = conectado a la corriente pero sin cargar
    readonly property string shortText: {
        const plug = charging ? "⚡" : (powered ? "🔌" : "")
        if (!connected || level < 0) return plug ? plug + " —" : "—"
        return plug + level + "%"
    }

    preferredRepresentation: compactRepresentation
    Plasmoid.icon: "input-mouse"
    toolTipMainText: "Ajazz AJ159"
    toolTipSubText: status + " · " + lastRead

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            // Sin disconnectSource el mismo comando no se vuelve a ejecutar.
            disconnectSource(sourceName)
            if (sourceName === root.readCmd) {
                root.handleOutput(data["stdout"] || "", data["exit code"])
            }
        }
    }

    function refresh() {
        exec.connectSource(readCmd)
    }


    function applyReading(isConnected, lvl, isCharging, isPowered, text) {
        connected = isConnected
        level = lvl
        charging = isCharging
        powered = isPowered || isCharging
        status = isConnected && powered && !charging ? "Conectado, sin cargar" : text
        lastRead = Qt.formatTime(new Date(), "hh:mm")
    }

    // aj159-battery (incluido en el paquete) imprime JSON
    function handleOutput(out, code) {
        let r
        try {
            r = JSON.parse(out)
        } catch (e) {
            applyReading(false, -1, false, "Salida no válida")
            return
        }
        const texts = {
            "ok": r.charging ? "Cargando" : "Descargando",
            "no_reading": "Sin lectura (mouse dormido o apagado)",
            "not_found": "Receptor no encontrado",
            "no_permission": "Sin permiso: instala la regla udev",
            "error": "Error: " + (r.error || "desconocido")
        }
        const text = (texts[r.status] || r.status) + (r.mode === "wired" ? " (cable)" : "")
        // Dormido, el mouse no responde: se conserva la última lectura válida y se reintenta antes.
        if (r.status === "no_reading" && r.mode === "wireless" && level >= 0) {
            status = "Dormido (mostrando la última lectura)"
            pollTimer.interval = 30000
            return
        }
        pollTimer.interval = r.status === "no_reading" ? 30000 : 60000
        applyReading(r.status === "ok", r.battery === null || r.battery === undefined ? -1 : r.battery, !!r.charging, !!r.powered, text)
    }

    Timer {
        id: pollTimer
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    compactRepresentation: MouseArea {
        // Margen a los lados para que el ícono y el texto no toquen el borde del fondo.
        readonly property int hPadding: Kirigami.Units.largeSpacing
        Layout.minimumWidth: row.implicitWidth + 2 * hPadding
        Layout.preferredWidth: row.implicitWidth + 2 * hPadding
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "input-mouse"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                opacity: root.connected ? 1 : 0.5
            }
            Kirigami.Icon {
                // Batería baja: ícono rojo junto al %, igual que el ⚡ al cargar.
                visible: root.isLow
                source: "battery-caution"
                color: Kirigami.Theme.negativeTextColor
                isMask: true
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PlasmaComponents.Label {
                text: root.shortText
                color: root.isLow ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 4
            text: "Ajazz AJ159"
        }
        PlasmaComponents.Label {
            text: root.connected && root.level >= 0 ? "Batería: " + root.level + "%" : "Batería: —"
        }
        PlasmaComponents.Label {
            text: "Estado: " + root.status
        }
        PlasmaComponents.Label {
            text: "Última lectura: " + root.lastRead
            opacity: 0.7
        }
        PlasmaComponents.Button {
            text: "Refrescar"
            icon.name: "view-refresh"
            onClicked: root.refresh()
        }
    }
}
