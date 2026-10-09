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
    // 按键小助手激活时恢复快速设置改版前的外观。
    readonly property bool useOriginalStyle: antiEmbs.active
    readonly property bool pluginMusicAvailable: typeof mediaSession !== "undefined" && mediaSession.active
    readonly property bool hostMusicAvailable: musicPlayer.hideFloatingWindow
                                        && mediaPlayerManager.playerMode === YEnum.PM_AudioPlayer
                                        && mediaPlayerManager.title.length > 0
                                        && mediaPlayerManager.playState !== YEnum.STOPPED
    readonly property bool musicControlsAvailable: pluginMusicAvailable || hostMusicAvailable

    property bool showingMusicControls: false
    property alias fastBlurTarget: id_fast_blur.source

    // 音乐不可用时强制回到控制菜单; 用户的视图偏好仍保留, 音乐再次可用时恢复
    onMusicControlsAvailableChanged: {
        if (!musicControlsAvailable) {
            showingMusicControls = false
        }
    }

    // 记录用户主动选择的视图, 供下次打开面板时沿用
    function setMusicControlsShown(show) {
        showingMusicControls = show
        musicPlayer.quickPanelMusicView = show
    }

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
        showingMusicControls = musicControlsAvailable && musicPlayer.quickPanelMusicView
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
        showProgress: !id_quick_setting_layer_root.useOriginalStyle
        visible: id_quick_setting_layer_root.showingMusicControls
                 && id_quick_setting_layer_root.musicControlsAvailable
        onAdjustSettingsRequested: id_quick_setting_layer_root.setMusicControlsShown(false)
        onPlayerRequested: {
            id_quick_setting_layer_root.forceClose()
            if (typeof mediaSession !== "undefined" && mediaSession.active) {
                mediaSession.openRequested()
            } else {
                qmlGlobal.showAudioPlayer()
            }
        }
    }

    Item {
        id: id_settings_panel
        anchors.fill: parent
        visible: !id_quick_setting_layer_root.showingMusicControls
                 || !id_quick_setting_layer_root.musicControlsAvailable

        YIconButton {
            anchors.right: parent.right
            anchors.rightMargin: id_quick_setting_layer_root.useOriginalStyle ? 4 : 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: id_quick_setting_layer_root.useOriginalStyle ? 0 : 8
            implicitWidth: 24
            implicitHeight: 24
            radius: 6
            mouseAreaMargins: -3
            sourceSize: Qt.size(16, 16)
            imageName: "audioplayer/authorized_play"
            visible: id_quick_setting_layer_root.musicControlsAvailable
            onValidClicked: id_quick_setting_layer_root.setMusicControlsShown(true)
            objectName: "YQuickSettingLayer.qml_id_show_music_button"
        }

        Item {
            id: id_status_bar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: id_quick_setting_layer_root.useOriginalStyle ? 0 : 26
            visible: !id_quick_setting_layer_root.useOriginalStyle

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

            Item {
                id: id_battery_icon
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 27
                height: 14

                readonly property real level: Math.max(0, Math.min(100, batteryManager.power)) / 100
                readonly property color fillColor: batteryManager.charging ? "#65D6A4"
                                                   : (level < 0.2 ? YColors.red : "#EEF1F6")

                Rectangle {
                    id: id_battery_body
                    anchors.left: parent.left
                    width: 24
                    height: parent.height
                    radius: 3
                    color: "#14FFFFFF"
                    border.width: 1
                    border.color: "#A6FFFFFF"
                    antialiasing: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: id_battery_icon.level > 0
                               ? Math.max(1, Math.round((parent.width - 6) * id_battery_icon.level)) : 0
                        height: parent.height - 6
                        radius: 1
                        color: id_battery_icon.fillColor
                    }
                }

                Rectangle {
                    anchors.left: id_battery_body.right
                    anchors.leftMargin: 1
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: 6
                    radius: 1
                    color: id_battery_body.border.color
                }
            }

            YImage {
                id: id_charging_icon
                anchors.right: id_battery_value.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                sourceSize: Qt.size(12, 12)
                imageName: "ic_battery_flash"
                visible: batteryManager.charging
            }
        }

        Grid {
            anchors.top: id_status_bar.bottom
            anchors.topMargin: id_quick_setting_layer_root.useOriginalStyle ? 0 : 4
            x: id_quick_setting_layer_root.useOriginalStyle ? 0 : (parent.width - width) / 2
            columns: 2
            rows: 2
            rowSpacing: id_quick_setting_layer_root.useOriginalStyle ? 12 : 10
            columnSpacing: id_quick_setting_layer_root.useOriginalStyle ? 24 : 16
            padding: id_quick_setting_layer_root.useOriginalStyle ? 20 : 0

            YVolmueAdjustor {
                id: id_volum_setting
                implicitWidth: id_quick_setting_layer_root.useOriginalStyle ? 178 : 150
                implicitHeight: id_quick_setting_layer_root.useOriginalStyle ? 56 : 46
                width: implicitWidth
                height: implicitHeight
            }

            YSlideWifiSetting {
                id: id_slide_wifi
                width: id_quick_setting_layer_root.useOriginalStyle ? implicitWidth : 72
                height: id_quick_setting_layer_root.useOriginalStyle ? implicitHeight : 46
            }

            YTouchRegulator {
                id: id_lum_setting
                implicitWidth: id_quick_setting_layer_root.useOriginalStyle ? 178 : 150
                implicitHeight: id_quick_setting_layer_root.useOriginalStyle ? 56 : 46
                width: implicitWidth
                height: implicitHeight
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
                width: id_quick_setting_layer_root.useOriginalStyle ? implicitWidth : 72
                height: id_quick_setting_layer_root.useOriginalStyle ? implicitHeight : 46
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
