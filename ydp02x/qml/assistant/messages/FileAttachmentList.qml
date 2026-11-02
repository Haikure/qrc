import QtQuick 2.15

// 气泡里的多文件预览（#21-3）：数量头 + 每个文件一行（名称/大小）。
// 只读：删除/清空只在草稿条的 AttachmentChipsBar 里做。
Column {
    id: root

    property var attachments: []
    property var fontFamily
    signal openRequested(string localPath)
    signal longPressed(real globalX, real globalY)

    spacing: 6
    visible: attachments && fileCount > 0

    readonly property int fileCount: !attachments ? 0
                                        : attachments.count !== undefined ? attachments.count
                                        : attachments.length !== undefined ? attachments.length : 0
    readonly property int fileWidth: 210

    // Column（QQuickPositioner）的 implicitWidth/Height 在 QML 里是只读的，不能赋值；
    // 它的 implicit 尺寸会按子项自动计算（header/每行都是 fileWidth 宽），无需再写。
    // 之前误加 `implicitWidth: fileWidth` 会让整个 FileAttachmentList 加载失败，
    // 进而使 AttachmentMessage / AI 助手页无法实例化。

    function formatIcon(name) {
        var lowerName = name ? name.toLowerCase() : "";
        if (/\.(md|markdown)$/.test(lowerName)) return "qrc:/images/format/suffix-md.png";
        if (/\.json$/.test(lowerName)) return "qrc:/images/format/suffix-json.png";
        if (/\.(xml|qml|html|htm)$/.test(lowerName)) return "qrc:/images/format/suffix-xml.png";
        if (/\.(sh|bash)$/.test(lowerName)) return "qrc:/images/format/suffix-sh.png";
        return "qrc:/images/format/suffix-txt.png";
    }

    function sizeLabel(bytes) {
        if (!bytes || bytes <= 0)
            return "文本文件";
        if (bytes < 1024)
            return bytes + " B";
        return Math.max(1, Math.round(bytes / 1024)) + " KB";
    }

    // 多文件时的数量头。
    Text {
        id: header
        visible: root.fileCount > 1
        width: root.fileWidth
        // Text 的 implicit 尺寸是只读的（由文本计算），不能再赋值；width/height 已显式给出。
        height: visible ? 14 : 0
        text: "共 " + root.fileCount + " 个文件"
        color: "#8FA3B5"
        font.pixelSize: 9
        font.family: root.fontFamily || ""
    }

    Repeater {
        model: root.attachments || []

        Rectangle {
            width: root.fileWidth
            implicitWidth: root.fileWidth
            height: 42
            implicitHeight: 42
            radius: 6
            color: "#17222D"
            border.width: 1
            border.color: "#34495B"

            Image {
                id: fileIcon
                width: 24
                height: 24
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                source: root.formatIcon(modelData.name)
                fillMode: Image.PreserveAspectFit
            }

            Column {
                anchors.left: fileIcon.right
                anchors.leftMargin: 7
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: modelData.name || "文本附件"
                    color: "#E6EDF3"
                    font.pixelSize: 11
                    font.family: root.fontFamily || ""
                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                }

                Text {
                    width: parent.width
                    text: root.sizeLabel(modelData.size)
                    color: "#8297A8"
                    font.pixelSize: 9
                    font.family: root.fontFamily || ""
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: "#000000"
                opacity: fileMouse.pressed ? 0.2 : 0
            }

            MouseArea {
                id: fileMouse
                anchors.fill: parent
                onClicked: {
                    if (modelData.localPath)
                        root.openRequested(modelData.localPath);
                }
                onPressAndHold: {
                    var pos = mapToItem(null, mouseX, mouseY);
                    root.longPressed(pos.x, pos.y);
                }
            }
        }
    }
}
