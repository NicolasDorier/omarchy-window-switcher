import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string monitorName: ""
  property int selectedIndex: -1
  property var windows: []

  readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-window-switcher.json"
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color scrim: Color.menu.scrim
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int rowHeight: Style.space(54)

  function close() {
    opened = false
    monitorName = ""
    selectedIndex = -1
    windows = []
  }

  function loadState(content) {
    try {
      var state = JSON.parse(String(content || ""))
      if (!state || state.version !== 1 || state.open !== true || !Array.isArray(state.windows) || state.windows.length === 0) {
        close()
        return
      }

      monitorName = String(state.monitor || "")
      windows = state.windows
      selectedIndex = Math.max(0, Math.min(Number(state.selected) || 0, windows.length - 1))
      opened = true
    } catch (e) {
      console.warn("window-switcher", "Ignoring invalid state", e)
      close()
    }
  }

  function desktopIconName(appClass) {
    var className = String(appClass || "").toLowerCase()
    var idMatch = ""
    var entries = DesktopEntries.applications.values || []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var icon = String(entry.icon || "")
      if (!icon) continue

      if (String(entry.startupClass || "").toLowerCase() === className)
        return icon

      var desktopId = String(entry.id || "").toLowerCase().replace(/\.desktop$/, "")
      if (desktopId === className) idMatch = icon
    }
    return idMatch
  }

  function iconSource(appClass, title) {
    var iconName = String(appClass || "")
    var titleName = String(title || "").toLowerCase()
    if (iconName.toLowerCase() === "brave-browser") {
      if (titleName.indexOf("gmail") !== -1)
        return Qt.resolvedUrl("icons/gmail.ico")
      if (titleName.indexOf("github") !== -1 || titleName.indexOf("pull request #") !== -1 || titleName.indexOf("issue #") !== -1)
        return Qt.resolvedUrl("icons/github.png")
    }
    iconName = desktopIconName(iconName) || iconName
    if (shell && shell.appLibrary)
      return shell.appLibrary.iconSource(iconName)
    return Quickshell.iconPath(iconName, true)
      || Quickshell.iconPath("application-x-executable", true)
  }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadState(text())
    onLoadFailed: root.close()
  }

  Variants {
    id: windowSurfaces
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.opened && (root.monitorName === "" || modelData.name === root.monitorName)
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "nicolasdorier-window-switcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      function revealSelection() {
        if (windowList.count === 0 || root.selectedIndex < 0) return
        if (root.selectedIndex <= 1) {
          windowList.positionViewAtIndex(0, ListView.Beginning)
        } else {
          windowList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        }
      }

      function scheduleRevealSelection() { Qt.callLater(revealSelection) }

      onVisibleChanged: if (visible) scheduleRevealSelection()

      Connections {
        target: root
        function onSelectedIndexChanged() { panel.scheduleRevealSelection() }
        function onWindowsChanged() { panel.scheduleRevealSelection() }
      }

      Rectangle {
        anchors.fill: parent
        color: root.scrim
      }

      BorderSurface {
        id: card
        width: Math.min(Style.space(540), panel.width - Style.gapsOut * 2)
        height: Math.min(
          root.windows.length * root.rowHeight + root.contentMargin * 2 + borderTop + borderBottom,
          panel.height * 0.72)
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: root.background
        borderSpec: root.borderSpec
        padding: root.contentMargin

        ListView {
          id: windowList
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          model: root.windows
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: false

          delegate: Rectangle {
            id: row
            required property int index
            required property var modelData
            readonly property bool selected: index === root.selectedIndex
            width: ListView.view.width
            height: root.rowHeight
            radius: Math.max(1, Math.round(Style.cornerRadius / 2))
            color: selected ? root.selectedBackground : "transparent"

            Image {
              id: appIcon
              width: Style.font.iconLarge
              height: width
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              fillMode: Image.PreserveAspectFit
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              source: root.iconSource(row.modelData.className, row.modelData.title)
              asynchronous: true
            }

            Column {
              anchors.left: appIcon.right
              anchors.leftMargin: Style.space(12)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: String(row.modelData.title || row.modelData.className || "Untitled window")
                textFormat: Text.PlainText
                color: row.selected ? root.selectedText : root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.heading
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

            }
          }
        }
      }
    }
  }
}
