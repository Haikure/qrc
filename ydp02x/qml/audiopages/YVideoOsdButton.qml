import QtQuick 2.12

import "../commons"

/**
 * 播放页 OSD 上的小按钮：半透明圆角块 + 一行文字。
 * 视频画面上不能叠模糊层（自定义 QSG 节点上的 ShaderEffectSource 不可靠），所以用纯色蒙版。
 */
Rectangle {
    id: id_osd_button

    property string text: ""
    property bool active: false

    signal tapped()

    implicitWidth: id_label.implicitWidth + 16
    implicitHeight: 24
    radius: 12
    color: active ? YColors.blueRect : YColors.black
    opacity: id_mouse.pressed ? 0.75 : (active ? 0.9 : 0.55)

    YText {
        id: id_label
        anchors.centerIn: parent
        font.pixelSize: 13
        text: id_osd_button.text
    }

    MouseArea {
        id: id_mouse
        anchors.fill: parent
        // 让视频手势层收不到这次点击
        onClicked: id_osd_button.tapped()
    }
}
