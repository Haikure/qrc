import "./commons"
import "./components"
import "./i18n"
import "./settingpages"
import "./audiopages"
import "./assistant/components"
import "./assistant/messages"
import "./assistant/messages/ChatNavigation.js" as ChatNavigation
import "./assistant/dialogs"
import QtQuick 2.15
import QtGraphicalEffects 1.12
import com.github.penuniverse 1.0

YPage {
    id: id_chat_assistant_page
    objectName: "YPage===ChatAssistant.qml"
    pageIndex: PageIndex.ChatAssistant
    deferHomeCloseUntilLongPress: true

    property bool historyLoaded: false
    property string messageContent: ""
    property bool isSearchEnabled: false
    property bool mathServerAvailable: false
    // 服务端是否支持"统一字号 + 长公式换行"（旧版只弹一次提示，不改变其它行为）
    property bool mathServerModern: false
    property bool _mathServerWarned: false
    // 服务端渲染器缺中文字体（/health 的 cjkFont === false）只提示一次
    property bool _mathServerFontWarned: false
    property bool bubbleTextureCacheEnabled: true
    property var keyboardPageRef: null
    property var _keyboardComponent: null
    property var _keyboardIncubator: null
    property bool _keyboardRequested: false
    property bool isGenerating: false
    property bool captureModeActive: false
    property bool _layoutStabilizing: false
    property bool _preparingSend: false
    property bool _toolCallActive: false
    property int _attachmentReadSeq: 0
    // 内嵌图片要等后端落盘才有 localPath，而视觉代理是异步落库的，所以记下发出去那一行，
    // 等 messagesChanged 时按历史把路径补回来（-1 = 没有待补的行）。
    property int _pendingAttachmentRow: -1
    property string _pendingAttachmentText: ""
    property int _pendingJumpIndex: -1
    property int _navigationTargetIndex: -1
    property bool _navigationJumping: false
    property int _jumpAttempts: 0
    property int _jumpStableFrames: 0
    property int _followAttempts: 0
    property int _followStableFrames: 0
    property real _followLastContentHeight: -1
    // 右侧手势条宽度 = 气泡右侧留白。
    readonly property int  chatListRightMargin: 2
    readonly property int  bubbleRightInset: 8
    readonly property real rightGestureWidth: chatListRightMargin + bubbleRightInset

    // 当前正在流式接收的思维链行下标（-1 表示没有）
    property int _activeReasoningIndex: -1
    property var _mathProbeRequest: null

    function _beginRichContentCommit() {
        if (id_chat_listview.moving)
            return;
        if (id_rich_content_anchor_timer.running)
            return;

        // 用户正在往回翻历史：钉住阅读位置，不做任何贴底。
        if (id_chat_listview.userScrolledUp) {
            id_chat_listview.captureReadAnchor();
            id_read_anchor_timer.hold();
            return;
        }

        var distanceToBottom = id_chat_listview.contentHeight - id_chat_listview.contentY - id_chat_listview.height;
        if (distanceToBottom <= id_chat_listview.bottomThreshold) {
            id_rich_content_anchor_timer.pinBottom = true;
            id_rich_content_anchor_timer.anchorIndex = -1;
            id_rich_content_anchor_timer.beginTracking();
            return;
        }

        var anchorIndex = id_chat_listview.probeViewportIndex();
        if (anchorIndex < 0)
            return;
        var anchorItem = id_chat_listview.itemAtIndex(anchorIndex);
        if (!anchorItem)
            return;

        id_rich_content_anchor_timer.pinBottom = false;
        id_rich_content_anchor_timer.anchorIndex = anchorIndex;
        id_rich_content_anchor_timer.anchorOffset = anchorItem.y - id_chat_listview.contentY;
        id_rich_content_anchor_timer.beginTracking();
    }

    function resetCaptureMode() {
        captureModeActive = false;
        if (typeof cameraCapture !== 'undefined' && cameraCapture !== null)
            cameraCapture.captureEnabled = false;
    }

    function _startMathServer() {
        var serverPath = chatbot.mathServerPath.trim();
        if (serverPath === "") {
            console.log("[MathServer] server_path 未配置，跳过启动");
            return;
        }
        var binName = serverPath.replace(/.*\//, "");
        if (binName === "")
            return;
        var pattern = "[" + binName[0] + "]" + binName.slice(1);
        var running = shell.exec("pgrep -f -- '" + pattern.replace(/'/g, "'\\''") + "'");
        if (running !== "") {
            console.log("[MathServer] 进程已在运行（pid:", running, "），跳过");
            return;
        }
        console.log("[MathServer] 启动服务器：", serverPath);
        shell.startDetached(serverPath);
    }

    Connections {
        target: chatbot
        function onMathRenderConfigChanged() {
            if (chatbot.mathRenderEnabled) {
                _startMathServer();
                mathServerProbe.restart();
            } else {
                mathServerProbe.stop();
                if (_mathProbeRequest !== null) {
                    _mathProbeRequest.abort();
                    _mathProbeRequest = null;
                }
                id_chat_assistant_page.mathServerAvailable = false;
            }
        }
    }

    Timer {
        id: mathServerProbe
        interval: 5000
        repeat: true
        running: id_chat_assistant_page.visible && chatbot.mathRenderEnabled && !id_chat_assistant_page.mathServerAvailable
        triggeredOnStart: true
        onTriggered: {
            if (_mathProbeRequest !== null)
                return;
            var xhr = new XMLHttpRequest();
            _mathProbeRequest = xhr;
            xhr.open("GET", "http://127.0.0.1:3000/health", true);
            xhr.timeout = 2000;
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE || _mathProbeRequest !== xhr)
                    return;
                _mathProbeRequest = null;
                id_chat_assistant_page.mathServerAvailable = (xhr.status > 0);
                if (!id_chat_assistant_page.mathServerAvailable)
                    return;
                // /health 由本项目服务端提供 renderer/cjkFont；不是本项目的服务端（status 非 ok）不提示。
                var health = null;
                try {
                    health = JSON.parse(xhr.responseText);
                } catch (e) {
                    health = null;
                }
                if (!health || health.status !== "ok")
                    return;
                id_chat_assistant_page.mathServerModern = (health.renderer || 1) >= 2;
                // 探测会在页面重新可见时重启，靠标志位保证每个问题只提示一次；
                // 两个问题合并成一条文案，避免两次 toast 互相覆盖。
                var problems = [];
                if (!id_chat_assistant_page.mathServerModern && !id_chat_assistant_page._mathServerWarned) {
                    id_chat_assistant_page._mathServerWarned = true;
                    problems.push("公式服务版本过旧：公式大小不会统一、长公式不会换行");
                }
                // 只有服务端明确给出 false 才算缺字体；字段缺失（旧服务端）不提示。
                if (health.cjkFont === false && !id_chat_assistant_page._mathServerFontWarned) {
                    id_chat_assistant_page._mathServerFontWarned = true;
                    problems.push("公式服务缺少中文字体：公式里的中文会显示不出来");
                }
                if (problems.length === 1)
                    toastBanner.warning(problems[0] + "，建议更新 mathjax-server", 8000);
                else if (problems.length > 1)
                    toastBanner.warning(problems.join("；") + "，请更新 mathjax-server", 8000);
            };
            xhr.ontimeout = function () {
                if (_mathProbeRequest === xhr)
                    _mathProbeRequest = null;
                id_chat_assistant_page.mathServerAvailable = false;
            };
            xhr.onerror = xhr.ontimeout;
            try {
                xhr.send();
            } catch (e) {
                if (_mathProbeRequest === xhr)
                    _mathProbeRequest = null;
                id_chat_assistant_page.mathServerAvailable = false;
            }
        }
    }

    ListModel {
        id: attachedFilesModel
    }
    ListModel {
        id: attachedMediaModel
    }
    // 编辑态专用，与"还没发出去的预发送附件"分开：取消编辑时才分得清两者。
    // 由 editMessage 回填、输入页的图片条直接读写，确认时再交回 chatbot.editMessageWithMedia。
    ListModel {
        id: editAttachedMediaModel
    }

    function clearAttachments() {
        attachedFilesModel.clear();
        attachedMediaModel.clear();
    }

    onVisibleChanged: {
        if (visible) {
            if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                keyBoard.autoSendScan = keyBoard.autoSendScanConfig;
            Qt.callLater(consumePendingVoiceChat);
        } else {
            _attachmentReadSeq++;
            _preparingSend = false;
            if (_mathProbeRequest !== null) {
                _mathProbeRequest.abort();
                _mathProbeRequest = null;
            }
            clearAttachments();
            if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                keyBoard.autoSendScan = false;
        }
    }

    function getFileLanguage(filePath) {
        var lowerPath = filePath.toLowerCase();
        if (lowerPath.endsWith(".cpp") || lowerPath.endsWith(".cc") || lowerPath.endsWith(".cxx"))
            return "cpp";
        if (lowerPath.endsWith(".hpp") || lowerPath.endsWith(".hh"))
            return "hpp";
        if (lowerPath.endsWith(".h"))
            return "h";
        if (lowerPath.endsWith(".c"))
            return "c";
        if (lowerPath.endsWith(".py") || lowerPath.endsWith(".python"))
            return "python";
        if (lowerPath.endsWith(".js"))
            return "javascript";
        if (lowerPath.endsWith(".ts") || lowerPath.endsWith(".tsx"))
            return "typescript";
        if (lowerPath.endsWith(".jsx"))
            return "jsx";
        if (lowerPath.endsWith(".html") || lowerPath.endsWith(".htm"))
            return "html";
        if (lowerPath.endsWith(".css"))
            return "css";
        if (lowerPath.endsWith(".json"))
            return "json";
        if (lowerPath.endsWith(".xml") || lowerPath.endsWith(".qml"))
            return "xml";
        if (lowerPath.endsWith(".md") || lowerPath.endsWith(".markdown"))
            return "markdown";
        if (lowerPath.endsWith(".yaml") || lowerPath.endsWith(".yml"))
            return "yaml";
        if (lowerPath.endsWith(".java"))
            return "java";
        if (lowerPath.endsWith(".sh") || lowerPath.endsWith(".bash"))
            return "bash";
        if (lowerPath.endsWith(".cmake") || lowerPath.endsWith("cmakelists.txt"))
            return "cmake";
        if (lowerPath.endsWith(".go"))
            return "go";
        if (lowerPath.endsWith(".rs"))
            return "rust";
        if (lowerPath.endsWith(".lua"))
            return "lua";
        if (lowerPath.endsWith(".sql"))
            return "sql";
        return "";
    }

    function isTextFile(filePath) {
        if (!filePath)
            return false;
        var lowerPath = filePath.toLowerCase();
        var exts = [".txt", ".md", ".json", ".py", ".js", ".ts", ".qml", ".cpp", ".h", ".c", ".java", ".html", ".css", ".xml", ".yaml", ".yml", ".ini", ".log", ".csv"];
        for (var i = 0; i < exts.length; i++) {
            if (lowerPath.endsWith(exts[i]))
                return true;
        }
        return false;
    }

    // 输入页只建一次：一次建造 ≈ 4 张字符键盘 + 一个 Rime 会话（RimeWrapper 里同步 create_session）。
    // 复用安全的前提是每次 show 前 resetInput() 清空状态；验证：连续编辑三次，日志里不再出现 destroy。
    property var _inputPage: null
    property var _inputPageDone: null
    property var _inputPageModel: null
    property bool _inputPagePending: false
    property string _inputPagePlaceholder: ""
    property string _inputPagePrefill: ""

    function _initInputPage(inputPage) {
        _inputPage = inputPage;
        // 回调只连一次，每次打开用 _inputPageDone 换目标（QML 的 connect 不能按引用解绑临时闭包）。
        inputPage.backButtonClicked.connect(function () {
            qmlGlobal.inputPageShowing = false;
            _inputPageDone = null;
            // 取消编辑时清掉上一轮的图片，避免下一次打开残留。
            if (_inputPageModel)
                _inputPageModel.clear();
        });
        inputPage.inputFinished.connect(function (input) {
            qmlGlobal.inputPageShowing = false;
            var done = _inputPageDone;
            _inputPageDone = null;
            if (done)
                done(input);
        });
        if (_inputPagePending)
            _showInputPage();
    }

    function _showInputPage() {
        _inputPagePending = false;
        var inputPage = _inputPage;
        if (!inputPage)
            return;
        inputPage.placeHolderText = _inputPagePlaceholder;
        // 图片模型每次都要重设：编辑里删光图片后 ✓ 应该重新变灰，取消编辑后条要消失。
        inputPage.attachmentModel = _inputPageModel;
        inputPage.allowEmptyAccept = Qt.binding(function () {
            return _inputPageModel !== null && _inputPageModel.count > 0;
        });
        inputPage.resetInput(_inputPagePrefill);
        inputPage.show();
        qmlGlobal.inputPageShowing = true;
    }

    function openInputPage(placeholder, prefill, onDone, attachmentModel) {
        _inputPageDone = onDone || null;
        _inputPageModel = attachmentModel || null;   // null = 普通输入（重命名会话等）
        _inputPagePlaceholder = placeholder || "";
        _inputPagePrefill = prefill || "";

        if (_inputPage) {
            _showInputPage();
            return;
        }
        if (_inputPagePending)
            return;
        _inputPagePending = true;

        // 必须显式 Asynchronous：默认的 PreferSynchronous 会在点击处理里同步编译整条
        // YInputPage 依赖链（9 个文件），点下去到出画面之间整段卡住。
        var component = Qt.createComponent("qrc:/qml/YInputPage.qml", Component.Asynchronous);
        if (component.status === Component.Error) {
            _inputPagePending = false;
            console.error("!!! YInputPage 组件创建失败 !!!", component.errorString());
            return;
        }
        var incubated = false;
        function incubateInputPage() {
            // 组件状态可能多次变化（Loading -> Ready），只允许孵化一次，避免建出两个实例。
            if (incubated)
                return;
            if (component.status === Component.Error) {
                // 异步编译失败：把 pending 放掉，用户再点一次还能重建，而不是永远打不开输入页。
                _inputPagePending = false;
                console.error("!!! YInputPage 组件创建失败 !!!", component.errorString());
                return;
            }
            if (component.status !== Component.Ready)
                return;
            incubated = true;
            var incubator = component.incubateObject(
                        id_page_pop_helper.containerItem,
                        { "visible": false, "destroyOnBack": false, "attachmentModel": _inputPageModel },
                        Qt.Asynchronous);
            function ready() {
                if (incubator.status === Component.Ready) {
                    _initInputPage(incubator.object);
                    component.destroy();
                } else if (incubator.status === Component.Error) {
                    _inputPagePending = false;
                    console.error("!!! YInputPage 孵化失败 !!!");
                    component.destroy();
                }
            }
            if (incubator.status === Component.Ready)
                ready();
            else
                incubator.onStatusChanged = ready;
        }
        if (component.status === Component.Ready)
            incubateInputPage();
        else
            component.statusChanged.connect(incubateInputPage);
    }

    function replaceThinkingOrAppend(entry) {
        var last = chatModel.count - 1;
        if (last >= 0 && chatModel.get(last).isThinking) {
            chatModel.remove(last);
            chatModel.insert(last, entry);
        } else {
            chatModel.append(entry);
        }
    }

    function _appendAnswerPlaceholder() {
        chatModel.append({
            "text": "",
            "raw_text": "",
            "reasoning_text": "",
            "isUser": false,
            "isThinking": false,
            "isReasoning": false,
            "isComplete": false,
            "isToolCall": false,
            "toolCallId": "",
            "toolState": "",
            "historyIndex": -1
        });
        return chatModel.count - 1;
    }

    function _completeLastReasoningCard() {
        _flushReasoningBuffer();
        if (_activeReasoningIndex >= 0 && _activeReasoningIndex < chatModel.count) {
            var item = chatModel.get(_activeReasoningIndex);
            if (item.isReasoning) {
                if (!item.isComplete) {
                    _beginRichContentCommit();
                    chatModel.setProperty(_activeReasoningIndex, "isComplete", true);
                }
                _activeReasoningIndex = -1;
                return;
            }
        }
        _activeReasoningIndex = -1;
    }

    function _makeReasoningEntry(content) {
        return {
            "text": "",
            "raw_text": content || "",
            "reasoning_text": "",
            "isUser": false,
            "isThinking": false,
            "isReasoning": true,
            "isComplete": false,
            "isToolCall": false,
            "toolCallId": "",
            "toolState": "",
            "historyIndex": -1
        };
    }

    function _makeToolCardEntry(toolCallId, toolState, text, rawText, isComplete, entries) {
        return {
            "text": text || "",
            "raw_text": rawText || "",
            "isUser": false,
            "isThinking": false,
            "isReasoning": false,
            "isComplete": typeof isComplete !== "undefined" ? isComplete : false,
            "isToolCall": true,
            "toolCallId": toolCallId,
            "toolState": toolState,
            "toolEntriesJson": entries ? JSON.stringify(entries) : "",
            "historyIndex": -1
        };
    }

    function _applyToolGroup(index, entries) {
        var completed = 0;
        var hasError = false;
        var activeState = "done";
        var details = [];
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            if (entry.complete)
                completed++;
            if (entry.state === "error")
                hasError = true;
            else if (!entry.complete)
                activeState = entry.state || "searching";
            details.push((i + 1) + ". " + entry.text + (entry.raw ? "\n" + entry.raw : ""));
        }
        var allComplete = completed === entries.length;
        var state = hasError ? "error" : (allComplete ? "done" : activeState);
        var title = entries.length === 1 ? entries[0].text
                                        : "工具调用 " + entries.length + " 项 · " + completed + " 已完成";
        chatModel.set(index, {
            "text": title,
            "raw_text": details.join("\n\n"),
            "toolState": state,
            "isComplete": allComplete,
            "toolCallId": entries.length > 0 ? entries[0].id : "",
            "toolEntriesJson": JSON.stringify(entries)
        });
    }

    function _upsertToolEntry(toolCallId, text, rawText, toolState, isComplete) {
        var groupIndex = -1;
        var entries = [];
        for (var searchIndex = chatModel.count - 1; searchIndex >= 0; searchIndex--) {
            var candidate = chatModel.get(searchIndex);
            if (candidate.isUser)
                break;
            if (!candidate.isToolCall || !candidate.toolEntriesJson)
                continue;
            var candidateEntries;
            try { candidateEntries = JSON.parse(candidate.toolEntriesJson); } catch (e) { candidateEntries = []; }
            for (var candidateIndex = 0; candidateIndex < candidateEntries.length; candidateIndex++) {
                if (candidateEntries[candidateIndex].id === toolCallId) {
                    groupIndex = searchIndex;
                    entries = candidateEntries;
                    break;
                }
            }
            if (groupIndex >= 0)
                break;
        }
        if (groupIndex < 0 && chatModel.count > 0) {
            var last = chatModel.get(chatModel.count - 1);
            if (last.isToolCall && last.toolEntriesJson) {
                groupIndex = chatModel.count - 1;
                try { entries = JSON.parse(last.toolEntriesJson); } catch (e) { entries = []; }
            }
        }
        if (groupIndex < 0) {
            entries = [];
            replaceThinkingOrAppend(_makeToolCardEntry("", toolState, text, rawText, isComplete, entries));
            groupIndex = chatModel.count - 1;
        }

        var entryIndex = -1;
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].id === toolCallId) {
                entryIndex = i;
                break;
            }
        }
        var entry = { "id": toolCallId, "text": text || "工具调用", "raw": rawText || "",
                      "state": toolState || "searching", "complete": !!isComplete };
        if (entryIndex >= 0)
            entries[entryIndex] = entry;
        else
            entries.push(entry);
        _applyToolGroup(groupIndex, entries);
    }

    function updateCardByToolCallId(toolCallId, updates) {
        for (var i = chatModel.count - 1; i >= 0; i--) {
            var item = chatModel.get(i);
            if (!item.isToolCall)
                continue;
            if (item.toolEntriesJson) {
                var entries;
                try { entries = JSON.parse(item.toolEntriesJson); } catch (e) { entries = []; }
                for (var j = 0; j < entries.length; j++) {
                    if (entries[j].id !== toolCallId)
                        continue;
                    if (updates.hasOwnProperty("toolState")) entries[j].state = updates.toolState;
                    if (updates.hasOwnProperty("text")) entries[j].text = updates.text;
                    if (updates.hasOwnProperty("raw_text")) entries[j].raw = updates.raw_text;
                    if (updates.hasOwnProperty("isComplete")) entries[j].complete = updates.isComplete;
                    _applyToolGroup(i, entries);
                    return;
                }
            }
            if (item.toolCallId === toolCallId) {
                chatModel.setProperty(i, "toolState", updates.hasOwnProperty("toolState") ? updates.toolState : item.toolState);
                chatModel.setProperty(i, "text", updates.hasOwnProperty("text") ? updates.text : item.text);
                chatModel.setProperty(i, "raw_text", updates.hasOwnProperty("raw_text") ? updates.raw_text : item.raw_text);
                chatModel.setProperty(i, "isComplete", updates.hasOwnProperty("isComplete") ? updates.isComplete : item.isComplete);
                return;
            }
        }
    }

    function _findCurrentAnswerIndex() {
        for (var i = chatModel.count - 1; i >= 0; i--) {
            var item = chatModel.get(i);
            if (item.isUser)
                return -1;
            if (!item.isToolCall && !item.isReasoning && !item.isThinking && !item.isComplete)
                return i;
        }
        return -1;
    }

    // 把一条历史消息渲染成聊天行。
    function _renderHistoryRow(m, idx, toolNameMap) {
        if (m.role === 'system')
            return;
        if (m.role === 'tool') {
            var toolName = toolNameMap[m.toolCallId] || "";
            var label = toolName === "shell_exec" ? "命令执行结果" : "搜索结果";
            _upsertToolEntry(m.toolCallId || "", label, m.content, "done", true);
            if (chatModel.count > 0)
                chatModel.setProperty(chatModel.count - 1, "historyIndex", idx);
            return;
        }
        if (m.role === 'assistant' && m.reasoning) {
            chatModel.append(_makeReasoningEntry(m.reasoning));
            chatModel.setProperty(chatModel.count - 1, "isComplete", true);
        }
        if (m.role === 'assistant' && m.toolCallsJson && m.toolCallsJson !== "") {
            if (!m.content || m.content.trim() === "")
                return;
        }
        var isUser = m.role === 'user';
        var messageAttachments = [];
        var messageParts = m.parts || [];
        for (var partIndex = 0; partIndex < messageParts.length; partIndex++) {
            if (messageParts[partIndex].type === "image_url" || messageParts[partIndex].type === "file")
                messageAttachments.push(messageParts[partIndex]);
        }
        chatModel.append({
            "text": isUser ? m.content : "",
            "attachmentsJson": JSON.stringify(messageAttachments),
            "isUser": isUser,
            "raw_text": m.content,
            "reasoning_text": "",
            "isComplete": true,
            "isThinking": false,
            "isToolCall": false,
            "toolCallId": "",
            "toolState": "",
            "historyIndex": idx
        });
    }

    function _buildToolNameMap(history, fromIndex) {
        var map = {};
        for (var i = fromIndex; i < history.length; i++) {
            var msg = history[i];
            if (msg.role !== 'assistant' || !msg.toolCallsJson)
                continue;
            try {
                var tcs = JSON.parse(msg.toolCallsJson);
                for (var k = 0; k < tcs.length; k++) {
                    if (tcs[k].id && tcs[k]["function"] && tcs[k]["function"].name)
                        map[tcs[k].id] = tcs[k]["function"].name;
                }
            } catch (e) {}
        }
        return map;
    }

    // 生成这一轮消息的行签名，用于和屏幕上的行比对。
    function _turnSignatureFromHistory(history, historyStart) {
        var parts = [];
        for (var idx = historyStart; idx < history.length; idx++) {
            var m = history[idx];
            if (m.role === 'system')
                continue;
            if (m.role === 'tool') {
                parts.push("T");
                continue;
            }
            if (m.role === 'assistant' && m.reasoning)
                parts.push("R:" + m.reasoning);
            if (m.role === 'assistant' && m.toolCallsJson && m.toolCallsJson !== "") {
                if (!m.content || m.content.trim() === "")
                    continue;
            }
            parts.push((m.role === 'user' ? "U:" : "A:") + (m.content || ""));
        }
        return parts.join("\u0001");
    }

    function _turnSignatureFromModel(modelStart) {
        var parts = [];
        for (var i = modelStart; i < chatModel.count; i++) {
            var row = chatModel.get(i);
            var kind = row.isUser ? "U:" : row.isToolCall ? "T" : row.isReasoning ? "R:" : "A:";
            var text = row.isToolCall ? "" : (row.raw_text || "");
            parts.push(kind + text + (row.isComplete ? "" : "\u0002"));
        }
        return parts.join("\u0001");
    }

    // 气泡行的图片附件要在后端落盘后换成带 localPath 的那一份，点开查看器靠它。
    // 调用点：发送后立刻一次（视觉模型同步落库）+ 每次 messagesChanged（视觉代理异步落库）。
    function _adoptPersistedAttachments() {
        if (_pendingAttachmentRow < 0)
            return;

        // 待补的行一旦过期（生成结束或已被按历史重建）就放弃，否则会把别的消息的附件写进这一行。
        if (!id_chat_assistant_page.isGenerating || _pendingAttachmentRow >= chatModel.count) {
            _pendingAttachmentRow = -1;
            return;
        }
        var row = chatModel.get(_pendingAttachmentRow);
        if (!row || !row.isUser || (row.raw_text || "") !== _pendingAttachmentText) {
            _pendingAttachmentRow = -1;
            return;
        }

        var history = chatbot.messages;
        if (history.length === 0)
            return;
        var last = history[history.length - 1];
        // 代理路径下这条还没进历史，最后一条是上一条消息：正文对不上就等下次 messagesChanged。
        // 代理落库时 content 会包一层「[图片描述]…[用户消息]…」，所以按后缀比对。
        if (last.role !== 'user' || !(last.content || "").endsWith(_pendingAttachmentText))
            return;
        var parts = last.parts || [];
        var attachments = [];
        var persisted = false;
        for (var p = 0; p < parts.length; p++) {
            if (parts[p].type !== 'image_url' && parts[p].type !== 'file')
                continue;
            attachments.push(parts[p]);
            if (parts[p].localPath)
                persisted = true;
        }
        // 后端还没落盘：留着下一次 messagesChanged 再补。
        if (!persisted)
            return;
        // 与 _renderHistoryRow 保持同一份内容，落盘后 source 已经是 file://，不再带 base64。
        var json = JSON.stringify(attachments);
        if (row.attachmentsJson !== json)
            chatModel.setProperty(_pendingAttachmentRow, "attachmentsJson", json);
        _pendingAttachmentRow = -1;
    }

    // 以落库的历史为准，不一致时重建这一轮的行。
    function _rebuildCurrentTurnRows() {
        if (!chatbot || !chatbot.messages)
            return;
        var history = chatbot.messages;
        if (history.length === 0)
            return;

        var historyStart = -1;
        for (var i = history.length - 1; i >= 0; i--) {
            if (history[i].role === 'user') {
                historyStart = i;
                break;
            }
        }
        if (historyStart < 0)
            return;

        var modelStart = -1;
        for (var j = chatModel.count - 1; j >= 0; j--) {
            if (chatModel.get(j).isUser) {
                modelStart = j;
                break;
            }
        }
        if (modelStart < 0)
            return;

        if (_turnSignatureFromHistory(history, historyStart) === _turnSignatureFromModel(modelStart))
            return;

        var toolNameMap = _buildToolNameMap(history, historyStart);
        // 整轮重建会让列表高度先塌再涨，用户正在看历史时先记下位置再还原。
        var keepReadingPosition = id_chat_listview.userScrolledUp;
        if (keepReadingPosition)
            id_chat_listview.captureReadAnchor();
        var removed = chatModel.count - modelStart;
        if (removed > 0)
            chatModel.remove(modelStart, removed);
        for (var idx = historyStart; idx < history.length; idx++)
            _renderHistoryRow(history[idx], idx, toolNameMap);
        if (keepReadingPosition) {
            id_chat_listview.forceLayout();
            // 先同步还原一次：重建过程中列表会把视口钳到底部，晚一帧才还原会被看见
            id_chat_listview.restoreReadAnchor();
            id_read_anchor_timer.hold();
        }
        _scheduleScrollToBottom();
    }

    function _resetStreamState() {
        throttlingTimer.stop();
        reasoningFlushTimer.stop();
        generationDoneTimer.stop();
        streamThrottle.content = "";
        streamThrottle.lastIndex = -1;
        streamThrottle.targetKind = "";
        streamThrottle.reasoning = "";
        streamThrottle.reasoningIndex = -1;
        streamThrottle.endProcessed = false;
        _activeReasoningIndex = -1;
    }

    // 思维链也按帧合并写入，避免逐块重排。
    function _flushReasoningBuffer() {
        var text = streamThrottle.reasoning;
        streamThrottle.reasoning = "";
        var index = streamThrottle.reasoningIndex;
        streamThrottle.reasoningIndex = -1;
        if (text === "" || index < 0 || index >= chatModel.count)
            return;
        var item = chatModel.get(index);
        if (!item || !item.isReasoning)
            return;
        chatModel.setProperty(index, "raw_text", (item.raw_text || "") + text);
    }

    function _flushStreamBuffer() {
        var index = streamThrottle.lastIndex;
        var content = streamThrottle.content;
        var targetKind = streamThrottle.targetKind;
        streamThrottle.content = "";
        streamThrottle.lastIndex = -1;
        streamThrottle.targetKind = "";
        if (content === "")
            return -1;

        var item = index >= 0 && index < chatModel.count ? chatModel.get(index) : null;
        var targetStillValid = item && !item.isUser && !item.isToolCall && !item.isReasoning && !item.isComplete
                               && (targetKind === "" || (targetKind === "thinking" && item.isThinking)
                                   || (targetKind === "answer" && !item.isThinking));
        if (!targetStillValid) {
            // The thinking row may be gone; re-locate the answer row.
            index = _findCurrentAnswerIndex();
            if (index < 0) {
                _appendAnswerPlaceholder();
                index = chatModel.count - 1;
            }
            item = chatModel.get(index);
        }

        var raw = item.isThinking ? content : (item.raw_text || "") + content;
        chatModel.set(index, {
            "text": raw,
            "raw_text": raw,
            "isUser": false,
            "isThinking": false,
            "isReasoning": false,
            "isToolCall": false,
            "isComplete": false,
            "toolCallId": "",
            "toolState": "",
            "historyIndex": -1
        });
        return index;
    }

    function _followLatestMessage() {
        _followAttempts = 0;
        _followStableFrames = 0;
        _followLastContentHeight = -1;
        id_chat_listview.userScrolledUp = false;
        id_chat_listview.showScrollToBottom = false;
        id_chat_listview.scrollToBottom();
        id_follow_latest_timer.restart();
    }

    function _scheduleScrollToBottom() {
        // 用户手动滚动时不自动贴底。
        if (id_chat_listview.userScrolledUp || id_chat_listview.userInteracting)
            return;
        if (streamThrottle.scrollScheduled)
            return;
        streamThrottle.scrollScheduled = true;
        Qt.callLater(function () {
            streamThrottle.scrollScheduled = false;
            id_chat_listview.autoFollowBottom();
        });
    }

    function _prepareSessionChange() {
        _attachmentReadSeq++;
        _preparingSend = false;
        clearAttachments();
        if (isGenerating && chatbot && typeof chatbot.cancelRequest === "function")
            chatbot.cancelRequest();
        else
            _resetStreamState();
        isGenerating = false;
    }

    function finalizeLastAssistantIfNeeded() {
        throttlingTimer.stop();
        _completeLastReasoningCard();
        _flushStreamBuffer();
        var lastIdx = chatModel.count - 1;
        if (lastIdx >= 0) {
            var lastItem = chatModel.get(lastIdx);
            if (!lastItem.isUser && !lastItem.isComplete && !lastItem.isThinking && !lastItem.isToolCall
                    && !lastItem.isReasoning) {
                var raw = lastItem.raw_text || "";
                chatModel.set(lastIdx, {
                    "text": "",
                    "raw_text": raw,
                    "isComplete": true,
                    "isThinking": false
                });
            }
        }
    }

    ChatToastBanner {
        id: toastBanner
        fontFamily: qmlGlobal.fontFamilyZhCn
    }

    Rectangle {
        anchors.fill: parent
        color: "#0E1621"
        z: -100
    }

    Component.onCompleted: {
        _ensureKeyboardPage(false);
        if (historyLoaded)
            return;
        historyLoaded = true;
        loadHistory();
        if (chatbot.mathRenderEnabled)
            _startMathServer();
        Qt.callLater(consumePendingVoiceChat);
    }
    Component.onDestruction: {
        _attachmentReadSeq++;
        if (_mathProbeRequest !== null)
            _mathProbeRequest.abort();
        resetCaptureMode();
    }

    function consumePendingVoiceChat() {
        var text = mod.pendingVoiceChatText.trim();
        if (text.length === 0 || _preparingSend || isGenerating)
            return;
        mod.pendingVoiceChatText = "";
        handleUserSend(text);
    }

    function loadHistory() {
        _resetStreamState();
        chatModel.clear();
        if (!chatbot || !chatbot.messages)
            return;
        var history = chatbot.messages;
        var toolNameMap = _buildToolNameMap(history, 0);
        for (var idx = 0; idx < history.length; idx++)
            _renderHistoryRow(history[idx], idx, toolNameMap);
        _layoutStabilizing = true;
        id_chat_listview.forceLayout();
        id_chat_listview.scrollToTop();
        id_layout_stabilize_timer.restart();
    }

    function _showCachedKeyboard() {
        if (!keyboardPageRef)
            return;
        _keyboardRequested = false;
        keyboardPageRef.placeHolderText = "输入消息...";
        // ✓ 可点与否由宿主决定（有预发送附件时空文字也要能确认）；预发送条随键盘隐藏，开页算一次就够。
        keyboardPageRef.allowEmptyAccept = attachedFilesModel.count > 0 || attachedMediaModel.count > 0;
        keyboardPageRef.resetInput(messageContent);
        keyboardPageRef.show();
        qmlGlobal.inputPageShowing = true;
    }

    function _initializeKeyboardPage(keyboardPage) {
        keyboardPageRef = keyboardPage;
        keyboardPage.backButtonClicked.connect(function () {
            qmlGlobal.inputPageShowing = false;
            if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                keyBoard.autoSendScan = keyBoard.autoSendScanConfig;
        });
        keyboardPage.inputFinished.connect(function (content) {
            if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                keyBoard.autoSendScan = keyBoard.autoSendScanConfig;
            // 有预发送附件时空文字也放行（只发图片/文件）；验证：选一张图 → 开键盘直接点 ✓ 应发出消息。
            var hasAttachment = attachedFilesModel.count > 0 || attachedMediaModel.count > 0;
            var text = content ? content.trim() : "";
            if (!hasAttachment && text.length === 0)
                return;
            handleUserSend(text);
        });
        if (_keyboardRequested)
            _showCachedKeyboard();
    }

    function _ensureKeyboardPage(showWhenReady) {
        if (showWhenReady)
            _keyboardRequested = true;
        if (keyboardPageRef) {
            if (_keyboardRequested)
                _showCachedKeyboard();
            return;
        }
        if (_keyboardComponent !== null || _keyboardIncubator !== null)
            return;

        var component = Qt.createComponent("qrc:/qml/YInputPage.qml", Component.Asynchronous);
        _keyboardComponent = component;
        function incubateKeyboard() {
            if (_keyboardComponent !== component || component.status !== Component.Ready)
                return;
            var incubator = component.incubateObject(id_page_pop_helper.containerItem,
                                                     { "visible": false, "destroyOnBack": false },
                                                     Qt.Asynchronous);
            _keyboardIncubator = incubator;
            function keyboardReady() {
                if (incubator.status === Component.Ready) {
                    _keyboardIncubator = null;
                    _keyboardComponent = null;
                    _initializeKeyboardPage(incubator.object);
                    component.destroy();
                } else if (incubator.status === Component.Error) {
                    _keyboardIncubator = null;
                    _keyboardComponent = null;
                    component.destroy();
                }
            }
            if (incubator.status === Component.Ready)
                keyboardReady();
            else
                incubator.onStatusChanged = keyboardReady;
        }
        if (component.status === Component.Ready)
            incubateKeyboard();
        else if (component.status === Component.Loading)
            component.statusChanged.connect(incubateKeyboard);
        else
            _keyboardComponent = null;
    }

    function showKeyboard() {
        if (qmlGlobal.inputPageShowing || id_chat_assistant_page.isGenerating || _preparingSend)
            return;
        if (typeof keyBoard !== 'undefined' && keyBoard !== null)
            keyBoard.autoSendScan = false;
        id_session_panel.close();
        id_message_index_panel.close();
        _ensureKeyboardPage(true);
    }

    // 只选图/文件、没打字时可直接发送：预发送条只在键盘收起时可见，没有草稿可带，文字按空处理。
    // 验证：只选图 → 点条右侧「发送」，应立刻出现用户气泡（缩略图 + "[图片]"）。
    function sendPendingAttachments() {
        if (_preparingSend || isGenerating)
            return;
        if (attachedFilesModel.count === 0 && attachedMediaModel.count === 0)
            return;

        var hasImage = false;
        for (var mi = 0; mi < attachedMediaModel.count; mi++) {
            if (attachedMediaModel.get(mi).type === "image_url") {
                hasImage = true;
                break;
            }
        }
        // 纯图片 + 模型不支持视觉：C++ 会剥掉图片（Backend::sendMessageWithMedia）只剩报错，先在这里拦住。
        if (hasImage && !chatbot.capVision && !chatbot.proxyVisionModelId) {
            toastBanner.warning("当前模型不支持视觉，请在模型设置中配置「视觉代理模型」");
            return;
        }
        handleUserSend("");
    }

    function handleUserSend(content) {
        if (_preparingSend || isGenerating)
            return;
        if (!chatbot.isAvailable) {
            toastBanner.error("请先在设置中配置 API 密钥");
            return;
        }

        var mediaParts = [];
        for (var mi = 0; mi < attachedMediaModel.count; mi++) {
            var mediaItem = attachedMediaModel.get(mi);
            if (mediaItem.type === "image_url")
                mediaParts.push({
                    "type": "image_url",
                    "url": mediaItem.url,
                    "label": mediaItem.label || "图片"
                });
            else if (mediaItem.type === "input_audio")
                mediaParts.push({
                    "type": "input_audio",
                    "data": mediaItem.data,
                    "format": mediaItem.format,
                    "label": mediaItem.label || "音频"
                });
        }

        var hasImageMedia = false;
        for (var miCheck = 0; miCheck < mediaParts.length; miCheck++) {
            if (mediaParts[miCheck].type === "image_url") {
                hasImageMedia = true;
                break;
            }
        }
        if (hasImageMedia && !chatbot.capVision && !chatbot.proxyVisionModelId) {
            // 空文字 + 只有图片：C++ 剥掉图片后只剩"没有可发送的文字或媒体内容"这条报错，先拦住。
            if ((!content || content.trim().length === 0) && attachedFilesModel.count === 0) {
                toastBanner.warning("当前模型不支持视觉，请在模型设置中配置「视觉代理模型」");
                return;
            }
            toastBanner.warning("当前模型不支持视觉，请在模型设置中配置「视觉代理模型」，本次将仅发送文字");
        }

        // 收集需异步读取的文件
        var fileItems = [];
        for (var fi = 0; fi < attachedFilesModel.count; fi++) {
            var fileItem = attachedFilesModel.get(fi);
            fileItems.push({
                path: fileItem.path,
                name: fileItem.name,
                language: fileItem.language
            });
        }
        clearAttachments();

        function sendMessageInternal(filesArray) {
            _preparingSend = false;
            var displayText = content;
            var filesJson = filesArray.length > 0 ? JSON.stringify(filesArray) : "";
            var nonImageLabels = [];
            var messageAttachments = [];
            for (var mediaIndex = 0; mediaIndex < mediaParts.length; mediaIndex++) {
                if (mediaParts[mediaIndex].type === "image_url")
                    messageAttachments.push({
                        "type": "image_url",
                        "source": mediaParts[mediaIndex].url,
                        "localPath": "",
                        "name": mediaParts[mediaIndex].label
                    });
                else
                    nonImageLabels.push(mediaParts[mediaIndex].label);
            }
            if (nonImageLabels.length > 0)
                displayText = (displayText ? displayText + "\n" : "") + nonImageLabels.join(" | ");

            // 空文字 + 只有附件时列表/落库/请求三处都要有占位（C++ 只在文字与附件都为空时报错）。
            // 占位文案必须与 C++ 落库的 content 逐字一致，否则行签名永不相等，会反复整轮重建。
            if (displayText.length === 0) {
                if (mediaParts.length > 0)
                    displayText = "[图片]";
                else if (filesArray.length > 0)
                    displayText = "请阅读附件内容";
            }
            for (var fileIndex = 0; fileIndex < filesArray.length; fileIndex++)
                messageAttachments.push({
                    "type": "file",
                    "localPath": filesArray[fileIndex].path,
                    "name": filesArray[fileIndex].name,
                    "mimeType": "text/plain",
                    "language": filesArray[fileIndex].language || "",
                    "size": filesArray[fileIndex].content ? filesArray[fileIndex].content.length : 0
                });

            var userModelIndex = chatModel.count;
            chatModel.append({
                "text": displayText,
                "attachmentsJson": JSON.stringify(messageAttachments),
                "isUser": true,
                "isComplete": true,
                "isThinking": false,
                // 与传给 C++ 的文本一致（含空文本时的占位），编辑回填与行签名比对都读它。
                "raw_text": displayText,
                "reasoning_text": "",
                "isToolCall": false,
                "toolCallId": "",
                "toolState": "",
                "historyIndex": -1
            });
            messageContent = "";

            chatModel.append({
                "text": "AI 正在思考...",
                "isUser": false,
                "isThinking": true,
                "isComplete": false,
                "raw_text": "",
                "isToolCall": false,
                "toolCallId": "",
                "toolState": "",
                "historyIndex": -1
            });

            id_chat_assistant_page.isGenerating = true;
            if (mediaParts.length > 0) {
                if (filesArray.length > 0) {
                    for (var requestFileIndex = 0; requestFileIndex < filesArray.length; requestFileIndex++)
                        mediaParts.push({
                            "type": "file",
                            "localPath": filesArray[requestFileIndex].path,
                            "name": filesArray[requestFileIndex].name,
                            "mimeType": "text/plain",
                            "language": filesArray[requestFileIndex].language || "",
                            "size": filesArray[requestFileIndex].content ? filesArray[requestFileIndex].content.length : 0
                        });
                }
                chatbot.sendMessageWithMedia(displayText, JSON.stringify(mediaParts));
            } else {
                chatbot.sendMessage(displayText, filesJson);
            }

            // 图片附件先按 data URL 建行、后端落盘后才有 localPath，而视觉代理是异步落库的
            // （此刻历史里最后一条可能还是上一条消息），所以只登记待补行，路径交给 messagesChanged。
            if (messageAttachments.length > 0) {
                _pendingAttachmentRow = userModelIndex;
                _pendingAttachmentText = displayText;
                _adoptPersistedAttachments();
            }

            if (typeof chatbot.getSessions === 'function') {
                var sessionsJson = chatbot.getSessions();
                try {
                    var data = JSON.parse(sessionsJson);
                    var activeId = data.activeSessionId;
                    if (activeId) {
                        var sessions = data.sessions || [];
                        for (var si = 0; si < sessions.length; si++) {
                            if (sessions[si].id === activeId && (sessions[si].messageCount || 0) <= 2) {
                                var autoTitle = displayText.substring(0, 20);
                                if (displayText.length > 20)
                                    autoTitle += "...";
                                chatbot.renameSession(activeId, autoTitle);
                                break;
                            }
                        }
                    }
                } catch (e) {}
            }
            _followLatestMessage();
        }

        sendMessageInternal(fileItems);
    }

    function _syncHistoryIndices() {
        if (!chatbot || !chatbot.messages)
            return;

        var history = chatbot.messages;
        var cursor = 0;

        function consumeToolTurn() {
            var start = cursor;
            if (cursor < history.length && history[cursor].role === "assistant"
                    && history[cursor].toolCallsJson) {
                cursor++;
            }
            while (cursor < history.length && history[cursor].role === "tool")
                cursor++;
            return cursor > start ? start : -1;
        }

        function consumeMessage(role) {
            while (cursor < history.length) {
                var message = history[cursor];
                if (message.role === role) {
                    var index = cursor;
                    cursor++;
                    return index;
                }
                if (message.role === "assistant" && message.toolCallsJson) {
                    consumeToolTurn();
                    continue;
                }
                if (message.role === "tool") {
                    cursor++;
                    continue;
                }
                cursor++;
            }
            return -1;
        }

        for (var rowIndex = 0; rowIndex < chatModel.count; rowIndex++) {
            var row = chatModel.get(rowIndex);
            var historyIndex = -1;
            if (row.isReasoning || row.isThinking) {
                historyIndex = -1;
            } else if (row.isToolCall) {
                historyIndex = consumeToolTurn();
            } else if (row.isUser) {
                historyIndex = consumeMessage("user");
            } else {
                historyIndex = consumeMessage("assistant");
            }
            if (row.historyIndex !== historyIndex)
                chatModel.setProperty(rowIndex, "historyIndex", historyIndex);
        }
    }

    function _cppIndex(qmlIndex) {
        _syncHistoryIndices();
        var item = chatModel.get(qmlIndex);
        if (item && item.historyIndex !== undefined && item.historyIndex >= 0)
            return item.historyIndex;
        return -1;
    }

    function deleteSingleMessage(index) {
        var cppIndex = _cppIndex(index);
        if (cppIndex < 0)
            return;
        chatModel.remove(index, 1);
        for (var i = index; i < chatModel.count; i++) {
            var it = chatModel.get(i);
            if (it && it.historyIndex !== undefined && it.historyIndex >= 0)
                chatModel.setProperty(i, "historyIndex", -1);
        }
        if (chatbot && typeof chatbot.deleteMessage === "function")
            chatbot.deleteMessage(cppIndex);
        Qt.callLater(function () {
            id_chat_listview.scrollToBottom();
        });
    }

    function regenerateMessage(index) {
        var cppIndex = _cppIndex(index);
        if (cppIndex < 0)
            return;
        let countToRemove = chatModel.count - index;
        if (countToRemove > 0)
            chatModel.remove(index, countToRemove);
        chatModel.append({
            "text": "AI 正在重新思考...",
            "raw_text": "",
            "isUser": false,
            "isComplete": false,
            "isThinking": true,
            "isToolCall": false,
            "toolCallId": "",
            "toolState": "",
            "historyIndex": -1
        });
        Qt.callLater(function () {
            id_chat_listview.scrollToBottom();
        });
        if (chatbot && typeof chatbot.regenerateMessage === "function")
            chatbot.regenerateMessage(cppIndex);

        id_chat_assistant_page.isGenerating = true;
    }

    function deleteMessageAndSubsequent(index) {
        var cppIndex = _cppIndex(index);
        if (cppIndex < 0)
            return;
        let countToRemove = chatModel.count - index;
        if (countToRemove > 0) {
            chatModel.remove(index, countToRemove);
            for (var i = index; i < chatModel.count; i++) {
                var it = chatModel.get(i);
                if (it && it.historyIndex !== undefined && it.historyIndex >= 0)
                    chatModel.setProperty(i, "historyIndex", -1);
            }
            if (chatbot && typeof chatbot.truncateHistory === "function")
                chatbot.truncateHistory(cppIndex);
            Qt.callLater(function () {
                id_chat_listview.scrollToBottom();
            });
        }
    }

    function navigateToMessageIndex(msgIndex) {
        if (msgIndex < 0 || msgIndex >= chatModel.count)
            return;
        id_navigation_target_expiry_timer.stop();
        id_message_jump_timer.stop();
        _pendingJumpIndex = msgIndex;
        _navigationTargetIndex = msgIndex;
        _navigationJumping = true;
        _jumpAttempts = 0;
        _jumpStableFrames = 0;
        id_chat_listview.currentIndex = msgIndex;
        id_chat_listview._programmaticScroll = true;
        id_chat_listview.positionViewAtIndex(msgIndex, ListView.Beginning);
        id_chat_listview._programmaticScroll = false;
        id_message_jump_timer.restart();
    }

    function editMessage(index) {
        var item = chatModel.get(index);
        var cppIndex = _cppIndex(index);
        if (cppIndex < 0)
            return;
        var oldContent = item.raw_text || "";

        // 回填原图片：不填编辑后图片就没了（attachmentsJson 由 _renderHistoryRow 或发送路径写入）。
        editAttachedMediaModel.clear();
        var oldAttachments = [];
        try {
            oldAttachments = JSON.parse(item.attachmentsJson || "[]");
        } catch (error) {
            oldAttachments = [];
        }
        for (var ai = 0; ai < oldAttachments.length; ai++) {
            var attachment = oldAttachments[ai];
            if (!attachment || attachment.type !== "image_url")
                continue;   // 文件附件不在编辑界面里，由 C++ 端原样保留（见 editMessageWithMedia）
            editAttachedMediaModel.append({
                "type": "image_url",
                "label": attachment.name || "图片",
                "source": attachment.source || attachment.url || "",
                "localPath": attachment.localPath || "",
                "name": attachment.name || "图片",
                "mimeType": attachment.mimeType || ""
            });
        }

        openInputPage("编辑消息...", oldContent, function (newContent) {
            // 一份数据两处用：气泡的 attachmentsJson 读 source，C++ 读 url/localPath；
            // 本地图只给 localPath，否则 file:// 会被当成远端 URL 发出去。
            var keptMedia = [];
            for (var mi = 0; mi < editAttachedMediaModel.count; mi++) {
                var mediaItem = editAttachedMediaModel.get(mi);
                var localPath = mediaItem.localPath || "";
                keptMedia.push({
                    "type": "image_url",
                    "source": mediaItem.source || "",
                    "url": localPath.length > 0 ? "" : (mediaItem.source || ""),
                    "localPath": localPath,
                    "name": mediaItem.name || "图片",
                    "mimeType": mediaItem.mimeType || ""
                });
            }
            editAttachedMediaModel.clear();

            // 文件/音频附件不在编辑界面里，但气泡读的是这份列表：拼回原行里非图片的条目，
            // 否则编辑一次文字，文件卡片就从气泡里消失（数据还在，只是界面看不到）。
            for (var oi = 0; oi < oldAttachments.length; oi++) {
                var kept = oldAttachments[oi];
                if (!kept || kept.type === "image_url")
                    continue;
                keptMedia.push(kept);
            }

            var finalText = newContent ? newContent.trim() : "";
            // 文字清空但图片还在：给一个占位，与 C++ 落库的 content 保持一致。
            if (finalText.length === 0 && keptMedia.length > 0)
                finalText = "[图片]";
            // 文字和图片都被清空：等同"删除本条"，不在编辑页里处理（保持原消息不动）。
            if (finalText.length === 0)
                return;

            let countToRemove = chatModel.count - index;
            if (countToRemove > 0)
                chatModel.remove(index, countToRemove);
            chatModel.append({
                "text": finalText,
                // MessageDelegate 靠这个字段渲染气泡里的缩略图，缺了图片就不显示。
                "attachmentsJson": JSON.stringify(keptMedia),
                "raw_text": finalText,
                "isUser": true,
                "isComplete": true,
                "isThinking": false,
                "isToolCall": false,
                "toolCallId": "",
                "toolState": "",
                "historyIndex": -1
            });
            chatModel.append({
                "text": "AI 正在思考...",
                "raw_text": "",
                "isUser": false,
                "isComplete": false,
                "isThinking": true,
                "isToolCall": false,
                "toolCallId": "",
                "toolState": "",
                "historyIndex": -1
            });
            Qt.callLater(function () {
                id_chat_listview.scrollToBottom();
            });
            // 图片全删时也要传 "[]"：后端只按这份列表增删图片、保留文件/音频附件
            // （旧接口 Backend::editMessage 会把 parts 整体清空）。
            if (chatbot && typeof chatbot.editMessageWithMedia === "function")
                chatbot.editMessageWithMedia(cppIndex, finalText, JSON.stringify(keptMedia));
            else if (chatbot && typeof chatbot.editMessage === "function")
                chatbot.editMessage(cppIndex, finalText);

            id_chat_assistant_page.isGenerating = true;
        }, editAttachedMediaModel);
    }

    YPagePopHelper {
        id: id_page_pop_helper
        z: 1000
        anchors.fill: parent
        isShowing: qmlGlobal.inputPageShowing
        objectName: "from_ChatAssistant.qml"
    }

    Item {
        id: id_main_content
        anchors.fill: parent
        visible: !qmlGlobal.inputPageShowing
        z: 1

        Rectangle {
            id: id_chat_container
            anchors.fill: parent
            color: "#0E1621"

            ListView {
                id: id_chat_listview
                anchors.fill: parent
                anchors.leftMargin: 44
                anchors.rightMargin: id_chat_assistant_page.chatListRightMargin
                anchors.topMargin: 2
                anchors.bottomMargin: 2

                clip: true
                model: chatModel
                spacing: 10
                // 缓存约 4 屏，避免常驻 delegate 过多。
                cacheBuffer: Math.min(1200, Math.max(600, Math.round(height * 4)))
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds

                add: Transition {
                    enabled: !id_chat_assistant_page.isGenerating && !id_chat_assistant_page._layoutStabilizing
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 150
                    }
                }
                displaced: Transition {
                    enabled: !id_chat_assistant_page.isGenerating && !id_chat_assistant_page._layoutStabilizing
                    NumberAnimation {
                        properties: "y"
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }

                property bool userScrolledUp: false
                // 是否显示「滑到底部」按钮。
                property bool showScrollToBottom: false
                property bool _programmaticScroll: false
                property bool _flicking: false
                // 用户是否正在拖动或滑动列表。
                readonly property bool userInteracting: dragging || flicking
                readonly property real bottomThreshold: 50
                // 显示按钮的离底距离阈值。
                readonly property real scrollHintDistance: Math.max(height * 1.2, 120)
                // 显示按钮的最小滑动速度（px/ms）。
                readonly property real scrollHintVelocity: 0.5
                property real _lastTrackedContentY: 0
                property double _lastTrackedTime: 0
                // 手势开始时只记录速度基准。
                property bool _trackingFresh: true

                // ── 阅读位置锚定 ──
                // 公式异步出图，成文后高度还会变很多次：用户不在底部时让视口顶部那条消息停在原处。
                property int _readAnchorIndex: -1
                property real _readAnchorOffset: 0

                // 顶部可能落在消息之间的间隙里，故按几个探针点找首条消息，都取不到就退回视口中线；
                // 否则锚点失效后视口只能被边界钳制，看起来就像被拽回底部。
                function probeViewportIndex() {
                    var probes = [8, 2, 18, 28, 40];
                    for (var i = 0; i < probes.length; i++) {
                        var idx = indexAt(4, contentY + probes[i]);
                        if (idx >= 0)
                            return idx;
                    }
                    return indexAt(width / 2, contentY + height / 2);
                }

                function captureReadAnchor() {
                    if (moving || !userScrolledUp) {
                        _readAnchorIndex = -1;
                        return;
                    }
                    var index = probeViewportIndex();
                    if (index < 0) {
                        _readAnchorIndex = -1;
                        return;
                    }
                    var item = itemAtIndex(index);
                    if (!item) {
                        _readAnchorIndex = -1;
                        return;
                    }
                    _readAnchorIndex = index;
                    _readAnchorOffset = item.y - contentY;
                }

                // 返回 false 表示锚点已经失效，调用方需要重新采集。
                function restoreReadAnchor() {
                    if (_readAnchorIndex < 0 || moving || !userScrolledUp)
                        return false;

                    var maxY = Math.max(originY, originY + contentHeight - height);
                    var item = itemAtIndex(_readAnchorIndex);
                    if (!item && _readAnchorIndex < count) {
                        // 目标消息不在缓存里（内容收缩后列表把视口钳到底部就会这样，那正是
                        // "突然跳到最底下"的来源）：用 positionViewAtIndex 按模型定位并建出委托。
                        _programmaticScroll = true;
                        positionViewAtIndex(_readAnchorIndex, ListView.Beginning);
                        _programmaticScroll = false;
                        item = itemAtIndex(_readAnchorIndex);
                    }
                    if (!item)
                        return false;

                    var targetY = Math.max(originY, Math.min(item.y - _readAnchorOffset, maxY));
                    if (Math.abs(targetY - contentY) > 0.5) {
                        _programmaticScroll = true;
                        contentY = targetY;
                        _programmaticScroll = false;
                    }
                    return true;
                }

                onMovementStarted: {
                    // 只处理真实手势产生的滚动。
                    if (!dragging && !flicking)
                        return;

                    _flicking = true;
                    id_bottom_scroll_animation.stop();
                    id_read_anchor_timer.stop();
                    _programmaticScroll = false;
                    if (id_rich_content_anchor_timer.running)
                        id_rich_content_anchor_timer.stop();
                    if (id_follow_latest_timer.running)
                        id_follow_latest_timer.stop();
                    if (_navigationTargetIndex >= 0) {
                        _navigationTargetIndex = -1;
                        _navigationJumping = false;
                        _pendingJumpIndex = -1;
                        id_navigation_target_expiry_timer.stop();
                    }
                    if (_layoutStabilizing) {
                        _layoutStabilizing = false;
                        id_layout_stabilize_timer.stop();
                    }
                    _lastTrackedContentY = contentY;
                    _lastTrackedTime = Date.now();
                    _trackingFresh = true;
                }
                onMovementEnded: {
                    _flicking = false;
                    updateUserScrolledState();
                    // 手势结束时记下阅读位置，之后的异步高度变化都围着它还原。
                    captureReadAnchor();
                    id_list_bounds_guard_timer.restart();
                }
                onContentYChanged: {
                    if (_programmaticScroll)
                        return;
                    // 只在真实手势下取消导航跳转。
                    if (id_chat_assistant_page._navigationTargetIndex >= 0 && (_flicking || dragging)) {
                        id_chat_assistant_page._navigationTargetIndex = -1;
                        id_chat_assistant_page._navigationJumping = false;
                        id_chat_assistant_page._pendingJumpIndex = -1;
                        id_message_jump_timer.stop();
                    }
                    // 只跟踪真实手势的位移。
                    if (!_flicking && !dragging)
                        return;
                    trackScrollDirection();
                }

                function updateUserScrolledState() {
                    var distToEnd = contentHeight - contentY - height;
                    userScrolledUp = distToEnd > bottomThreshold;
                    if (!userScrolledUp)
                        showScrollToBottom = false;
                }

                // 按 contentY 的方向与速度决定按钮显隐。
                function trackScrollDirection() {
                    var now = Date.now();
                    var distToEnd = contentHeight - contentY - height;
                    userScrolledUp = distToEnd > bottomThreshold;
                    if (!userScrolledUp) {
                        showScrollToBottom = false;
                        _trackingFresh = true;
                        return;
                    }

                    if (_trackingFresh) {
                        _trackingFresh = false;
                        _lastTrackedContentY = contentY;
                        _lastTrackedTime = now;
                        return;
                    }

                    // 采样间隔不足时先跳过本次计算。
                    var dt = now - _lastTrackedTime;
                    if (dt < 48)
                        return;

                    var dy = contentY - _lastTrackedContentY;
                    _lastTrackedContentY = contentY;
                    _lastTrackedTime = now;

                    if (dy < -1) {
                        // 往历史方向滑动时收起按钮。
                        showScrollToBottom = false;
                        return;
                    }
                    if (dy > 1 && distToEnd > scrollHintDistance && (dy / dt) >= scrollHintVelocity)
                        showScrollToBottom = true;
                }

                function scrollToTop() {
                    id_bottom_scroll_animation.stop();
                    _programmaticScroll = true;
                    positionViewAtBeginning();
                    _programmaticScroll = false;
                    userScrolledUp = false;
                    showScrollToBottom = false;
                }

                // 流式回复时自动贴底。
                function autoFollowBottom() {
                    if (userScrolledUp || userInteracting)
                        return;
                    id_bottom_scroll_animation.stop();
                    _programmaticScroll = true;
                    positionViewAtEnd();
                    _programmaticScroll = false;
                }

                // 用户主动跳到底部。
                function scrollToBottom(animated) {
                    id_bottom_scroll_animation.stop();
                    var targetY = Math.max(originY, originY + contentHeight - height);
                    if (animated && Math.abs(targetY - contentY) > 1) {
                        _programmaticScroll = true;
                        id_bottom_scroll_animation.from = contentY;
                        id_bottom_scroll_animation.to = targetY;
                        id_bottom_scroll_animation.start();
                    } else {
                        _programmaticScroll = true;
                        positionViewAtEnd();
                        _programmaticScroll = false;
                    }
                    userScrolledUp = false;
                    showScrollToBottom = false;
                }

                NumberAnimation {
                    id: id_bottom_scroll_animation
                    target: id_chat_listview
                    property: "contentY"
                    duration: 90
                    easing.type: Easing.OutQuad
                    onStopped: id_chat_listview._programmaticScroll = false
                }

                onContentHeightChanged: {
                    if (_layoutStabilizing)
                        id_layout_stabilize_timer.restart();
                    // 内容高度变化（公式出图、流式增长、整轮重建）时用户不在底部就按锚点还原，不交给边界钳制。
                    if (!moving && userScrolledUp) {
                        if (!restoreReadAnchor())
                            captureReadAnchor();
                        id_read_anchor_timer.hold();
                    } else if (!moving && !id_rich_content_anchor_timer.running) {
                        id_list_bounds_guard_timer.restart();
                    }
                }

                header: Item {
                    width: id_chat_listview.width
                    height: 10
                }

                footer: Item {
                    height: 16
                    width: id_chat_listview.width
                }

                // 「滑到底部」按钮。
                Rectangle {
                    width: 88
                    height: 26
                    radius: 13
                    color: "#2B5278"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    opacity: id_chat_listview.showScrollToBottom ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }

                    Text {
                        text: "滑到底部"
                        color: "white"
                        font.pixelSize: 11
                        font.family: qmlGlobal.fontFamilyZhCn
                        anchors.centerIn: parent
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: id_chat_listview.scrollToBottom(true)
                    }
                }

                delegate: MessageDelegate {
                    text: model.text
                    rawText: model.raw_text
                    reasoningText: model.reasoning_text || ""
                    isUser: model.isUser
                    isComplete: model.isComplete
                    isThinking: model.isThinking
                    isReasoning: model.isReasoning || false
                    isToolCall: model.isToolCall
                    toolState: model.toolState
                    attachmentsJson: model.attachmentsJson || "[]"
                    mathServerAvailable: id_chat_assistant_page.mathServerAvailable
                    textureCacheEnabled: id_chat_assistant_page.bubbleTextureCacheEnabled
                    renderMode: chatbot.bubbleRenderMode
                    listMoving: id_chat_listview.moving
                    listScrolledUp: id_chat_listview.userScrolledUp
                    navigationJumping: id_chat_assistant_page._navigationJumping
                    messageIndex: model.index
                    listWidth: id_chat_listview.width
                    listContentY: id_chat_listview.contentY
                    listViewportHeight: id_chat_listview.height
                    richPreloadMargin: id_chat_listview.height * 2
                    fontFamily: qmlGlobal.fontFamilyZhCn
                    onLongPressed: id_context_menu.showMenu(globalX, globalY, msgIndex)
                    onAttachmentOpenRequested: function (attachmentType, localPath) {
                        if (attachmentType === "image_url") {
                            if (imageViewer.openAbsolute(localPath))
                                id_pop_container.show("audiopages/FileManagerImageViewer");
                            else
                                toastBanner.error("图片附件不可用");
                        } else if (attachmentType === "file") {
                            if (textReader.openAbsolute(localPath))
                                id_pop_container.show("audiopages/FileManagerTextViewer");
                            else
                                toastBanner.error("文本附件不可用");
                        }
                    }
                    onToolCardExpansionStarted: {
                        if (expanding)
                            id_tool_expansion_anchor_timer.preserveViewport();
                    }
                    onRichContentCommitStarted: function (itemY) {
                        if (id_chat_assistant_page._navigationTargetIndex >= 0) {
                            id_chat_assistant_page._pendingJumpIndex = id_chat_assistant_page._navigationTargetIndex;
                            id_chat_assistant_page._jumpAttempts = 0;
                            id_chat_assistant_page._jumpStableFrames = 0;
                            id_chat_assistant_page._navigationJumping = true;
                            id_navigation_target_expiry_timer.stop();
                            id_message_jump_timer.restart();
                        } else {
                            id_chat_assistant_page._beginRichContentCommit();
                        }
                    }
                }
            }
        }

        // 左边条：靠声明顺序压在按钮之下。
        EdgeSwipeGesture {
            id: id_left_edge_gesture
            edge: "left"
            edgeWidth: id_chat_assistant_page.rightGestureWidth
            gestureEnabled: !qmlGlobal.inputPageShowing
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            onTriggered: {
                if (id_session_panel.isOpen)
                    id_session_panel.close();
                else {
                    id_message_index_panel.close();
                    id_session_panel.open();
                }
            }
            onTriggeredOutward: {
                if (id_session_panel.isOpen)
                    id_session_panel.close();
            }
        }
        // 右边条：宽度正好铺满气泡右侧留白。
        EdgeSwipeGesture {
            id: id_right_edge_gesture
            edge: "right"
            edgeWidth: id_chat_assistant_page.rightGestureWidth
            gestureEnabled: !qmlGlobal.inputPageShowing
            anchors {
                right: parent.right
                top: parent.top
                bottom: parent.bottom
            }
            onTriggered: {
                if (id_message_index_panel.isOpen)
                    id_message_index_panel.close();
                else {
                    id_session_panel.close();
                    id_message_index_panel.open();
                }
            }
            onTriggeredOutward: {
                if (id_message_index_panel.isOpen)
                    id_message_index_panel.close();
            }
        }

        Column {
            id: id_empty_state
            anchors.centerIn: parent
            spacing: 10
            visible: chatModel.count === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "💬"
                font.pixelSize: 40
                font.family: qmlGlobal.fontFamilyZhCn
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "AI 助手"
                font.pixelSize: 15
                color: "#FFFFFF"
                font.family: qmlGlobal.fontFamilyZhCn
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "点击左侧键盘开始对话"
                font.pixelSize: 12
                color: "#5A6B7D"
                font.family: qmlGlobal.fontFamilyZhCn
            }
        }

        YVerticalTitleBar {
            id: id_title_bar
            onCallBack: backButtonClicked()
        }

        Column {
            id: id_column_sidebar
            anchors {
                left: parent.left
                bottom: parent.bottom
                leftMargin: 10
                bottomMargin: 20
            }
            spacing: 8

            YIconButton {
                width: 28
                height: 28
                radius: 8
                realSource: "qrc:/images/chat/keyboard"
                sourceSize: Qt.size(18, 18)
                color: "#182533"
                border.width: 1
                border.color: "#2B3A4A"
                onValidClicked: showKeyboard()
            }
            YIconButton {
                width: 28
                height: 28
                radius: 8
                realSource: "qrc:/images/chat/more"
                sourceSize: Qt.size(18, 18)
                color: "#182533"
                border.width: 1
                border.color: "#2B3A4A"
                onValidClicked: id_more_menu.show()
            }
            YIconButton {
                width: 28
                height: 28
                radius: 8
                realSource: "qrc:/images/chat/settings"
                sourceSize: Qt.size(18, 18)
                color: "#182533"
                border.width: 1
                border.color: "#2B3A4A"
                onValidClicked: id_pop_container.show("settingpages/ChatAssistantSettings")
            }
        }

        AttachmentChipsBar {
            id: fileChipsBar
            anchors {
                left: id_column_sidebar.right
                leftMargin: 6
                right: parent.right
                rightMargin: 6
                bottom: parent.bottom
                bottomMargin: 6
            }
            filesModel: attachedFilesModel
            mediaModel: attachedMediaModel
            fontFamily: qmlGlobal.fontFamilyZhCn
            // 预发送区是"只选图/文件、没打字"时唯一的发送入口（键盘页的 ✓ 被输入文本长度卡着）。
            showSendButton: attachedFilesModel.count > 0 || attachedMediaModel.count > 0
            onSendRequested: sendPendingAttachments()
            visible: attachedFilesModel.count > 0 || attachedMediaModel.count > 0
            z: 100
        }

        Rectangle {
            id: id_stop_button
            width: 28
            height: 28
            radius: 8
            color: "#182533"
            border.width: 1
            border.color: "#2B3A4A"
            visible: id_chat_assistant_page.isGenerating || id_chat_assistant_page._preparingSend
            opacity: visible ? 1.0 : 0.0
            anchors {
                right: parent.right
                rightMargin: 10
                bottom: parent.bottom
                bottomMargin: 20
            }
            z: 100

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            Canvas {
                id: stopIcon
                anchors.centerIn: parent
                width: 16
                height: 16
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = "#FF6B6B";
                    ctx.fillRect(2, 2, 12, 12);
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (id_chat_assistant_page._preparingSend) {
                        id_chat_assistant_page._attachmentReadSeq++;
                        id_chat_assistant_page._preparingSend = false;
                        toastBanner.warning("已取消发送");
                    } else {
                        chatbot.cancelRequest();
                    }
                }
            }
        }

        MoreMenuPopup {
            id: id_more_menu
            fontFamily: qmlGlobal.fontFamilyZhCn
            searchEnabled: chatbot.searchEnabled
            searchConfigured: chatbot.searchConfigured
            onWebSearchToggled: {
                if (!chatbot.searchConfigured) {
                    toastBanner.warning("请先在设置中配置搜索服务的 API Key");
                    return;
                }
                chatbot.searchEnabled = !chatbot.searchEnabled;
                isSearchEnabled = chatbot.searchEnabled;
            }
            onFileReferenceRequested: {
                if (typeof qmlGlobal !== 'undefined' && qmlGlobal !== null) {
                    qmlGlobal.tempFileSelectorConfig = {
                        allowMultiSelect: false,
                        fileExtensions: ["txt", "md", "json", "py", "js", "ts", "qml", "cpp", "h", "c", "java", "html", "css"]
                    };
                }
                id_pop_container.show('audiopages/FileManagerSelector');
            }
            onNewConversationRequested: {
                if (chatbot) {
                    _prepareSessionChange();
                    chatbot.createSession("新对话");
                }
            }
            onAttachImageRequested: {
                captureModeActive = true;
                if (typeof cameraCapture !== 'undefined' && cameraCapture !== null)
                    cameraCapture.captureEnabled = true;
                id_pop_container.show('assistant/dialogs/CapturePreviewPage');
            }
        }

        ChatSessionListPanel {
            id: id_session_panel
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            z: 200

            onSessionSelected: {
                if (typeof chatbot !== 'undefined' && chatbot !== null) {
                    _prepareSessionChange();
                    chatbot.switchSession(sessionId);
                }
            }
            onNewSessionRequested: {
                if (typeof chatbot !== 'undefined' && chatbot !== null) {
                    _prepareSessionChange();
                    chatbot.createSession("新对话");
                }
            }
            onRenameSessionRequested: {
                openInputPage("重命名会话", sessionTitle, function (newTitle) {
                    if (newTitle && newTitle.trim().length > 0 && typeof chatbot !== 'undefined' && chatbot !== null) {
                        chatbot.renameSession(sessionId, newTitle.trim());
                        id_session_panel.refreshSessions();
                    }
                });
            }
            onCloseRequested: close()
        }

        ChatMessageIndexPanel {
            id: id_message_index_panel
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            z: 200
            messageModel: chatModel
            fontFamily: qmlGlobal.fontFamilyZhCn

            onNavigateToMessage: navigateToMessageIndex(messageIndex)
            onCloseRequested: close()
        }
    }

    Timer {
        id: id_navigation_target_expiry_timer
        interval: 1200
        repeat: false
        onTriggered: {
            _navigationTargetIndex = -1;
            _navigationJumping = false;
            _pendingJumpIndex = -1;
            id_message_jump_timer.stop();
        }
    }

    Timer {
        id: highlightTimer
        interval: 1500
        repeat: false
        onTriggered: id_chat_listview.currentIndex = -1
    }

    Timer {
        id: id_rich_content_anchor_timer
        property int anchorIndex: -1
        property real anchorOffset: 0
        property bool pinBottom: false
        property int ticks: 0
        property int stableFrames: 0
        property real lastContentHeight: -1
        interval: 16
        repeat: true

        function beginTracking() {
            ticks = 0;
            stableFrames = 0;
            lastContentHeight = -1;
            restart();
        }

        onTriggered: {
            if (id_chat_listview.moving) {
                stop();
                anchorIndex = -1;
                return;
            }
            var minY = id_chat_listview.originY;
            var maxY = Math.max(minY, minY + id_chat_listview.contentHeight - id_chat_listview.height);
            var currentY = isFinite(id_chat_listview.contentY) ? id_chat_listview.contentY : minY;
            var targetY = Math.max(minY, Math.min(currentY, maxY));
            if (pinBottom) {
                targetY = maxY;
            } else if (anchorIndex >= 0) {
                var anchorItem = id_chat_listview.itemAtIndex(anchorIndex);
                if (anchorItem)
                    targetY = Math.max(minY, Math.min(anchorItem.y - anchorOffset, maxY));
            }
            id_chat_listview._programmaticScroll = true;
            id_chat_listview.contentY = targetY;
            id_chat_listview._programmaticScroll = false;

            var currentHeight = id_chat_listview.contentHeight;
            if (lastContentHeight >= 0 && Math.abs(currentHeight - lastContentHeight) <= 1)
                stableFrames++;
            else
                stableFrames = 0;
            lastContentHeight = currentHeight;
            ticks++;
            if ((ticks >= 10 && stableFrames >= 3) || ticks >= 30) {
                stop();
                anchorIndex = -1;
                id_list_bounds_guard_timer.restart();
            }
        }
    }

    Timer {
        id: id_list_bounds_guard_timer
        interval: 0
        repeat: false
        onTriggered: {
            if (id_chat_listview.moving || id_rich_content_anchor_timer.running)
                return;
            // 用户不在底部时只还原阅读位置：内容高度收缩时直接钳制 contentY 会把视口掼到底部。
            if (id_chat_listview.userScrolledUp && id_chat_listview.restoreReadAnchor())
                return;
            // 只把 contentY 夹回边界，不做强排。
            var minY = id_chat_listview.originY;
            var maxY = Math.max(minY, minY + id_chat_listview.contentHeight - id_chat_listview.height);
            var currentY = isFinite(id_chat_listview.contentY) ? id_chat_listview.contentY : minY;
            var boundedY = Math.max(minY, Math.min(currentY, maxY));
            if (!isFinite(id_chat_listview.contentY) || Math.abs(boundedY - id_chat_listview.contentY) > 0.5) {
                id_chat_listview._programmaticScroll = true;
                id_chat_listview.contentY = boundedY;
                id_chat_listview._programmaticScroll = false;
            }
            id_chat_listview.returnToBounds();
        }
    }

    // 内容高度连续变化（公式陆续出图）时按锚点还原几帧，等高度稳定后重新采集锚点。
    Timer {
        id: id_read_anchor_timer
        interval: 16
        repeat: true
        property int ticks: 0

        function hold() {
            ticks = 0;
            if (!running)
                restart();
        }

        onTriggered: {
            ticks++;
            var restored = id_chat_listview.restoreReadAnchor();
            if (!restored || id_chat_listview.moving || ticks >= 10) {
                stop();
                id_chat_listview.captureReadAnchor();
                id_list_bounds_guard_timer.restart();
            }
        }
    }

    Timer {
        id: id_tool_expansion_anchor_timer
        property real anchorContentY: 0
        property int ticks: 0
        interval: 20
        repeat: true

        function preserveViewport() {
            anchorContentY = id_chat_listview.contentY;
            ticks = 0;
            restart();
        }

        onTriggered: {
            if (ticks === 0)
                id_chat_listview.forceLayout();
            var maxY = Math.max(id_chat_listview.originY,
                                id_chat_listview.originY + id_chat_listview.contentHeight - id_chat_listview.height);
            id_chat_listview._programmaticScroll = true;
            id_chat_listview.contentY = Math.max(id_chat_listview.originY, Math.min(anchorContentY, maxY));
            id_chat_listview._programmaticScroll = false;
            ticks++;
            if (ticks >= 10)
                stop();
        }
    }

    Timer {
        id: id_follow_latest_timer
        interval: 40
        repeat: true
        onTriggered: {
            // 用户已手动滚动时停止自动跟随。
            if (id_chat_listview.userScrolledUp || id_chat_listview.userInteracting) {
                stop();
                return;
            }
            id_chat_listview.autoFollowBottom();
            _followAttempts++;

            var sameHeight = Math.abs(id_chat_listview.contentHeight - _followLastContentHeight) <= 1;
            var targetY = Math.max(id_chat_listview.originY,
                                   id_chat_listview.originY + id_chat_listview.contentHeight - id_chat_listview.height);
            var atBottom = Math.abs(targetY - id_chat_listview.contentY) <= 1;
            _followStableFrames = sameHeight && atBottom ? _followStableFrames + 1 : 0;
            _followLastContentHeight = id_chat_listview.contentHeight;
            if ((_followAttempts >= 6 && _followStableFrames >= 3) || _followAttempts >= 12)
                stop();
        }
    }

    Timer {
        id: id_message_jump_timer
        interval: 20
        repeat: true
        onTriggered: {
            var index = _pendingJumpIndex;
            if (index < 0 || index >= chatModel.count) {
                stop();
                _pendingJumpIndex = -1;
                _navigationTargetIndex = -1;
                _navigationJumping = false;
                return;
            }

            id_chat_listview.forceLayout();
            id_chat_listview._programmaticScroll = true;
            id_chat_listview.positionViewAtIndex(index, ListView.Beginning);
            id_chat_listview._programmaticScroll = false;
            _jumpAttempts++;

            var targetItem = id_chat_listview.itemAtIndex(index);
            var expectedY = targetItem !== null
                          ? ChatNavigation.clampedTargetY(id_chat_listview.originY,
                                                          id_chat_listview.contentHeight,
                                                          id_chat_listview.height,
                                                          targetItem.y)
                          : id_chat_listview.originY;
            var aligned = targetItem !== null && Math.abs(expectedY - id_chat_listview.contentY) <= 1;
            _jumpStableFrames = aligned ? _jumpStableFrames + 1 : 0;
            if (_jumpStableFrames >= 2 || _jumpAttempts >= 40) {
                stop();
                _pendingJumpIndex = -1;
                _navigationJumping = false;
                id_navigation_target_expiry_timer.restart();
                highlightTimer.restart();
            }
        }
    }

    Timer {
        id: generationDoneTimer
        interval: 200
        repeat: false
        onTriggered: {
            id_chat_assistant_page.isGenerating = false;
            consumePendingVoiceChat();
        }
    }

    Timer {
        id: id_layout_stabilize_timer
        interval: 300
        repeat: false
        onTriggered: {
            if (_layoutStabilizing) {
                id_chat_listview.forceLayout();
                id_chat_listview.scrollToTop();
                _layoutStabilizing = false;
            }
        }
    }

    YDynamicPageStack {
        id: id_pop_container
        anchors.fill: parent
        z: 500
        visible: popItemObject !== null
        logTag: "ChatAssistant"

        function show(tpage) {
            function restoreAutoSend() {
                if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                    keyBoard.autoSendScan = keyBoard.autoSendScanConfig;
            }
            function newComponentInit(incubatorObject) {
                if (!incubatorObject) {
                    restoreAutoSend();
                    newComponent.destroy();
                    return;
                }

                registerPage(incubatorObject, tpage, {
                    "pageIndex": PageIndex.ChatAssistant,
                    "closeOnHomeRelease": true,
                    "component": newComponent,
                    "cleanups": [restoreAutoSend]
                });
                incubatorObject.show();
            }
            closeSameItem(tpage);
            if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                keyBoard.autoSendScan = false;
            var componentPath = "./%1.qml".arg(tpage);
            var newComponent = Qt.createComponent(componentPath);
            if (newComponent.status === Component.Ready) {
                var incubator = newComponent.incubateObject(id_pop_container);
                if (incubator.status !== Component.Ready) {
                    incubator.onStatusChanged = function (s) {
                        if (s === Component.Ready)
                            newComponentInit(incubator.object);
                        else if (s === Component.Error) {
                            restoreAutoSend();
                            newComponent.destroy();
                        }
                    };
                } else {
                    newComponentInit(incubator.object);
                }
            } else {
                console.error("Component Error: " + newComponent.errorString());
                restoreAutoSend();
                newComponent.destroy();
            }
        }
    }

    ListModel {
        id: chatModel
        dynamicRoles: true
    }

    QtObject {
        id: streamThrottle
        property string content: ""
        property int lastIndex: -1
        property string targetKind: ""
        property string reasoning: ""
        property int reasoningIndex: -1
        property bool scrollScheduled: false
        property bool endProcessed: false
    }

    Timer {
        id: throttlingTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (_flushStreamBuffer() >= 0)
                _scheduleScrollToBottom();
        }
    }

    Timer {
        id: reasoningFlushTimer
        interval: 60
        repeat: false
        onTriggered: _flushReasoningBuffer()
    }

    Connections {
        target: mod
        function onPendingVoiceChatTextChanged() {
            if (id_chat_assistant_page.visible)
                Qt.callLater(consumePendingVoiceChat);
        }
    }

    Connections {
        target: chatbot
        ignoreUnknownSignals: true

        function onMessageReceived(content, isComplete) {
            _toolCallActive = false;
            _completeLastReasoningCard();
            // 非流式回复的终态事件。
            if (!isComplete)
                return;
            // 同一次回复只写一次。
            if (!streamThrottle.endProcessed) {
                var lastIndex = chatModel.count - 1;
                if (lastIndex < 0 || chatModel.get(lastIndex).isUser
                        || chatModel.get(lastIndex).isToolCall || chatModel.get(lastIndex).isReasoning)
                    lastIndex = _appendAnswerPlaceholder();
                chatModel.set(lastIndex, {
                    "text": "",
                    "raw_text": content,
                    "isComplete": true,
                    "isThinking": false,
                    "isReasoning": false
                });
                streamThrottle.endProcessed = true;
            }
            _rebuildCurrentTurnRows();
            // 保证生成态总能收尾。
            generationDoneTimer.restart();
        }
        function onReasoningChunk(content) {
            if (!content)
                return;

            // 追加到已有思维链行，等定时器合并写入。
            if (streamThrottle.reasoningIndex >= 0
                    && streamThrottle.reasoningIndex === _activeReasoningIndex) {
                streamThrottle.reasoning += content;
                if (!reasoningFlushTimer.running)
                    reasoningFlushTimer.start();
                return;
            }

            // Flush buffered answer text before changing rows.
            _flushReasoningBuffer();
            if (streamThrottle.content !== "")
                _flushStreamBuffer();

            var lastIndex = chatModel.count - 1;
            if (lastIndex >= 0 && chatModel.get(lastIndex).isReasoning) {
                _activeReasoningIndex = lastIndex;
                streamThrottle.reasoningIndex = lastIndex;
                streamThrottle.reasoning += content;
                if (!reasoningFlushTimer.running)
                    reasoningFlushTimer.start();
                return;
            }
            if (lastIndex >= 0 && chatModel.get(lastIndex).isThinking)
                chatModel.remove(lastIndex);

            // Keep late reasoning before the answer row.
            var answerIndex = _findCurrentAnswerIndex();
            var reasoningIndex = -1;
            if (answerIndex >= 0) {
                chatModel.insert(answerIndex, _makeReasoningEntry(""));
                reasoningIndex = answerIndex;
            } else {
                chatModel.append(_makeReasoningEntry(""));
                reasoningIndex = chatModel.count - 1;
            }
            _activeReasoningIndex = reasoningIndex;
            streamThrottle.reasoningIndex = reasoningIndex;
            streamThrottle.reasoning += content;
            if (!reasoningFlushTimer.running)
                reasoningFlushTimer.start();
            _scheduleScrollToBottom();
        }
        function onStreamChunk(content) {
            streamThrottle.endProcessed = false;
            _completeLastReasoningCard();
            // 同一条回答行持续接收时的快路径。
            if (streamThrottle.lastIndex >= 0 && streamThrottle.targetKind === "answer"
                    && streamThrottle.lastIndex === chatModel.count - 1) {
                streamThrottle.content += content;
                if (!throttlingTimer.running)
                    throttlingTimer.start();
                return;
            }
            var lastIndex = chatModel.count - 1;
            if (lastIndex < 0)
                return;
            var item = chatModel.get(lastIndex);
            if (item.isUser)
                return;
            if (item.isToolCall || item.isReasoning || item.isComplete) {
                lastIndex = _appendAnswerPlaceholder();
                item = chatModel.get(lastIndex);
            }
            // Keep the thinking bubble until the chunk is flushed.
            if (streamThrottle.lastIndex >= 0 && streamThrottle.lastIndex !== lastIndex)
                _flushStreamBuffer();
            streamThrottle.content += content;
            streamThrottle.lastIndex = lastIndex;
            streamThrottle.targetKind = item.isThinking ? "thinking" : "answer";
            if (!throttlingTimer.running)
                throttlingTimer.start();
        }
        function onStreamStart() {
            _toolCallActive = false;
            _resetStreamState();
        }
        function onMessagesChanged() {
            _syncHistoryIndices();
            // 后端落盘图片附件后走这个信号，借它把气泡里那一行的 localPath 补上。
            _adoptPersistedAttachments();
        }
        function onImageAttachmentsReceived(attachments) {
            for (var index = chatModel.count - 1; index >= 0; index--) {
                var item = chatModel.get(index);
                if (item.isUser || item.isToolCall || item.isReasoning)
                    continue;
                chatModel.setProperty(index, "attachmentsJson", JSON.stringify(attachments));
                _scheduleScrollToBottom();
                return;
            }
        }
        function onStreamEnd() {
            throttlingTimer.stop();
            reasoningFlushTimer.stop();
            _completeLastReasoningCard();
            _flushStreamBuffer();
            var lastIndex = chatModel.count - 1;
            if (lastIndex >= 0) {
                var item = chatModel.get(lastIndex);
                if (item.isThinking && item.raw_text === "") {
                    // 一个字段都没产出，收掉空占位。
                    chatModel.remove(lastIndex);
                } else if (!item.isUser && !item.isToolCall && !item.isReasoning) {
                    var rawContent = item.raw_text;
                    chatModel.set(lastIndex, {
                        "text": "",
                        "raw_text": rawContent,
                        "isComplete": true,
                        "isThinking": false
                    });
                    _scheduleScrollToBottom();
                }
            }
            if (!_toolCallActive)
                generationDoneTimer.restart();
            streamThrottle.endProcessed = true;
            // 最后按落库历史校正这一轮。
            _rebuildCurrentTurnRows();
        }
        function onErrorOccurred(error) {
            _completeLastReasoningCard();
            _resetStreamState();
            _preparingSend = false;
            _toolCallActive = false;
            toastBanner.error(error, 8000);
            var lastIndex = chatModel.count - 1;
            if (lastIndex >= 0 && chatModel.get(lastIndex).isThinking)
                chatModel.remove(lastIndex);
            id_chat_assistant_page.isGenerating = false;
            Qt.callLater(consumePendingVoiceChat);
        }
        function onToolCallProgress(text, isComplete) {
            generationDoneTimer.stop();
            _completeLastReasoningCard();
            _toolCallActive = !isComplete;
            finalizeLastAssistantIfNeeded();
            _upsertToolEntry("__server__", text, "", isComplete ? "done" : "searching", isComplete);
        }
        function onToolCallReceived(toolCallsJson) {
            generationDoneTimer.stop();
            _completeLastReasoningCard();
            finalizeLastAssistantIfNeeded();
            var lastIndex = chatModel.count - 1;
            if (lastIndex >= 0 && chatModel.get(lastIndex).isThinking)
                chatModel.remove(lastIndex);
        }
        function onWebSearchStarted(toolCallId, query) {
            generationDoneTimer.stop();
            _toolCallActive = true;
            id_chat_assistant_page.isGenerating = true;
            finalizeLastAssistantIfNeeded();
            _upsertToolEntry(toolCallId, "正在搜索：" + query, "", "searching", false);
            Qt.callLater(function () {
                id_chat_listview.scrollToBottom();
            });
        }
        function onWebSearchFinished(toolCallId, success, summary, resultText) {
            updateCardByToolCallId(toolCallId, {
                "text": success ? "已完成搜索：" + summary : "搜索失败：" + summary,
                "raw_text": resultText,
                "toolState": success ? "done" : "error",
                "isComplete": true
            });
        }
        function onShellCommandPending(toolCallId, command) {
            generationDoneTimer.stop();
            _toolCallActive = true;
            id_chat_assistant_page.isGenerating = true;
            finalizeLastAssistantIfNeeded();
            _upsertToolEntry(toolCallId, "请求执行：" + command, command, "pending", false);
            Qt.callLater(function () {
                id_chat_listview.scrollToBottom();
            });
            shellConfirmDialog.show(toolCallId, command);
        }
        function onShellCommandStarted(toolCallId, command) {
            _toolCallActive = true;
            id_chat_assistant_page.isGenerating = true;
            updateCardByToolCallId(toolCallId, {
                "text": "正在执行...",
                "toolState": "searching"
            });
        }
        function onShellCommandFinished(toolCallId, success, summary, resultText) {
            updateCardByToolCallId(toolCallId, {
                "text": success ? "执行完成" : "执行失败：" + summary,
                "raw_text": resultText,
                "toolState": success ? "done" : "error",
                "isComplete": true
            });
        }
        function onToolBatchFlushed() {
            generationDoneTimer.stop();
            chatModel.append({
                "text": "AI 正在思考...",
                "raw_text": "",
                "isUser": false,
                "isThinking": true,
                "isComplete": false,
                "isToolCall": false,
                "toolCallId": "",
                "toolState": "",
                "historyIndex": -1
            });
            Qt.callLater(function () {
                id_chat_listview.scrollToBottom();
            });
        }
        function onRequestCancelled() {
            _completeLastReasoningCard();
            _resetStreamState();
            _toolCallActive = false;
            _attachmentReadSeq++;
            _preparingSend = false;
            var removeIndices = [];
            for (var i = chatModel.count - 1; i >= 0; i--) {
                var item = chatModel.get(i);
                if (item.isThinking) {
                    removeIndices.push(i);
                    continue;
                }
                if (item.isToolCall && !item.isComplete) {
                    updateCardByToolCallId(item.toolCallId, {
                        "text": "已取消",
                        "toolState": "error",
                        "isComplete": true
                    });
                }
            }
            for (var ri = 0; ri < removeIndices.length; ri++)
                chatModel.remove(removeIndices[ri]);
            id_chat_assistant_page.isGenerating = false;
            Qt.callLater(consumePendingVoiceChat);
        }
        function onSessionSwitched(sessionId) {
            historyLoaded = false;
            loadHistory();
            historyLoaded = true;
        }
    }

    MessageContextMenu {
        id: id_context_menu
        chatModel: chatModel
        blurSource: id_main_content
        fontFamily: qmlGlobal.fontFamilyZhCn
        onEditRequested: editMessage(index)
        onRegenerateRequested: regenerateMessage(index)
        onDeleteSingleRequested: deleteSingleMessage(index)
        onDeleteSubsequentRequested: deleteMessageAndSubsequent(index)
    }

    ShellConfirmDialog {
        id: shellConfirmDialog
        fontFamily: qmlGlobal.fontFamilyZhCn
        onApproved: chatbot.approveShellCommand(toolCallId)
        onDenied: chatbot.denyShellCommand(toolCallId)
    }

    Connections {
        id: fileSelectorConnections
        target: null
        ignoreUnknownSignals: true

        function onFileSelected(filePath) {
            var fileName = filePath.split('/').pop();
            var language = getFileLanguage(fileName);
            var exists = false;
            for (var i = 0; i < attachedFilesModel.count; i++) {
                if (attachedFilesModel.get(i).path === filePath) {
                    exists = true;
                    break;
                }
            }
            if (!exists)
                attachedFilesModel.append({
                    "path": filePath,
                    "name": fileName,
                    "language": language
                });
        }

    }

    Connections {
        id: capturePreviewConnections
        target: null
        ignoreUnknownSignals: true

        function onCaptureConfirmed(imageBase64) {
            attachedMediaModel.append({
                "type": "image_url",
                "url": "data:image/jpeg;base64," + imageBase64,
                "data": "",
                "format": "",
                "label": "拍摄图片"
            });
            resetCaptureMode();
        }
        function onCaptureCancelled() {
            resetCaptureMode();
        }
    }

    Connections {
        target: id_pop_container
        function onPopItemObjectChanged() {
            if (id_pop_container.popItemObject && typeof id_pop_container.popItemObject.fileSelected !== 'undefined' && typeof id_pop_container.popItemObject.fileSelectionCancelled !== 'undefined')
                fileSelectorConnections.target = id_pop_container.popItemObject;
            else if (id_pop_container.popItemObject && typeof id_pop_container.popItemObject.captureConfirmed !== 'undefined')
                capturePreviewConnections.target = id_pop_container.popItemObject;
            else {
                if (captureModeActive)
                    resetCaptureMode();
                fileSelectorConnections.target = null;
                capturePreviewConnections.target = null;
            }
        }
    }

    Connections {
        target: systemBase
        ignoreUnknownSignals: true
        function onOcrStart() {
            if (mod.voiceChatEnabled)
                return;
            backButtonClicked();
        }
        function onOcrCompletedResultChanged() {
            if (typeof keyBoard !== 'undefined' && keyBoard.autoSendScan && !qmlGlobal.inputPageShowing && id_chat_assistant_page.visible) {
                if (typeof qmlGlobal.hideDictPage === 'function')
                    qmlGlobal.hideDictPage();
            }
        }
        function onOcrStop(scanType) {
            if (typeof keyBoard !== 'undefined' && keyBoard.autoSendScan && !qmlGlobal.inputPageShowing && id_chat_assistant_page.visible) {
                if (typeof qmlGlobal.hideDictPage === 'function')
                    qmlGlobal.hideDictPage();
            }
        }
    }

    Connections {
        target: keyBoard
        ignoreUnknownSignals: true
        function onAutoSendScanConfigChanged() {
            if (id_chat_assistant_page.visible && typeof keyBoard !== 'undefined' && keyBoard !== null && !qmlGlobal.inputPageShowing)
                keyBoard.autoSendScan = keyBoard.autoSendScanConfig;
        }
        function onScanFinished(content) {
            if (captureModeActive || (keyboardPageRef && keyboardPageRef.visible)
                    || qmlGlobal.inputPageShowing || id_pop_container.count > 0)
                return;
            if (content && content.trim().length > 0 && id_chat_assistant_page.visible) {
                if (typeof qmlGlobal.hideDictPage === 'function')
                    qmlGlobal.hideDictPage();
                handleUserSend(content.trim());
            }
        }
    }
}
