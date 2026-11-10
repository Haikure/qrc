import QtQuick 2.12
import com.github.penuniverse 1.0

import "../commons"
import "../components"
import "../i18n"
import "../settingpages"

YBackButtonPage {
    id: id_setting_item
    objectName: "YPage===ChatAssistantSettingsPage.qml"

    function openKeyboard(placeholder, prefill, onDone) {
        id_settings_pop.pendingCallback = onDone;
        id_settings_pop.pendingPrefill  = prefill || "";
        id_settings_pop.pendingPlaceholder = placeholder || "";
        var component = qmlCreateComponent("YInputPage");
        if (Component.Ready === component.status) {
            var incubator = component.incubateObject(id_settings_pop.containerItem);
            if (incubator.status !== Component.Ready) {
                incubator.onStatusChanged = function(s) {
                    if (s === Component.Ready) id_settings_pop.inputPageCreated(incubator.object);
                };
            } else {
                id_settings_pop.inputPageCreated(incubator.object);
            }
        }
    }

    property var titleModels: []
    property string titleModelLabel: "请选择"
    function refreshTitleModels() {
        try { titleModels = JSON.parse(chatbot.getModelSummaries()).models || []; }
        catch (e) { titleModels = []; }
        titleModelLabel = titleModelName();
    }
    function titleModelName() {
        for (var i = 0; i < titleModels.length; ++i)
            if (titleModels[i].id === chatbot.autoTitleModelId) return titleModels[i].name;
        return "请选择";
    }
    Connections {
        target: chatbot
        onModelsChanged: id_setting_item.refreshTitleModels()
        onAutoTitleSettingsChanged: id_setting_item.refreshTitleModels()
    }

    property bool showMathSettings: false
    Component.onCompleted: {
        refreshTitleModels();
        if (showMathSettings) Qt.callLater(function() {
            id_flickable.contentY = Math.max(0, Math.min(mathRenderTitle.y + id_column.y,
                id_flickable.contentHeight - id_flickable.height));
        })
    }

    // ---- Shell 模式（新库提供 shellMode；旧库回退到 shellToolEnabled，绝不误开 automatic） ----
    function automaticModeSupported() {
        return typeof chatbot.shellMode === "string";
    }
    function shellModes() {
        try {
            var cfg = JSON.parse(chatbot.getShellToolConfig());
            if (cfg.policy_version >= 2)
                return ["off", "confirm", "automatic", "restricted", "full"];
        } catch (e) {}
        return automaticModeSupported() ? ["off", "confirm", "automatic"] : ["off", "confirm"];
    }
    function currentShellMode() {
        if (typeof chatbot.shellMode === "string")
            return chatbot.shellMode;
        return chatbot.shellToolEnabled ? "confirm" : "off";
    }
    function shellModeLabel(mode) {
        if (mode === "off") return "关闭";
        if (mode === "automatic") return "只读网页";
        if (mode === "restricted") return "受限用户";
        if (mode === "full") return "完全权限";
        return "手动确认";
    }
    function applyShellMode(mode) {
        if (typeof chatbot.shellMode === "string") {
            chatbot.shellMode = mode;
        } else {
            // 旧版主库没有 automatic，只做 off/confirm 映射
            chatbot.shellToolEnabled = (mode !== "off");
        }
    }

    Flickable {
        id: id_flickable
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "对话相关"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 9

            YSettingAboutClickableItem {
                title: "气泡渲染"
                value: chatbot.bubbleRenderMode === "basic" ? "基础"
                       : chatbot.bubbleRenderMode === "plain" ? "纯文本" : "完全"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    if (chatbot.bubbleRenderMode === "full")
                        chatbot.bubbleRenderMode = "basic";
                    else if (chatbot.bubbleRenderMode === "basic")
                        chatbot.bubbleRenderMode = "plain";
                    else
                        chatbot.bubbleRenderMode = "full";
                }
            }

            DescribedSwitchItem {
                title: "流式输出"
                description: "随 LLM 模型处理进度动态更新消息内容"
                switchOn: chatbot.isStreaming
                interval: 0
                onTimerTriggered: {
                    chatbot.isStreaming = !chatbot.isStreaming;
                }
            }

            DescribedSwitchItem {
                title: "扫描结果快速发送"
                description: "扫描文字后当作消息直接发送"
                switchOn: keyBoard.autoSendScanConfig
                interval: 0
                onTimerTriggered: {
                    keyBoard.autoSendScanConfig = !keyBoard.autoSendScanConfig;
                }
            }

            DescribedSwitchItem {
                title: "语音输入"
                description: "语音助手识别完成后发送给 AI 助手"
                switchOn: mod.voiceChatEnabled
                interval: 0
                onTimerTriggered: {
                    mod.voiceChatEnabled = !mod.voiceChatEnabled;
                }
            }

            DescribedSwitchItem {
                title: "AI 自动标题"
                description: "使用独立模型生成；手动改名后不再覆盖"
                switchOn: chatbot.autoTitleEnabled
                interval: 0
                onTimerTriggered: chatbot.autoTitleEnabled = !chatbot.autoTitleEnabled
            }

            DescribedClickableTextBox {
                title: "标题模型"
                describe: id_setting_item.titleModelLabel
                describeItem.width: width - 34
                onClicked: {
                    var models = id_setting_item.titleModels;
                    if (!models.length) return;
                    var next = 0;
                    for (var i = 0; i < models.length; ++i)
                        if (models[i].id === chatbot.autoTitleModelId) next = (i + 1) % models.length;
                    chatbot.autoTitleModelId = models[next].id;
                    id_setting_item.refreshTitleModels();
                }
            }

            YSettingAboutClickableItem {
                title: "标题频率"
                value: chatbot.autoTitleFrequency === 3 ? "每 3 轮" : "仅首轮"
                imageName: "settings/info_more_arrow"
                onClicked: chatbot.autoTitleFrequency = chatbot.autoTitleFrequency === 3 ? 0 : 3
            }

            YSettingAboutClickableItem {
                title: "导出当前会话"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    chatbot.saveMessages();
                }
            }

        YSettingItemTitle {
            title: "服务配置"
        }

            YSettingAboutClickableItem {
                title: "模型管理"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    var component = Qt.createComponent("ModelManagePage.qml");
                    var initPage = function (page) {
                        page.backButtonClicked.connect(function () {
                            page.todoDestroy();
                        });
                        page.show();
                    };
                    if (component.status === Component.Ready) {
                        var obj = component.incubateObject(id_setting_item);
                        if (obj.status !== Component.Ready) {
                            obj.onStatusChanged = function (s) {
                                if (s === Component.Ready)
                                    initPage(obj.object);
                            };
                        } else {
                            initPage(obj.object);
                        }
                    } else {
                        console.error("ModelManagePage load error:", component.errorString());
                    }
                }
            }

            YSettingAboutClickableItem {
                title: "提示词管理"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    var component = Qt.createComponent("PromptManagePage.qml");
                    var initPage = function (page) {
                        page.backButtonClicked.connect(function () {
                            page.todoDestroy();
                        });
                        page.show();
                    };
                    if (component.status === Component.Ready) {
                        var obj = component.incubateObject(id_setting_item);
                        if (obj.status !== Component.Ready) {
                            obj.onStatusChanged = function (s) {
                                if (s === Component.Ready)
                                    initPage(obj.object);
                            };
                        } else {
                            initPage(obj.object);
                        }
                    } else {
                        console.error("PromptManagePage load error:", component.errorString());
                    }
                }
            }

            YSettingAboutClickableItem {
                title: "API 缓存统计"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    var component = Qt.createComponent("ApiCacheStatsPage.qml");
                    if (component.status !== Component.Ready) {
                        console.error("ApiCacheStatsPage load error:", component.errorString());
                        return;
                    }
                    var page = component.createObject(id_setting_item);
                    page.backButtonClicked.connect(function () { page.todoDestroy(); });
                    page.show();
                }
            }

            YSettingItemTitle {
                title: "网络搜索"
            }

            YSettingAboutClickableItem {
                title: "搜索服务"
                value: chatbot.searchProvider === "tavily" ? "Tavily"
                       : chatbot.searchProvider === "deepseek" ? "DeepSeek" : "关闭"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    if (chatbot.searchProvider === "off")
                        chatbot.searchProvider = "tavily";
                    else if (chatbot.searchProvider === "tavily")
                        chatbot.searchProvider = "deepseek";
                    else
                        chatbot.searchProvider = "off";
                }
            }

            DescribedSwitchItem {
                title: "启用网络搜索"
                description: !chatbot.searchConfigured ? "请先配置搜索服务的 API Key"
                             : chatbot.searchProvider === "deepseek" ? "DeepSeek 网页搜索"
                             : "Tavily 网页搜索"
                switchOn: chatbot.searchEnabled && chatbot.searchConfigured
                interval: 0
                enabled: chatbot.searchConfigured
                onTimerTriggered: {
                    chatbot.searchEnabled = !chatbot.searchEnabled;
                }
            }

            YSettingAboutClickableItem {
                title: "密钥"
                value: chatbot.searchConfigured ? "已配置" : "未配置"
                visible: chatbot.searchProvider !== "off"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    var cfg = {};
                    try {
                        cfg = JSON.parse(chatbot.getSearchConfig());
                    } catch (error) {
                        console.warn("读取网络搜索配置失败:", error);
                    }
                    var isDeepseek = chatbot.searchProvider === "deepseek";
                    var placeholder = isDeepseek ? "输入 DeepSeek API Key（留空则用模型 Key）..."
                                                 : "输入 Tavily API Key...";
                    var current = isDeepseek ? (cfg.deepseekApiKey || "") : (cfg.tavilyApiKey || "");
                    openKeyboard(placeholder, current, function(key) {
                        var next = {};
                        try {
                            next = JSON.parse(chatbot.getSearchConfig());
                        } catch (error) {
                            console.warn("读取网络搜索配置失败:", error);
                        }
                        if (isDeepseek)
                            next.deepseekApiKey = key ? key.trim() : "";
                        else
                            next.tavilyApiKey = key ? key.trim() : "";
                        chatbot.setSearchConfig(JSON.stringify(next));
                    });
                }
            }

            YSettingAboutClickableItem {
                title: "返回条数"
                value: chatbot.searchCount + " 条"
                visible: chatbot.searchProvider !== "off"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    var opts = [3, 5, 8, 10];
                    var idx = opts.indexOf(chatbot.searchCount);
                    chatbot.searchCount = opts[(idx + 1) % opts.length];
                }
            }

            YSettingItemTitle {
                title: "AI 服务"
            }

            YSettingAboutClickableItem {
                title: "重置 AI 服务"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    aiResetDialog.failText = "";
                    aiResetDialog.show();
                }
            }

            YSettingItemTitle {
                title: "Shell 工具"
            }

            YSettingAboutClickableItem {
                id: shellModeItem
                title: "执行模式"
                value: shellModeLabel(currentShellMode())
                imageName: "settings/info_more_arrow"
                onClicked: {
                    var order = shellModes();
                    var idx = order.indexOf(currentShellMode());
                    var next = order[(idx + 1) % order.length];
                    if (next !== "off" && next !== "confirm") {
                        shellRiskDialog.mode = next;
                        shellRiskDialog.show();
                    } else {
                        applyShellMode(next);
                    }
                }
            }

            YSettingAboutClickableItem {
                visible: currentShellMode() !== "off" && currentShellMode() !== "confirm"
                title: "切回手动确认"
                imageName: "settings/info_more_arrow"
                onClicked: applyShellMode("confirm")
            }

            YSettingAboutClickableItem {
                id: shellTimeoutItem
                title: "超时时间"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    var cfg = JSON.parse(chatbot.getShellToolConfig());
                    openKeyboard("超时时间（秒）", String(cfg.timeout_ms / 1000), function(val) {
                        var secs = parseInt(val);
                        if (secs >= 1 && secs <= 120) {
                            cfg.timeout_ms = secs * 1000;
                            chatbot.setShellToolConfig(JSON.stringify(cfg));
                        }
                    });
                }
            }

            YSettingAboutClickableItem {
                id: shellOutputItem
                title: "最大输出"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    var cfg = JSON.parse(chatbot.getShellToolConfig());
                    openKeyboard("最大输出（KB）", String(cfg.max_output_bytes / 1024), function(val) {
                        var kb = parseInt(val);
                        if (kb >= 1 && kb <= 64) {
                            cfg.max_output_bytes = kb * 1024;
                            chatbot.setShellToolConfig(JSON.stringify(cfg));
                        }
                    });
                }
            }

            Connections {
                target: chatbot
                function onShellToolConfigChanged() {
                    var cfg = JSON.parse(chatbot.getShellToolConfig());
                    shellTimeoutItem.value = (cfg.timeout_ms / 1000) + "s";
                    shellOutputItem.value = (cfg.max_output_bytes / 1024) + " KB";
                }
            }

            Component.onCompleted: {
                var cfg = JSON.parse(chatbot.getShellToolConfig());
                shellTimeoutItem.value = (cfg.timeout_ms / 1000) + "s";
                shellOutputItem.value = (cfg.max_output_bytes / 1024) + " KB";
            }

        YSettingItemTitle {
            id: mathRenderTitle
            title: "数学公式渲染"
        }

            DescribedSwitchItem {
                title: "启用公式渲染"
                description: "使用本地 MathJax 服务将 LaTeX 公式渲染为图片"
                switchOn: chatbot.mathRenderEnabled
                interval: 0
                onTimerTriggered: {
                    chatbot.mathRenderEnabled = !chatbot.mathRenderEnabled;
                }
            }

            YText {
                width: parent.width
                font.pixelSize: 12
                color: YColors.grayText
                wrapMode: Text.WrapAnywhere
                text: "服务：" + (chatbot.mathServerPath || "未安装")
                      + (chatbot.mathServerStatus ? "\n" + chatbot.mathServerStatus : "")
                      + "\n公式图片需使用完全气泡模式；文本阅读器也使用此服务。"
            }

        YSettingItemTitle {
            title: "配置文件"
        }

            YSettingAboutClickableItem {
                title: "重载配置"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    chatbot.reloadConfig();
                }
            }

            YSettingAboutClickableItem {
                title: "清洗配置"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    chatbot.sanitizeConfig();
                }
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }

    // 统一使用有道原生双按钮询问组件。
    YTwoButtonDialog {
        id: shellRiskDialog
        anchors.fill: parent
        z: 1500
        property string mode: "automatic"
        tipItem.font.family: qmlGlobal.fontFamilyZhCn
        tipItem.font.pixelSize: 12
        tipItem.text: "启用" + shellModeLabel(mode) + "？\n"
                      + (mode === "full"
                         ? "以 root 执行，不逐条询问。可修改系统和用户文件，仅用于可信任务。\n保留黑名单、超时和输出限制。"
                         : mode === "restricted"
                           ? "以非特权用户执行，不逐条询问，禁止提权。\n仍可联网、读写公共文件，不是沙盒。"
                           : "仅放行只读网页抓取，其他命令拒绝。\n保留黑名单、超时和输出限制。")
        // 原生组件的别名沿用宿主命名：buttonItemCancel 实际是右侧确认按钮。
        buttonItemCancel.text: "启用此模式"
        onClickedConfirm: {
            close();
            applyShellMode(mode);
        }
        onClickedCancel: close()
    }

    YTwoButtonDialog {
        id: aiResetDialog
        anchors.fill: parent
        z: 1500
        property bool busy: false
        property string failText: ""
        tipItem.font.family: qmlGlobal.fontFamilyZhCn
        tipItem.font.pixelSize: 13
        tipItem.text: failText !== "" ? failText
                      : "重置 AI 服务？\n取消在途请求与 Shell 命令，\n保留会话历史。"
        buttonItemCancel.text: busy ? "重置中..." : "确认重置"
        onClickedConfirm: {
            if (busy) return;
            busy = true;
            var supported = typeof chatbot.resetService === "function";
            var ok = supported ? chatbot.resetService() : false;
            busy = false;
            if (ok) {
                close();
            } else {
                failText = supported ? "重置失败，请稍后重试（详见 applog）"
                                     : "当前主库不支持重置，请更新主库后重试";
                qmlGlobal.showToast(failText, YColors.yellow);
            }
        }
        onClickedCancel: close()
    }

    YPagePopHelper {
        id: id_settings_pop
        z: 1000
        anchors.fill: parent
        isShowing: qmlGlobal.inputPageShowing
        objectName: "from_ChatAssistantSettings.qml"

        property var    pendingCallback:    null
        property string pendingPrefill:     ""
        property string pendingPlaceholder: ""

        function inputPageCreated(kbPage) {
            var cb          = pendingCallback;
            var placeholder = pendingPlaceholder;
            var prefill     = pendingPrefill;

            kbPage.placeHolderText = placeholder;
            kbPage.backButtonClicked.connect(function() {
                qmlGlobal.inputPageShowing = false;
                kbPage.todoDestroy();
            });
            kbPage.inputFinished.connect(function(input) {
                qmlGlobal.inputPageShowing = false;
                kbPage.todoDestroy();
                if (cb && input !== null) cb(input);
            });
            kbPage.enterText(prefill);
            kbPage.show();
            qmlGlobal.inputPageShowing = true;
        }
    }
}
