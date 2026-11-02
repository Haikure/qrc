import QtQuick 2.12

// 草稿/输入页的附件条（#21-3 多附件预览）：
//   - 图片显示缩略图 + 名称，文件显示扩展名图标 + 文件名；
//   - 每个附件单独 ×（locked 的“编辑时保留的文件”不显示删除）；
//   - 「清空」一次清掉全部可删附件，locked 保留；
//   - showCount 时右侧显示附件数量。
Rectangle {
    id: root

    property var filesModel: null
    property var mediaModel: null
    property var fontFamily

    // 只有"有预发送附件就允许空文字发送"的宿主才打开（聊天页预发送条、编辑页图片条），默认关闭。
    // 验证：打开后右侧出现「发送」，点它不依赖输入框内容。
    property bool showSendButton: false
    // 草稿条用：右侧多一个「清空」，一次性清掉全部可删附件。
    property bool showClearButton: false
    // 草稿条用：右侧显示附件数量（多附件时更直观）。
    property bool showCount: false
    signal sendRequested()

    readonly property int totalCount: (filesModel ? filesModel.count : 0) + (mediaModel ? mediaModel.count : 0)
    readonly property int clearWidth: 40
    readonly property int countWidth: 26
    // 列表要让出右侧按钮/计数的宽度，否则最后一个 chip 被盖住。
    readonly property int trailingWidth: 4
                                           + (showSendButton ? 44 + 8 : 0)
                                           + ((showClearButton && totalCount > 0) ? clearWidth + 8 : 0)
                                           + ((showCount && totalCount > 0) ? countWidth + 6 : 0)

    function clearAll() {
        // locked 的附件（编辑旧消息时原消息里的文件/音频）不能删，只清可删项。
        if (filesModel) {
            for (var f = filesModel.count - 1; f >= 0; --f) {
                if (!filesModel.get(f).locked)
                    filesModel.remove(f, 1);
            }
        }
        if (mediaModel) {
            for (var m = mediaModel.count - 1; m >= 0; --m) {
                if (!mediaModel.get(m).locked)
                    mediaModel.remove(m, 1);
            }
        }
    }

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

    // 图片缩略图源：data URL（草稿新拍的图）或 file://（历史/编辑回填的图）。
    function imageSource(item) {
        if (!item)
            return "";
        if (item.source)
            return item.source;
        if (item.url)
            return item.url;
        if (item.localPath)
            return "file://" + item.localPath;
        return "";
    }

    function itemLabel(item) {
        if (!item)
            return "";
        return item.label || item.name || item.type || "";
    }

    height: 34
    implicitWidth: 96
    implicitHeight: 34
    radius: 8
    color: "#CC0E1621"
    border.width: 1
    border.color: "#2B3A4A"

    ListView {
        id: chipsView
        anchors { fill: parent; margins: 4; rightMargin: root.trailingWidth }
        orientation: ListView.Horizontal
        spacing: 6
        clip: true
        model: root.totalCount

        delegate: Rectangle {
            readonly property int fileCount: root.filesModel ? root.filesModel.count : 0
            readonly property bool isMediaChip: index >= fileCount
            readonly property int mediaIndex: index - fileCount
            readonly property var chipData: isMediaChip
                ? (root.mediaModel && mediaIndex < root.mediaModel.count ? root.mediaModel.get(mediaIndex) : null)
                : (root.filesModel && index < root.filesModel.count ? root.filesModel.get(index) : null)
            readonly property bool isImageChip: isMediaChip && chipData && chipData.type === "image_url"
            readonly property bool locked: chipData ? chipData.locked === true : false
            readonly property int labelWidth: Math.min(chipLabelMetrics.advanceWidth, 110)
            readonly property int chipWidth: 8 + 20 + 4 + labelWidth + (locked ? 42 : 36)

            // 宽度显式算（不依赖 Row 的 implicitWidth：Image 子项的 implicitWidth 不会按 width 推导）。
            TextMetrics {
                id: chipLabelMetrics
                font.pixelSize: 11
                font.family: root.fontFamily || ""
                text: root.itemLabel(chipData)
            }

            height: 26
            implicitWidth: chipWidth
            implicitHeight: 26
            width: chipWidth
            radius: 6
            color: locked ? "#3A3F48" : (isMediaChip ? "#28552A" : "#2B5278")

            Row {
                id: chipContent
                anchors {
                    left: parent.left
                    leftMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 4

                // 图片：缩略图；其它：类型图标。
                Image {
                    width: 20
                    height: 20
                    // Image 的 implicitWidth/Height 是只读的计算属性，不能赋值（320x170 实测报错）。
                    visible: !parent.parent.isImageChip
                    source: root.formatIcon(chipData, isMediaChip)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                Image {
                    width: 20
                    height: 20
                    visible: parent.parent.isImageChip
                    source: root.imageSource(chipData)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.itemLabel(chipData)
                    color: "#FFFFFF"
                    font.pixelSize: 11
                    font.family: root.fontFamily || ""
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                    width: labelWidth
                }
            }

            // 单个删除（locked 的保留附件不可删）。
            Rectangle {
                visible: !parent.locked
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
                        if (isMediaChip)
                            root.mediaModel.remove(mediaIndex, 1);
                        else
                            root.filesModel.remove(index, 1);
                    }
                }
            }

            // locked：编辑旧消息时原消息里的文件/音频，只展示“保留”，不允许删除。
            Text {
                visible: parent.locked
                anchors {
                    right: parent.right
                    rightMargin: 6
                    verticalCenter: parent.verticalCenter
                }
                text: "保留"
                color: "#C8D6E2"
                font.pixelSize: 9
                font.family: root.fontFamily || ""
            }
        }
    }

    Text {
        visible: root.showCount && root.totalCount > 0
        width: visible ? root.countWidth : 0
        anchors {
            right: root.showClearButton && root.totalCount > 0 ? clearButton.left : parent.right
            rightMargin: 6
            verticalCenter: parent.verticalCenter
        }
        text: root.totalCount + " 个"
        color: "#8FA3B5"
        font.pixelSize: 9
        font.family: root.fontFamily || ""
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }

    Rectangle {
        id: sendButton
        // 320x170 上没有空间再开一行：按钮与 chip 同高（26）、靠右对齐，44px 够放两个汉字。
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

    Rectangle {
        id: clearButton
        // 草稿条右侧的「清空」：只清可删的预发送附件，不取消草稿文字、不动 locked 附件。
        visible: root.showClearButton && root.totalCount > 0
        width: visible ? root.clearWidth : 0
        height: 26
        radius: 6
        color: clearArea.pressed ? "#3A2020" : "#17222D"
        border.width: 1
        border.color: "#34495B"
        anchors {
            right: root.showSendButton ? sendButton.left : parent.right
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }

        Text {
            anchors.centerIn: parent
            text: "清空"
            color: "#C8D6E2"
            font.pixelSize: 11
            font.family: root.fontFamily || ""
        }

        MouseArea {
            id: clearArea
            anchors.fill: parent
            onClicked: root.clearAll()
        }
    }
}
