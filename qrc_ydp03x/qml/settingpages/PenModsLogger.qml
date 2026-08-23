import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../i18n"

// 日志与隐私：拦截原生日志上报
YSettingItemPage {
    id: id_logger
    objectName: "YPage===PenModsLogger.qml"

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 90
        anchors.rightMargin: 16
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "禁止日志上传"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            PenModsSwitchRow {
                title: "不上传用户行为日志"
                checked: loggerMonitor.noUploadUserAction
                onRowToggled: loggerMonitor.noUploadUserAction = checked
            }
            PenModsSwitchRow {
                title: "不上传扫描原图"
                checked: loggerMonitor.noUploadRawScanImg
                onRowToggled: loggerMonitor.noUploadRawScanImg = checked
            }
            PenModsSwitchRow {
                title: "不上传 HTTP 日志"
                checked: loggerMonitor.noUploadHttplog
                onRowToggled: loggerMonitor.noUploadHttplog = checked
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }
}
