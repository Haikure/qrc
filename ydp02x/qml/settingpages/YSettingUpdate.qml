import QtQuick 2.12

import "../commons"
import "../components"

YSettingItemPage {
    id: page
    objectName: "YPage===YSettingUpdate.qml"

    property string selectedId: ""
    property bool confirmingRestart: false
    readonly property var selectedComponent: componentById(selectedId)
    ignoreDefaultBackButtonClicked: selectedId.length > 0 || confirmingRestart

    function componentById(id) {
        var items = updateCenter.components
        for (var i = 0; i < items.length; ++i) {
            if (items[i].id === id) return items[i]
        }
        return null
    }

    // Keep the legacy entry point used by YSettingPage.
    function checkUpdate() {
        updater.ensureChecked()
        updateCenter.refresh()
    }

    function navigationActivated(resumed) {
        checkUpdate()
    }

    function installedText(component) {
        if (!component || !component.installed) return "未安装"
        if (!component.installedVersion || component.installedVersion === "0.0.0")
            return "已安装 · 版本未知"
        return "已装 " + component.installedVersion
    }

    function actionText(component) {
        if (!component) return "安装"
        if (component.pending && !component.canDownload) return "待重启"
        if (component.busy) return "处理中"
        if (!component.available) return "暂无包"
        if (!component.canDownload)
            return component.installed && component.availableVersion === component.installedVersion ? "已安装" : "不可用"
        if (updateCenter.busy) return "排队"
        return component.installed ? "更新" : "安装"
    }

    function purposeText(component) {
        if (!component) return ""
        switch (component.id) {
        case "core": return "PenMods 主程序与界面资源一起更新。"
        case "player": return "内嵌视频播放器扩展。安装后重启生效。"
        case "mathjax": return "AI 助手的本地公式渲染服务。"
        case "ppocr": return "可选 OCR 识别引擎。安装后仍需在实验性功能中启用。"
        }
        return ""
    }

    function usageText(component) {
        if (!component || component.id === "core") return ""
        if (!component.installed) return component.pending ? "重启后可使用此组件" : "安装并重启后可使用"
        switch (component.id) {
        case "player": return "视频文件会自动使用已安装的内嵌播放器。"
        case "mathjax":
            return (chatbot.mathRenderEnabled ? "公式渲染已开启" : "公式渲染未开启")
                    + (chatbot.bubbleRenderMode === "full" ? "" : "\n聊天公式需在公式渲染设置中切换为完全气泡模式")
                    + (chatbot.mathServerStatus ? "\n" + chatbot.mathServerStatus : "")
        case "ppocr": return ocrBackend.enabled ? "已启用 PP-OCRv5 引擎" : "已安装，尚未启用 PP-OCRv5 引擎"
        }
        return ""
    }

    onBackButtonClickedCallback: {
        if (confirmingRestart) confirmingRestart = false
        else selectedId = ""
    }

    YIconButton {
        x: 10; y: 50
        width: 30; height: 30; radius: 6
        source: "commons/more"
        onValidClicked: openSettingPage("UpdateSourceSettings")
    }

    YPressedButton {
        x: 6; y: 94
        width: 38; height: 32; radius: 6
        pixelSize: 11
        text: "取消\n下载"
        visible: updateCenter.busy && !confirmingRestart
        onClicked: updateCenter.cancelDownload()
    }

    Item {
        id: contentArea
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10

        Item {
            id: header
            width: parent.width
            height: 34
            YText {
                anchors.left: parent.left
                anchors.right: checkButton.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: page.selectedComponent ? page.selectedComponent.name : "更新中心"
                font.pixelSize: 16
                elide: Text.ElideRight
            }
            YPressedButton {
                id: checkButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 62; height: 28; radius: 7
                pixelSize: 13
                text: updater.checking ? "取消检查" : "检查更新"
                visible: !page.selectedComponent && !page.confirmingRestart
                enabled: !updateCenter.busy
                onClicked: {
                    if (updater.checking) updater.cancelCheck()
                    else updater.check()
                }
            }
        }

        Item {
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            visible: !page.selectedComponent && !page.confirmingRestart

            Rectangle {
                id: pendingBar
                width: parent.width
                height: visible ? 40 : 0
                visible: updateCenter.pendingRestart
                radius: 6
                color: YColors.grayNormal
                YText {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 86
                    text: "更新已就绪\n下次启动生效"
                    font.pixelSize: 12
                    color: YColors.blueText
                }
                YPressedButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 70; height: 30; radius: 6
                    text: "重启生效"
                    pixelSize: 13
                    enabled: !updateCenter.busy && updateCenter.launcherReady
                    onClicked: page.confirmingRestart = true
                }
            }

            YText {
                id: summary
                anchors.top: pendingBar.bottom
                width: parent.width
                height: 22
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: 11
                color: YColors.grayText
                elide: Text.ElideRight
                text: updater.checking ? updater.sourceStatus : updateCenter.statusText
            }

            ListView {
                id: componentList
                anchors.top: summary.bottom
                anchors.bottom: parent.bottom
                width: parent.width
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                // Components have a fixed order. Progress refreshes row bindings, not the ListView model.
                model: updateCenter.components.length
                delegate: Rectangle {
                    id: componentRow
                    width: componentList.width
                    height: 59
                    radius: 7
                    color: YColors.grayNormal
                    readonly property var component: updateCenter.components[index]

                    Column {
                        x: 8; y: 5
                        width: parent.width - 85
                        spacing: 1
                        YText {
                            width: parent.width
                            text: componentRow.component.name
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }
                        YText {
                            width: parent.width
                            text: page.installedText(componentRow.component)
                                  + (componentRow.component.availableVersion ? " → " + componentRow.component.availableVersion : "")
                            font.pixelSize: 11
                            color: YColors.grayText
                            elide: Text.ElideRight
                        }
                        YText {
                            width: parent.width
                            text: componentRow.component.stateText
                            font.pixelSize: 11
                            color: componentRow.component.pending ? YColors.blueText : YColors.grayText
                            elide: Text.ElideRight
                        }
                    }
                    YMouseArea {
                        width: parent.width - 78
                        height: parent.height
                        objectName: "UpdateCenter_component_" + componentRow.component.id
                        onClicked: {
                            page.selectedId = componentRow.component.id
                            detailScroll.contentY = 0
                        }
                    }
                    YPressedButton {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 68; height: 34; radius: 7
                        pixelSize: 13
                        text: page.actionText(componentRow.component)
                        enabled: componentRow.component.canDownload && !componentRow.component.busy
                        onClicked: updateCenter.downloadComponent(componentRow.component.id)
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        height: 2
                        radius: 1
                        visible: componentRow.component.busy
                        width: parent.width * Math.max(0, Math.min(100, componentRow.component.progress)) / 100
                        color: YColors.blueRect
                    }
                }
            }
        }

        Item {
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            visible: page.selectedComponent !== null && !page.confirmingRestart

            Flickable {
                id: detailScroll
                width: parent.width
                anchors.top: parent.top
                anchors.bottom: detailAction.top
                anchors.bottomMargin: 5
                contentHeight: details.height + 6
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: details
                    width: parent.width
                    spacing: 6
                    YText {
                        width: parent.width
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                        text: page.installedText(page.selectedComponent)
                              + (page.selectedComponent && page.selectedComponent.availableVersion ? "\n可用 " + page.selectedComponent.availableVersion + "  " + page.selectedComponent.sizeText : "")
                    }
                    YText {
                        width: parent.width
                        font.pixelSize: 13
                        color: YColors.blueText
                        wrapMode: Text.Wrap
                        text: page.selectedComponent ? page.selectedComponent.stateText : ""
                    }
                    YText {
                        width: parent.width
                        visible: text.length > 0
                        font.pixelSize: 12
                        color: YColors.yellow
                        wrapMode: Text.WrapAnywhere
                        text: page.selectedComponent && page.selectedComponent.error ? page.selectedComponent.error : ""
                    }
                    YText {
                        width: parent.width
                        font.pixelSize: 12
                        color: YColors.grayText
                        wrapMode: Text.Wrap
                        text: page.purposeText(page.selectedComponent)
                    }
                    YText {
                        width: parent.width
                        visible: text.length > 0
                        font.pixelSize: 13
                        color: YColors.blueText
                        wrapMode: Text.Wrap
                        text: page.usageText(page.selectedComponent)
                    }
                    YPressedButton {
                        width: parent.width
                        height: visible ? 32 : 0
                        radius: 6
                        pixelSize: 13
                        objectName: "UpdateCenter_useComponent"
                        visible: page.selectedComponent !== null && page.selectedComponent.installed
                                 && (page.selectedId === "mathjax" || page.selectedId === "ppocr")
                        enabled: !updateCenter.busy
                        text: page.selectedId === "mathjax" ? "公式渲染设置" : "OCR 启用设置"
                        onClicked: {
                            if (page.selectedId === "mathjax") {
                                openSettingPage("ChatAssistantSettings", {showMathSettings: true})
                            } else if (page.selectedId === "ppocr") {
                                openSettingPage("SystemTweakSettingPage", {showOcrSettings: true})
                            }
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 42
                        radius: 6
                        color: YColors.grayNormal
                        YText {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "自动更新此组件"
                            font.pixelSize: 13
                        }
                        YSwitch {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            switchOn: page.selectedComponent ? page.selectedComponent.autoUpdate : false
                        }
                        YMouseArea {
                            anchors.fill: parent
                            objectName: "UpdateCenter_componentAuto"
                            onClicked: {
                                if (page.selectedComponent)
                                    updateCenter.setComponentAutoUpdate(page.selectedId, !page.selectedComponent.autoUpdate)
                            }
                        }
                    }
                    YText {
                        width: parent.width
                        font.pixelSize: 11
                        color: YColors.grayText
                        wrapMode: Text.Wrap
                        text: "自动更新仅用于已安装组件，并需在更新设置中开启自动下载安装。"
                    }
                    YText {
                        width: parent.width
                        font.pixelSize: 12
                        color: YColors.grayText
                        wrapMode: Text.Wrap
                        text: page.selectedComponent && page.selectedComponent.note ? page.selectedComponent.note : "暂未发布更新说明"
                    }
                }
            }
            YPressedButton {
                id: detailAction
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                width: parent.width
                height: 32; radius: 7
                pixelSize: 14
                text: page.actionText(page.selectedComponent)
                enabled: page.selectedComponent !== null && page.selectedComponent.canDownload
                         && !page.selectedComponent.busy
                onClicked: updateCenter.downloadComponent(page.selectedId)
            }
        }

        Column {
            anchors.top: header.bottom
            width: parent.width
            spacing: 10
            visible: page.confirmingRestart
            YText {
                width: parent.width
                text: "现在重启并应用已就绪的更新？\n重启期间会短暂退出应用。"
                font.pixelSize: 14
                wrapMode: Text.Wrap
            }
            Row {
                spacing: 8
                YPressedButton {
                    width: (contentArea.width - 8) / 2; height: 34
                    radius: 7; pixelSize: 14
                    text: "稍后"
                    onClicked: page.confirmingRestart = false
                }
                YPressedButton {
                    width: (contentArea.width - 8) / 2; height: 34
                    radius: 7; pixelSize: 14
                    text: "现在重启"
                    enabled: updateCenter.pendingRestart && !updateCenter.busy && updateCenter.launcherReady
                    onClicked: updateCenter.restartNow()
                }
            }
        }
    }
}
