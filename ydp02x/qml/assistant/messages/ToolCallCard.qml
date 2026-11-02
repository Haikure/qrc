import QtQuick 2.12
import "ToolDetails.js" as ToolDetails

Item {
    id: root
    property string text: ""
    property string rawText: ""
    property string toolState: ""
    property string entriesJson: "[]"
    property real maxWidth: 300
    property var fontFamily
    property bool expanded: false
    readonly property var entries: ToolDetails.entries(entriesJson, text, toolState, rawText)

    signal expansionStarted(bool expanding)

    function toggleExpanded() {
        expansionStarted(!expanded);
        expanded = !expanded;
    }

    width: maxWidth
    height: panel.height

    Rectangle {
        id: panel
        width: parent.width
        height: 36 + (root.expanded && detailLoader.item ? Math.min(detailLoader.item.contentHeight, 126) : 0)
        radius: 8
        color: "#14212D"
        border.color: "#30485B"
        clip: true

        Item {
            id: header
            width: parent.width
            height: 36
            Rectangle {
                x: 10; width: 6; height: 6; radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: ToolDetails.stateColor(root.toolState)
            }
            Text {
                x: 23
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - toggle.width - 43
                text: root.entries.length > 1 ? "工具调用 · " + root.entries.length + " 项" : ToolDetails.toolLabel(root.entries[0].name)
                color: "#CFDCE7"
                font.pixelSize: 12
                font.bold: true
                font.family: root.fontFamily || qmlGlobal.fontFamilyZhCn
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }
            Text {
                id: toggle
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: ToolDetails.stateLabel(root.toolState) + (root.expanded ? " ▴" : " ▾")
                color: ToolDetails.stateColor(root.toolState)
                font.pixelSize: 10
                font.family: root.fontFamily || qmlGlobal.fontFamilyZhCn
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.toggleExpanded()
            }
        }
        Loader {
            id: detailLoader
            anchors.top: header.bottom
            width: parent.width
            height: parent.height - header.height
            active: root.expanded
            visible: active
            sourceComponent: Flickable {
                id: detailFlick
                contentWidth: width
                contentHeight: detailColumn.height + 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: detailColumn
                    x: 8; y: 8
                    width: detailFlick.width - 16
                    spacing: 8
                    Repeater {
                        model: root.entries
                        delegate: ToolCallEntry {
                            entry: modelData
                            number: index + 1
                            fontFamily: root.fontFamily
                        }
                    }
                }
            }
        }
    }
}
