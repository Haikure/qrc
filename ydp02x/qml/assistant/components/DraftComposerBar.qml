import QtQuick 2.12

// 待发送草稿条：键盘 ✓ 之后出现，点「发送」才真正调用 ChatBot（#21-4）。
// 320x170 下只占底部：有附件时 34 + 4 + 30，无附件时仅 30，不再往界面里塞控件。
Item {
    id: root

    property var filesModel: null
    property var mediaModel: null
    property string draftText: ""
    property bool editing: false
    property bool sending: false
    property var fontFamily

    signal editRequested()
    signal addRequested()
    signal cancelRequested()
    signal sendRequested()

    readonly property int attachmentCount: (filesModel ? filesModel.count : 0)
                                             + (mediaModel ? mediaModel.count : 0)
    readonly property bool hasContent: draftText.length > 0 || attachmentCount > 0
    readonly property bool canSend: hasContent && !sending

    // 显式算高度，不依赖 Column 的 implicitHeight（Area/Positioner 的 implicit 尺寸
    // 来自子项 implicit 尺寸，而 chips 条是有附件时才 34、否则 0）。
    readonly property int chipsHeight: attachmentCount > 0 ? 34 : 0
    implicitHeight: chipsHeight + (chipsHeight > 0 ? 4 : 0) + 30
    height: implicitHeight

    Column {
        id: composerColumn
        width: parent.width
        spacing: 4

        AttachmentChipsBar {
            id: chips
            width: parent.width
            height: root.chipsHeight
            implicitHeight: root.chipsHeight
            visible: root.attachmentCount > 0
            filesModel: root.filesModel
            mediaModel: root.mediaModel
            fontFamily: root.fontFamily
            // 多附件预览：图片缩略图/文件名 + 数量 + 删单个 + 清空全部。
            showClearButton: true
            showCount: true
            showSendButton: false
        }

        Rectangle {
            id: inputRow
            width: parent.width
            height: 30
            implicitHeight: 30
            radius: 8
            color: "#CC0E1621"
            border.width: 1
            border.color: root.editing ? "#4A90D9" : "#2B3A4A"

            Rectangle {
                id: addButton
                width: 28
                height: 22
                radius: 6
                anchors {
                    left: parent.left
                    leftMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                color: addArea.pressed ? "#2B5278" : "#1B2B3A"

                Text {
                    anchors.centerIn: parent
                    text: "＋"
                    color: "#FFFFFF"
                    font.pixelSize: 14
                    font.family: root.fontFamily || ""
                }

                MouseArea {
                    id: addArea
                    anchors.fill: parent
                    enabled: !root.sending
                    onClicked: root.addRequested()
                }
            }

            Item {
                id: textArea
                clip: true
                anchors {
                    left: addButton.right
                    leftMargin: 6
                    right: cancelButton.left
                    rightMargin: 4
                    top: parent.top
                    bottom: parent.bottom
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.sending
                          ? "发送中…"
                          : (root.draftText.length > 0
                             ? root.draftText
                             : (root.editing
                                ? "编辑消息…"
                                : (root.attachmentCount > 0
                                   ? root.attachmentCount + " 个附件"
                                   : "输入消息…")))
                    color: root.draftText.length > 0 || root.sending ? "#E6EDF3" : "#8297A8"
                    font.pixelSize: 12
                    font.family: root.fontFamily || ""
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !root.sending
                    onClicked: root.editRequested()
                }
            }

            Rectangle {
                id: sendButton
                width: 42
                height: 22
                radius: 6
                anchors {
                    right: parent.right
                    rightMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                color: !root.canSend ? "#22303F" : (sendArea.pressed ? "#3E7CB1" : "#2B5278")
                border.width: 1
                border.color: root.canSend ? "#4A90D9" : "#2B3A4A"

                Text {
                    anchors.centerIn: parent
                    text: root.sending ? "…" : "发送"
                    color: root.canSend ? "#FFFFFF" : "#6B7C8C"
                    font.pixelSize: 11
                    font.family: root.fontFamily || ""
                }

                MouseArea {
                    id: sendArea
                    anchors.fill: parent
                    enabled: root.canSend
                    onClicked: root.sendRequested()
                }
            }

            Rectangle {
                id: cancelButton
                width: 30
                height: 22
                radius: 6
                anchors {
                    right: sendButton.left
                    rightMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                color: cancelArea.pressed ? "#3A2020" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: "#9FB0C0"
                    font.pixelSize: 15
                    font.bold: true
                    font.family: root.fontFamily || ""
                }

                MouseArea {
                    id: cancelArea
                    anchors.fill: parent
                    enabled: !root.sending
                    onClicked: root.cancelRequested()
                }
            }
        }
    }
}
