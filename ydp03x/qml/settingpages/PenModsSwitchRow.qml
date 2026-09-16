import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../components"
import "../common"
import "../i18n"

// PenMods 开关行（原生设置风格）：灰底圆角块 + 左侧标题 + 右侧 YSwitch
YSettingItemBackground {
    id: id_switch_row
    implicitHeight: 76

    property string title: ""
    property bool checked: false

    signal rowToggled()

    YMouseArea {
        anchors.fill: parent
        onClicked: {
            id_switch_row.checked = !id_switch_row.checked
            id_switch_row.rowToggled()
        }
    }

    YTextMedium {
        anchors.left: parent.left
        anchors.leftMargin: 28
        anchors.right: id_row_switch.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: 24
        color: YColors.white
        text: id_switch_row.title
        elide: Text.ElideRight
    }

    YSwitch {
        id: id_row_switch
        anchors.right: parent.right
        anchors.rightMargin: 28
        anchors.verticalCenter: parent.verticalCenter
        switchOn: id_switch_row.checked
    }
}
