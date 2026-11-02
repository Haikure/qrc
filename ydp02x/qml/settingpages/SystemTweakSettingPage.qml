import QtQuick 2.12
import com.youdao.pen 1.0

import "../commons"
import "../components"
import "../i18n"

YSettingItemPage {
    id: id_setting_item
    objectName: "YPage===SystemTweakSettingPage.qml"

    property bool showOcrSettings: false
    Component.onCompleted: {
        if (showOcrSettings) Qt.callLater(function() {
            id_setting_item_view.contentY = Math.max(0, Math.min(id_title_experimental.y + id_column.y,
                id_setting_item_view.contentHeight - id_setting_item_view.height));
        })
    }

    Flickable {
        id: id_setting_item_view
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: id_column.height

        Column {
            id: id_column
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            // ======================================
            // 应用重启（只结束 YoudaoDictPen 进程，由 guardian 重新拉起；不是整机 reboot）

            YText {
                id: id_title_restart
                font.pixelSize: 16
                font.italic: true
                color: YColors.grayText
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 24
                width: parent.width
                text: "应用重启"
            }

            YSettingAboutClickableItem {
                title: mod.applicationRestartPending ? "正在重启应用…" : "重启应用"
                enabled: !mod.applicationRestartPending
                onClicked: {
                    id_restart_app_dialog.show();
                }
            }

            // ======================================

            YText {
                id: id_title_log
                font.pixelSize: 16
                font.italic: true
                color: YColors.grayText
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 24
                width: parent.width
                text: "日志策略"
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "阻止上传行为记录"
                switchOn: loggerMonitor.noUploadUserAction
                interval: 0
                onTimerTriggered: {
                    loggerMonitor.noUploadUserAction = switchOn
                }
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "阻止上传扫描图像"
                switchOn: loggerMonitor.noUploadRawScanImg
                interval: 0
                onTimerTriggered: {
                    loggerMonitor.noUploadRawScanImg = switchOn
                }
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "阻止上传HTTP日志"
                switchOn: loggerMonitor.noUploadHttplog
                interval: 0
                onTimerTriggered: {
                    loggerMonitor.noUploadHttplog = switchOn
                }
            }

            // ======================================

            YText {
                id: id_title_column_db
                font.pixelSize: 16
                font.italic: true
                color: YColors.grayText
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 24
                width: parent.width
                text: "列式数据库"
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "提高单次加载数量"
                switchOn: columnDb.patch
                interval: 0
                onTimerTriggered: {
                    columnDb.patch = switchOn
                }
            }

            // ======================================

            YText {
                id: id_title_other
                font.pixelSize: 16
                font.italic: true
                color: YColors.grayText
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 24
                width: parent.width
                text: "音乐播放器"
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "扫描时暂停播放"
                switchOn: musicPlayer.pauseOnScan
                interval: 0
                onTimerTriggered: {
                    musicPlayer.pauseOnScan = switchOn
                }
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "隐藏音乐悬浮窗"
                switchOn: musicPlayer.hideFloatingWindow
                interval: 0
                onTimerTriggered: {
                    musicPlayer.hideFloatingWindow = switchOn
                }
            }

            // ======================================

            YText {
                id: id_title_experimental
                font.pixelSize: 16
                font.italic: true
                color: YColors.grayText
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 24
                width: parent.width
                text: "实验性功能"
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "PP-OCRv5 引擎"
                enabled: ocrBackend.installed
                switchOn: ocrBackend.enabled
                interval: 0
                onTimerTriggered: {
                    ocrBackend.enabled = switchOn
                }
            }

            YText {
                font.pixelSize: 13
                color: YColors.grayText
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 18
                width: parent.width
                text: ocrBackend.installed
                      ? "中文更准，速度稍慢；切换后重启应用。"
                      : "未安装，需先安装 PP-OCRv5 组件。"
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "识别精度优先"
                enabled: ocrBackend.installed && ocrBackend.enabled
                switchOn: ocrBackend.accuracyFirst
                interval: 0
                onTimerTriggered: {
                    ocrBackend.accuracyFirst = switchOn
                }
            }

            YText {
                font.pixelSize: 13
                color: YColors.grayText
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 18
                width: parent.width
                text: "更准确，速度较慢；立即生效。"
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "屏幕触摸校准"
                switchOn: touchCalibration.enabled
                // 不设 interval: 0：保留组件默认的 600ms 防抖，避免连点两下
                // 先写后删、再排两次重启
                onTimerTriggered: {
                    touchCalibration.enabled = switchOn
                }
            }

            YText {
                font.pixelSize: 13
                color: YColors.grayText
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 18
                width: parent.width
                text: "改善屏幕边缘触控；切换后重启设备。"
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "VPU 硬件解码"
                enabled: vpuUnlock.supported
                switchOn: vpuUnlock.enabled
                // 不设 interval: 0：保留组件默认防抖，避免连点排两次重启
                onTimerTriggered: {
                    vpuUnlock.enabled = switchOn
                }
            }

            YText {
                font.pixelSize: 13
                color: YColors.grayText
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 18
                width: parent.width
                text: vpuUnlock.supported
                      ? "提升视频播放性能；修改启动分区并重启。"
                      : "当前设备不支持。"
            }

            YSpacingForColumn {
                implicitHeight: 16
            }
        }

    }

    // 软重启确认：只重启应用进程，不关机；C++ 侧会先落盘并延迟执行 sync + killall。
    YTwoButtonDialog {
        id: id_restart_app_dialog
        z: 1500
        anchors.fill: parent
        tipItem.font.pixelSize: 13
        tipItem.text: "只重启应用进程，设备不会关机\n约 3-5 秒后恢复\n配置与聊天记录会先保存\n正在进行的 AI 请求会被取消"
        onClickedConfirm: {
            close();
            if (mod.restartApplication()) {
                qmlGlobal.showToast("应用将重新启动，约几秒后恢复…", YColors.yellow);
            }
        }
        onClickedCancel: {
            close();
        }
    }
}
