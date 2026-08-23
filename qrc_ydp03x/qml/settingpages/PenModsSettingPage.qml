import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../i18n"

// =====================================================================
// PenMods 设置入口页：息屏 / 休眠 / 电池 / 防尴尬 / 开发者(含 adb/ssh) /
// 网络代理 / 日志上传 / 安全锁
// =====================================================================
YSettingItemPage {
    id: id_penmods_setting
    objectName: "YPage===PenModsSettingPage.qml"

    Flickable {
        id: id_setting_view
        anchors.fill: parent
        anchors.leftMargin: 90
        anchors.rightMargin: 16
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "PenMods 设置"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            PenModsSettingRow {
                title: "息屏设置"
                value: screenManager.autoSleepDuration
                onClicked: { id_pop_container.show("PenModsAutoScreenOff") }
            }
            PenModsSettingRow {
                title: "自动休眠"
                value: batteryInfo.autoSuspendDuration
                onClicked: { id_pop_container.show("PenModsAutoSuspend") }
            }
            PenModsSettingRow {
                title: "电池信息"
                onClicked: { id_pop_container.show("PenModsBattery") }
            }
            PenModsSwitchRow {
                title: "扫描查询转小写"
                checked: keyBoard.scanToLower
                onRowToggled: { keyBoard.scanToLower = checked }
            }
            PenModsSwitchRow {
                title: "手电筒"
                checked: torch.switch
                onRowToggled: { torch.switch = checked }
            }
            PenModsSettingRow {
                title: "防尴尬"
                onClicked: { id_pop_container.show("PenModsAntiEmbs") }
            }
            PenModsSettingRow {
                title: "开发者选项"
                onClicked: { id_penmods_setting.showPage("PenModsDeveloper", true, "dev_setting") }
            }
            PenModsSettingRow {
                title: "网络与代理"
                onClicked: { id_pop_container.show("PenModsNetwork") }
            }
            PenModsSettingRow {
                title: "日志与隐私"
                onClicked: { id_pop_container.show("PenModsLogger") }
            }
            PenModsSettingRow {
                title: "安全锁"
                onClicked: { id_pop_container.show("PenModsLocker") }
            }
            PenModsSettingRow {
                title: "查询设置"
                onClicked: { id_pop_container.show("QuerySettingPage") }
            }
            PenModsSettingRow {
                title: "壁纸"
                onClicked: { id_pop_container.show("WallpaperSettingPage") }
            }
            PenModsSettingRow {
                title: "关于 PenMods"
                onClicked: { id_pop_container.show("PenModsAbout") }
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }

    // PenMods 锁屏门控：needPasswd && locker.enabled && 场景开启 时先要求输入密码。
    function showPage(page, needPasswd, scene) {
        if (needPasswd && (typeof locker !== 'undefined' && locker !== null) && locker.enabled
                && !(scene && !locker.getScene(scene))) {
            requestKeyboard(page)
            return null
        }
        id_pop_container.show(page)
    }

    function requestKeyboard(page) {
        let component = qmlCreateComponent("input/YInputPage")
        if (Component.Ready === component.status) {
            var incubator = component.incubateObject(id_page_pop_helper.containerItem)
            if (incubator.status !== Component.Ready) {
                incubator.onStatusChanged = function(status) {
                    if (status === Component.Ready) {
                        id_page_pop_helper.inputPageCreated(incubator.object, page)
                    }
                }
            } else {
                id_page_pop_helper.inputPageCreated(incubator.object, page)
            }
        }
    }

    YPagePopHelper {
        id: id_page_pop_helper
        isShowing: YInputProperty.inputPageShowing
        objectName: "from_PenModsSettingPage.qml"
        function inputPageCreated(keyboardPage, page) {
            keyboardPage.backButtonClicked.connect(function () {
                YInputProperty.inputPageShowing = false
                keyboardPage.todoDestroy()
                keyboardPage = null
            })
            keyboardPage.inputFinished.connect(function (content) {
                if (content === locker.password) {
                    id_penmods_setting.showPage(page)
                } else {
                    baseSignals.showToast("密码错误，请重试", YColors.yellow)
                    requestKeyboard(page)
                }
            })
            keyboardPage.placeHolderText = "请输入密码..."
            keyboardPage.show()
            YInputProperty.inputPageShowing = true
        }
    }

    // 子页弹出容器（参照 2 代 BatteryInfoPage 的做法）
    Item {
        id: id_pop_container
        anchors.fill: parent

        signal closeSameItem(string popStackId)

        function show(page) {
            closeSameItem(page)
            function newComponentInit(incubatorObject) {
                Object.defineProperty(incubatorObject, 'popStackId', {
                    enumerable: false, configurable: false,
                    writable: false, value: page
                })
                incubatorObject.backButtonClicked.connect(function() {
                    closeSameItem(incubatorObject.popStackId)
                    incubatorObject.destroy(1)
                })
                id_pop_container.closeSameItem.connect(function(popStackId) {
                    if (popStackId === incubatorObject.popStackId) {
                        incubatorObject.destroy(1)
                    }
                })
                incubatorObject.show()
            }

            const newComponent = Qt.createComponent(("./%1.qml").arg(page))
            const incubator = newComponent.incubateObject(id_pop_container)
            if (incubator.status !== Component.Ready) {
                incubator.onStatusChanged = function(status) {
                    if (status === Component.Ready) {
                        newComponentInit(incubator.object)
                    }
                }
            } else {
                newComponentInit(incubator.object)
            }
        }
    }
}
