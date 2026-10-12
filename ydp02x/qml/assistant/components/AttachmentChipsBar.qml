import QtQuick 2.12

Rectangle {
    id: root

    property var filesModel: null
    property var mediaModel: null
    property var fontFamily

    // 只有"有预发送附件就允许空文字发送"的宿主才打开（聊天页预发送条、编辑页图片条），默认关闭。
    // 验证：打开后右侧出现「发送」，点它不依赖输入框内容。
    property bool showSendButton: false
    signal sendRequested()

    function formatIcon(item, isMedia) {
        if (isMedia)
            return item && item.type === "input_audio"
                    ? "qrc:/images/format/suffix-mp3.png"
                    : "qrc:/images/format/suffix-image.png";
        var name = item && item.name ? item.name.toLowerCase() : "";
        if (/\.(md|markdown)$/.test(name)) return "qrc:/images/format/suffix-md.png";
        if (/\.json$/.test(name)) return "qrc:/images/format/suffix-json.png";
        if (/\.(xml|qml|html|htm)$/.test(name)) return "qrc:/images/format/suffix-xml.png";
        if (/\.(sh|bash)$/.test(name)) return "qrc:/images/format/suffix-sh.png";
        return "qrc:/images/format/suffix-txt.png";
    }

    height: 34
    radius: 8
    color: "#CC0E1621"
    border.width: 1
    border.color: "#2B3A4A"

    ListView {
        // 有发送按钮时把列表右边界让出来，否则最后一个 chip 会被按钮盖住。
        anchors { fill: parent; margins: 4; rightMargin: root.showSendButton ? sendButton.width + 12 : 4 }
        orientation: ListView.Horizontal
        spacing: 6
        clip: true
        model: (root.filesModel ? root.filesModel.count : 0) + (root.mediaModel ? root.mediaModel.count : 0)

        delegate: Rectangle {
            readonly property int fileCount: root.filesModel ? root.filesModel.count : 0
            readonly property bool isMediaChip: index >= fileCount
            readonly property int mediaIndex: index - fileCount
            readonly property var chipData: isMediaChip
                ? (root.mediaModel && mediaIndex < root.mediaModel.count ? root.mediaModel.get(mediaIndex) : null)
                : (root.filesModel && index < root.filesModel.count ? root.filesModel.get(index) : null)

            height: 26
            width: chipContent.implicitWidth + 36
            radius: 6
            color: isMediaChip ? "#28552A" : "#2B5278"

            Row {
                id: chipContent
                anchors {
                    left: parent.left
                    leftMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 4

                Image {
                    width: 15
                    height: 15
                    source: root.formatIcon(chipData, isMediaChip)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: chipData ? (chipData.label || chipData.name || chipData.type || "") : ""
                    color: "#FFFFFF"
                    font.pixelSize: 11
                    font.family: root.fontFamily || ""
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                    width: Math.min(implicitWidth, 120)
                }
            }

            Rectangle {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    rightMargin: 2
                }
                width: 22
                height: 22
                radius: 11
                color: "#44FFFFFF"

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: "#FFFFFF"
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: {
                        if (isMediaChip) {
                            root.mediaModel.remove(mediaIndex, 1);
                        } else {
                            root.filesModel.remove(index, 1);
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: sendButton
        // 320x170 上没有空间再开一行：按钮与 chip 同高（26）、靠右对齐，44px 够放两个汉字。
        // 验证：键盘关着时点它应能发出，键盘打开时整条随父项一起隐藏。
        visible: root.showSendButton
        width: visible ? 44 : 0
        height: 26
        radius: 6
        color: sendArea.pressed ? "#3E7CB1" : "#2B5278"
        border.width: 1
        border.color: "#4A90D9"
        anchors {
            right: parent.right
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }

        Text {
            anchors.centerIn: parent
            text: "发送"
            color: "#FFFFFF"
            font.pixelSize: 11
            font.family: root.fontFamily || ""
        }

        MouseArea {
            id: sendArea
            anchors.fill: parent
            onClicked: root.sendRequested()
        }
    }
}
