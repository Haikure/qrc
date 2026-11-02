import QtQuick 2.12
import "ToolDetails.js" as ToolDetails

Rectangle {
    id: root
    property var entry: ({})
    property int number: 1
    property var fontFamily
    property bool expanded: true
    readonly property bool terminal: entry.state === "done" || entry.state === "error" || entry.state === "cancelled"
    width: parent.width
    height: entryColumn.height + 16
    radius: 7
    color: "#182430"
    border.color: "#304253"

    Column {
        id: entryColumn
        x: 8; y: 8
        width: parent.width - 16
        spacing: 7
        Item {
            width: parent.width
            height: 24
            Rectangle {
                width: 22; height: 22; radius: 6
                color: "#2A4154"
                Text {
                    anchors.centerIn: parent
                    text: root.number
                    color: "#B5D6EF"
                    font.pixelSize: 11
                    font.family: root.fontFamily || qmlGlobal.fontFamilyZhCn
                }
            }
            Text {
                x: 29
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - status.width - 40
                text: ToolDetails.toolLabel(root.entry.name)
                textFormat: Text.PlainText
                color: "#E3EBF2"
                font.bold: true
                font.pixelSize: 12
                font.family: root.fontFamily || qmlGlobal.fontFamilyZhCn
                elide: Text.ElideRight
            }
            Text {
                id: status
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: ToolDetails.stateLabel(root.entry.state) + (root.expanded ? " ▴" : " ▾")
                color: ToolDetails.stateColor(root.entry.state)
                font.pixelSize: 10
                font.family: root.fontFamily || qmlGlobal.fontFamilyZhCn
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.expanded = !root.expanded
            }
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.entry.text || ""
            textFormat: Text.PlainText
            color: "#9AAEBE"
            font.pixelSize: 10
            font.family: root.fontFamily || qmlGlobal.fontFamilyZhCn
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Loader {
            width: parent.width
            active: root.expanded
            visible: active
            height: item ? item.implicitHeight : 0
            sourceComponent: Column {
                width: parent.width
                spacing: 6
                Text {
                    text: "调用参数"
                    color: "#8BA9C0"
                    font.pixelSize: 10
                    font.family: root.fontFamily || qmlGlobal.fontFamilyZhCn
                }
                ToolDataView {
                    width: parent.width
                    value: root.entry.arguments || ""
                    fontFamily: root.fontFamily
                }
                Text {
                    text: root.terminal ? "执行结果" : "执行进度"
                    color: "#8BA9C0"
                    font.pixelSize: 10
                    font.family: root.fontFamily || qmlGlobal.fontFamilyZhCn
                }
                ToolDataView {
                    width: parent.width
                    value: root.entry.result || (root.terminal ? "未记录结果" : "等待工具返回…")
                    shellResult: root.entry.name === "shell_exec"
                    fontFamily: root.fontFamily
                }
            }
        }
    }
}
