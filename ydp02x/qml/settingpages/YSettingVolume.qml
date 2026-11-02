import QtQuick 2.12
import com.youdao.pen 1.0

import "../commons"
import "../components"
import "../i18n"

YPage {
    id: id_setting_item
    objectName: "YPage===YSettingVolume.qml"

    property alias title: id_title_container.title

    Flickable {
        id: id_setting_item_view
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: id_speaking_rate_grid.y + id_speaking_rate_grid.height + 12
        interactive: !id_slider_moving_timer.running

        YSettingItemTitle {
            id: id_title_container
            title: YTranslateText.adjustVolume
        }

        YSettingItemBackground {
            id: id_slider_rect
            implicitHeight: 60
            anchors.top: id_title_container.bottom

            YSlider {
                id: id_slider
                implicitWidth: 140
                anchors.centerIn: parent
                property int spkSettingVolume: settingManager.spkVolume
                onValueChanged: {
                    id_slider_moving_timer.restart()
                    if (spkSettingVolume != value) {
                        settingManager.setSpkVolume(value)
                        Qt.callLater(function() { value = settingManager.spkVolume })
                    }
                }
                onSpkSettingVolumeChanged: {
                    if (spkSettingVolume != value) {
                        value = spkSettingVolume
                    }
                }
                Component.onCompleted: value = spkSettingVolume
            }

            YTimer {
                id: id_slider_moving_timer
                interval: 300
                objectName: "YSettingVolume.qml_id_slider_moving_timer"
            }

            YClickabledImage {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: id_slider.left
                anchors.rightMargin: 16
                mouseAreaMargins: -4
                imageName: "settings/sound-dec"
                onClicked: {
                    id_slider.decrementTenValue()
                }
            }

            YClickabledImage {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: id_slider.right
                anchors.leftMargin: 16
                mouseAreaMargins: -4
                imageName: "settings/sound-inc"
                onClicked: {
                    id_slider.incrementTenValue()
                }
            }
        }

        DescribedSwitchItem {
            id: volume_guard_switch
            anchors.top: id_slider_rect.bottom
            anchors.topMargin: 8
            title: "音量上限保护"
            description: "按输出设备分别限音量，切换后自动检查。"
            switchOn: volumeGuard.enabled
            interval: 0
            onTimerTriggered: volumeGuard.enabled = switchOn
        }

        Column {
            id: volume_limits
            anchors.top: volume_guard_switch.bottom
            anchors.topMargin: 8
            width: parent.width
            spacing: 6

            Rectangle {
                width: parent.width
                height: 64
                radius: 12
                color: YColors.surface

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: volume_status_badge.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    YText {
                        text: "音频输出"
                        font.pixelSize: 12
                        color: YColors.grayText
                    }
                    YText {
                        width: parent.width
                        text: volumeGuard.outputName.replace("USB / Type-C", "USB")
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: volume_status_badge
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 68
                    height: 28
                    radius: 14
                    color: volumeGuard.enabled ? YColors.greenFamily.tint : YColors.neutral.n700

                    YText {
                        anchors.centerIn: parent
                        text: volumeGuard.enabled ? "≤ " + volumeGuard.currentLimit + "%" : "未开启"
                        font.pixelSize: 14
                        color: volumeGuard.enabled ? YColors.greenFamily.text : YColors.grayText
                    }
                }
            }

            Repeater {
                model: ["扬声器", "模拟耳机", "USB 数字耳机", "蓝牙音频"]
                delegate: Row {
                    id: limit_row
                    property int cap: volumeGuard.limit(index)
                    spacing: 6
                    height: 40
                    enabled: volumeGuard.enabled
                    Connections {
                        target: volumeGuard
                        onSettingsChanged: limit_row.cap = volumeGuard.limit(index)
                    }
                    YText {
                        width: 134
                        height: 40
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 14
                        text: modelData + " " + limit_row.cap + "%"
                    }
                    YPressedButton {
                        implicitWidth: 48
                        implicitHeight: 36
                        text: "−"
                        onClicked: volumeGuard.setLimit(index, limit_row.cap - 5)
                    }
                    YPressedButton {
                        implicitWidth: 48
                        implicitHeight: 36
                        text: "+"
                        onClicked: volumeGuard.setLimit(index, limit_row.cap + 5)
                    }
                }
            }
            YText {
                width: parent.width
                height: 40
                font.pixelSize: 12
                color: YColors.grayText
                wrapMode: Text.Wrap
                text: "百分比不是声压值。蓝牙设备自身音量、播放器额外增益仍需单独调整。"
            }
        }

        DescribedSwitchItem {
            id: switch_fast_mute
            anchors.left: parent.left
            anchors.top: volume_limits.bottom
            anchors.topMargin: 8
            title: "快速静音"
            description: "点击控制中心的音量图标时直接静音。"
            switchOn: antiEmbs.fastMute
            interval: 0
            onTimerTriggered: {
                antiEmbs.fastMute = switchOn
            }
        }

        YSettingSwitchItem {
            id: switch_low_voice
            anchors.left: parent.left
            anchors.top: switch_fast_mute.bottom
            anchors.topMargin: 8
            implicitHeight: 54
            title: "降低最低音量"
            switchOn: antiEmbs.lowVoiceMode
            interval: 0
            onTimerTriggered: {
                antiEmbs.lowVoiceMode = switchOn
            }
        }

        YText {
            id: id_speaking_rate_label
            anchors.left: parent.left
            anchors.top: switch_low_voice.bottom
            anchors.topMargin: 12
            height: 20
            font.pixelSize: 16
            color: YColors.grayText
            text: YTranslateText.soundSpeedChoice
        }

        Grid {
            id: id_speaking_rate_grid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: id_speaking_rate_label.bottom
            anchors.topMargin: 8
            columns: 2
            spacing: 8

            YPressedButton {
                id: id_quickly_button
                implicitWidth: 124
                clickable: settingManager.audioSpeed !== YEnum.SPEED_QUICK
                checkedIndicatorScale: settingManager.audioSpeed === YEnum.SPEED_QUICK
                text: YTranslateText.soundSpeedQuick
                onClicked: {
                    logManager.sendHttpLog("action=setting_sound_f_click")
                    settingManager.audioSpeed = YEnum.SPEED_QUICK
                    soundCenter.play("How are you", "en")
                }
            }

            YPressedButton {
                id: id_middle_button
                implicitWidth: 124
                clickable: settingManager.audioSpeed !== YEnum.SPEED_MID
                checkedIndicatorScale: settingManager.audioSpeed === YEnum.SPEED_MID
                text: YTranslateText.soundSpeedMiddle
                onClicked: {
                    logManager.sendHttpLog("action=setting_sound_m_click")
                    settingManager.audioSpeed = YEnum.SPEED_MID
                    soundCenter.play("How are you", "en")
                }
            }

            YPressedButton {
                id: id_slowly_button
                implicitWidth: 124
                clickable: settingManager.audioSpeed !== YEnum.SPEED_SLOW
                checkedIndicatorScale: settingManager.audioSpeed === YEnum.SPEED_SLOW
                text: YTranslateText.soundSpeedSlow
                onClicked: {
                    logManager.sendHttpLog("action=setting_sound_s_click")
                    settingManager.audioSpeed = YEnum.SPEED_SLOW
                    soundCenter.play("How are you", "en")
                }
            }
        }

    }

    YVerticalTitleBar {
        id: id_title_bar
        onCallBack: {
            soundCenter.stop()
            backButtonClicked()
        }
    }
}

