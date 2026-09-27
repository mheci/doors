import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root
    property int focusedId: 1
    property string windowTitle: ""

    Variants {
        model: Quickshell.screens
        delegate: Component {
            PanelWindow {
                required property var modelData
                screen: modelData
                anchors {
                    top: true
                    left: true
                    right: true
                }
                implicitHeight: 32
                color: "transparent"

                Rectangle {
                    anchors.fill: parent
                    color: "#cc11111b"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "Doors"
                        color: "#89b4fa"
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Repeater {
                        model: spaces
                        delegate: Rectangle {
                            implicitWidth: 22
                            implicitHeight: 22
                            radius: 6
                            color: model.wsId === root.focusedId ? "#89b4fa" : "#313244"
                            Text {
                                anchors.centerIn: parent
                                text: model.wsId
                                color: model.wsId === root.focusedId ? "#11111b" : "#cdd6f4"
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    dispatch.command = ["hyprctl", "dispatch", "workspace", String(model.wsId)]
                                    dispatch.running = true
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.windowTitle
                        color: "#cdd6f4"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        color: "#cdd6f4"
                        font.pixelSize: 13
                        text: Qt.formatDateTime(clockTimer.now, "ddd d MMM  HH:mm")
                    }
                }
            }
        }
    }

    ListModel {
        id: spaces
    }

    Timer {
        id: clockTimer
        property date now: new Date()
        interval: 1000
        running: true
        repeat: true
        onTriggered: now = new Date()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!wsProc.running)
                wsProc.running = true
            if (!titleProc.running)
                titleProc.running = true
        }
    }

    Process {
        id: wsProc
        command: ["hyprctl", "-j", "workspaces"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data)
                    spaces.clear()
                    parsed.sort((a, b) => a.id - b.id)
                    for (const ws of parsed) {
                        if (ws.id > 0)
                            spaces.append({ wsId: ws.id })
                    }
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: titleProc
        command: ["hyprctl", "-j", "activewindow"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const win = JSON.parse(data)
                    root.windowTitle = win.title || win.class || ""
                    if (win.workspace && win.workspace.id > 0)
                        root.focusedId = win.workspace.id
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: dispatch
    }
}
