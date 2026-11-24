import QtQuick 2.12
import com.youdao.pen 1.0

import "../commons"
import "../components"
import "../i18n"

YSettingItemPage {
    id: page
    objectName: "YPage===YSettingTranslate.qml"
    property var models: []
    property string modelLabel: "请选择"

    function refreshModels() {
        var available = []
        try {
            var all = JSON.parse(chatbot.getModelSummaries()).models || []
            for (var i = 0; i < all.length; ++i) {
                var model = all[i]
                if (model.capabilities && model.capabilities.text === false) continue
                if (model.apiProtocol !== "chat_completions" && model.apiProtocol !== "responses") continue
                available.push(model)
            }
        } catch (e) {}
        models = available
        modelLabel = aiTranslation.modelId.length ? "模型已删除或不支持文本" : "请选择"
        for (var j = 0; j < models.length; ++j) {
            if (models[j].id === aiTranslation.modelId) {
                modelLabel = models[j].name + (models[j].apiKeySet ? "" : "（未配置密钥）")
                break
            }
        }
    }
    Component.onCompleted: refreshModels()
    Connections {
        target: chatbot
        function onModelsChanged() { page.refreshModels() }
    }
    Connections {
        target: aiTranslation
        function onSettingsChanged() { page.refreshModels() }
    }

    Flickable {
        id: id_setting_item_view
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        clip: true
        contentHeight: column.height + 16

        Column {
            id: column
            width: parent.width
            spacing: 9

        YSettingItemTitle {
            id: id_title_container
            title: YTranslateText.priorityTranslationLanguageChoice
        }

        Grid {
            width: parent.width
            columns: 2
            spacing: 8

            YPressedButton {
                implicitWidth: 124
                clickable: settingManager.transLanguage !== YEnum.EN_US
                checkedIndicatorScale: settingManager.transLanguage === YEnum.EN_US
                text: YTranslateText.english
                visible: qmlGlobal.checkFeature(YEnum.FEATURE_LANG_ENG)
                onClicked: {
                    settingManager.transLanguage = YEnum.EN_US
                }
            }

            YPressedButton {
                implicitWidth: 124
                clickable: settingManager.transLanguage !== YEnum.ZH_CN
                checkedIndicatorScale: settingManager.transLanguage === YEnum.ZH_CN
                text: YTranslateText.chinese
                visible: false // mod: only support chinese version.
                onClicked: {
                    settingManager.transLanguage = YEnum.ZH_CN
                }
            }

            YPressedButton {
                implicitWidth: 124
                clickable: settingManager.transLanguage !== YEnum.JA_JP
                checkedIndicatorScale: settingManager.transLanguage === YEnum.JA_JP
                text: YTranslateText.japanese
                visible: qmlGlobal.checkFeature(YEnum.FEATURE_LANG_JPN)
                onClicked: {
                    settingManager.transLanguage = YEnum.JA_JP
                }
            }

            YPressedButton {
                implicitWidth: 124
                clickable: settingManager.transLanguage !== YEnum.KO_KR
                checkedIndicatorScale: settingManager.transLanguage === YEnum.KO_KR
                text: YTranslateText.korean
                visible: qmlGlobal.checkFeature(YEnum.FEATURE_LANG_KOR)
                onClicked: {
                    settingManager.transLanguage = YEnum.KO_KR
                }
            }

            YPressedButton {
                implicitWidth: 124
                clickable: settingManager.transLanguage !== YEnum.ES_ES
                checkedIndicatorScale: settingManager.transLanguage === YEnum.ES_ES
                text: YTranslateText.spanish
                visible: qmlGlobal.checkFeature(YEnum.FEATURE_LANG_ES)
                pixelSize: 26
                onClicked: {
                    settingManager.transLanguage = YEnum.ES_ES
                }
            }
        }
            YSettingItemTitle { title: "AI 翻译" }
            DescribedSwitchItem {
                title: "使用 AI 翻译"
                description: "仅无词典命中时替换译文，不影响 AI 助手会话"
                switchOn: aiTranslation.enabled
                interval: 0
                onTimerTriggered: aiTranslation.enabled = switchOn
            }
            DescribedClickableTextBox {
                title: "翻译模型"
                describe: page.modelLabel
                describeItem.width: width - 34
                onClicked: {
                    if (!page.models.length) return
                    var next = 0
                    for (var i = 0; i < page.models.length; ++i)
                        if (page.models[i].id === aiTranslation.modelId) next = (i + 1) % page.models.length
                    aiTranslation.modelId = page.models[next].id
                }
            }
            YSettingAboutClickableItem {
                title: "最长等待"
                value: Math.round(aiTranslation.timeoutMs / 1000) + " 秒"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    if (aiTranslation.timeoutMs < 15000) aiTranslation.timeoutMs = 15000
                    else if (aiTranslation.timeoutMs < 30000) aiTranslation.timeoutMs = 30000
                    else if (aiTranslation.timeoutMs < 60000) aiTranslation.timeoutMs = 60000
                    else aiTranslation.timeoutMs = 5000
                }
            }
            YText {
                width: parent.width
                text: "提示词自动使用原生翻译解析出的目标语言，不使用界面语言。逐字显示 AI 译文；离线、超时、错误或无效回复自动恢复原生译文。"
                font.pixelSize: 14
                color: YColors.grayText
                wrapMode: Text.Wrap
            }
            YText {
                width: parent.width
                text: "模型与 AI 助手共用配置，支持 Chat Completions、Responses 和 /messages（Anthropic）端点。密钥和模型参数请在 AI 助手的模型管理中设置。扫描文字会发送给所选模型服务。"
                font.pixelSize: 14
                color: YColors.grayText
                wrapMode: Text.Wrap
            }
            YSettingAboutClickableItem {
                title: "模型管理"
                imageName: "settings/info_more_arrow"
                onClicked: openSettingPage("ModelManagePage")
            }

        }
    }
}
