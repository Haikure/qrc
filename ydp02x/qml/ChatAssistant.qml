import "./commons"
import "./components"
import "./i18n"
import "./settingpages"
import "./audiopages"
import "./assistant/components"
import "./assistant/messages"
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
    // 右侧手势条宽度 = 气泡右侧留白。
    readonly property int  chatListRightMargin: 2
    readonly property int  bubbleRightInset: 8
    readonly property real rightGestureWidth: chatListRightMargin + bubbleRightInset

    // 当前正在流式接收的思维链行下标（-1 表示没有）
    property int _activeReasoningIndex: -1
    property var _mathProbeRequest: null

    function _beginRichContentCommit() { scrollController.beforeLayout(); }

    ChatScrollController {
        id: scrollController
        view: id_chat_listview
        model: chatModel
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
            "messageId": chatbot.responseMessageId + ":answer",
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
            "messageId": chatbot.responseMessageId + ":reasoning",
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

    function _toolRow(batchId, entries) {
        var completed = 0, error = false, cancelled = false, details = [];
        for (var i = 0; i < entries.length; ++i) {
            var entry = entries[i];
            if (entry.state === "done" || entry.state === "error" || entry.state === "cancelled") ++completed;
            error = error || entry.state === "error";
            cancelled = cancelled || entry.state === "cancelled";
            details.push((i + 1) + ". " + entry.text + "\n" + (entry.result || entry.arguments || ""));
        }
        var complete = completed === entries.length;
        return {messageId: batchId + ":tools", batchId: batchId,
                text: entries.length === 1 ? entries[0].text : "工具调用 " + entries.length + " 项 · " + completed + " 已结束",
                raw_text: details.join("\n\n"), reasoning_text: "", isUser: false,
                isThinking: false, isReasoning: false, isToolCall: true, isComplete: complete,
                toolCallId: entries.length ? entries[0].callId : "",
                toolState: complete ? (error ? "error" : cancelled ? "cancelled" : "done") :
                           entries.some(function (e) { return e.state === "pending"; }) ? "pending" : "searching",
                toolEntriesJson: JSON.stringify(entries), historyIndex: -1};
    }

    function _upsertToolSnapshot(state) {
        if (state.sessionId !== chatbot.currentSessionId) return;
        scrollController.beforeLayout();
        var id = state.batchId + ":tools";
        var index = -1, entries = [];
        for (var i = 0; i < chatModel.count; ++i) {
            if (chatModel.get(i).messageId !== id) continue;
            index = i;
            try { entries = JSON.parse(chatModel.get(i).toolEntriesJson); } catch (e) {}
            break;
        }
        var found = false;
        for (var j = 0; j < entries.length; ++j) {
            if (entries[j].key !== state.key) continue;
            entries[j] = state;
            found = true;
            break;
        }
        if (!found) entries.push(state);
        var row = _toolRow(state.batchId, entries);
        if (index >= 0) chatModel.set(index, row);
        else replaceThinkingOrAppend(row);
        _scheduleScrollToBottom();
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

    function _historyRows(history) {
        var rows = [], states = chatbot.toolStates || [], groups = {}, emitted = {};
        for (var t = 0; t < states.length; ++t) {
            var st = states[t];
            if (!groups[st.batchId]) groups[st.batchId] = [];
            groups[st.batchId].push(st);
        }
        function group(id, idx) {
            if (!groups[id] || emitted[id]) return;
            var row = _toolRow(id, groups[id]);
            row.historyIndex = idx;
            rows.push(row);
            emitted[id] = true;
        }
        for (var i = 0; i < history.length; ++i) {
            var m = history[i], id = m.messageId;
            if (m.role === "system") continue;
            if (m.role === "tool") continue;
            if (m.reasoning) {
                var reasoning = _makeReasoningEntry(m.reasoning);
                reasoning.messageId = id + ":reasoning";
                reasoning.isComplete = true;
                rows.push(reasoning);
            }
            var attachments = (m.parts || []).filter(function (p) { return p.type === "image_url" || p.type === "file"; });
            if (m.role === "user" || m.content || attachments.length) {
                rows.push({messageId: id + (m.role === "user" ? ":user" : ":answer"),
                           text: m.role === "user" ? m.content : "", raw_text: m.content || "", reasoning_text: "",
                           attachmentsJson: JSON.stringify(attachments), isUser: m.role === "user", isComplete: true,
                           isThinking: false, isReasoning: false, isToolCall: false,
                           toolCallId: "", toolState: "", historyIndex: i});
            }
            group(id, i);
            // Old sessions have no snapshots. Preserve an unresolved status rather
            // than presenting an unrecorded outcome as a successful execution.
            if (m.toolCallsJson && !groups[id]) {
                var calls = [];
                try { calls = JSON.parse(m.toolCallsJson); } catch (e) {}
                var legacy = [];
                for (var c = 0; c < calls.length; ++c) {
                    var result = "调用结果未知", status = "error";
                    for (var k = i + 1; k < history.length && history[k].role === "tool"; ++k) {
                        if (history[k].toolCallId !== calls[c].id) continue;
                        result = history[k].content;
                        // Old files never recorded success; leave that uncertainty visible.
                        if (/取消|中断|拒绝/.test(result)) status = "cancelled";
                    }
                    legacy.push({key: id + ":tool:" + c, callId: calls[c].id, state: status,
                                 text: "历史工具调用（" + (status === "cancelled" ? "已取消" : "状态未记录") + "）",
                                 result: result});
                }
                if (legacy.length) { var old = _toolRow(id, legacy); old.historyIndex = i; rows.push(old); }
            }
        }
        for (var batch in groups) group(batch, -1);
        return rows;
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

    function _rebuildCurrentTurnRows() {
        if (!chatbot) return;
        var rows = _historyRows(chatbot.messages);
        scrollController.beforeLayout();
        for (var i = 0; i < rows.length; ++i) {
            var row = rows[i], found = -1;
            for (var j = i; j < chatModel.count; ++j) {
                if (chatModel.get(j).messageId === row.messageId) { found = j; break; }
            }
            // Adopt the locally inserted user row once the backend saves it.
            if (found < 0 && row.isUser) {
                for (var u = i; u < chatModel.count; ++u) {
                    var candidate = chatModel.get(u);
                    if (candidate.isUser && !candidate.messageId && candidate.raw_text === row.raw_text) { found = u; break; }
                }
            }
            if (found >= 0) {
                if (found !== i) chatModel.move(found, i, 1);
                // Avoid touching unchanged roles: this preserves delegates and layout versions.
                for (var role in row)
                    if (chatModel.get(i)[role] !== row[role]) chatModel.setProperty(i, role, row[role]);
            } else chatModel.insert(i, row);
        }
        // The projection includes every live tool snapshot, including calls which
        // have not written their API result yet. Only obsolete rows are removed.
        if (chatModel.count > rows.length) chatModel.remove(rows.length, chatModel.count - rows.length);
        id_chat_listview.forceLayout();
        scrollController.schedule();
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

    function _followLatestMessage() { scrollController.follow(); }

    function _scheduleScrollToBottom() {
        scrollController.schedule();
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
        var rows = _historyRows(chatbot.messages);
        for (var idx = 0; idx < rows.length; idx++) chatModel.append(rows[idx]);
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
        var history = chatbot.messages;
        for (var r = 0; r < chatModel.count; ++r) {
            var row = chatModel.get(r), idx = -1;
            for (var i = 0; i < history.length; ++i) {
                if (row.messageId === history[i].messageId + ":user"
                    || row.messageId === history[i].messageId + ":answer"
                    || row.messageId === history[i].messageId + ":tools") { idx = i; break; }
            }
            if (row.historyIndex !== idx) chatModel.setProperty(r, "historyIndex", idx);
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
        id_chat_listview.currentIndex = msgIndex;
        scrollController.locate(msgIndex);
        highlightTimer.restart();
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
                reuseItems: false
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
                readonly property bool userScrolledUp: scrollController.mode !== "following"
                property bool showScrollToBottom: userScrolledUp
                readonly property bool userInteracting: dragging || flicking
                readonly property real bottomThreshold: 2

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

                function captureReadAnchor() { scrollController.capture(); }
                function restoreReadAnchor() { return scrollController.apply(); }
                function scrollToTop() { scrollController.locate(0); }
                function autoFollowBottom() { scrollController.schedule(); }
                function scrollToBottom(animated) { scrollController.follow(); }
                onDraggingChanged: { if (dragging) scrollController.gestureStarted(); }
                onMovementStarted: { if (dragging || flicking) scrollController.gestureStarted(); }
                onMovementEnded: scrollController.gestureEnded()
                onContentHeightChanged: scrollController.schedule()

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
                    messageId: model.messageId || "local:" + model.index
                    sessionId: chatbot.currentSessionId
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
                    navigationJumping: false
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
                    onToolCardExpansionStarted: scrollController.beforeLayout()
                    onRichContentCommitStarted: scrollController.beforeLayout()
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
        id: highlightTimer
        interval: 1500
        onTriggered: id_chat_listview.currentIndex = -1
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
                scrollController.schedule();
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
            var last = chatModel.count - 1;
            if (last >= 0 && chatModel.get(last).isThinking)
                chatModel.setProperty(last, "messageId", chatbot.responseMessageId + ":answer");
        }
        function onMessagesChanged() {
            // Backend saves the user row synchronously before streamStart.
            // Give the provisional row its identity before any tools or replies arrive.
            var history = chatbot.messages;
            for (var h = history.length - 1; h >= 0; --h) {
                if (history[h].role !== "user") continue;
                for (var r = chatModel.count - 1; r >= 0; --r) {
                    var row = chatModel.get(r);
                    if (!row.isUser) continue;
                    if (!row.messageId && row.raw_text === history[h].content)
                        chatModel.setProperty(r, "messageId", history[h].messageId + ":user");
                    break;
                }
                break;
            }
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
            shellConfirmDialog.clear();
            toastBanner.error(error, 8000);
            var lastIndex = chatModel.count - 1;
            if (lastIndex >= 0 && chatModel.get(lastIndex).isThinking)
                chatModel.remove(lastIndex);
            id_chat_assistant_page.isGenerating = false;
            Qt.callLater(consumePendingVoiceChat);
        }
        function onToolStateChanged(state) {
            generationDoneTimer.stop();
            _completeLastReasoningCard();
            finalizeLastAssistantIfNeeded();
            _upsertToolSnapshot(state);
            _toolCallActive = (chatbot.toolStates || []).some(function (s) {
                return s.state !== "done" && s.state !== "error" && s.state !== "cancelled";
            });
        }
        function onToolCallProgress(text, isComplete) {}
        function onToolCallReceived(toolCallsJson) { generationDoneTimer.stop(); }
        function onShellCommandPending(toolCallId, command) {
            shellConfirmDialog.show(toolCallId, command);
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
            _scheduleScrollToBottom();
        }
        function onRequestCancelled() {
            _completeLastReasoningCard();
            _resetStreamState();
            _toolCallActive = false;
            shellConfirmDialog.clear();
            _flushStreamBuffer();
            _attachmentReadSeq++;
            _preparingSend = false;
            var removeIndices = [];
            for (var i = chatModel.count - 1; i >= 0; i--) {
                var item = chatModel.get(i);
                if (item.isThinking) {
                    removeIndices.push(i);
                    continue;
                }

            }
            for (var ri = 0; ri < removeIndices.length; ri++)
                chatModel.remove(removeIndices[ri]);
            _rebuildCurrentTurnRows();
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
