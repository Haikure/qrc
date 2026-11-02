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

    // ---------------- 草稿（待发送编辑区） ----------------
    // 键盘 ✓ 只把文字写进草稿，点「发送」才真正调用 ChatBot（Issue #21-4）。
    property bool draftVisible: false
    property string draftText: ""
    // 编辑旧消息时的 C++ 历史下标（-1 = 新消息草稿）；messageId 用于发送前复核，避免删除后索引漂移。
    property int draftEditingMessageIndex: -1
    property bool sending: false
    // 异步拍照/选文件回调必须同时匹配这两个值，否则结果写进新草稿或已切换的会话。
    property int _draftRequestId: 0
    property string _draftSessionId: ""
    property string _draftEditingMessageId: ""
    // 视觉代理是异步落库的：发送后要等 messagesChanged 才能确认成功。
    property bool _draftProxyPending: false
    // 消息已落库、但随后请求失败（离线/服务端错误）时回滚成草稿，满足“失败保留草稿可重试”。
    // 请求正常开始响应（streamStart）或用户开始新动作后就解除，避免误删已成功的消息。
    property bool _draftRollbackArmed: false
    property var _draftRollbackSnapshot: null
    // 区分“调用 API 期间同步抛错”和“稍后异步报错”。
    property bool _draftDispatching: false
    property bool _draftSyncFailed: false
    property int _historyRevision: 0
    property string _draftSentText: ""
    property string _draftSentSessionId: ""
    property int _draftSentHistoryLength: 0
    property int _draftSentEditIndex: -1
    property int _captureRequestId: -1
    property string _captureSessionId: ""
    property int _filePickRequestId: -1
    property string _filePickSessionId: ""
    // C++ 侧边界：AttachmentManager::persistImage 单图 9 MiB；sendMessageWithMedia 的 mediaParts JSON 12 MiB。
    // QML 在追加附件时就提前拦，避免发送时才丢草稿（base64 长度 ≈ 二进制 * 4/3）。
    // 优先取 Backend 暴露的常量，旧主库没有该 invokable 时回退到同值常量（资源库/主库升级不同步时仍可用）。
    readonly property int _maxImageBytes: (typeof chatbot !== 'undefined' && chatbot
                                           && typeof chatbot.maxImageBytes === 'function')
                                          ? chatbot.maxImageBytes() : 9 * 1024 * 1024
    readonly property int _maxMediaJsonChars: (typeof chatbot !== 'undefined' && chatbot
                                               && typeof chatbot.maxMediaJsonBytes === 'function')
                                              ? chatbot.maxMediaJsonBytes() : 12 * 1024 * 1024
    readonly property int _maxImageDataChars: Math.ceil(_maxImageBytes * 4 / 3) + 64
    readonly property int _maxMediaDataChars: _maxMediaJsonChars - 4096
    readonly property int _maxDraftFiles: 8

    // 生成中/界面忙碌时扫描到的文本先排队（按扫描顺序 flush），避免“快速多行扫描”丢句。
    // 队列绑定会话：切会话、离开页面时整体丢弃；日志只记条数，不打印正文。
    property var _pendingTexts: []
    property string _pendingTextsSessionId: ""

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
        chatbot.startMathServer();
    }

    Connections {
        target: chatbot
        function onMathRenderConfigChanged() {
            if (_mathProbeRequest !== null) {
                var previousRequest = _mathProbeRequest;
                _mathProbeRequest = null;
                previousRequest.abort();
            }
            id_chat_assistant_page.mathServerAvailable = false;
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
            _startMathServer();
            var xhr = new XMLHttpRequest();
            _mathProbeRequest = xhr;
            xhr.open("GET", "http://127.0.0.1:3000/health", true);
            xhr.timeout = 2000;
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE || _mathProbeRequest !== xhr)
                    return;
                _mathProbeRequest = null;
                id_chat_assistant_page.mathServerAvailable = chatbot.mathRenderEnabled && (xhr.status === 200);
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
                if (_mathProbeRequest !== xhr) return;
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
    // 草稿附件：未发送前只存在于 QML 里（图片是 data URL），成功发送后才由 C++ 落盘到当前会话目录。
    ListModel {
        id: attachedMediaModel
    }

    function clearAttachments() {
        attachedFilesModel.clear();
        attachedMediaModel.clear();
    }

    // 回滚快照用：ListModel.get() 返回的是模型项包装，clear() 之后可能失效/取空，
    // 所以必须按已知 role 拷贝成普通 JS 对象再保存（否则回滚出来的附件只剩空壳）。
    function _snapshotMediaItem(item) {
        var keys = ["type", "url", "source", "data", "format", "localPath",
                    "label", "name", "mimeType", "size"];
        var copy = {};
        for (var i = 0; i < keys.length; ++i)
            copy[keys[i]] = item && item[keys[i]] !== undefined ? item[keys[i]] : "";
        return copy;
    }

    function _snapshotFileItem(item) {
        var keys = ["path", "name", "language", "size", "mimeType", "type"];
        var copy = {};
        for (var i = 0; i < keys.length; ++i)
            copy[keys[i]] = item && item[keys[i]] !== undefined ? item[keys[i]] : "";
        return copy;
    }

    // ---------------- 草稿状态机辅助 ----------------
    function _draftHasUpload() {
        return attachedFilesModel.count > 0 || attachedMediaModel.count > 0;
    }

    function _draftHasContent() {
        return draftText.trim().length > 0 || _draftHasUpload();
    }

    // 清空草稿，并让所有在途的异步捕获/选文件回调失效（递增 request id）。
    // 附件在发送成功前只存在于 QML 模型里，所以切会话/返回页面时清空即可，不会残留在任何 session 目录。
    function _clearDraft(reason) {
        // 诊断日志：不打印正文/附件，只打印“谁清空了草稿 + 当时草稿发送状态”，用于定位失败回滚。
        console.log("[ChatAssistant] clearDraft reason=", reason || "unknown",
                    "armed=", _draftRollbackArmed, "sending=", sending,
                    "visible=", visible, "draftVisible=", draftVisible);
        _attachmentReadSeq++;
        _draftRequestId++;
        _draftSessionId = "";
        _draftEditingMessageId = "";
        draftEditingMessageIndex = -1;
        draftText = "";
        draftVisible = false;
        sending = false;
        _draftDispatching = false;
        _draftSyncFailed = false;
        _draftProxyPending = false;
        _draftRollbackArmed = false;
        _draftRollbackSnapshot = null;
        _draftSentText = "";
        _draftSentSessionId = "";
        _draftSentHistoryLength = 0;
        _draftSentEditIndex = -1;
        _captureRequestId = -1;
        _captureSessionId = "";
        _filePickRequestId = -1;
        _filePickSessionId = "";
        clearAttachments();
        resetCaptureMode();
    }

    // 用户已经开始新动作（重新输入/加附件/再次发送/取消/已开始收到回复）：不再回滚上一条消息。
    function _disarmDraftRollback(reason) {
        if (_draftRollbackArmed)
            console.log("[ChatAssistant] disarm-rollback reason=", reason || "unknown");
        _draftRollbackArmed = false;
        _draftRollbackSnapshot = null;
    }

    function _cancelDraft(notify) {
        if (sending)
            return;
        _disarmDraftRollback("cancel-draft");
        var hadContent = draftVisible && (_draftHasContent() || draftEditingMessageIndex >= 0);
        _clearDraft("cancel-draft");
        if (notify && hadContent)
            toastBanner.info("已取消草稿");
    }

    // 键盘 ✓：只写入草稿，绝不直接发送（#21-4 的核心行为）。
    function _commitDraftText(text) {
        if (sending || _preparingSend)
            return;
        _disarmDraftRollback("commit-text");
        var value = text ? text.trim() : "";
        // 新建草稿：空文字且无附件等于取消；编辑草稿允许清空文字（图片还在）。
        if (draftEditingMessageIndex < 0 && value.length === 0 && !_draftHasUpload()) {
            _clearDraft("commit-empty");
            return;
        }
        if (_draftSessionId !== "" && chatbot && _draftSessionId !== chatbot.currentSessionId) {
            _clearDraft("commit-session-changed");
            toastBanner.warning("会话已切换，草稿已取消");
            return;
        }
        draftText = value;
        draftVisible = true;
        if (_draftSessionId === "" && chatbot)
            _draftSessionId = chatbot.currentSessionId;
    }

    function _draftMediaChars() {
        var total = 0;
        for (var i = 0; i < attachedMediaModel.count; ++i) {
            var item = attachedMediaModel.get(i);
            if (!item)
                continue;
            if (item.url)
                total += ("" + item.url).length;
            else if (item.source)
                total += ("" + item.source).length;
        }
        return total;
    }

    // 追加一张图片到草稿；返回是否成功（重复/超限会被拒绝并提示）。
    function _appendDraftImage(base64Data) {
        if (!base64Data)
            return false;
        _disarmDraftRollback("append-image");
        var dataUrl = "data:image/jpeg;base64," + base64Data;
        // 单图上限（C++ AttachmentManager 落盘 9 MiB）。
        if (dataUrl.length > _maxImageDataChars) {
            toastBanner.warning("图片过大（单张上限 9 MiB），请裁剪后再试");
            return false;
        }
        // 去重：同一张图（base64 内容完全一致）不重复加入、也不和已有本地图路径重复。
        for (var i = 0; i < attachedMediaModel.count; ++i) {
            var existing = attachedMediaModel.get(i);
            if (!existing)
                continue;
            if (existing.url === dataUrl || existing.source === dataUrl) {
                toastBanner.info("这张图片已在草稿中");
                return false;
            }
        }
        // 总媒体大小（C++ mediaParts JSON 上限 12 MiB，含每个 part 的元数据开销）。
        if (_draftMediaChars() + dataUrl.length + 256 > _maxMediaDataChars) {
            toastBanner.warning("图片总大小超出上限（12 MiB），请减少附件后再试");
            return false;
        }
        var label = "图片 " + (attachedMediaModel.count + 1);
        attachedMediaModel.append({
            "type": "image_url",
            "url": dataUrl,
            "source": dataUrl,
            "data": "",
            "format": "",
            "localPath": "",
            "label": label,
            "name": label,
            "mimeType": "image/jpeg",
            "size": Math.round((dataUrl.length - 23) * 3 / 4)
        });
        draftVisible = true;
        if (chatbot)
            _draftSessionId = chatbot.currentSessionId;
        return true;
    }

    function _imageMimeForName(name) {
        var lower = ("" + name).toLowerCase();
        if (lower.endsWith(".png")) return "image/png";
        if (lower.endsWith(".webp")) return "image/webp";
        if (lower.endsWith(".gif")) return "image/gif";
        if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
        return "";
    }

    function _isImageFileName(name) {
        return _imageMimeForName(name) !== "";
    }

    // 只带本地路径的图片（从文件管理器选图，不在 QML 里读文件转 base64；后端请求时再转 data URL）。
    function _appendDraftImagePath(filePath) {
        if (!filePath)
            return false;
        _disarmDraftRollback("append-image");
        var canonical = _canonicalPath(filePath);
        var fileName = canonical.split('/').pop();
        var mime = _imageMimeForName(fileName);
        if (!mime) {
            toastBanner.warning("不支持的图片格式：" + fileName);
            return false;
        }
        for (var i = 0; i < attachedMediaModel.count; ++i) {
            var existing = attachedMediaModel.get(i);
            if (existing && existing.localPath
                    && _canonicalPath(existing.localPath) === canonical) {
                toastBanner.info("这张图片已在草稿中");
                return false;
            }
        }
        var label = fileName || ("图片 " + (attachedMediaModel.count + 1));
        attachedMediaModel.append({
            "type": "image_url",
            "url": "",
            "source": "file://" + canonical,
            "localPath": canonical,
            "data": "",
            "format": "",
            "label": label,
            "name": label,
            "mimeType": mime,
            "size": 0
        });
        draftVisible = true;
        if (chatbot)
            _draftSessionId = chatbot.currentSessionId;
        return true;
    }

    // 规范化路径用于去重：去掉多余斜杠与结尾斜杠。
    function _canonicalPath(path) {
        if (!path)
            return "";
        var p = ("" + path).replace(/\/+/g, "/");
        while (p.length > 1 && p.charAt(p.length - 1) === "/")
            p = p.slice(0, -1);
        return p;
    }

    // 追加一个文本文件到草稿；返回是否成功（重复/超量/编辑态会被拒绝并提示）。
    function _appendDraftFile(filePath) {
        if (!filePath)
            return false;
        _disarmDraftRollback("append-file");
        var canonical = _canonicalPath(filePath);
        var fileName = canonical.split('/').pop();
        if (!fileName)
            return false;
        if (!isTextFile(fileName)) {
            toastBanner.warning("暂不支持该附件类型：" + fileName);
            return false;
        }
        for (var i = 0; i < attachedFilesModel.count; i++) {
            if (_canonicalPath(attachedFilesModel.get(i).path) === canonical) {
                toastBanner.info("该文件已在草稿中");
                return false;
            }
        }
        if (attachedFilesModel.count >= _maxDraftFiles) {
            toastBanner.warning("单条消息最多 " + _maxDraftFiles + " 个文件附件");
            return false;
        }
        attachedFilesModel.append({
            "path": canonical,
            "name": fileName,
            "language": getFileLanguage(fileName),
            "size": 0
        });
        draftVisible = true;
        if (chatbot)
            _draftSessionId = chatbot.currentSessionId;
        return true;
    }

    function _isMainChatSurface() {
        return id_chat_assistant_page.visible
                && id_pop_container.count === 0
                && !qmlGlobal.inputPageShowing
                && !(keyboardPageRef && keyboardPageRef.visible);
    }

    function _startDraftCapture() {
        if (sending || _preparingSend)
            return;
        if (chatbot)
            _draftSessionId = chatbot.currentSessionId;
        _captureRequestId = _draftRequestId;
        _captureSessionId = _draftSessionId;
        captureModeActive = true;
        if (typeof cameraCapture !== 'undefined' && cameraCapture !== null)
            cameraCapture.captureEnabled = true;
        id_pop_container.show('assistant/dialogs/CapturePreviewPage');
    }

    function _pickDraftFile() {
        if (sending || _preparingSend)
            return;
        if (attachedFilesModel.count >= _maxDraftFiles) {
            toastBanner.warning("单条消息最多 " + _maxDraftFiles + " 个文件附件");
            return;
        }
        if (chatbot)
            _draftSessionId = chatbot.currentSessionId;
        _filePickRequestId = _draftRequestId;
        _filePickSessionId = _draftSessionId;
        // #21-3：在创建 FileManagerSelector 时传入初始属性。vendor 组件支持多选/扩展名过滤，
        // 但属性必须在 incubate 前给出；之前设置在页面创建之后（且确认按钮绑定不刷新）导致不可用。
        id_pop_container.show('audiopages/FileManagerSelector', {
            allowMultiSelect: true,
            fileExtensions: ["txt", "md", "json", "py", "js", "ts", "qml", "cpp", "h", "c", "java",
                             "html", "css", "jpg", "jpeg", "png", "webp", "gif"]
        });
    }

    // 异步拍照/裁剪回调的最终落点校验：session 或草稿请求号变了就丢弃（日志不打 base64）。
    function _validateCaptureResult() {
        if (!chatbot || _captureSessionId === "" || _captureSessionId !== chatbot.currentSessionId) {
            console.log("[ChatAssistant] 丢弃过期拍照结果：会话已切换");
            return false;
        }
        if (_captureRequestId !== _draftRequestId) {
            console.log("[ChatAssistant] 丢弃过期拍照结果：草稿已重置");
            return false;
        }
        return true;
    }

    function _findMessageRowById(messageId) {
        if (!messageId)
            return -1;
        var target = messageId + ":user";
        for (var i = 0; i < chatModel.count; i++) {
            if (chatModel.get(i).messageId === target)
                return i;
        }
        return -1;
    }

    // ---------------- 忙碌时的文本队列（快速多行扫描不丢句） ----------------
    function _queuePendingText(text, origin) {
        var value = text ? ("" + text).trim() : "";
        if (value.length === 0)
            return false;
        if (!chatbot)
            return false;
        // 会话已经变了：旧队列不能串到新会话。
        if (_pendingTextsSessionId !== "" && _pendingTextsSessionId !== chatbot.currentSessionId)
            _clearPendingTexts();
        _pendingTextsSessionId = chatbot.currentSessionId;
        _pendingTexts.push(value);
        console.log("[ChatAssistant] 文本已排队等待空闲（来源:", origin || "unknown",
                    "队列条数:", _pendingTexts.length, "）");
        return true;
    }

    function _clearPendingTexts() {
        if (_pendingTexts.length > 0)
            console.log("[ChatAssistant] 清空待处理文本队列（" + _pendingTexts.length + " 条）");
        _pendingTexts = [];
        _pendingTextsSessionId = "";
    }

    function _pendingTextsFlushBlocked() {
        return !chatbot || sending || _preparingSend || isGenerating
                || qmlGlobal.inputPageShowing || id_pop_container.count > 0
                || shellConfirmDialog.active
                || (keyboardPageRef && keyboardPageRef.visible);
    }

    // 空闲后按顺序处理队列：逐条走统一入口；第一条进入生成后，剩余条目继续排队等下一轮。
    function _flushPendingTexts() {
        if (_pendingTexts.length === 0)
            return;
        if (!chatbot || (_pendingTextsSessionId !== "" && _pendingTextsSessionId !== chatbot.currentSessionId)) {
            _clearPendingTexts();
            return;
        }
        if (_pendingTextsFlushBlocked())
            return;
        var texts = _pendingTexts;
        _pendingTexts = [];
        _pendingTextsSessionId = "";
        // 队列里的都是扫描文本：真正发出前和 onScanFinished 的直接路径一样收起词典页。
        if (typeof qmlGlobal.hideDictPage === 'function')
            qmlGlobal.hideDictPage();
        for (var i = 0; i < texts.length; i++) {
            handleUserSend(texts[i]);
            if (isGenerating || sending) {
                if (i + 1 < texts.length) {
                    for (var j = i + 1; j < texts.length; j++)
                        _queuePendingText(texts[j], "flush");
                }
                break;
            }
        }
    }

    // 空闲时机统一出口：先放语音待发送（handleUserSend 忙时会给扫描文本排队），再放扫描队列。
    function _flushIdleWork() {
        consumePendingVoiceChat();
        _flushPendingTexts();
    }

    onVisibleChanged: {
        if (visible) {
            if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                keyBoard.autoSendScan = keyBoard.autoSendScanConfig;
            Qt.callLater(_flushIdleWork);
        } else {
            id_pop_container.closeAllPages();
            _preparingSend = false;
            if (_mathProbeRequest !== null) {
                _mathProbeRequest.abort();
                _mathProbeRequest = null;
            }
            // 离开页面时草稿和附件一律丢弃：未落盘的附件不能留在任何 session 目录里。
            console.log("[ChatAssistant] page-hidden armed=", _draftRollbackArmed, "sending=", sending);
            _clearDraft("page-hidden");
            _clearPendingTexts();
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

    // 输入页只建一次，复用四张字符键盘；Rime 会话在首次拼音输入时按需创建。
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
            Qt.callLater(_flushIdleWork);
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
        // 切会话/新会话：草稿、附件与待处理队列一律作废，绝不能让附件跟着发进新 session。
        _clearDraft("prepare-session-change");
        _clearPendingTexts();
        _preparingSend = false;
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
        Qt.callLater(_flushIdleWork);
    }
    Component.onDestruction: {
        _attachmentReadSeq++;
        _draftRequestId++;
        _draftProxyPending = false;
        sending = false;
        _clearPendingTexts();
        if (_mathProbeRequest !== null)
            _mathProbeRequest.abort();
        resetCaptureMode();
    }

    function consumePendingVoiceChat() {
        var text = mod.pendingVoiceChatText.trim();
        // 忙/弹层/键盘打开时不丢：文本留在 mod.pendingVoiceChatText，等空闲信号再试。
        if (text.length === 0 || _preparingSend || isGenerating || sending || _pendingTexts.length > 0)
            return;
        if (qmlGlobal.inputPageShowing || id_pop_container.count > 0 || (keyboardPageRef && keyboardPageRef.visible))
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
        var isEditDraft = draftEditingMessageIndex >= 0;
        keyboardPageRef.placeHolderText = isEditDraft ? "编辑消息..." : "输入消息...";
        // 键盘页复用图片条：草稿里的图片一边改字一边可删；空文字在“有附件或编辑旧消息”时才能 ✓。
        keyboardPageRef.attachmentModel = (draftVisible || isEditDraft) ? attachedMediaModel : null;
        keyboardPageRef.allowEmptyAccept = Qt.binding(function () {
            return id_chat_assistant_page.draftEditingMessageIndex >= 0
                    || attachedFilesModel.count > 0 || attachedMediaModel.count > 0;
        });
        keyboardPageRef.resetInput(draftText);
        keyboardPageRef.show();
        qmlGlobal.inputPageShowing = true;
    }

    function _initializeKeyboardPage(keyboardPage) {
        keyboardPageRef = keyboardPage;
        keyboardPage.backButtonClicked.connect(function () {
            qmlGlobal.inputPageShowing = false;
            if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                keyBoard.autoSendScan = keyBoard.autoSendScanConfig;
            // 返回（非 ✓）丢弃本次键盘输入；若草稿因此变成空的新草稿，顺手收起草稿条。
            if (id_chat_assistant_page.draftVisible
                    && id_chat_assistant_page.draftEditingMessageIndex < 0
                    && !id_chat_assistant_page._draftHasContent())
                id_chat_assistant_page._clearDraft("keyboard-back-empty");
            // 键盘收起后如果有排队文本（扫描时键盘正好开着），继续处理。
            Qt.callLater(_flushIdleWork);
        });
        keyboardPage.inputFinished.connect(function (content) {
            if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                keyBoard.autoSendScan = keyBoard.autoSendScanConfig;
            // 关键行为：✓ 只把文字写进草稿，发送必须由草稿条上的「发送」触发。
            _commitDraftText(content);
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
        if (qmlGlobal.inputPageShowing || id_chat_assistant_page.isGenerating || _preparingSend || sending)
            return;
        if (typeof keyBoard !== 'undefined' && keyBoard !== null)
            keyBoard.autoSendScan = false;
        id_session_panel.close();
        id_message_index_panel.close();
        _ensureKeyboardPage(true);
    }

    // 草稿条上的「发送」（也兼容旧调用点）：只走 sendDraft，附件与文字都从草稿取。
    function sendPendingAttachments() {
        sendDraft();
    }

    // 扫描自动发送 / 语音待发送等外部入口：保持“立即发送”语义，但统一走草稿状态机。
    // 已经存在草稿时不丢弃附件，只把文字并入草稿（发送仍由用户点「发送」）。
    function handleUserSend(content) {
        var text = content ? ("" + content).trim() : "";
        if (text.length === 0)
            return;
        // 忙（生成中/发送中/准备中）时不能静默丢弃：先排队，空闲后按顺序继续。
        if (_preparingSend || isGenerating || sending) {
            _queuePendingText(text, "busy");
            return;
        }
        if (draftVisible && (_draftHasContent() || draftEditingMessageIndex >= 0)) {
            draftText = draftText.length > 0 ? (draftText + "\n" + text) : text;
            toastBanner.info("已加入草稿");
            return;
        }
        _clearDraft("handle-send-reset");
        if (!chatbot || !chatbot.isAvailable) {
            toastBanner.error("请先在设置中配置 API 密钥");
            return;
        }
        draftText = text;
        draftVisible = true;
        _draftSessionId = chatbot.currentSessionId;
        sendDraft();
    }

    // 发送草稿：唯一真正调用 ChatBot 的入口（新消息 sendMessage*/编辑 editMessageWithMedia）。
    function sendDraft() {
        if (sending || _preparingSend)
            return;
        _disarmDraftRollback("send-start");
        if (isGenerating) {
            toastBanner.warning("请等待当前回复完成");
            return;
        }
        if (!chatbot)
            return;
        if (!chatbot.isAvailable) {
            toastBanner.error("请先在设置中配置 API 密钥");
            return;
        }

        var trimmed = draftText ? draftText.trim() : "";
        var isEdit = draftEditingMessageIndex >= 0;
        if (trimmed.length === 0 && !_draftHasUpload() && !isEdit) {
            toastBanner.warning("请输入文字或添加附件");
            return;
        }
        if (isEdit && trimmed.length === 0 && attachedMediaModel.count === 0
                && attachedFilesModel.count === 0) {
            // 文字和附件都空了：等于删消息，不允许用“编辑”实现（会丢历史）。
            toastBanner.warning("编辑消息不能同时清空文字和附件");
            return;
        }
        var sessionId = chatbot.currentSessionId;
        if (_draftSessionId !== "" && _draftSessionId !== sessionId) {
            _clearDraft("send-session-changed");
            toastBanner.warning("会话已切换，草稿已取消");
            return;
        }

        // 能力校验（#21-3 要求“不支持 vision/audio 的模型发送前明确提示”）：
        // - 不支持视觉且没有视觉代理：纯图片（无文字/文件）直接拦；图文混合时提示“本次只发文字”；
        // - 不支持音频：提示并丢弃音频 part（后端也会兜底丢弃，避免 API 400）。
        var imageCount = 0;
        var audioCount = 0;
        for (var mi = 0; mi < attachedMediaModel.count; mi++) {
            var mediaKind = attachedMediaModel.get(mi).type;
            if (mediaKind === "image_url")
                imageCount++;
            else if (mediaKind === "input_audio")
                audioCount++;
        }
        if (imageCount > 0 && !chatbot.capVision && !chatbot.proxyVisionModelId) {
            if (trimmed.length === 0 && attachedFilesModel.count === 0) {
                toastBanner.warning("当前模型不支持视觉，请在模型设置中配置「视觉代理模型」，或移除图片后再发送");
                return;
            }
            toastBanner.warning("当前模型不支持视觉，本次将跳过 " + imageCount + " 张图片，仅发送文字/文件");
        }
        if (audioCount > 0 && !chatbot.capAudio) {
            if (trimmed.length === 0 && attachedFilesModel.count === 0 && imageCount === 0) {
                toastBanner.warning("当前模型不支持音频，请先在模型设置中启用音频能力");
                return;
            }
            toastBanner.warning("当前模型不支持音频，本次将跳过 " + audioCount + " 个音频附件");
        }

        _draftSessionId = sessionId;
        _draftRequestId++;             // 新一轮发送的快照号；在途的拍照结果不再属于本草稿
        _draftSentSessionId = sessionId;
        _draftProxyPending = false;
        _draftSyncFailed = false;
        _draftSentEditIndex = isEdit ? draftEditingMessageIndex : -1;
        var revisionBefore = _historyRevision;
        sending = true;
        _draftDispatching = true;
        var dispatched = isEdit ? _dispatchDraftEdit(trimmed) : _dispatchDraftNew(trimmed);
        _draftDispatching = false;
        if (!dispatched) {
            sending = false;
            _draftSyncFailed = false;
            return;
        }
        console.log("[ChatAssistant] sendDispatched dispatched=", dispatched, "sending=", sending,
                    "revDelta=", _historyRevision - revisionBefore,
                    "proxy=", _draftProxyPending, "armed=", _draftRollbackArmed,
                    "histLen=", chatbot ? chatbot.messages.length : -1);
        // 同步落库时 messagesChanged 已经清掉草稿；视觉代理要等异步回调；两者都没有 = C++ 静默拒绝。
        if (sending && _historyRevision === revisionBefore && !_draftProxyPending)
            _failDraftSend("发送失败，请重试（草稿已保留）");
    }

    function _dispatchDraftNew(trimmed) {
        var mediaParts = [];
        for (var mi = 0; mi < attachedMediaModel.count; mi++) {
            var mediaItem = attachedMediaModel.get(mi);
            if (!mediaItem)
                continue;
            if (mediaItem.type === "image_url") {
                var url = mediaItem.url || (mediaItem.localPath ? "" : (mediaItem.source || ""));
                var imageLocalPath = mediaItem.localPath || "";
                // 只有本地路径的图片也允许（后端会按路径转 data URL/持久化，避免 QML 读文件）。
                if (!url && !imageLocalPath)
                    continue;
                mediaParts.push({
                    "type": "image_url",
                    "url": url,
                    "localPath": imageLocalPath,
                    "label": mediaItem.label || mediaItem.name || "图片",
                    "name": mediaItem.name || "图片",
                    "mimeType": mediaItem.mimeType || "image/jpeg"
                });
            } else if (mediaItem.type === "input_audio") {
                // 模型不支持音频时不把音频 part 发出去（QML 已提前 toast 提示）。
                if (!chatbot.capAudio)
                    continue;
                mediaParts.push({
                    "type": "input_audio",
                    "data": mediaItem.data,
                    "format": mediaItem.format,
                    "label": mediaItem.label || "音频"
                });
            }
        }

        var fileItems = [];
        for (var fi = 0; fi < attachedFilesModel.count; fi++) {
            var fileItem = attachedFilesModel.get(fi);
            fileItems.push({
                "path": fileItem.path,
                "name": fileItem.name,
                "language": fileItem.language
            });
        }

        var displayText = trimmed;
        var filesJson = fileItems.length > 0 ? JSON.stringify(fileItems) : "";
        var nonImageLabels = [];
        var messageAttachments = [];
        for (var mediaIndex = 0; mediaIndex < mediaParts.length; mediaIndex++) {
            if (mediaParts[mediaIndex].type === "image_url")
                messageAttachments.push({
                    "type": "image_url",
                    "source": mediaParts[mediaIndex].url
                              || (mediaParts[mediaIndex].localPath
                                  ? "file://" + mediaParts[mediaIndex].localPath : ""),
                    "localPath": mediaParts[mediaIndex].localPath || "",
                    "name": mediaParts[mediaIndex].label,
                    "mimeType": mediaParts[mediaIndex].mimeType || "image/jpeg"
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
            else if (fileItems.length > 0)
                displayText = "请阅读附件内容";
        }
        for (var fileIndex = 0; fileIndex < fileItems.length; fileIndex++)
            messageAttachments.push({
                "type": "file",
                "localPath": fileItems[fileIndex].path,
                "name": fileItems[fileIndex].name,
                "mimeType": "text/plain",
                "language": fileItems[fileIndex].language || "",
                "size": 0
            });

        _draftSentText = displayText;
        _draftSentHistoryLength = chatbot.messages ? chatbot.messages.length : 0;

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
            var requestParts = mediaParts.slice();
            for (var requestFileIndex = 0; requestFileIndex < fileItems.length; requestFileIndex++)
                requestParts.push({
                    "type": "file",
                    "localPath": fileItems[requestFileIndex].path,
                    "name": fileItems[requestFileIndex].name,
                    "mimeType": "text/plain",
                    "language": fileItems[requestFileIndex].language || "",
                    "size": 0
                });
            chatbot.sendMessageWithMedia(displayText, JSON.stringify(requestParts));
        } else {
            chatbot.sendMessage(displayText, filesJson);
        }
        // C++ 同步校验失败（超限/无内容）已在 onErrorOccurred 里回滚临时气泡，这里不再做后续 UI 动作。
        if (_draftSyncFailed)
            return false;

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
        return true;
    }

    function _dispatchDraftEdit(trimmed) {
        var cppIndex = draftEditingMessageIndex;
        var history = chatbot.messages ? chatbot.messages : [];
        if (cppIndex < 0 || cppIndex >= history.length
                || history[cppIndex].messageId !== _draftEditingMessageId
                || history[cppIndex].role !== "user") {
            toastBanner.warning("原消息已不可编辑，草稿已保留");
            return false;
        }

        // #21-3：编辑时按草稿里的完整附件列表（图片 + 文件 + 音频）全量替换，
        // 顺序 = 模型里的顺序；C++ 检测到 file/audio 条目时走“全量替换”，否则兼容旧行为只重建图片。
        var editParts = [];
        var imageCount = 0;
        for (var mi = 0; mi < attachedMediaModel.count; mi++) {
            var mediaItem = attachedMediaModel.get(mi);
            if (!mediaItem)
                continue;
            if (mediaItem.type === "image_url") {
                var localPath = mediaItem.localPath || "";
                var source = mediaItem.source || mediaItem.url || "";
                if (!localPath && !source)
                    continue;
                editParts.push({
                    "type": "image_url",
                    "source": source,
                    "url": localPath.length > 0 ? "" : source,
                    "localPath": localPath,
                    "name": mediaItem.name || mediaItem.label || "图片",
                    "mimeType": mediaItem.mimeType || "image/jpeg"
                });
                imageCount++;
            } else if (mediaItem.type === "input_audio") {
                if (!chatbot.capAudio || !mediaItem.data)
                    continue;
                editParts.push({
                    "type": "input_audio",
                    "data": mediaItem.data,
                    "format": mediaItem.format || "mp3",
                    "name": mediaItem.name || mediaItem.label || "音频"
                });
            }
        }
        for (var fi = 0; fi < attachedFilesModel.count; fi++) {
            var fileItem = attachedFilesModel.get(fi);
            if (!fileItem || !fileItem.path)
                continue;
            editParts.push({
                "type": "file",
                "localPath": fileItem.path,
                "name": fileItem.name || "文件",
                "mimeType": fileItem.mimeType || "text/plain",
                "language": fileItem.language || "",
                "size": fileItem.size || 0
            });
        }

        var finalText = trimmed;
        if (finalText.length === 0) {
            // 文字清空但附件还在：给与 C++ 落库一致的占位。
            if (imageCount > 0)
                finalText = "[图片]";
            else if (editParts.length > 0)
                finalText = "请阅读附件内容";
        }

        _draftSentText = finalText;
        _draftSentHistoryLength = history.length;

        // 和旧编辑流程一致：编辑目标及其后的行整段换成新的用户气泡 + 思考占位。
        var qmlRow = _findMessageRowById(_draftEditingMessageId);
        var removeFrom = qmlRow >= 0 ? qmlRow : chatModel.count;
        var countToRemove = chatModel.count - removeFrom;
        if (countToRemove > 0)
            chatModel.remove(removeFrom, countToRemove);
        chatModel.append({
            "text": finalText,
            "attachmentsJson": JSON.stringify(editParts),
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

        // 传完整附件列表（图片/文件/音频）；全删时传 "[]"。
        // 新主库优先用 editMessageWithParts（明确全量替换，支持文件增删）；旧主库回退兼容接口。
        if (typeof chatbot.editMessageWithParts === "function")
            chatbot.editMessageWithParts(cppIndex, finalText, JSON.stringify(editParts));
        else if (typeof chatbot.editMessageWithMedia === "function")
            chatbot.editMessageWithMedia(cppIndex, finalText, JSON.stringify(editParts));
        else if (typeof chatbot.editMessage === "function")
            chatbot.editMessage(cppIndex, finalText);
        // 同步校验失败（如角色/索引不合法、媒体超限）已由 onErrorOccurred 回滚。
        if (_draftSyncFailed)
            return false;

        id_chat_assistant_page.isGenerating = true;
        return true;
    }

    // messagesChanged 时判定发送是否已落库：只有确认成功才清草稿，失败保留可重试。
    function _resolveDraftSend() {
        if (!sending || !chatbot)
            return;
        if (_draftSentSessionId !== "" && _draftSentSessionId !== chatbot.currentSessionId) {
            sending = false;
            _draftProxyPending = false;
            return;
        }
        var history = chatbot.messages ? chatbot.messages : [];
        var ok = false;
        if (_draftSentEditIndex >= 0) {
            ok = _draftSentEditIndex < history.length
                    && history[_draftSentEditIndex].role === "user"
                    && history[_draftSentEditIndex].messageId === _draftEditingMessageId
                    && history[_draftSentEditIndex].content === _draftSentText;
        } else {
            ok = history.length > _draftSentHistoryLength
                    && history[history.length - 1].role === "user";
        }
        console.log("[ChatAssistant] resolveDraftSend ok=", ok,
                    "histLen=", history.length, "sentHistLen=", _draftSentHistoryLength,
                    "editIdx=", _draftSentEditIndex,
                    "lastRole=", history.length > 0 ? history[history.length - 1].role : "-",
                    "lastId8=", history.length > 0
                        ? ("" + (history[history.length - 1].messageId || "")).slice(0, 8) : "-");
        if (!ok)
            return;
        _draftProxyPending = false;
        sending = false;
        // 新消息发送：先留一份“发送前草稿”快照，若随后请求失败（离线/服务端错误）可以原样恢复，
        // 并把已落库的失败消息删掉，重试不会重复。编辑旧消息不做回滚（原附件/后续历史已被 C++ 截断）。
        var rollbackSnapshot = null;
        if (_draftSentEditIndex < 0) {
            // 深拷贝：不能保存 ListModel.get() 的结果（clear() 后角色会丢，回滚出空壳附件）。
            var snapMedia = [];
            for (var mi = 0; mi < attachedMediaModel.count; mi++)
                snapMedia.push(_snapshotMediaItem(attachedMediaModel.get(mi)));
            var snapFiles = [];
            for (var fi = 0; fi < attachedFilesModel.count; fi++)
                snapFiles.push(_snapshotFileItem(attachedFilesModel.get(fi)));
            var lastMessage = history[history.length - 1];
            if (lastMessage && lastMessage.role === "user" && lastMessage.messageId) {
                rollbackSnapshot = {
                    "text": draftText,
                    "media": snapMedia,
                    "files": snapFiles,
                    "sessionId": chatbot.currentSessionId,
                    "messageId": lastMessage.messageId
                };
            }
        }
        _clearDraft("resolve-ok");
        if (rollbackSnapshot) {
            _draftRollbackSnapshot = rollbackSnapshot;
            _draftRollbackArmed = true;
            console.log("[ChatAssistant] rollback-armed snapId8=",
                        ("" + rollbackSnapshot.messageId).slice(0, 8),
                        "media=", rollbackSnapshot.media.length, "files=", rollbackSnapshot.files.length);
        }
        _followLatestMessage();
    }

    // 请求失败时尝试把“已落库但没发成功”的用户消息回滚成草稿。
    // 只在：快照仍有效、会话未变、用户没开始新草稿、历史最后一条就是这次发送的消息 时执行。
    function _tryRollbackDraftSend() {
        if (!_draftRollbackArmed || !_draftRollbackSnapshot) {
            console.log("[ChatAssistant] rollback-skip: not-armed");
            return false;
        }
        var snap = _draftRollbackSnapshot;
        var disarm = function (why) {
            console.log("[ChatAssistant] rollback-disarm:", why || "unknown");
            _draftRollbackArmed = false;
            _draftRollbackSnapshot = null;
        };
        var curSession = chatbot ? chatbot.currentSessionId : "";
        if (!chatbot || snap.sessionId !== curSession) {
            disarm("session-mismatch snap=" + ("" + snap.sessionId).slice(0, 8)
                   + " cur=" + ("" + curSession).slice(0, 8));
            return false;
        }
        if (draftVisible && _draftHasContent()) {
            // 用户已经在写新草稿了，不能覆盖。
            disarm("new-draft-in-progress");
            return false;
        }
        var history = chatbot.messages ? chatbot.messages : [];
        if (history.length === 0) {
            disarm("empty-history");
            return false;
        }
        var last = history[history.length - 1];
        if (last.role !== "user" || last.messageId !== snap.messageId) {
            disarm("last-message-mismatch role=" + last.role
                   + " lastId8=" + ("" + (last.messageId || "")).slice(0, 8)
                   + " snapId8=" + ("" + snap.messageId).slice(0, 8));
            return false;
        }
        disarm("restore");
        var failedIndex = history.length - 1;
        _clearDraft("rollback-restore");
        _pendingAttachmentRow = -1;
        draftText = snap.text ? snap.text : "";
        for (var mi = 0; mi < snap.media.length; mi++)
            attachedMediaModel.append(snap.media[mi]);
        for (var fi = 0; fi < snap.files.length; fi++)
            attachedFilesModel.append(snap.files[fi]);
        draftVisible = true;
        _draftSessionId = snap.sessionId;
        // 删除已落库的失败消息（不会触发 API 请求），重试时不会产生重复气泡。
        if (typeof chatbot.deleteMessage === "function")
            chatbot.deleteMessage(failedIndex);
        _rebuildCurrentTurnRows();
        _followLatestMessage();
        console.log("[ChatAssistant] 发送失败，已回滚为草稿（附件", snap.media.length + snap.files.length,
                    "个）snapId8=", ("" + snap.messageId).slice(0, 8));
        return true;
    }

    // 发送失败：回滚临时气泡，但保留草稿文字与附件（附件此时还没写入任何 session 目录）。
    function _failDraftSend(message) {
        sending = false;
        _draftProxyPending = false;
        _rebuildCurrentTurnRows();
        if (!chatbot || _draftSentSessionId === "" || _draftSentSessionId !== chatbot.currentSessionId) {
            _clearDraft("fail-session-gone");
            return;
        }
        if (message)
            toastBanner.error(message, 8000);
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
        // 编辑草稿不能指向被删掉/错位的消息，否则发送会改到别的消息上。
        if (draftEditingMessageIndex === cppIndex) {
            _cancelDraft(true);
        } else if (draftEditingMessageIndex > cppIndex) {
            draftEditingMessageIndex--;
        }
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
        // 重新生成会截断历史：编辑目标落在被截断范围里就取消编辑草稿。
        if (draftEditingMessageIndex >= cppIndex)
            _cancelDraft(true);
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
        // 删除目标之后的历史会消失，编辑草稿指向那里就没有意义了。
        if (draftEditingMessageIndex >= cppIndex)
            _cancelDraft(true);
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

    // 编辑旧消息也走草稿：进入编辑草稿（回填原文字 + 原图片），点「发送」才调用 editMessageWithMedia。
    // 文件/音频附件由 C++ 原样保留（当前不支持在编辑页里增删文件，见 Issue #21-3 的后续扩展）。
    function editMessage(index) {
        if (sending || _preparingSend) {
            toastBanner.warning("发送中，请稍候");
            return;
        }
        if (isGenerating) {
            toastBanner.warning("请等待当前回复完成");
            return;
        }
        var item = chatModel.get(index);
        var cppIndex = _cppIndex(index);
        if (!item || !item.isUser || cppIndex < 0)
            return;
        var history = chatbot.messages;
        var editedMessageId = history[cppIndex] ? history[cppIndex].messageId : "";
        if (!editedMessageId) {
            toastBanner.warning("该消息暂不支持编辑");
            return;
        }

        _clearDraft("edit-start");
        draftEditingMessageIndex = cppIndex;
        _draftEditingMessageId = editedMessageId;
        _draftSessionId = chatbot.currentSessionId;

        var oldAttachments = [];
        try {
            oldAttachments = JSON.parse(item.attachmentsJson || "[]");
        } catch (error) {
            oldAttachments = [];
        }
        var imageCount = 0;
        for (var ai = 0; ai < oldAttachments.length; ai++) {
            var attachment = oldAttachments[ai];
            if (!attachment)
                continue;
            if (attachment.type === "image_url") {
                var source = attachment.source || attachment.url || "";
                attachedMediaModel.append({
                    "type": "image_url",
                    "label": attachment.name || "图片",
                    "source": source,
                    "url": attachment.localPath ? "" : source,
                    "localPath": attachment.localPath || "",
                    "name": attachment.name || "图片",
                    "mimeType": attachment.mimeType || "image/jpeg"
                });
                imageCount++;
            } else if (attachment.type === "input_audio") {
                // 音频与图片一样按“媒体附件”回填，可删可保留；发送时按模型能力决定是否上传。
                attachedMediaModel.append({
                    "type": "input_audio",
                    "data": attachment.data || "",
                    "format": attachment.format || "mp3",
                    "label": attachment.name || "音频",
                    "name": attachment.name || "音频",
                    "localPath": attachment.localPath || "",
                    "mimeType": attachment.mimeType || ""
                });
            } else {
                // 文件：编辑草稿里可删/可继续加（阶段 B 的 editMessageWithMedia 全量替换语义）。
                attachedFilesModel.append({
                    "path": attachment.localPath || "",
                    "name": attachment.name || "文件",
                    "language": attachment.language || "",
                    "size": attachment.size || 0,
                    "mimeType": attachment.mimeType || "text/plain",
                    "type": "file"
                });
            }
        }

        var oldContent = item.raw_text || "";
        // “[图片]”/“请阅读附件内容”是空正文的占位，编辑时不要把它当用户文字回填。
        if (imageCount > 0 && oldContent === "[图片]")
            oldContent = "";
        else if (attachedFilesModel.count > 0 && oldContent === "请阅读附件内容")
            oldContent = "";
        draftText = oldContent;
        draftVisible = true;

        id_session_panel.close();
        id_message_index_panel.close();
        navigateToMessageIndex(index);
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
                // 草稿条盖在列表底部，留出它的高度，最后一条消息不会被挡住。
                anchors.bottomMargin: id_chat_assistant_page.draftVisible ? draftComposer.height + 10 : 2

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
                property bool showScrollToBottom: userScrolledUp && chatModel.count > 0
                                                       && contentHeight > height + bottomThreshold
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
                    toolEntriesJson: model.toolEntriesJson || "[]"
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
                color: YColors.white
                font.family: qmlGlobal.fontFamilyZhCn
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "键盘输入开始对话"
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

        DraftComposerBar {
            id: draftComposer
            anchors {
                left: id_column_sidebar.right
                leftMargin: 6
                right: parent.right
                rightMargin: 6
                bottom: parent.bottom
                bottomMargin: 6
            }
            visible: id_chat_assistant_page.draftVisible
            filesModel: attachedFilesModel
            mediaModel: attachedMediaModel
            draftText: id_chat_assistant_page.draftText
            editing: id_chat_assistant_page.draftEditingMessageIndex >= 0
            sending: id_chat_assistant_page.sending
            fontFamily: qmlGlobal.fontFamilyZhCn
            // 点文字（或左侧键盘按钮）继续改字：✓ 仍然只回写草稿。
            onEditRequested: showKeyboard()
            // 拍照 / 加文件沿用「更多」菜单，草稿条不再多塞两个按钮。
            onAddRequested: id_more_menu.show()
            onCancelRequested: id_chat_assistant_page._cancelDraft(true)
            onSendRequested: id_chat_assistant_page.sendDraft()
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
            onFileReferenceRequested: id_chat_assistant_page._pickDraftFile()
            onNewConversationRequested: {
                if (chatbot) {
                    _prepareSessionChange();
                    chatbot.createSession("新对话");
                }
            }
            // 拍照/选文件只往草稿里追加，绝不自动发送；发送由草稿条的「发送」按钮触发。
            onAttachImageRequested: id_chat_assistant_page._startDraftCapture()
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
            // 生成结束：把生成期间排队的语音/扫描文本按顺序放出去。
            _flushIdleWork();
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

        function show(tpage, initialProps) {
            function restoreAutoSend() {
                if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                    keyBoard.autoSendScan = keyBoard.autoSendScanConfig;
            }
            createPage(Qt.resolvedUrl("./%1.qml".arg(tpage)), tpage, {
                "pageIndex": PageIndex.ChatAssistant,
                "closeOnHomeRelease": true,
                "asynchronous": tpage === "settingpages/ChatAssistantSettings",
                "cleanups": [restoreAutoSend]
            }, initialProps || {}, function(page) {
                if (typeof keyBoard !== 'undefined' && keyBoard !== null)
                    keyBoard.autoSendScan = false;
            });
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
                Qt.callLater(_flushIdleWork);
        }
    }

    Connections {
        target: chatbot
        ignoreUnknownSignals: true

        function onMessageReceived(content, isComplete) {
            // 非流式回复到达 = 请求成功，不再回滚。
            _disarmDraftRollback("message-received");
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
            // 已收到实际内容：之后失败不再回滚（保留消息，交给重新生成）。
            _disarmDraftRollback("reasoning-chunk");

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
            // 已收到实际内容：之后失败不再回滚（保留消息，交给重新生成）。
            _disarmDraftRollback("stream-chunk");
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
            // 重要：Backend::makeApiRequest 在“创建请求时”就同步 emit streamStart（不是收到内容/响应），
            // 所以这里绝不能解除失败回滚，否则离线/连接拒绝时回滚永远失效。
            // 真正“已开始返回内容”的解除点放在 onStreamChunk / onReasoningChunk。
            _toolCallActive = false;
            _resetStreamState();
            var last = chatModel.count - 1;
            if (last >= 0 && chatModel.get(last).isThinking)
                chatModel.setProperty(last, "messageId", chatbot.responseMessageId + ":answer");
        }
        function onMessagesChanged() {
            _historyRevision++;
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
            // 草稿发送是否已落库也由这个信号确认：成功才清草稿。
            _resolveDraftSend();
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
            // 草稿发送失败分三种：
            // 1) 调 API 期间同步抛错（超限/无内容）：消息未落库，保留草稿，回滚临时气泡；
            // 2) 消息已落库、但请求随后失败（离线/服务端错误）：删掉失败消息并把发送前草稿恢复出来（可重试）；
            // 3) 已开始收到回复后的失败：不回滚消息，只提示错误（交给重新生成）。
            var errHist = chatbot && chatbot.messages ? chatbot.messages : [];
            console.log("[ChatAssistant] onErrorOccurred sending=", sending,
                        "armed=", _draftRollbackArmed, "dispatching=", _draftDispatching,
                        "visible=", visible, "draftVisible=", draftVisible,
                        "histLen=", errHist.length,
                        "lastRole=", errHist.length > 0 ? errHist[errHist.length - 1].role : "-",
                        "lastId8=", errHist.length > 0
                            ? ("" + (errHist[errHist.length - 1].messageId || "")).slice(0, 8) : "-");
            var rolledBack = _tryRollbackDraftSend();
            var draftFailed = sending || rolledBack;
            if (_draftDispatching)
                _draftSyncFailed = true;
            toastBanner.error(draftFailed ? (error + "（草稿已保留，可修改后重试）") : error, 8000);
            var lastIndex = chatModel.count - 1;
            if (lastIndex >= 0 && chatModel.get(lastIndex).isThinking)
                chatModel.remove(lastIndex);
            id_chat_assistant_page.isGenerating = false;
            if (sending)
                _failDraftSend("");
            Qt.callLater(_flushIdleWork);
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
            _disarmDraftRollback("request-cancelled");
            _completeLastReasoningCard();
            _resetStreamState();
            _toolCallActive = false;
            shellConfirmDialog.clear();
            _flushStreamBuffer();
            _attachmentReadSeq++;
            _preparingSend = false;
            // 停止生成时如果正处在草稿发送中：草稿没落库，保留下来可以重试。
            var draftCancelled = sending;
            var draftSessionKept = draftCancelled && chatbot
                                   && (_draftSentSessionId === "" || _draftSentSessionId === chatbot.currentSessionId);
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
            if (draftCancelled) {
                sending = false;
                _draftProxyPending = false;
                if (!draftSessionKept)
                    _clearDraft("cancel-session-gone");
                else
                    toastBanner.info("已取消发送，草稿已保留");
            }
            id_chat_assistant_page.isGenerating = false;
            Qt.callLater(_flushIdleWork);
        }
        function onSessionSwitched(sessionId) {
            // 会话切换（包括从外部页面触发）后草稿和待处理队列必须作废，附件不能残留到新 session。
            _clearDraft("session-switched");
            _clearPendingTexts();
            historyLoaded = false;
            loadHistory();
            historyLoaded = true;
        }
        function onProxyVisionStarted() {
            // 视觉代理是异步落库的：标记一下，避免 sendDraft 误判为“C++ 静默拒绝”。
            if (sending)
                _draftProxyPending = true;
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
            // 选择器可能已过期（会话/草稿被重置）：只接受当前草稿请求的结果。
            if (!chatbot || (_filePickSessionId !== "" && _filePickSessionId !== chatbot.currentSessionId)) {
                console.log("[ChatAssistant] 丢弃过期文件选择结果：会话已切换");
                return;
            }
            if (_filePickRequestId !== -1 && _filePickRequestId !== _draftRequestId) {
                console.log("[ChatAssistant] 丢弃过期文件选择结果：草稿已重置");
                return;
            }
            // 多选模式用 ';' 拼接路径（#21-3 支持一次选多个文件）。
            var paths = ("" + filePath).split(';');
            var added = 0;
            for (var i = 0; i < paths.length; i++) {
                var p = paths[i];
                if (!p)
                    continue;
                var name = p.split('/').pop();
                if (_isImageFileName(name)) {
                    if (_appendDraftImagePath(p))
                        added++;
                } else if (_appendDraftFile(p)) {
                    added++;
                }
            }
            if (paths.length > 1)
                toastBanner.info("已添加 " + added + " 个文件附件");
        }
        function onFileSelectionCancelled() {
            // 取消选择不改草稿。
        }

    }

    Connections {
        id: capturePreviewConnections
        target: null
        ignoreUnknownSignals: true

        function onCaptureConfirmed(imageBase64) {
            if (!_validateCaptureResult()) {
                resetCaptureMode();
                return;
            }
            _appendDraftImage(imageBase64);
            resetCaptureMode();
        }
        // 多帧不拼接：逐张作为独立附件加入草稿（#21-3）。
        function onCaptureConfirmedMulti(images) {
            if (!_validateCaptureResult()) {
                resetCaptureMode();
                return;
            }
            var added = 0;
            for (var i = 0; i < images.length; ++i) {
                if (_appendDraftImage(images[i]))
                    added++;
            }
            resetCaptureMode();
            if (added > 0)
                toastBanner.info("已添加 " + added + " 张图片");
        }
        function onCaptureCancelled() {
            resetCaptureMode();
        }
    }

    Connections {
        target: id_pop_container
        function onPopItemObjectChanged() {
            if (id_pop_container.popItemObject && typeof id_pop_container.popItemObject.fileSelected !== 'undefined' && typeof id_pop_container.popItemObject.fileSelectionCancelled !== 'undefined') {
                fileSelectorConnections.target = id_pop_container.popItemObject;
                // 文件选择器默认是单选、且不过滤扩展名；这里把草稿需要的多选/扩展名配置真正下发
                // （qmlGlobal.tempFileSelectorConfig 之前没有消费者，导致多选/过滤一直不生效）。
                id_pop_container.popItemObject.allowMultiSelect = true;
                id_pop_container.popItemObject.fileExtensions = [
                    "txt", "md", "json", "py", "js", "ts", "qml", "cpp", "h", "c", "java",
                    "html", "css", "jpg", "jpeg", "png", "webp", "gif"
                ];
            }
            else if (id_pop_container.popItemObject && typeof id_pop_container.popItemObject.captureConfirmed !== 'undefined')
                capturePreviewConnections.target = id_pop_container.popItemObject;
            else {
                if (captureModeActive)
                    resetCaptureMode();
                fileSelectorConnections.target = null;
                capturePreviewConnections.target = null;
                // 弹层关闭后（拍照页/文件选择器）继续处理排队文本与语音待发送。
                Qt.callLater(id_chat_assistant_page._flushIdleWork);
            }
        }
    }

    Connections {
        target: systemBase
        ignoreUnknownSignals: true
        function onOcrStart() {
            if (mod.voiceChatEnabled)
                return;
            // 只有 AI 助手主界面才保留页面，让拦截后的 scanFinished 进入直发流程。
            // 设置页、输入键盘和其它覆盖层中的扫描仍走原来的普通扫描行为。
            if (typeof keyBoard !== 'undefined' && keyBoard !== null
                    && keyBoard.autoSendScan && id_chat_assistant_page._isMainChatSurface())
                return;
            if (sending || _draftRollbackArmed)
                console.log("[ChatAssistant] OcrStart while draft-send pending -> backButtonClicked");
            backButtonClicked();
        }
        function onOcrCompletedResultChanged() {
            if (typeof keyBoard !== 'undefined' && keyBoard.autoSendScan && id_chat_assistant_page._isMainChatSurface()) {
                if (typeof qmlGlobal.hideDictPage === 'function')
                    qmlGlobal.hideDictPage();
            }
        }
        function onOcrStop(scanType) {
            if (typeof keyBoard !== 'undefined' && keyBoard.autoSendScan && id_chat_assistant_page._isMainChatSurface()) {
                if (typeof qmlGlobal.hideDictPage === 'function')
                    qmlGlobal.hideDictPage();
            }
        }
    }

    Connections {
        target: keyBoard
        ignoreUnknownSignals: true
        function onAutoSendScanConfigChanged() {
            if (id_chat_assistant_page._isMainChatSurface()
                    && typeof keyBoard !== 'undefined' && keyBoard !== null)
                keyBoard.autoSendScan = keyBoard.autoSendScanConfig;
        }
        function onScanFinished(content) {
            var text = content ? ("" + content).trim() : "";
            if (text.length === 0 || !id_chat_assistant_page._isMainChatSurface())
                return;
            // 生成中/键盘或弹层还开着时不能静默丢句：先排队，界面空闲后再按顺序处理。
            if (captureModeActive || (keyboardPageRef && keyboardPageRef.visible)
                    || qmlGlobal.inputPageShowing || id_pop_container.count > 0
                    || isGenerating || sending || _preparingSend) {
                _queuePendingText(text, "scan-busy");
                return;
            }
            if (typeof qmlGlobal.hideDictPage === 'function')
                qmlGlobal.hideDictPage();
            handleUserSend(text);
        }
    }
}
