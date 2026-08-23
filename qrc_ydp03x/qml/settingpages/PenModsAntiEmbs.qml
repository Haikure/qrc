import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../i18n"

// 防尴尬系列：蓝牙断连自动静音 / 强制关闭自动发音 / 降低最低音量 / 快速静音 / 快速隐藏
YSettingItemPage {
    id: id_anti_embs
    objectName: "YPage===PenModsAntiEmbs.qml"

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 90
        anchors.rightMargin: 16
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "防尴尬设置（蓝牙断连自动静音、禁用自动发音、降低最低音量）"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            PenModsSwitchRow {
                title: "蓝牙断连自动静音"
                checked: antiEmbs.autoMute
                onRowToggled: antiEmbs.autoMute = checked
            }
            PenModsSwitchRow {
                title: "强制禁用自动发音"
                checked: antiEmbs.autoPronLocked
                onRowToggled: antiEmbs.autoPronLocked = checked
            }
            PenModsSwitchRow {
                title: "降低最低音量"
                checked: antiEmbs.lowVoiceMode
                onRowToggled: antiEmbs.lowVoiceMode = checked
            }
            PenModsSwitchRow {
                title: "快速静音"
                checked: antiEmbs.fastMute
                onRowToggled: antiEmbs.fastMute = checked
            }
            PenModsSwitchRow {
                title: "快速隐藏（连按 4 次 Home 切换隐藏文件）"
                checked: antiEmbs.fastHide
                onRowToggled: antiEmbs.fastHide = checked
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }
}
