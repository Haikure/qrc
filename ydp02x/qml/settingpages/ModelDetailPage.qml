import QtQuick 2.12
import com.github.penuniverse 1.0

import "../commons"
import "../components"
import "../i18n"
import "../settingpages"

// 模型编辑页。
//
// 打开方式（ModelManagePage）：异步创建 Component + incubateObject，并把 modelId 作为
// initial property 传进来。因此本页不再有“先按默认空数据初始化一次、再赋值重复初始化”的问题：
// Component.onCompleted 时 modelId 已经就位，initFormData() 只跑一次（也可重复调用，幂等）。
//
// 表单状态用 QtObject 的显式属性保存：改一个字段只通知对应绑定，不再用 `fd = fd` 全量重绑。
YBackButtonPage {
    id: id_detail_page
    objectName: "YPage===ModelDetailPage.qml"

    // '' = 新建模型；非空 = 编辑已配置模型
    property string modelId: ""
    property bool missingModel: false
    readonly property bool isNew: modelId.length === 0
    property bool isActive: false
    property bool formReady: false
    // modelId 作为 incubateObject 的 initial property 进来，正常情况下 onCompleted 时已就位；
    // 这里兜住“完成后再赋值”的情况，保证 initFormData() 只在需要时重跑（幂等）。
    property bool initialized: false

    signal modelSaved()
    signal modelDeleted()

    QtObject {
        id: fd

        property string name: ""
        property string provider: ""
        property string endpoint: ""
        property string modelId: ""
        property string apiProtocol: "chat_completions"
        // 只保存用户本次新输入的密钥。已存密钥不下发到 QML（C++ 侧未收到 apiKey 时保持原值）
        property string apiKey: ""
        property bool apiKeySet: false
        property string temperature: "0.7"
        property int maxContextSize: 0
        property bool capText: true
        property bool capVision: false
        property bool capAudio: false
        property bool capToolCall: false
        property bool capReasoning: false
        property bool capImageGeneration: false
        property string reasoningEffort: ""
        property bool nativeWebSearchEnabled: false
        property string nativeWebSearchProvider: "auto"
        // extraParams 以 JSON 文本形式编辑；保存时统一 parse 成 object 再交给 C++（不会嵌套成字符串）
        property string extraParams: ""
        property string proxyVisionModelId: ""
        property string proxyVisionPrompt: ""
    }

    property var visionModelList: []
    property var modelNames: ({})
    property bool proxySelectorOpen: false

    // ------------------------------------------------------------------
    // 表单读写
    // ------------------------------------------------------------------

    function hasApiKey() {
        return fd.apiKeySet || fd.apiKey.length > 0;
    }

    function formValue(key) {
        switch (key) {
        case "name": return fd.name;
        case "provider": return fd.provider;
        case "endpoint": return fd.endpoint;
        case "modelId": return fd.modelId;
        case "apiKey": return fd.apiKey;
        case "temperature": return fd.temperature;
        case "maxContextSize": return fd.maxContextSize;
        case "reasoningEffort": return fd.reasoningEffort;
        case "extraParams": return fd.extraParams;
        case "proxyVisionModelId": return fd.proxyVisionModelId;
        case "proxyVisionPrompt": return fd.proxyVisionPrompt;
        }
        return "";
    }

    function setFormValue(key, value) {
        switch (key) {
        case "name": fd.name = value; break;
        case "provider": fd.provider = value; break;
        case "endpoint": fd.endpoint = value; break;
        case "modelId": fd.modelId = value; break;
        case "temperature": fd.temperature = value; break;
        case "maxContextSize": fd.maxContextSize = value; break;
        case "reasoningEffort": fd.reasoningEffort = value; break;
        case "extraParams": fd.extraParams = value; break;
        case "proxyVisionModelId": fd.proxyVisionModelId = value; break;
        case "proxyVisionPrompt": fd.proxyVisionPrompt = value; break;
        }
    }

    function initFormData() {
        formReady = false;

        var data = null;
        try {
            data = JSON.parse(chatbot.getModelDetail(modelId));
        } catch (e) {
            console.error("ModelDetailPage: 读取模型配置失败:", e);
        }
        if (!data) {
            showToast("模型配置读取失败", 2);
            return;
        }

        missingModel = data.missing === true;
        isActive = data.isActive === true;
        if (missingModel) showToast("该模型配置已不存在，请返回列表", 2);

        var caps = (data.capabilities && typeof data.capabilities === "object") ? data.capabilities : {};
        fd.name = typeof data.name === "string" ? data.name : "";
        fd.provider = typeof data.provider === "string" ? data.provider : "";
        fd.endpoint = typeof data.endpoint === "string" ? data.endpoint : "";
        fd.modelId = typeof data.modelId === "string" ? data.modelId : "";
        fd.apiProtocol = data.apiProtocol === "responses" ? "responses" : "chat_completions";
        fd.apiKey = "";
        fd.apiKeySet = data.apiKeySet === true;
        fd.temperature = (typeof data.temperature === "number") ? String(data.temperature) : "0.7";
        fd.maxContextSize = (typeof data.maxContextSize === "number" && data.maxContextSize > 0) ? data.maxContextSize : 0;
        fd.capText = caps.text !== false;
        fd.capVision = caps.vision === true;
        fd.capAudio = caps.audio === true;
        fd.capToolCall = caps.toolCall === true;
        fd.capReasoning = caps.reasoning === true;
        fd.capImageGeneration = caps.imageGeneration === true;
        fd.reasoningEffort = typeof data.reasoningEffort === "string" ? data.reasoningEffort : "";
        fd.nativeWebSearchEnabled = data.nativeWebSearchEnabled === true;
        fd.nativeWebSearchProvider =
                typeof data.nativeWebSearchProvider === "string" ? data.nativeWebSearchProvider : "auto";
        fd.extraParams = summarizeExtraParamsSource(data.extraParams);
        fd.proxyVisionModelId = typeof data.proxyVisionModelId === "string" ? data.proxyVisionModelId : "";
        fd.proxyVisionPrompt = typeof data.proxyVisionPrompt === "string" ? data.proxyVisionPrompt : "";

        formReady = true;
        refreshVisionModels();
        // 便于真机量化闭环：不打印任何密钥/extraParams 内容，只打印长度与状态
        console.log("[ModelEditor] form ready id=", modelId, "isNew=", isNew, "missing=", missingModel,
                    "extraParamsLen=", fd.extraParams.length, "hasWarning=", !!data.normalizeWarning);

        // 归一化阶段丢弃过非法/超长 extraParams 时明确提示（不静默）
        if (typeof data.normalizeWarning === "string" && data.normalizeWarning.length > 0) {
            var warning = data.normalizeWarning;
            if (warning.length > 48) warning = warning.substring(0, 48) + "…";
            showToast("配置已修正：" + warning, 2);
        }
    }

    // 把模型配置里的 extraParams（object 或旧格式字符串）转成编辑用的 JSON 文本
    function summarizeExtraParamsSource(extraParams) {
        if (extraParams === undefined || extraParams === null) return "";
        if (typeof extraParams === "string") {
            var text = extraParams.trim();
            if (text === "" || text === "{}" || text === "null") return "";
            return text;
        }
        if (typeof extraParams !== "object") return "";
        try {
            if (Object.keys(extraParams).length === 0) return "";
            return JSON.stringify(extraParams);
        } catch (e) {
            return "";
        }
    }

    // 页面上只显示摘要，不整段渲染可能很长的 extraParams
    function extraParamsSummary() {
        var text = (fd.extraParams || "").trim();
        if (text === "" || text === "{}") return "";
        try {
            var obj = JSON.parse(text);
            if (typeof obj !== "object" || obj === null || Array.isArray(obj)) return "（不是 JSON object，保存前请修正）";
            var compact = JSON.stringify(obj);
            if (compact.length > 42) compact = compact.substring(0, 42) + "…";
            return compact + " · " + Object.keys(obj).length + " 项";
        } catch (e) {
            return "（JSON 不合法，保存前请修正）";
        }
    }

    // 代理提示词同理：只显示摘要，避免超长文本整段渲染
    function proxyPromptSummary() {
        var text = fd.proxyVisionPrompt || "";
        if (text === "") return "";
        var compact = text.replace(/\s+/g, " ");
        if (compact.length > 36) compact = compact.substring(0, 36) + "…";
        return compact + "（" + text.length + " 字）";
    }

    function parseExtraParamsInput() {
        var text = (fd.extraParams || "").trim();
        if (text === "") return { "ok": true, "value": {} };
        var maxBytes = chatbot.extraParamsMaxBytes();
        if (text.length > maxBytes) return { "ok": false, "error": "额外参数过长（上限 " + maxBytes + " 字节）" };
        var obj = null;
        try {
            obj = JSON.parse(text);
        } catch (e) {
            return { "ok": false, "error": "额外参数不是合法的 JSON" };
        }
        if (typeof obj !== "object" || obj === null || Array.isArray(obj))
            return { "ok": false, "error": "额外参数必须是 JSON object" };
        if (JSON.stringify(obj).length > maxBytes)
            return { "ok": false, "error": "额外参数过长（上限 " + maxBytes + " 字节）" };
        return { "ok": true, "value": obj };
    }

    // ------------------------------------------------------------------
    // 保存 / 删除 / 切换使用中
    // ------------------------------------------------------------------

    function saveModel() {
        if (missingModel) {
            showToast("该模型配置已不存在，请返回列表", 2);
            return;
        }
        if (!fd.name) {
            showToast("名称不能为空", 2);
            return;
        }
        if (!fd.endpoint) {
            showToast("接口地址不能为空", 2);
            return;
        }
        if (!fd.modelId) {
            showToast("模型 ID 不能为空", 2);
            return;
        }

        var extra = parseExtraParamsInput();
        if (!extra.ok) {
            showToast(extra.error, 2);
            return;
        }

        var temperature = parseFloat(fd.temperature);
        if (isNaN(temperature)) temperature = 0.7;
        temperature = Math.max(0, Math.min(2, temperature));
        var maxContextSize = parseInt(fd.maxContextSize);
        if (isNaN(maxContextSize) || maxContextSize < 0) maxContextSize = 0;

        // 只提交本页编辑的字段；apiKey 为空表示“不修改已存密钥”（完整密钥不会显示在界面里）
        var payload = {
            "id": isNew ? "" : modelId,
            "name": fd.name,
            "provider": fd.provider,
            "endpoint": fd.endpoint,
            "modelId": fd.modelId,
            "apiProtocol": fd.apiProtocol,
            "temperature": temperature,
            "maxContextSize": maxContextSize,
            "reasoningEffort": fd.capReasoning ? fd.reasoningEffort : "",
            "nativeWebSearchEnabled": (fd.apiProtocol === "responses") && fd.nativeWebSearchEnabled,
            "nativeWebSearchProvider": fd.nativeWebSearchProvider,
            "capabilities": {
                "text": fd.capText,
                "vision": fd.capVision,
                "audio": fd.capAudio,
                "toolCall": fd.capToolCall,
                "reasoning": fd.capReasoning,
                "imageGeneration": fd.capImageGeneration
            },
            "extraParams": extra.value,
            "proxyVisionModelId": fd.proxyVisionModelId,
            "proxyVisionPrompt": fd.proxyVisionPrompt
        };

        // 完整密钥只在新输入时提交；留空则 C++ 保留已存密钥（旧资源库路径同理）
        if (fd.apiKey.length > 0) payload["apiKey"] = fd.apiKey;

        if (chatbot.addModel(JSON.stringify(payload))) {
            showToast(isNew ? "模型已添加" : "模型已更新", 1);
            modelSaved();
            backButtonClicked();
        } else {
            var error = chatbot.getLastModelError();
            showToast(error ? ("保存失败：" + error) : "保存失败，请检查输入", 2);
        }
    }

    function makeActiveModel() {
        if (chatbot.setActiveModel(modelId)) {
            isActive = true;
            showToast("已设为使用中的模型", 1);
            modelSaved();
        } else {
            var error = chatbot.getLastModelError();
            showToast(error ? ("切换失败：" + error) : "切换失败", 2);
        }
    }

    function deleteModel() {
        if (chatbot.removeModel(modelId)) {
            showToast("已删除: " + (fd.name || modelId), 1);
            modelDeleted();
            id_delete_dialog.close();
            backButtonClicked();
        } else {
            var error = chatbot.getLastModelError();
            showToast(error ? ("删除失败：" + error) : "删除失败", 2);
            id_delete_dialog.close();
        }
    }

    // ------------------------------------------------------------------
    // 选项循环 / 视觉代理模型
    // ------------------------------------------------------------------

    function reasoningEffortLabel(value) {
        var labels = { "": "默认", "none": "关闭", "minimal": "极低", "low": "低", "medium": "中", "high": "高", "xhigh": "极高" };
        return labels[value] || "默认";
    }

    function nativeWebSearchProviderLabel(value) {
        var labels = { "auto": "自动识别", "openai": "OpenAI", "xai": "xAI", "compatible": "兼容服务" };
        return labels[value] || "自动识别";
    }

    function cycleNativeWebSearchProvider() {
        var providers = ["auto", "openai", "xai", "compatible"];
        var index = providers.indexOf(fd.nativeWebSearchProvider);
        fd.nativeWebSearchProvider = providers[(index + 1) % providers.length];
    }

    function cycleReasoningEffort() {
        var values = ["", "none", "minimal", "low", "medium", "high", "xhigh"];
        var index = values.indexOf(fd.reasoningEffort);
        fd.reasoningEffort = values[(index + 1) % values.length];
    }

    function refreshVisionModels() {
        var list = [];
        var names = ({});
        try {
            var parsed = JSON.parse(chatbot.getModelSummaries());
            var models = parsed.models || [];
            if (Array.isArray(models)) {
                for (var i = 0; i < models.length; i++) {
                    var model = models[i];
                    if (!model || typeof model !== "object") continue;
                    names[model.id] = model.name || model.id;
                    var cap = model.capabilities || {};
                    if (cap.vision === true && model.id !== modelId)
                        list.push({ "modelId": model.id, "modelName": model.name || model.id });
                }
            }
        } catch (e) {
            console.error("ModelDetailPage: 读取模型摘要失败:", e);
        }
        visionModelList = list;
        modelNames = names;
    }

    function getProxyModelName() {
        if (!fd.proxyVisionModelId) return "未设置";
        return modelNames[fd.proxyVisionModelId] || "已删除的模型";
    }

    // ------------------------------------------------------------------
    // 输入页
    // ------------------------------------------------------------------

    function openKeyboard(key, placeholder) {
        id_detail_pop.currentKey = key;
        id_detail_pop.currentPlaceholder = placeholder;
        // API Key 不回填到可见输入框里（完整密钥不得出现在界面上）
        id_detail_pop.currentPrefill = key === "apiKey" ? "" : String(formValue(key));
        var component = qmlCreateComponent("YInputPage");
        if (Component.Ready === component.status) {
            var incubator = component.incubateObject(id_detail_pop.containerItem);
            if (incubator.status !== Component.Ready) {
                incubator.onStatusChanged = function(s) {
                    if (s === Component.Ready) id_detail_pop.inputPageCreated(incubator.object);
                };
            } else {
                id_detail_pop.inputPageCreated(incubator.object);
            }
        } else {
            console.error("ModelDetailPage: 输入页加载失败:", component.errorString());
        }
    }

    // ------------------------------------------------------------------
    // Toast
    // ------------------------------------------------------------------

    property string toastMsg: ""
    property bool toastVisible: false
    property int toastType: 0

    function showToast(msg, type) {
        toastMsg = msg;
        toastType = type || 0;
        toastVisible = true;
        id_toast_timer.restart();
    }

    Timer {
        id: id_toast_timer
        interval: 2500
        onTriggered: toastVisible = false
    }

    Component.onCompleted: {
        initialized = true;
        initFormData();
    }

    onModelIdChanged: {
        if (initialized) initFormData();
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: toastVisible ? 16 : -40
        width: Math.min(id_toast_text.implicitWidth + 32, parent.width - 20)
        height: 30
        radius: 6
        color: toastType === 2 ? "#4A1A1D" : toastType === 1 ? "#1A3A2A" : "#1A2A3A"
        z: 2000
        visible: opacity > 0
        opacity: toastVisible ? 1 : 0

        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            id: id_toast_text
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 16)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: toastMsg
            color: toastType === 2 ? "#FF6B6B" : toastType === 1 ? "#4CAF50" : YColors.grayText
            font.pixelSize: 12
            font.family: qmlGlobal.fontFamilyZhCn
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: id_detail_col.height + 24
        clip: true
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: id_detail_col
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 6

            YSettingItemTitle {
                title: isNew ? "添加模型" : (isActive ? "编辑模型（使用中）" : "编辑模型")
            }

            // ─── 基本信息 ─────────────────────────────
            YText {
                text: "基本信息"
                color: YColors.grayText
                font.pixelSize: 12
                anchors.left: parent.left
                anchors.leftMargin: 4
            }

            DescribedClickableTextBox {
                title: "模型名称"
                describe: fd.name || "点击输入显示名称"
                describeItem.color: YColors.grayText
                opacityChangableWhenPressed: false
                onClicked: openKeyboard("name", "请输入模型名称")
            }

            DescribedClickableTextBox {
                title: "提供商"
                describe: fd.provider || "点击输入（选填）"
                describeItem.color: YColors.grayText
                opacityChangableWhenPressed: false
                onClicked: openKeyboard("provider", "请输入提供商名称")
            }

            // ─── 接口配置 ─────────────────────────────
            YText {
                text: "接口配置"
                color: YColors.grayText
                font.pixelSize: 12
                anchors.left: parent.left
                anchors.leftMargin: 4
            }

            DescribedClickableTextBox {
                title: "接口地址"
                describe: fd.endpoint || "点击输入 API 服务端点 URL"
                describeItem.color: YColors.grayText
                opacityChangableWhenPressed: false
                onClicked: openKeyboard("endpoint", "https://api.example.com/v1")
            }

            DescribedClickableTextBox {
                title: "模型 ID"
                describe: fd.modelId || "点击输入传给 API 的 model 参数"
                describeItem.color: YColors.grayText
                opacityChangableWhenPressed: false
                onClicked: openKeyboard("modelId", "请输入模型 ID")
            }

            DescribedSwitchItem {
                title: "Responses API"
                description: "使用 /responses 协议"
                switchOn: fd.apiProtocol === "responses"
                interval: 0
                onTimerTriggered: {
                    var chatEndpoint = "https://api.deepseek.com/v1/chat/completions";
                    var responsesEndpoint = "https://api.deepseek.com/v1/responses";
                    if (switchOn && fd.endpoint === chatEndpoint)
                        fd.endpoint = responsesEndpoint;
                    else if (!switchOn && fd.endpoint === responsesEndpoint)
                        fd.endpoint = chatEndpoint;
                    fd.apiProtocol = switchOn ? "responses" : "chat_completions";
                }
            }

            DescribedClickableTextBox {
                title: "API 密钥"
                describe: hasApiKey() ? "已配置（点击可重新输入）" : "未配置，点击输入"
                describeItem.color: YColors.grayText
                opacityChangableWhenPressed: false
                onClicked: openKeyboard("apiKey", hasApiKey() ? "留空保持不变，输入以覆盖" : "请输入 API 密钥")
            }

            // ─── 高级选项 ─────────────────────────────
            YText {
                text: "高级选项"
                color: YColors.grayText
                font.pixelSize: 12
                anchors.left: parent.left
                anchors.leftMargin: 4
            }

            DescribedClickableTextBox {
                title: "温度"
                describe: fd.temperature !== undefined ? String(fd.temperature) : "0.7"
                describeItem.color: YColors.grayText
                opacityChangableWhenPressed: false
                onClicked: openKeyboard("temperature", "0.0 ~ 2.0")
            }

            DescribedClickableTextBox {
                title: "上下文窗口大小"
                describe: fd.maxContextSize > 0 ? String(fd.maxContextSize) + " tokens" : "未设置"
                describeItem.color: YColors.grayText
                opacityChangableWhenPressed: false
                onClicked: openKeyboard("maxContextSize", "输入模型最大上下文 Token 数，0 为未设置")
            }

            DescribedClickableTextBox {
                title: "自定义请求体参数"
                describe: extraParamsSummary() || "点击输入额外 JSON 参数"
                describeItem.color: YColors.grayText
                opacityChangableWhenPressed: false
                onClicked: openKeyboard("extraParams", "{ \"top_p\": 0.9 }")
            }

            // ─── 模型能力 ─────────────────────────────
            YText {
                text: "模型能力"
                color: YColors.grayText
                font.pixelSize: 12
                anchors.left: parent.left
                anchors.leftMargin: 4
            }

            DescribedSwitchItem {
                title: "文本"
                description: "支持文本输入与生成"
                switchOn: fd.capText
                interval: 0
                onTimerTriggered: { fd.capText = switchOn; }
            }

            DescribedSwitchItem {
                title: "图像（Vision）"
                description: "支持图片输入"
                switchOn: fd.capVision
                interval: 0
                onTimerTriggered: { fd.capVision = switchOn; }
            }

            DescribedSwitchItem {
                title: "音频"
                description: "支持音频输入"
                switchOn: fd.capAudio
                interval: 0
                onTimerTriggered: { fd.capAudio = switchOn; }
            }

            DescribedSwitchItem {
                title: "工具使用（Tool Call）"
                description: "支持函数调用"
                switchOn: fd.capToolCall
                interval: 0
                onTimerTriggered: { fd.capToolCall = switchOn; }
            }

            DescribedSwitchItem {
                title: "推理（Reasoning）"
                description: "支持推理摘要与深度控制"
                switchOn: fd.capReasoning
                interval: 0
                onTimerTriggered: { fd.capReasoning = switchOn; }
            }

            DescribedSwitchItem {
                title: "图片生成"
                description: "使用 Responses API 图片生成工具"
                switchOn: fd.capImageGeneration
                enabled: fd.apiProtocol === "responses"
                interval: 0
                onTimerTriggered: { fd.capImageGeneration = switchOn; }
            }

            DescribedSwitchItem {
                title: "厂商联网搜索"
                description: "使用 Responses API 原生搜索工具"
                switchOn: fd.nativeWebSearchEnabled
                enabled: fd.apiProtocol === "responses"
                interval: 0
                onTimerTriggered: { fd.nativeWebSearchEnabled = switchOn; }
            }

            DescribedClickableTextBox {
                title: "联网搜索来源"
                describe: nativeWebSearchProviderLabel(fd.nativeWebSearchProvider)
                describeItem.color: YColors.grayText
                visible: fd.apiProtocol === "responses" && fd.nativeWebSearchEnabled
                opacityChangableWhenPressed: false
                onClicked: cycleNativeWebSearchProvider()
            }

            DescribedClickableTextBox {
                title: "推理深度"
                describe: reasoningEffortLabel(fd.reasoningEffort)
                describeItem.color: fd.reasoningEffort ? YColors.blueText : YColors.grayText
                visible: fd.capReasoning
                opacityChangableWhenPressed: false
                onClicked: cycleReasoningEffort()
            }

            // ─── 视觉代理设置（仅 Vision 关闭时显示）────
            YText {
                text: "视觉代理设置"
                color: YColors.grayText
                font.pixelSize: 12
                anchors.left: parent.left
                anchors.leftMargin: 4
                visible: !fd.capVision
            }

            DescribedClickableTextBox {
                title: "视觉代理模型"
                describe: getProxyModelName()
                describeItem.color: fd.proxyVisionModelId ? YColors.blueText : YColors.grayText
                visible: !fd.capVision
                opacityChangableWhenPressed: false
                onClicked: {
                    refreshVisionModels();
                    if (visionModelList.length === 0) {
                        showToast("暂无支持视觉的模型，请先添加", 2);
                        return;
                    }
                    proxySelectorOpen = true;
                }
            }

            DescribedClickableTextBox {
                title: "代理提示词"
                describe: proxyPromptSummary() || "点击输入（默认：请详细描述图片内容）"
                describeItem.color: fd.proxyVisionPrompt ? YColors.blueText : YColors.grayText
                visible: !fd.capVision
                opacityChangableWhenPressed: false
                onClicked: openKeyboard("proxyVisionPrompt", "请输入发给视觉模型的分析提示词")
            }

            // ─── 操作 ────────────────────────────────
            YSettingAboutClickableItem {
                title: "设为使用中的模型"
                visible: !isNew && !isActive && !missingModel
                onClicked: makeActiveModel()
            }

            YSettingAboutClickableItem {
                title: isNew ? "添加模型" : "保存修改"
                enabled: !missingModel
                onClicked: saveModel()
            }

            YSettingAboutClickableItem {
                title: "删除模型"
                visible: !isNew
                onClicked: {
                    id_delete_dialog.tipItem.text =
                            "确定删除模型「" + (fd.name || modelId) + "」吗？此操作不可撤销。";
                    id_delete_dialog.show();
                }
            }
        }
    }

    // ─── 视觉代理模型选择器覆盖层 ─────────────────
    Rectangle {
        anchors.fill: parent
        color: "#AA000000"
        visible: proxySelectorOpen
        z: 1500

        MouseArea {
            anchors.fill: parent
            onClicked: proxySelectorOpen = false
        }

        Rectangle {
            width: 260
            height: Math.min(260, visionModelList.length * 40 + 80)
            color: "#1C1C1E"
            radius: 12
            anchors.centerIn: parent

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4

                YText {
                    text: "选择视觉代理模型"
                    color: "white"
                    font.pixelSize: 13
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Rectangle {
                    width: parent.width - 24
                    height: 1
                    color: "#333"
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Flickable {
                    width: parent.width - 8
                    height: parent.height - 52
                    contentHeight: id_proxy_model_col.height
                    clip: true

                    Column {
                        id: id_proxy_model_col
                        width: parent.width

                        Repeater {
                            model: visionModelList
                            YSettingAboutClickableItem {
                                title: modelData.modelName
                                imageName: modelData.modelId === fd.proxyVisionModelId ? 'settings/st-check' : ''
                                onClicked: {
                                    fd.proxyVisionModelId = modelData.modelId;
                                    proxySelectorOpen = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    YTwoButtonDialog {
        id: id_delete_dialog
        z: 1500
        anchors.fill: parent

        onClickedConfirm: deleteModel()
        onClickedCancel: close()
    }

    YPagePopHelper {
        id: id_detail_pop
        z: 1000
        anchors.fill: parent
        objectName: "from_ModelDetailPage.qml"
        isShowing: qmlGlobal.inputPageShowing

        property string currentKey: ""
        property string currentPlaceholder: ""
        property string currentPrefill: ""

        function inputPageCreated(kbPage) {
            var key = currentKey;
            var placeholder = currentPlaceholder;
            var prefill = currentPrefill;

            kbPage.placeHolderText = placeholder;

            kbPage.backButtonClicked.connect(function() {
                qmlGlobal.inputPageShowing = false;
                kbPage.todoDestroy();
            });

            kbPage.inputFinished.connect(function(input) {
                qmlGlobal.inputPageShowing = false;
                kbPage.todoDestroy();
                if (input === null) return;

                if (key === "temperature") {
                    var temperature = parseFloat(input);
                    fd.temperature = isNaN(temperature) ? "0.7" : String(Math.max(0, Math.min(2, temperature)));
                } else if (key === "maxContextSize") {
                    var size = parseInt(input);
                    fd.maxContextSize = (isNaN(size) || size < 0) ? 0 : size;
                } else if (key === "extraParams") {
                    // 先原样收下（保留用户输入），保存时统一校验；这里只拦明显超长的情况
                    if (input.length > chatbot.extraParamsMaxBytes()) {
                        showToast("额外参数过长（上限 " + chatbot.extraParamsMaxBytes() + " 字节）", 2);
                        return;
                    }
                    fd.extraParams = input;
                } else if (key === "apiKey") {
                    if (input.length > 0) fd.apiKey = input;
                } else {
                    setFormValue(key, input);
                }
            });

            kbPage.enterText(prefill);
            kbPage.show();
            qmlGlobal.inputPageShowing = true;
        }
    }
}
