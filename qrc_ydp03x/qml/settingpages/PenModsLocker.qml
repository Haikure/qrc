import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../i18n"

// 安全锁：启用后按场景锁定；具体场景项集中在 LockSceneSettingPage（使用与消费端一致的场景键）。
YSettingItemPage {
    id: id_locker
    objectName: "YPage===PenModsLocker.qml"

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 90
        anchors.rightMargin: 16
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "安全锁（默认密码 abcd）"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            PenModsSwitchRow {
                title: "启用安全锁"
                checked: locker.enabled
                onRowToggled: {
                    locker.enabled = checked
                }
            }
            PenModsSettingRow {
                title: "设置密码"
                value: locker.password.length > 0 ? "已设置" : "未设置"
                onClicked: { id_locker.requestKeyboard() }
            }
            PenModsSettingRow {
                title: "需要密码的场景"
                onClicked: { id_pop_container.show("LockSceneSettingPage") }
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
        objectName: "from_PenModsLocker.qml"

        function inputPageCreated(keyboardPage) {
            keyboardPage.backButtonClicked.connect(function () {
                YInputProperty.inputPageShowing = false
                keyboardPage.todoDestroy()
                keyboardPage = null
            })
            keyboardPage.inputFinished.connect(function (content) {
                if (content.length > 0) {
                    locker.password = content
                    baseSignals.showToast("安全锁密码已更新", YColors.green)
                } else {
                    baseSignals.showToast("密码不能为空", YColors.yellow)
                }
            })
            keyboardPage.placeHolderText = "请输入密码..."
            keyboardPage.show()
            YInputProperty.inputPageShowing = true
        }
    }

    // 子页弹出容器
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
                    if (status === Component.Ready) newComponentInit(incubator.object)
                }
            } else {
                newComponentInit(incubator.object)
            }
        }
    }
}
