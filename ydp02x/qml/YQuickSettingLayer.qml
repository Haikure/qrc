import QtQuick 2.12
import com.youdao.pen 1.0
import QtGraphicalEffects 1.14

import "./commons"
import "./components"

Item {
    id: id_quick_setting_layer_root
    width: YEnum.Screen.Width
    height: YEnum.Screen.Height
    state: "close"

    readonly property bool isOpening: ("open" === state)
    readonly property bool musicControlsAvailable: musicPlayer.hideFloatingWindow
                                        && mediaPlayerManager.playerMode === YEnum.PM_AudioPlayer
                                        && mediaPlayerManager.title.length > 0
                                        && mediaPlayerManager.playState !== YEnum.STOPPED

    property bool showingMusicControls: false
    property alias fastBlurTarget: id_fast_blur.source

    function close() {
        if ("open" === state) {
            forceClose()
        }
    }

    function open() {
        if ("close" === state) {
            reopen()
        }
    }

    function reopen() {
        state = "openning"
        showingMusicControls = musicControlsAvailable
        id_open_close_animator.to = 0
        id_open_close_animator.restart()
        settingManager.updateVolumeAndLcd()
    }

    function forceClose() {
        state = "closing"
        id_volum_setting.rebinding()
        id_lum_setting.rebinding()
        id_open_close_animator.to = - id_quick_setting_layer_root.height
        id_open_close_animator.restart()
    }

    YMouseArea {
        anchors.fill: parent
        drag.target: id_quick_setting_layer_root
        drag.axis: Drag.YAxis
        drag.minimumY: - id_quick_setting_layer_root.height
        drag.maximumY: 0
        objectName: "YQuickSettingLayer.qml_YMouseArea"
        enabled: settingManager.isVerified
        property real pressedY: 0
        onPressed: {
            pressedY = id_quick_setting_layer_root.y
            id_check_timer.restart()
        }

        onReleased: {
            doReleased()
        }

        onCanceled: {
            doReleased()
        }

        YTimer {
            id: id_check_timer
            interval: 300
            objectName: "YQuickSettingLayer.qml_id_check_timer"
        }

        function doReleased() {
            if (id_quick_setting_layer_root.y < - id_quick_setting_layer_root.height / 5
                    || (id_check_timer.running
                        && (pressedY - id_quick_setting_layer_root.y > 10))) {
                id_quick_setting_layer_root.forceClose()
            } else {
                id_quick_setting_layer_root.reopen()
            }
        }
    }

    YAnimator {
        id: id_open_close_animator
        target: id_quick_setting_layer_root
        from: id_quick_setting_layer_root.y
        to: - id_quick_setting_layer_root.height
        duration: 120
        running: false
        alwaysRunToEnd: true
        onRunningChanged: {
            if (!running) {
                if ("openning" === id_quick_setting_layer_root.state) {
                    id_quick_setting_layer_root.state = "open"
                } else if ("closing" === id_quick_setting_layer_root.state) {
                    id_quick_setting_layer_root.state = "close"
                }
            }
        }
    }

    FastBlur {
        id: id_fast_blur
        anchors.fill: parent
        radius: 16
    }

    Rectangle {
        anchors.fill: parent
        color: "#E6000000"
    }

    YQuickMusicPlayer {
        visible: id_quick_setting_layer_root.showingMusicControls
                 && id_quick_setting_layer_root.musicControlsAvailable
        onAdjustSettingsRequested: id_quick_setting_layer_root.showingMusicControls = false
        onPlayerRequested: {
            id_quick_setting_layer_root.forceClose()
            qmlGlobal.showAudioPlayer()
        }
    }

    Item {
        id: id_settings_panel
        anchors.fill: parent
        visible: !id_quick_setting_layer_root.showingMusicControls
                 || !id_quick_setting_layer_root.musicControlsAvailable

        YIconButton {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            implicitWidth: 24
            implicitHeight: 24
            radius: 6
            mouseAreaMargins: -3
            sourceSize: Qt.size(16, 16)
            imageName: "audioplayer/authorized_play"
            visible: id_quick_setting_layer_root.musicControlsAvailable
            onValidClicked: id_quick_setting_layer_root.showingMusicControls = true
            objectName: "YQuickSettingLayer.qml_id_show_music_button"
        }

        Item {
            id: id_status_bar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 26

            YText {
                id: id_time
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: paintedWidth
                height: paintedHeight
                font.pixelSize: 14
                text: timeManager.currentTime
            }

            YImage {
                id: id_headset_icon
                anchors.left: id_time.right
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                sourceSize: Qt.size(14, 14)
                imageName: "settings/bluetooth-headset"
                visible: blueToothManager.link || systemBase.digHeadset
            }

            YText {
                id: id_battery_value
                anchors.right: id_battery_icon.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: paintedWidth
                height: paintedHeight
                font.pixelSize: 14
                text: ("%1%").arg(batteryManager.power)
            }

            Rectangle {
                id: id_battery_icon
                anchors.right: batteryManager.charging ? id_charging_icon.left : parent.right
                anchors.rightMargin: batteryManager.charging ? 4 : 16
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 11
                radius: 4
                color: "transparent"
                border.width: 1
                border.color: YColors.white

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: (parent.width - 4) * Math.max(0, Math.min(100, batteryManager.power)) / 100
                    height: 6
                    radius: 2
                    color: batteryManager.charging
                          ? (batteryManager.power < 100 ? "#00FF66" : YColors.white)
                          : (batteryManager.power < 20 ? YColors.red : YColors.white)
                }

                Rectangle {
                    anchors.left: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: 5
                    radius: 1
                    color: YColors.white
                }
            }

            YImage {
                id: id_charging_icon
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                sourceSize: Qt.size(14, 14)
                imageName: "ic_battery_flash"
                visible: batteryManager.charging
            }
        }

        Grid {
            anchors.top: id_status_bar.bottom
            anchors.topMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 2
            rows: 2
            rowSpacing: 10
            columnSpacing: 16
            padding: 0

            YVolmueAdjustor {
                id: id_volum_setting
                implicitWidth: 150
                implicitHeight: 46
                width: 150
                height: 46
            }

            YSlideWifiSetting {
                id: id_slide_wifi
                width: 72
                height: 46
            }

            YTouchRegulator {
                id: id_lum_setting
                implicitWidth: 150
                implicitHeight: 46
                width: 150
                height: 46
                property int lcdSettingBrightness: settingManager.lcdBrightness
                YImage {
                    sourceSize: Qt.size(30, 30)
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    imageName: {
                        if (0 === id_lum_setting.value) {
                            return "slide/lum_off"
                        } else if (id_lum_setting.value <= 50) {
                            return "slide/lum_half"
                        } else {
                            return "slide/lum"
                        }
                    }
                }
                onValueChanged: {
                    if (lcdSettingBrightness != value) {
                        settingManager.setLcdBrightness(value)
                    }
                }
                onLcdSettingBrightnessChanged: {
                    if (lcdSettingBrightness != value) {
                        value = lcdSettingBrightness
                    }
                }

                function rebinding() {
                    value = Qt.binding(function(){ return lcdSettingBrightness })
                }

                Component.onCompleted: rebinding()
            }

            YSlideBluetoothSetting {
                id: id_slide_bluetooth
                width: 72
                height: 46
            }
        }
    }

    YImage {
        sourceSize: Qt.size(40, 10)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        imageName: "slide/ic_collapse"
    }
}

