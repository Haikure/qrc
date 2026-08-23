import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../i18n"

// 自动休眠设置：5/10/20/40 分钟 / 永不
YSettingItemPage {
    id: id_auto_suspend
    objectName: "YPage===PenModsAutoSuspend.qml"

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 90
        anchors.rightMargin: 16
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "无操作自动休眠"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            Repeater {
                model: [
                    { label: "5 分钟",  value: "5分钟" },
                    { label: "10 分钟", value: "10分钟" },
                    { label: "20 分钟", value: "20分钟" },
                    { label: "40 分钟", value: "40分钟" },
                    { label: "永不",    value: "永不" }
                ]
                delegate: PenModsSettingRow {
                    title: modelData.label
                    checked: batteryInfo.autoSuspendDuration === modelData.value
                    onClicked: {
                        batteryInfo.autoSuspendDuration = modelData.value
                    }
                }
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }
}
