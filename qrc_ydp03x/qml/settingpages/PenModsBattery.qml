import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../i18n"

// 电池信息（QEMU 无电池时显示 0/未知，真机可用）
YSettingItemPage {
    id: id_battery
    objectName: "YPage===PenModsBattery.qml"

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 90
        anchors.rightMargin: 16
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "电池信息"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            PenModsSettingRow { title: "状态"; value: batteryInfo.status }
            PenModsSettingRow { title: "当前电压"; value: batteryInfo.voltage }
            PenModsSettingRow { title: "电池温度"; value: batteryInfo.temperature }
            PenModsSettingRow { title: "电池健康"; value: batteryInfo.health }
            PenModsSettingRow { title: "实时电流"; value: batteryInfo.current }
            PenModsSettingRow { title: "续航预测"; value: batteryInfo.prediction }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 3000
        onTriggered: batteryInfo.update()
    }
}
