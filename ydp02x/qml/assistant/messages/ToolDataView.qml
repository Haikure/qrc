import QtQuick 2.12
import "ToolDetails.js" as ToolDetails

Column {
    id: root
    property var value: ""
    property bool shellResult: false
    property var fontFamily
    readonly property var rows: ToolDetails.rows(value, shellResult)
    spacing: 4

    Repeater {
        model: root.rows
        delegate: Rectangle {
            id: row
            property var field: modelData
            x: Math.min(field.depth, 5) * 8
            width: root.width - x
            height: content.height + 12
            radius: 4
            color: field.group ? "#22313F" : "#101A24"

            Rectangle {
                width: 2
                height: parent.height - 8
                x: 0; y: 4
                color: row.field.group ? "#547D9E" : "#304454"
                visible: row.field.depth > 0
            }
            Column {
                id: content
                x: 7; y: 6
                width: parent.width - 14
                spacing: 3
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: row.field.label
                    textFormat: Text.PlainText
                    color: "#8BA9C0"
                    font.pixelSize: 10
                    font.family: root.fontFamily || qmlGlobal.fontFamilyZhCn
                    wrapMode: Text.WrapAnywhere
                }
                Text {
                    width: parent.width
                    text: row.field.value
                    textFormat: Text.PlainText
                    color: row.field.group ? "#A2B4C3" : "#DAE3EB"
                    font.pixelSize: row.field.group ? 10 : 11
                    font.family: root.fontFamily || qmlGlobal.fontFamilyZhCn
                    wrapMode: Text.WrapAnywhere
                    lineHeight: 1.15
                }
            }
        }
    }
}
