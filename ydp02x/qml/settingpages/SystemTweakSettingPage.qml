import QtQuick 2.12
import com.youdao.pen 1.0

import "../commons"
import "../components"
import "../i18n"

YSettingItemPage {
    id: id_setting_item
    objectName: "YPage===SystemTweakSettingPage.qml"

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
                title: ocrBackend.installed ? "使用 PP-OCRv5 识别引擎" : "PP-OCRv5 识别引擎（未安装）"
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
                      ? "扫描识别改用飞桨 PP-OCRv5 模型，中文更准、速度稍慢。切换后会自动重启一次以生效。"
                      : "需要先在设备上运行 penmods-ppocr.sh 安装识别组件。"
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: "识别精度优先（较慢）"
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
                text: "开：输入高度 48，密集中文更准；关：输入高度 32，约快一倍。立即生效，无需重启。"
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
                text: "补偿屏幕边缘一像素的死区。可解决从屏幕右边缘向内滑动时系统不响应的问题。切换后会自动重启一次以生效。"
            }

            YSettingSwitchItem {
                implicitHeight: 54
                title: vpuUnlock.supported ? "VPU 硬件解码" : "VPU 硬件解码（不可用）"
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
                      ? "给设备树的 VPU 节点打补丁，播放器就能用硬件解码（更省电、高分辨率更流畅）。会给 boot 分区打补丁并自动重启一次，出厂镜像会自动备份到 /userdisk/PenMods/。"
                      : "本机不支持：需要可写的 boot 分区，且设备树里存在 vpu_combo 节点。"
            }

            YSpacingForColumn {
                implicitHeight: 16
            }
        }

    }
}
