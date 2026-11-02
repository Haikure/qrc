import QtQuick 2.12
import "../commons"
import "../components"
import "../i18n"

YSettingItemPage {
    id: page
    objectName: "YPage===UpdateSourceSettings.qml"
    property bool editingProxy: false

    function editAddress(proxy) {
        editingProxy = proxy
        var component = qmlCreateComponent("YInputPage")
        if (component.status !== Component.Ready) return
        var incubator = component.incubateObject(pop.containerItem)
        if (incubator.status === Component.Ready) pop.inputPageCreated(incubator.object)
        else incubator.onStatusChanged = function(status) {
            if (status === Component.Ready) pop.inputPageCreated(incubator.object)
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: content.height + 16
        clip: true
        Column {
            id: content
            width: parent.width
            spacing: 10
            YSettingItemTitle { title: "更新设置" }
            Rectangle {
                width: parent.width
                height: 58
                radius: 8
                color: YColors.grayNormal
                Column {
                    x: 10; y: 8
                    width: parent.width - 80
                    spacing: 3
                    YText { text: "自动检查更新"; font.pixelSize: 15 }
                    YText {
                        width: parent.width
                        text: "联网后检查主程序与扩展"
                        font.pixelSize: 11
                        color: YColors.grayText
                        wrapMode: Text.Wrap
                    }
                }
                YSwitch {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    switchOn: updateCenter.autoCheck
                }
                YMouseArea {
                    anchors.fill: parent
                    objectName: "UpdateSettings_autoCheck"
                    onClicked: updateCenter.autoCheck = !updateCenter.autoCheck
                }
            }
            Rectangle {
                width: parent.width
                height: 70
                radius: 8
                color: YColors.grayNormal
                Column {
                    x: 10; y: 8
                    width: parent.width - 80
                    spacing: 3
                    YText { text: "自动下载安装"; font.pixelSize: 15 }
                    YText {
                        width: parent.width
                        text: "仅更新已安装且允许自动更新的组件，下次启动生效"
                        font.pixelSize: 11
                        color: YColors.grayText
                        wrapMode: Text.Wrap
                    }
                }
                YSwitch {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    switchOn: updateCenter.autoDownload
                }
                YMouseArea {
                    anchors.fill: parent
                    objectName: "UpdateSettings_autoDownload"
                    onClicked: updateCenter.autoDownload = !updateCenter.autoDownload
                }
            }
            YText {
                width: parent.width
                text: "在更新中心点选组件，可设置该组件的自动更新。扩展默认不自动安装。"
                wrapMode: Text.Wrap
                font.pixelSize: 12
                color: YColors.grayText
            }
            YText {
                width: parent.width
                text: updateCenter.statusText
                wrapMode: Text.Wrap
                font.pixelSize: 12
                color: YColors.grayText
            }
            YPressedButton {
                width: parent.width
                height: 38
                pixelSize: 14
                text: "清除待生效更新"
                visible: updateCenter.pendingRestart
                enabled: !updateCenter.busy
                onClicked: updateCenter.cancelPending()
            }
            Rectangle {
                width: parent.width
                implicitHeight: Math.max(connectionDetails.height, 24) + 20
                radius: 8
                color: YColors.grayNormal
                visible: updater.sourceStatus.length > 0

                Image {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    source: res.get(updater.sourceConnected ? "color-success" : "color-notice")
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                    id: connectionDetails
                    x: 44
                    y: 10
                    width: parent.width - 54
                    spacing: 4
                    YText {
                        text: "连接状态"
                        font.pixelSize: 12
                        color: YColors.grayText
                    }
                    YText {
                        width: parent.width
                        text: updater.sourceStatus
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.pixelSize: 14
                    }
                }
            }
            YText {
                width: parent.width
                text: "默认自动轮换镜像，失败后回退原地址。自定义地址优先，留空使用默认。"
                wrapMode: Text.Wrap
                font.pixelSize: 14
                color: YColors.grayText
            }
            YText {
                width: parent.width
                text: updater.hasManifest ? "清单缓存：" + updater.cacheTimeText : "暂无清单缓存"
                wrapMode: Text.Wrap
                font.pixelSize: 12
                color: YColors.grayText
            }
            DescribedClickableTextBox {
                title: "更新清单地址"
                describe: updater.manifestUrl || "默认 updates.json"
                enabled: !updater.busy && !updateCenter.busy
                onClicked: page.editAddress(false)
            }
            DescribedClickableTextBox {
                title: "GitHub 加速前缀"
                describe: updater.githubProxy || "自动选择预置镜像"
                enabled: !updater.busy && !updateCenter.busy
                onClicked: page.editAddress(true)
            }
            YText {
                width: parent.width
                text: "清单填写完整 HTTPS 链接；前缀例如 https://gh-proxy.com/，会自动拼接 GitHub 原始链接。仅填写你信任的更新源。"
                wrapMode: Text.Wrap
                font.pixelSize: 14
                color: YColors.grayText
            }
            YText {
                width: parent.width
                text: "预置顺序：gh-proxy.com → ghproxy.net → gh-proxy.org → GitHub → 原 jsDelivr。下载优先使用本次检查成功的镜像。"
                wrapMode: Text.Wrap
                font.pixelSize: 14
                color: YColors.grayText
            }
            YPressedButton {
                width: parent.width
                text: "恢复默认更新源"
                enabled: !updater.busy && !updateCenter.busy
                onClicked: updater.saveSources("", "")
            }
        }
    }
    YPagePopHelper {
        id: pop
        isShowing: qmlGlobal.inputPageShowing
        function inputPageCreated(kb) {
            kb.backButtonClicked.connect(function() {
                qmlGlobal.inputPageShowing = false
                kb.todoDestroy()
            })
            kb.inputFinished.connect(function(value) {
                if (updateCenter.busy) {
                    qmlGlobal.showToast("更新期间无法修改更新源", YColors.yellow)
                    return
                }
                var ok = updater.saveSources(page.editingProxy ? updater.manifestUrl : value,
                                             page.editingProxy ? value : updater.githubProxy)
                if (!ok) qmlGlobal.showToast("请输入有效的 HTTPS 地址；更新期间无法修改", YColors.yellow)
            })
            kb.show()
            kb.enterText(page.editingProxy ? updater.githubProxy : updater.manifestUrl)
            qmlGlobal.inputPageShowing = true
        }
    }
}
