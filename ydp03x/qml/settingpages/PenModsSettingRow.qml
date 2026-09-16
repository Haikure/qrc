import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../components"
import "../i18n"

// PenMods 设置行（原生设置风格）：灰底圆角块 + 左侧标题 + 右侧值/选中对勾
YSettingItemBackground {
    id: id_row
    implicitHeight: 76

    property string title: ""
    property string value: ""
    property bool checked: false

    signal clicked()

    YMouseArea {
        anchors.fill: parent
        onClicked: id_row.clicked()
    }

    // 右侧值（信息行，如电池/网络）
    YTextMedium {
        id: id_row_value
        anchors.right: parent.right
        anchors.rightMargin: 28
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: 22
        color: YColors.grayText
        text: id_row.value
        elide: Text.ElideLeft
        horizontalAlignment: Text.AlignRight
        width: 200
        visible: text !== ""
    }

    // 选中对勾（单选列表，如息屏/休眠时长）
    YImage {
        anchors.right: parent.right
        anchors.rightMargin: 28
        anchors.verticalCenter: parent.verticalCenter
        sourceSize: Qt.size(26, 26)
        imageName: "textbook/select-check"
        visible: id_row.checked && id_row.value === ""
    }

    // 左侧标题（右侧预留 210px 给值/对勾）
    YTextMedium {
        anchors.left: parent.left
        anchors.leftMargin: 28
        anchors.right: parent.right
        anchors.rightMargin: 210
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: 24
        color: YColors.white
        text: id_row.title
        elide: Text.ElideRight
    }
}
