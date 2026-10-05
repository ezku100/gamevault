import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    Plasmoid.icon: "input-gaming"
    preferredRepresentation: fullRepresentation

    readonly property string screenCommand: "sh -c \"python3 $HOME/.local/share/plasma/plasmoids/com.ezku.gamevault/contents/scripts/active_screen.py\""

    // --- Active screen geometry (async) ---
    Plasma5Support.DataSource {
        id: screenInfo
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            positionDrawer(data.stdout)
            disconnectSource(sourceName)
        }
    }

    function toggleDrawer() {
        if (drawerLoader.active && drawerLoader.item && drawerLoader.item.visible) {
            drawerLoader.item.visible = false
        } else {
            drawerLoader.active = true
            if (!drawerLoader.item) return
            // Geometría de la pantalla con foco (KWin); al responder se centra y muestra
            screenInfo.connectSource(screenCommand)
        }
    }

    function positionDrawer(stdout) {
        // Panel centrado en mitad de pantalla (estilo waywallen-gallery).
        // Sin dato válido se usa la pantalla del panel (comportamiento anterior)
        var sx = Screen.virtualX, sy = Screen.virtualY
        var sw = Screen.width, sh = Screen.height
        try {
            var geo = JSON.parse(stdout)
            if (geo && geo.width > 0 && geo.height > 0) {
                sx = geo.x; sy = geo.y; sw = geo.width; sh = geo.height
            }
        } catch (e) {}
        var w = Math.round(sw * 0.85)
        var h = Math.round(sh * 0.25)
        drawerLoader.item.width = w
        drawerLoader.item.height = h
        drawerLoader.item.x = sx + Math.round((sw - w) / 2)
        drawerLoader.item.y = sy + Math.round((sh - h) / 2)
        drawerLoader.item.visible = true
        // requestActivate pide el foco a KWin (como DynamicIsland);
        // el timer de foco lo reintenta si aún no está activa
        if (drawerLoader.item.requestActivate) drawerLoader.item.requestActivate()
        if (drawerLoader.item.mainItem) {
            drawerLoader.item.mainItem.resetLoopIndex()
            drawerLoader.item.mainItem.forceActiveFocus()
            drawerLoader.item.mainItem.startFocusTimer()
            drawerLoader.item.mainItem.startCenterTimer()
        }
    }

    Plasmoid.onActivated: {
        toggleDrawer()
    }

    property var rawGames: []
    property var gamesModel: []
    property bool quietScan: false

    readonly property string scanCommand: "sh -c \"python3 $HOME/.local/share/plasma/plasmoids/com.ezku.gamevault/contents/scripts/scan.py\""

    // --- Launching games (fire-and-forget) ---
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
        }
    }

    function runCommand(cmd) {
        if (!cmd || typeof cmd !== "string") return
        var safe = cmd.replace(/"/g, '\\"')
        var detachedCmd = 'nohup ' + safe + ' > /dev/null 2>&1 &'
        executable.connectSource('sh -c "' + detachedCmd + '"')
    }

    // --- Scanning Steam library (wait for result) ---
    Plasma5Support.DataSource {
        id: scanner
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            parseGamesData(data.stdout)
            disconnectSource(sourceName)
        }
    }

    function scanGames(silent) {
        root.quietScan = (silent === true)
        scanner.connectSource(scanCommand)
        if (!root.quietScan && drawerLoader.item && drawerLoader.item.mainItem) {
            drawerLoader.item.mainItem.beginScan()
        }
    }

    function recordLaunch(name) {
        if (!name || typeof name !== "string" || name.length === 0) return
        var safe = name.replace(/"/g, '\\"')
        root.runCommand('python3 $HOME/.local/share/plasma/plasmoids/com.ezku.gamevault/contents/scripts/record_launch.py "' + safe + '"')
    }

    function matchesExcludePattern(name, patterns) {
        for (var i = 0; i < patterns.length; i++) {
            if (patterns[i].length === 0) continue
            if (name.toLowerCase().indexOf(patterns[i].toLowerCase()) !== -1) {
                return true
            }
        }
        return false
    }
    
    function applyFilters() {
        var patterns = Plasmoid.configuration.excludePatterns || []
        var filtered = []

        for (var i = 0; i < root.rawGames.length; i++) {
            var g = root.rawGames[i]
            if (!g || !g.name || !g.image || !g.runcmd) continue
            if (matchesExcludePattern(g.name, patterns)) continue
            filtered.push(g)
        }

        root.gamesModel = filtered
        if (drawerLoader.item && drawerLoader.item.mainItem) {
            drawerLoader.item.mainItem.rebaseLoop()
        }
    }

    function parseGamesData(stdout) {
        try {
            var parsed = JSON.parse(stdout)
            if (!Array.isArray(parsed)) {
                console.log("Scan output is not an array")
                return
            }
            // Si la lista es idéntica no se reconstruye (evita el parpadeo
            // y que el loop "cargue tarde" al abrir): solo se refrescan flags
            var same = parsed.length === root.rawGames.length
            if (same) {
                for (var i = 0; i < parsed.length; i++) {
                    if (String(parsed[i].name) !== String(root.rawGames[i].name)
                        || String(parsed[i].runcmd) !== String(root.rawGames[i].runcmd)) {
                        same = false
                        break
                    }
                }
            }
            if (same) {
                for (var j = 0; j < parsed.length; j++) {
                    var cur = root.rawGames[j], nxt = parsed[j]
                    cur.lastPlayed = nxt.lastPlayed
                    cur.favorite = nxt.favorite
                    cur.hidden = nxt.hidden
                    cur.image = nxt.image
                    cur.runcmd = nxt.runcmd
                }
            } else {
                root.rawGames = parsed
            }
        } catch (e) {
            console.log("Failed to parse steam scan output:", e)
            return
        }
        applyFilters()
        if (drawerLoader.item && drawerLoader.item.mainItem) {
            if (root.quietScan) {
                root.quietScan = false
            } else {
                drawerLoader.item.mainItem.finishScanWithCount(root.gamesModel.length)
            }
        }
    }
    
    Connections {
        target: Plasmoid.configuration
        function onExcludePatternsChanged() {
            applyFilters()
        }
    }

    Component.onCompleted: {
        scanGames()
    }


    fullRepresentation: Item {
        Layout.minimumWidth: 64
        Layout.minimumHeight: 32
        Layout.preferredWidth: 64
        Layout.preferredHeight: 32

        Image {
            anchors.centerIn: parent
            width: 28
            height: 28
            source: "../images/cat-manual.svg"
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toggleDrawer()
        }
    }

    Loader {
        id: drawerLoader
        active: false

        sourceComponent: PlasmaCore.Dialog {
            id: dialog

            // Tipo Dock + flotante (igual que DynamicIsland): KWin/BetterBlur
            // lo trata como dock y le aplica blur detrás.
            type: PlasmaCore.Dialog.Dock
            location: PlasmaCore.Types.Floating
            backgroundHints: PlasmaCore.Dialog.NoBackground
            flags: Qt.WindowStaysOnTopHint
            hideOnWindowDeactivate: true

            // El visible que sí cambia es el del diálogo (los hijos conservan
            // su visible aunque se oculten): aquí se resetea cada apertura
            onVisibleChanged: {
                if (!mainItem) return
                if (visible) {
                    mainItem.resetLoopIndex()
                    mainItem.category = "Todos"
                    mainItem.searchText = ""
                    searchField.text = ""
                    mainItem.searchVisible = false
                    scrollAnim.stop()
                    flickable.contentX = 0
                    if (requestActivate) requestActivate()
                    mainItem.forceActiveFocus()
                    mainItem.startFocusTimer()
                    mainItem.startCenterTimer()
                    root.applyFilters()
                    root.scanGames(true)
                } else {
                    focusTimer.stop()
                    centerTimer.stop()
                    settleTimer.stop()
                    fixupTimer.stop()
                    scanMinTimer.stop()
                    scanStatusTimer.stop()
                    mainItem.scanStatus = ""
                    mainItem.scanning = false
                }
            }

            mainItem: FocusScope {
                id: drawerRoot
                width: dialog.width
                height: dialog.height
                focus: true

                property int currentIndex: 0
                // Centrado pendiente (el área puede no tener ancho al abrir)
                property bool needsCenter: false
                // Al buscar se reserva calle arriba para el campo (sin encimarse)
                readonly property real contentTop: searchVisible ? 58 : 14
                property string searchText: ""
                property bool searchVisible: false
                property string category: "Todos"
                readonly property var categories: ["Todos", "Recientes", "Steam", "Emulación", "No-Steam", "Favoritos"]
                property var filteredGames: {
                    var base = root.gamesModel
                    if (category === "Ocultos") {
                        base = base.filter(function(g) { return g.hidden })
                    } else {
                        base = base.filter(function(g) { return !g.hidden })
                    }
                    if (category === "Recientes") {
                        base = base.filter(function(g) { return (g.lastPlayed || 0) > 0 }).slice(0, 12)
                    } else if (category === "Steam") {
                        base = base.filter(function(g) { return g.source === "steam" })
                    } else if (category === "Emulación") {
                        base = base.filter(function(g) { return g.source === "shortcut" })
                    } else if (category === "No-Steam") {
                        base = base.filter(function(g) { return g.source === "nosteam" })
                    } else if (category === "Favoritos") {
                        base = base.filter(function(g) { return g.favorite })
                    }
                    if (searchText === "") return base
                    return base.filter(function(g) { return (g.name || "").toLowerCase().indexOf(searchText.toLowerCase()) !== -1 }).slice(0, 80)
                }
                // Carrusel infinito: se repite la base para que la fila siempre
                // se vea llena; el índice vive en las copias centrales
                function loopReps() {
                    var n = filteredGames.length
                    if (n <= 1) return 1
                    if (n < 8) return 6
                    if (n < 20) return 4
                    if (n < 60) return 3
                    return 2
                }
                property var loopedGames: {
                    var base = filteredGames
                    var out = []
                    for (var k = 0; k < loopReps(); k++) out = out.concat(base)
                    return out
                }
                function resetLoopIndex() {
                    var n = filteredGames.length
                    if (n === 0) {
                        currentIndex = 0
                        return
                    }
                    currentIndex = Math.min(n * Math.floor(loopReps() / 2), loopedGames.length - 1)
                }
                // Tras reconstruir el modelo conserva la posición equivalente
                // dentro de las copias centrales
                function rebaseLoop() {
                    var n = filteredGames.length
                    if (n === 0 || loopedGames.length === 0) {
                        currentIndex = 0
                        return
                    }
                    var mid = n * Math.floor(loopReps() / 2)
                    var off = ((currentIndex % n) + n) % n
                    currentIndex = Math.min(mid + off, loopedGames.length - 1)
                }

                function setCategory(c) {
                    category = c
                    resetLoopIndex()
                    centerTimer.start()
                    fixupTimer.restart()
                }

                function nextCategory(delta) {
                    var i = categories.indexOf(category)
                    if (i < 0) {
                        setCategory(categories[0])
                        return
                    }
                    setCategory(categories[(i + delta + categories.length) % categories.length])
                }

                function toggleHidden() {
                    if (loopedGames.length === 0) return
                    var g = loopedGames[Math.max(0, Math.min(loopedGames.length - 1, currentIndex))]
                    if (!g || !g.name) return
                    var safe = String(g.name).replace(/"/g, '\\"')
                    root.runCommand('python3 $HOME/.local/share/plasma/plasmoids/com.ezku.gamevault/contents/scripts/toggle_hidden.py "' + safe + '"')
                    var target = String(g.name).toLowerCase()
                    var nowHidden = !g.hidden
                    for (var i = 0; i < root.rawGames.length; i++) {
                        var e = root.rawGames[i]
                        if (e && e.name && String(e.name).toLowerCase() === target) e.hidden = nowHidden
                    }
                    // Solo reconstruir si sale de la vista (evita el parpadeo)
                    var leavesView = (category !== "Ocultos" && nowHidden)
                        || (category === "Ocultos" && !nowHidden)
                    if (leavesView) {
                        root.applyFilters()
                        rebaseLoop()
                    }
                }

                function toggleFavorite() {
                    if (loopedGames.length === 0) return
                    var g = loopedGames[Math.max(0, Math.min(loopedGames.length - 1, currentIndex))]
                    if (!g || !g.name) return
                    var safe = String(g.name).replace(/"/g, '\\"')
                    root.runCommand('python3 $HOME/.local/share/plasma/plasmoids/com.ezku.gamevault/contents/scripts/toggle_favorite.py "' + safe + '"')
                    var target = String(g.name).toLowerCase()
                    var nowFav = !g.favorite
                    for (var i = 0; i < root.rawGames.length; i++) {
                        var e = root.rawGames[i]
                        if (e && e.name && String(e.name).toLowerCase() === target) e.favorite = nowFav
                    }
                    // Solo reconstruir si sale de la vista (evita el parpadeo):
                    // la estrella se actualiza sola por binding en el mismo delegate
                    if (category === "Favoritos" && !nowFav) {
                        root.applyFilters()
                        rebaseLoop()
                    }
                }
                readonly property real tileH: (height - contentTop - 14 - 44) / 1.3
                readonly property real tileW: tileH * 2.1395
                readonly property real tileGap: 48
                // Sin scripts: el acento se toma del sistema en vivo (blanco si no hay).
                // Si el tema no entrega acento válido se usan los colores manuales
                readonly property bool followAccent: Plasmoid.configuration.followAccent ?? true
                readonly property color sysAccent: Kirigami.Theme.highlightColor
                readonly property bool sysAccentOk: sysAccent.a > 0
                readonly property bool useSysAccent: followAccent && sysAccentOk
                readonly property string themeBg: useSysAccent
                    ? Qt.darker(sysAccent, 4.0).toString()
                    : (Plasmoid.configuration.bgColor || "#12131c")
                readonly property string themeAccent: useSysAccent
                    ? sysAccent.toString()
                    : (Plasmoid.configuration.accentColor || "#ffffff")
                readonly property string themeText: Plasmoid.configuration.textColor || "white"
                readonly property real themeOpacity: Plasmoid.configuration.bgOpacity ?? 0.93
                readonly property int themeRadius: Plasmoid.configuration.cornerRadius ?? 14
                readonly property bool mouseEnabled: Plasmoid.configuration.mouseEnabled ?? false

                function ensureVisible(animated) {
                    var vw = flickable.width
                    if (vw <= 0) {
                        needsCenter = true
                        return
                    }
                    needsCenter = false
                    // Fila corta: se centra completa en vez de recargarse a la izquierda
                    // (los espaciadores inflan contentWidth: se mide solo tarjetas,
                    // incluyendo las copias del loop)
                    if (loopedGames.length * (tileW + tileGap) <= vw) {
                        scrollAnim.stop()
                        flickable.contentX = (flickable.contentWidth - vw) / 2
                        return
                    }
                    var pad = Math.max(0, (vw - tileW) / 2)
                    // OJO: el Row suma un spacing tras el espaciador inicial
                    var x = pad + tileGap + currentIndex * (tileW + tileGap)
                    var target = x - vw / 2 + tileW / 2
                    var maxX = Math.max(0, flickable.contentWidth - vw)
                    target = Math.max(0, Math.min(target, maxX))
                    // Si ya está centrada no reiniciar el scroll: le robaba
                    // cuadros a la animación de escala de la tarjeta
                    if (Math.abs(target - flickable.contentX) < 2) {
                        scrollAnim.stop()
                        return
                    }
                    if (animated) {
                        scrollAnim.to = target
                        scrollAnim.restart()
                    } else {
                        scrollAnim.stop()
                        flickable.contentX = target
                    }
                }

                function moveSelection(delta) {
                    var total = loopedGames.length
                    if (total === 0) return
                    var n = filteredGames.length
                    var next = (currentIndex + delta) % total
                    if (next < 0) next += total
                    // Rebote entre copias centrales: loop infinito real
                    if (n > 0) {
                        var mid = n * Math.floor(loopReps() / 2)
                        while (next < mid) next += n
                        while (next >= mid + n) next -= n
                        next = Math.min(next, total - 1)
                    }
                    var wrapped = (delta > 0 && next < currentIndex) || (delta < 0 && next > currentIndex)
                    currentIndex = next
                    // Al dar la vuelta se salta sin animar el scroll largo
                    ensureVisible(!wrapped)
                    settleTimer.restart()
                }

                function launchIndex(i) {
                    if (i < 0 || i >= loopedGames.length) return
                    var g = loopedGames[i]
                    root.recordLaunch(g.name)
                    var arr = root.rawGames.slice()
                    var idx = arr.indexOf(g)
                    if (idx > 0) {
                        arr.splice(idx, 1)
                        arr.unshift(g)
                        root.rawGames = arr
                        root.applyFilters()
                    }
                    resetLoopIndex()
                    drawerLoader.item.visible = false
                    root.runCommand(g.runcmd)
                }

                function launchCurrent() { launchIndex(currentIndex) }

                // Los Timer hijos no se ven desde fuera del FocusScope
                function startCenterTimer() { centerTimer.start() }
                function startFocusTimer() { focusTimer.start() }

                property string scanStatus: ""
                property bool scanning: false
                property double scanStartMs: 0
                property int pendingCount: 0
                readonly property int scanMinMs: 1200
                function showScanStatus(s, sticky) {
                    scanStatus = s
                    scanning = sticky
                    if (sticky) scanStatusTimer.stop()
                    else scanStatusTimer.restart()
                }
                function beginScan() {
                    scanStartMs = Date.now()
                    scanMinTimer.stop()
                    showScanStatus("Escaneando…", true)
                }
                function finishScanWithCount(n) {
                    pendingCount = n
                    var wait = scanMinMs - (Date.now() - scanStartMs)
                    if (wait <= 0) finishScan()
                    else {
                        scanMinTimer.interval = wait
                        scanMinTimer.start()
                    }
                }
                function finishScan() {
                    showScanStatus(pendingCount + " juegos", false)
                }

                function setSearchVisible(v) {
                    if (v) {
                        searchVisible = true
                        searchField.forceActiveFocus()
                    } else {
                        // Soltar el foco del campo ANTES de ocultar: si no, el
                        // FocusScope se lo devuelve y lo escrito filtra sin mostrarse
                        searchField.focus = false
                        searchVisible = false
                        searchText = ""
                        searchField.text = ""
                        resetLoopIndex()
                        focus = true
                        forceActiveFocus()
                    }
                }

                onSearchTextChanged: {
                    resetLoopIndex()
                    centerTimer.start()
                    fixupTimer.restart()
                }

                // En Wayland el diálogo Dock no siempre toma el foco al
                // mostrarse: se reintenta hasta que lo tenga (o 15 intentos)
                Timer {
                    id: focusTimer
                    interval: 60
                    repeat: true
                    property int tries: 0
                    onTriggered: {
                        if (!drawerLoader.item || !drawerLoader.item.visible) {
                            stop(); tries = 0; return
                        }
                        if (drawerRoot.activeFocus || tries >= 15) {
                            stop(); tries = 0; return
                        }
                        tries++
                        drawerRoot.forceActiveFocus()
                    }
                }

                // Scroll suave al navegar con flechas (la rueda sigue directa)
                NumberAnimation {
                    id: scrollAnim
                    target: flickable
                    property: "contentX"
                    duration: 120
                    easing.type: Easing.OutCubic
                }

                // Centrado con reintentos: si el área aún no midió al abrir,
                // insiste hasta lograrlo (máx 10 intentos)
                Timer {
                    id: centerTimer
                    interval: 150
                    repeat: true
                    property int tries: 0
                    onTriggered: {
                        if (!drawerLoader.item || !drawerLoader.item.visible) {
                            stop(); tries = 0; return
                        }
                        drawerRoot.ensureVisible(false)
                        tries++
                        if (!drawerRoot.needsCenter || tries >= 10) {
                            stop(); tries = 0
                        }
                    }
                }

                // Clavado final: tras navegar, el foco queda EXACTO al centro
                // aunque la animación de scroll se haya reiniciado en vuelo
                Timer {
                    id: settleTimer
                    interval: 200
                    onTriggered: drawerRoot.ensureVisible(false)
                }

                // Reintento tras cambio de filtro: por si los bindings
                // aún no se habían actualizado al resetear el índice
                Timer {
                    id: fixupTimer
                    interval: 120
                    onTriggered: {
                        drawerRoot.rebaseLoop()
                        drawerRoot.ensureVisible(false)
                    }
                }

                Keys.onLeftPressed: moveSelection(-1)
                Keys.onRightPressed: moveSelection(1)
                Keys.onUpPressed: moveSelection(-1)
                Keys.onDownPressed: moveSelection(1)
                Keys.onReturnPressed: launchCurrent()
                Keys.onEnterPressed: launchCurrent()
                Keys.onSpacePressed: launchCurrent()
                Keys.onTabPressed: nextCategory(1)
                Keys.onBacktabPressed: nextCategory(-1)
                // Esc cierra siempre (Shortcut = funciona tenga el foco quien lo tenga):
                // 1º limpia el texto, 2º oculta el buscador, 3º cierra el drawer
                Shortcut {
                    sequence: "Escape"
                    context: Qt.WindowShortcut
                    onActivated: {
                        if (drawerRoot.searchVisible && searchField.text !== "") searchField.text = ""
                        else if (drawerRoot.searchVisible) drawerRoot.setSearchVisible(false)
                        else drawerLoader.item.visible = false
                    }
                }
                // Reescanear sin mouse (el botón de recarga se desactiva con el mouse)
                Shortcut {
                    sequence: "F5"
                    context: Qt.WindowShortcut
                    onActivated: {
                        spinAnimation.start()
                        root.scanGames()
                    }
                }
                // Escribir cualquier letra abre el buscador (como waywallen-gallery)
                // Ctrl+F marca favorito, Ctrl+O oculta, Ctrl+H abre Ocultos
                Keys.onPressed: (event) => {
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
                        toggleFavorite()
                        event.accepted = true
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_O) {
                        toggleHidden()
                        event.accepted = true
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_H) {
                        setCategory("Ocultos")
                        event.accepted = true
                    } else if (!searchVisible && event.text.length === 1 && event.text !== " "
                            && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))) {
                        setSearchVisible(true)
                        searchField.text = event.text
                        searchText = event.text
                        event.accepted = true
                    }
                }

                // Fondo: solo el fondo lleva alfa, el contenido queda opaco
                // EXPERIMENTO: fondo oculto, solo se ven los juegos flotando
                Rectangle {
                    id: background
                    anchors.fill: parent
                    visible: false
                    color: drawerRoot.themeBg
                    opacity: drawerRoot.themeOpacity
                    radius: drawerRoot.themeRadius
                    border.color: drawerRoot.themeAccent
                    border.width: 1
                }

                // (sin chevrón de cierre: se cierra con Esc, el atajo o clic fuera)

                readonly property string categoryIcon: "../images/cat-" + ({
                    "Todos": "all", "Recientes": "recents", "Steam": "steam",
                    "Emulación": "manual", "No-Steam": "pc", "Favoritos": "favorites",
                    "Ocultos": "hidden"
                }[category] || "all") + ".svg"

                // Insignia de la categoría activa: fondo sólido para verse
                // sobre el wallpaper, junto al botón de recarga
                Rectangle {
                    id: categoryBadge
                    width: 28
                    height: 28
                    radius: width / 2
                    color: drawerRoot.themeBg
                    border.color: drawerRoot.themeAccent
                    border.width: 1
                    z: 100

                    anchors.right: reloadButton.left
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    anchors.rightMargin: 8

                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: drawerRoot.categoryIcon
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: drawerRoot.themeAccent
                        }
                    }
                }

                // Botón de recarga flotante: fondo sólido para que no se
                // recorte ni se mezcle con las tarjetas que pasan debajo
                Rectangle {
                    id: reloadButton
                    width: 28
                    height: 28
                    radius: width / 2
                    color: drawerRoot.themeBg
                    border.color: drawerRoot.themeAccent
                    border.width: 1
                    z: 100
                
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    anchors.rightMargin: 12
                
                    Text {
                        id: reloadIcon
                        anchors.centerIn: parent
                        text: "↺"
                        color: drawerRoot.themeText
                        font.pixelSize: 18
                    }
                
                    MouseArea {
                        anchors.fill: parent
                        enabled: drawerRoot.mouseEnabled
                        onClicked: {
                            spinAnimation.start()
                            root.scanGames()
                        }
                    }
                
                    RotationAnimation {
                        id: spinAnimation
                        target: reloadIcon
                        from: 0
                        to: -360
                        duration: 500
                        easing.type: Easing.InOutQuad
                    }
                }

                // Buscador: oculto hasta que se escribe (Enter lanza el seleccionado).
                // Flota sobre la lista (z alto) para no comprimirla ni recortar sombras
                PlasmaComponents3.TextField {
                    id: searchField
                    visible: drawerRoot.searchVisible
                    z: 200
                    width: Math.min(340, parent.width - 140)
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 10
                    placeholderText: "Buscar juego…  (Tab categoría, Esc cierra)"
                    onTextChanged: {
                        // Con debounce: no reconstruir todo por cada letra
                        searchDebounce.restart()
                        if (text !== "" && !drawerRoot.searchVisible) drawerRoot.searchVisible = true
                    }
                    onAccepted: {
                        searchDebounce.stop()
                        drawerRoot.searchText = text
                        if (drawerRoot.currentIndex >= drawerRoot.loopedGames.length) {
                            drawerRoot.rebaseLoop()
                        }
                        drawerRoot.launchCurrent()
                    }
                    Keys.onPressed: (event) => {
                        function flushFilter() {
                            searchDebounce.stop()
                            if (drawerRoot.searchText !== text) drawerRoot.searchText = text
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
                            flushFilter()
                            drawerRoot.toggleFavorite()
                            event.accepted = true
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_O) {
                            flushFilter()
                            drawerRoot.toggleHidden()
                            event.accepted = true
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_H) {
                            drawerRoot.setCategory("Ocultos")
                            event.accepted = true
                        } else if (event.key === Qt.Key_Tab) {
                            drawerRoot.nextCategory(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backtab) {
                            drawerRoot.nextCategory(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            flushFilter()
                            drawerRoot.moveSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            if (text === "" && drawerRoot.currentIndex === 0) {
                                drawerRoot.setSearchVisible(false)
                            } else {
                                flushFilter()
                                drawerRoot.moveSelection(-1)
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Left) {
                            flushFilter()
                            drawerRoot.moveSelection(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Right) {
                            flushFilter()
                            drawerRoot.moveSelection(1)
                            event.accepted = true
                        }
                    }
                }

                // Filtra 200ms después de dejar de escribir
                Timer {
                    id: searchDebounce
                    interval: 200
                    onTriggered: drawerRoot.searchText = searchField.text
                }

                // Oculta la píldora de estado tras mostrar el resultado
                Timer {
                    id: scanStatusTimer
                    interval: 2500
                    onTriggered: drawerRoot.scanStatus = ""
                }

                // Garantiza duración mínima visible del "Escaneando…"
                Timer {
                    id: scanMinTimer
                    onTriggered: drawerRoot.finishScan()
                }

                // Estado del escaneo al centro, sobre la tarjeta central (se oculta solo)
                Item {
                    anchors.centerIn: parent
                    width: statusText.width + 48
                    height: 56
                    visible: drawerRoot.scanStatus !== ""
                    z: 300

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: drawerRoot.themeBg
                        opacity: 0.92
                        border.color: drawerRoot.themeAccent
                        border.width: 2
                    }

                    Text {
                        id: statusText
                        anchors.centerIn: parent
                        text: drawerRoot.scanStatus
                        color: drawerRoot.themeText
                        font.pixelSize: 17
                        font.bold: true
                    }
                }

                // Pestañas de categoría (arriba-izquierda, Tab rota, Shift+Tab atrás).
                // Se ocultan al buscar para no encimarse con el campo
                Row {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: 14
                    anchors.leftMargin: 16
                    spacing: 12
                    z: 200
                    visible: !drawerRoot.searchVisible

                    Repeater {
                        model: drawerRoot.categories

                        delegate: Text {
                            text: modelData
                            color: drawerRoot.category === modelData ? drawerRoot.themeAccent : drawerRoot.themeText
                            opacity: drawerRoot.category === modelData ? 1.0 : 0.9
                            font.pixelSize: 12
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                enabled: drawerRoot.mouseEnabled
                                onClicked: drawerRoot.setCategory(modelData)
                            }
                        }
                    }
                }

                // Contador de resultados al buscar (derecha)
                Text {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 16
                    anchors.rightMargin: 20
                    visible: drawerRoot.searchText !== ""
                    text: drawerRoot.filteredGames.length + " resultados"
                    color: drawerRoot.themeText
                    opacity: 0.7
                    font.pixelSize: 12
                }

                // Row of games — flotante sin panel, el contraste va en cada tarjeta
                Flickable {
                    id: flickable
                    onWidthChanged: {
                        if (drawerRoot.needsCenter && width > 0) drawerRoot.ensureVisible(false)
                    }
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: drawerRoot.contentTop
                    anchors.bottomMargin: 14
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14

                    contentWidth: gameRow.width
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true

                    // Desvanecido en los bordes: lo que se corta se disuelve
                    // en vez de terminar en filo (una sola capa extra)
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Item {
                            width: flickable.width
                            height: flickable.height
                            visible: false
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#00000000" }
                                    GradientStop { position: 0.07; color: "#ffffffff" }
                                    GradientStop { position: 0.93; color: "#ffffffff" }
                                    GradientStop { position: 1.0; color: "#00000000" }
                                }
                            }
                        }
                    }


                    Row {
                        id: gameRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: drawerRoot.tileGap

                        // Aire dinámico en ambos extremos: así la primera y la
                        // última también pueden quedar clavadas al centro
                        Item { width: Math.max(0, (flickable.width - drawerRoot.tileW) / 2); height: 1 }

                        Repeater {
                            model: drawerRoot.loopedGames

                            delegate: Item {
                                id: gameTile
                                property var game: modelData
                                property int tileIndex: index
                                property bool selected: drawerRoot.currentIndex === tileIndex

                                height: drawerRoot.tileH
                                width: drawerRoot.tileW
                                // La seleccionada crece con rebote y queda por encima
                                scale: selected ? 1.15 : 0.97
                                z: selected ? 10 : 1

                                Behavior on scale {
                                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                }

                                // La activa se eleva (no mueve el layout, solo visual)
                                transform: Translate {
                                    id: liftTr
                                    y: selected ? -12 : 0
                                    Behavior on y {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                }

                                // Glow de énfasis potente en la seleccionada
                                layer.enabled: selected
                                layer.effect: DropShadow {
                                    transparentBorder: true
                                    horizontalOffset: 0
                                    verticalOffset: 2
                                    radius: 16
                                    samples: 33
                                    spread: 0.3
                                    color: drawerRoot.themeAccent
                                }

                                Rectangle {
                                    id: mask
                                    anchors.fill: parent
                                    radius: drawerRoot.themeRadius > 10 ? 10 : drawerRoot.themeRadius
                                    visible: false
                                }

                                // Contenido recortado con las esquinas + leve atenuado si no está seleccionado
                                Item {
                                    id: clipContainer
                                    anchors.fill: parent
                                    opacity: drawerRoot.scanning ? 0.15 : (selected ? 1.0 : 0.75)

                                    Behavior on opacity {
                                        NumberAnimation { duration: 120 }
                                    }

                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: mask
                                    }

                                    Image {
                                        id: image
                                        anchors.fill: parent
                                        source: game.image
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }

                                    // Estrella de favorito (arriba-izquierda)
                                    Text {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.leftMargin: 8
                                        anchors.topMargin: 4
                                        visible: !!game.favorite
                                        text: "★"
                                        color: drawerRoot.themeAccent
                                        font.pixelSize: 16
                                        style: Text.Outline
                                        styleColor: "black"
                                    }

                                    // Marca de oculto (arriba-derecha, solo en Ocultos)
                                    Text {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.rightMargin: 8
                                        anchors.topMargin: 4
                                        visible: !!game.hidden
                                        text: "⊘"
                                        color: drawerRoot.themeAccent
                                        font.pixelSize: 16
                                        style: Text.Outline
                                        styleColor: "black"
                                    }

                                    // Franja inferior con el nombre del juego
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 38
                                        gradient: Gradient {
                                            orientation: Gradient.Vertical
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.9) }
                                        }
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.bottomMargin: 6
                                        text: game.name || ""
                                        elide: Text.ElideRight
                                        font.pixelSize: 13
                                        font.bold: selected
                                        color: selected ? drawerRoot.themeAccent : "white"
                                        style: Text.Outline
                                        styleColor: "black"
                                    }
                                }

                                // Anillo neón sobre la imagen: borde de énfasis en la seleccionada
                                Rectangle {
                                    anchors.fill: parent
                                    radius: drawerRoot.themeRadius > 10 ? 10 : drawerRoot.themeRadius
                                    color: "transparent"
                                    border.color: drawerRoot.themeAccent
                                    border.width: selected ? 2 : 0
                                    opacity: selected ? 1.0 : 0.0

                                    Behavior on opacity {
                                        NumberAnimation { duration: 120 }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: drawerRoot.mouseEnabled
                                    hoverEnabled: true
                                    onEntered: {
                                        drawerRoot.currentIndex = tileIndex
                                        drawerRoot.ensureVisible(true)
                                        // El hover es interacción de usuario: KWin sí concede el foco aquí
                                        if (drawerLoader.item && drawerLoader.item.requestActivate) drawerLoader.item.requestActivate()
                                        drawerRoot.forceActiveFocus()
                                    }
                                    onPressed: drawerRoot.forceActiveFocus()
                                    onClicked: {
                                        drawerRoot.launchIndex(tileIndex)
                                    }
                                }
                            }
                        }

                        // Espaciador final dinámico (igual que el inicial)
                        Item { width: Math.max(0, (flickable.width - drawerRoot.tileW) / 2); height: 1 }
                    }

                    // Allow mouse wheel scrolling (only when mouse is enabled).
                    MouseArea {
                        anchors.fill: parent
                        enabled: drawerRoot.mouseEnabled
                        propagateComposedEvents: true
                        onPressed: {
                            drawerRoot.forceActiveFocus()
                            mouse.accepted = false
                        }
                        onWheel: function(wheel) {
                            var maxX = Math.max(0, flickable.contentWidth - flickable.width)
                            var newX = flickable.contentX - wheel.angleDelta.y
                            flickable.contentX = Math.max(0, Math.min(newX, maxX))
                        }
                    }
                }

                // Estado vacío al buscar sin resultados
                Text {
                    anchors.centerIn: parent
                    visible: drawerRoot.filteredGames.length === 0
                    text: drawerRoot.searchText === "" ? "Sin juegos" : "Sin resultados para \"" + drawerRoot.searchText + "\""
                    color: drawerRoot.themeText
                    font.pixelSize: 15
                }
            }
        }
    }
}
