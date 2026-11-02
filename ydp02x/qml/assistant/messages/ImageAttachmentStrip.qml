import QtQuick 2.15
import QtGraphicalEffects 1.12

// 气泡里的多图预览（#21-3）：横向可滚动缩略图 + “共 N 张”数量。
// 这里只读（历史消息），删除/清空只在草稿条的 AttachmentChipsBar 里做。
Item {
    id: root

    property var attachments: []
    property var fontFamily
    signal openRequested(string localPath)
    signal longPressed(real globalX, real globalY)

    readonly property int imageCount: !attachments ? 0
                                             : attachments.count !== undefined ? attachments.count
                                             : attachments.length !== undefined ? attachments.length : 0

    function attachmentAt(index) {
        if (!attachments)
            return null;
        return typeof attachments.get === "function" ? attachments.get(index) : attachments[index];
    }

    function sourceAt(index) {
        var a = attachmentAt(index);
        if (!a)
            return "";
        if (a.source)
            return a.source;
        if (a.url)
            return a.url;
        if (a.localPath)
            return "file://" + a.localPath;
        return "";
    }

    readonly property int thumbnailSize: 58
    readonly property int thumbnailSpacing: 6
    readonly property int countRowHeight: 14
    // 320x170 下气泡可用宽度约 304（左右各 8），给多图留到 272，超过横向滚动。
    readonly property int stripMaxWidth: 272
    readonly property int contentWidth: imageCount * thumbnailSize + Math.max(0, imageCount - 1) * thumbnailSpacing
    implicitWidth: Math.min(stripMaxWidth, contentWidth)
    implicitHeight: imageCount > 0 ? thumbnailSize + (imageCount > 1 ? 4 + countRowHeight : 0) : 0
    width: implicitWidth
    height: implicitHeight
    visible: imageCount > 0
    clip: true

    Flickable {
        id: strip
        width: parent.width
        height: root.thumbnailSize
        contentWidth: root.contentWidth
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        Row {
            id: row
            spacing: root.thumbnailSpacing

            Repeater {
                model: root.imageCount

                Item {
                    id: thumbnail
                    readonly property var attachment: root.attachmentAt(index)
                    width: root.thumbnailSize
                    height: root.thumbnailSize
                    implicitWidth: root.thumbnailSize
                    implicitHeight: root.thumbnailSize

                    Image {
                        id: sourceImage
                        anchors.fill: parent
                        anchors.margins: 1
                        source: root.sourceAt(index)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        visible: false
                    }

                    Rectangle {
                        id: imageMask
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 6
                        visible: false
                    }

                    OpacityMask {
                        anchors.fill: sourceImage
                        source: sourceImage
                        maskSource: imageMask
                        cached: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: "transparent"
                        border.width: 1
                        border.color: "#3A5268"
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: "#000000"
                        opacity: imageMouse.pressed ? 0.25 : 0
                    }

                    MouseArea {
                        id: imageMouse
                        anchors.fill: parent
                        onClicked: {
                            if (parent.attachment && parent.attachment.localPath)
                                root.openRequested(parent.attachment.localPath);
                        }
                        onPressAndHold: {
                            var pos = mapToItem(null, mouseX, mouseY);
                            root.longPressed(pos.x, pos.y);
                        }
                    }
                }
            }
        }
    }

    // 数量 + 横向滚动提示（>1 张时显示）。
    Item {
        visible: root.imageCount > 1
        anchors {
            left: parent.left
            right: parent.right
            top: strip.bottom
            topMargin: 4
        }
        height: root.countRowHeight

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "共 " + root.imageCount + " 张" + (root.contentWidth > root.stripMaxWidth ? " · 左右滑动" : "")
            color: "#8FA3B5"
            font.pixelSize: 9
            font.family: root.fontFamily || ""
        }
    }
}
