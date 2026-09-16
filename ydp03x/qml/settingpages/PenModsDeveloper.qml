import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../i18n"

// 开发者选项：离线资源管理 + ADB / SSH 服务
// （原独立的「服务（ADB / SSH）」页已并入此处）
YSettingItemPage {
    id: id_developer
    objectName: "YPage===PenModsDeveloper.qml"

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 90
        anchors.rightMargin: 16
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "开发者选项"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            PenModsSwitchRow {
                title: "关闭离线资源管理"
                checked: developerSettings.offlineRM
                onRowToggled: developerSettings.offlineRM = checked
            }

            // ---- ADB / SSH 服务（QEMU 中 adb_onoff 会失败，真机可用）----

            PenModsSettingRow {
                title: "ADB 服务"
                value: serviceManager.adbStatus ? "运行中" : "已停止"
                onClicked: {
                    if (serviceManager.adbStatus) {
                        serviceManager.stopAdb()
                    } else {
                        serviceManager.startAdb()
                    }
                }
            }
            PenModsSwitchRow {
                title: "ADB 开机自启"
                checked: serviceManager.adbAutoRun
                onRowToggled: serviceManager.adbAutoRun = checked
            }
            PenModsSwitchRow {
                title: "跳过 ADB 验证"
                checked: serviceManager.skipAdbVerification
                onRowToggled: serviceManager.skipAdbVerification = checked
            }
            PenModsSettingRow {
                title: "SSH 服务"
                value: serviceManager.sshStatus ? "运行中" : "已停止"
                onClicked: {
                    if (serviceManager.sshStatus) {
                        serviceManager.stopSsh()
                    } else {
                        serviceManager.startSsh()
                    }
                }
            }
            PenModsSwitchRow {
                title: "SSH 开机自启"
                checked: serviceManager.sshAutoRun
                onRowToggled: serviceManager.sshAutoRun = checked
            }
            PenModsSettingRow {
                title: "修改 root 密码"
                onClicked: { id_developer.requestKeyboard() }
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }

    function requestKeyboard() {
        let component = qmlCreateComponent("input/YInputPage")
        if (Component.Ready === component.status) {
            var incubator = component.incubateObject(id_page_pop_helper.containerItem)
            if (incubator.status !== Component.Ready) {
                incubator.onStatusChanged = function (status) {
                    if (status === Component.Ready) {
                        id_page_pop_helper.inputPageCreated(incubator.object)
                    }
                }
            } else {
                id_page_pop_helper.inputPageCreated(incubator.object)
            }
        }
    }

    YPagePopHelper {
        id: id_page_pop_helper
        isShowing: YInputProperty.inputPageShowing
        objectName: "from_PenModsDeveloper.qml"

        function inputPageCreated(keyboardPage) {
            keyboardPage.backButtonClicked.connect(function () {
                YInputProperty.inputPageShowing = false
                keyboardPage.todoDestroy()
                keyboardPage = null
            })
            keyboardPage.inputFinished.connect(function (content) {
                if (serviceManager.setSshRootPasswd(content)) {
                    baseSignals.showToast("SSH root 密码已更新", YColors.green)
                } else {
                    baseSignals.showToast("设置 SSH 密码失败", YColors.yellow)
                }
            })
            keyboardPage.placeHolderText = "请设置 root 密码..."
            keyboardPage.show()
            YInputProperty.inputPageShowing = true
        }
    }
}
