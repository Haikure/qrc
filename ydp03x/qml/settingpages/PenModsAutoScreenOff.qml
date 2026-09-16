import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../i18n"

// 息屏设置：30秒 / 1-5分钟 / 永不（写 input-event-daemon 配置）
YSettingItemPage {
    id: id_auto_screen_off
    objectName: "YPage===PenModsAutoScreenOff.qml"

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 90
        anchors.rightMargin: 16
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "息屏前 10 秒屏幕自动变暗"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            Repeater {
                model: [
                    { label: "30 秒", value: "30秒" },
                    { label: "1 分钟", value: "1分钟" },
                    { label: "2 分钟", value: "2分钟" },
                    { label: "3 分钟", value: "3分钟" },
                    { label: "4 分钟", value: "4分钟" },
                    { label: "5 分钟", value: "5分钟" },
                    { label: "永不",   value: "永不" }
                ]
                delegate: PenModsSettingRow {
                    title: modelData.label
                    checked: screenManager.autoSleepDuration === modelData.value
                    onClicked: {
                        screenManager.autoSleepDuration = modelData.value
                    }
                }
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }
}
