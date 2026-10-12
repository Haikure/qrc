// 跨组件 SVG/PNG 缓存 + 并发请求队列
// 键格式：latex + "|" + (display ? "d" : "i") + "|" + 可用宽度
// 值格式：{ lines: [dataUri…], widths: [px…], heights: [px…], gap: px }
// 长公式由服务端拆成多行（每行同一字号），因此缓存的是整组行。
.pragma library

// ── 状态枚举（替代字符串比较，减少 QML 绑定中的比较开销）──
var IDLE = 0;
var LOADING = 1;
var DONE = 2;
var ERROR = 3;

// ── LRU 缓存 ──
// 一轮长会话里所有公式都留着：用户往上翻历史时，同一公式（同宽）会再次命中缓存，
// 不必重新请求服务端、也不会闪一下占位。1200 条约等于 100 个含公式的长回答。
var _MAX = 1200;
var _store = {};
var _order = [];

// ── 发送节奏 ──
// 返回调用方还需要等待的毫秒数（0 表示可以立刻发送）。缓存命中或已有同公式在途时
// 不占额度，避免同一公式被多次排队。
function reserveSendSlot(latex, display, maxWidth) {
    var key = _cacheKey(latex, display, maxWidth);
    if (_store.hasOwnProperty(key) || _waiters.hasOwnProperty(key))
        return 0;
    var now = Date.now();
    var at = Math.max(now, _nextSendAt);
    _nextSendAt = at + MIN_SEND_GAP_MS;
    return Math.round(at - now);
}

var _nextSendAt = 0;

// ── 并发请求队列 ──
var _MAX_CONCURRENT = 4;            // 同一时间最多 4 个进行中的 XHR
// 发送节奏：约 8 请求/秒。旧版服务端每个 IP 每秒只放行 10 次，客户端的 4 并发会在
// 几百毫秒内把额度打满，导致一条长回答里后半截公式全部 429；按这个节奏发送，
// 无论服务端新旧都不会被限流。
var MIN_SEND_GAP_MS = 120;
var _requestQueue = [];           // 排队等待的请求
var _activeCount = 0;            // 当前进行中的请求数
var _waiters = {};               // cacheKey -> 等待同一公式的回调列表

function _cacheKey(latex, display, maxWidth) {
    return latex + "|" + (display ? "d" : "i") + "|" + Math.round(maxWidth || 0);
}

// ── 原有 LRU 缓存接口 ──
function get(key) {
    if (!_store.hasOwnProperty(key)) return null;
    var idx = _order.indexOf(key);
    if (idx !== -1) _order.splice(idx, 1);
    _order.push(key);
    return _store[key];
}

function set(key, val) {
    if (_store.hasOwnProperty(key)) {
        _store[key] = val;
        var idx = _order.indexOf(key);
        if (idx !== -1) _order.splice(idx, 1);
        _order.push(key);
        return;
    }
    if (_order.length >= _MAX) {
        var evict = _order.shift();
        delete _store[evict];
    }
    _store[key] = val;
    _order.push(key);
}

// ── 并发请求队列 ──
// 同一公式（同宽度）在一次渲染期间只会发出一个请求，其余气泡等待同一个结果。
function enqueueRequest(latex, display, maxWidth, resolveCallback) {
    var cacheKey = _cacheKey(latex, display, maxWidth);
    var cached = get(cacheKey);
    if (cached !== null) {
        resolveCallback({ success: true, lines: cached.lines, widths: cached.widths,
                          heights: cached.heights, gap: cached.gap, fromCache: true });
        return;
    }
    if (_waiters.hasOwnProperty(cacheKey)) {
        _waiters[cacheKey].push(resolveCallback);
        return;
    }
    _waiters[cacheKey] = [resolveCallback];
    _requestQueue.push({
        latex: latex,
        display: display,
        maxWidth: Math.round(maxWidth || 0),
        cacheKey: cacheKey
    });
    _drainQueue();
}

function _settle(cacheKey, result) {
    var waiters = _waiters[cacheKey];
    if (waiters === undefined) return;
    delete _waiters[cacheKey];
    for (var i = 0; i < waiters.length; i++) waiters[i](result);
}

function _drainQueue() {
    while (_activeCount < _MAX_CONCURRENT && _requestQueue.length > 0) {
        var item = _requestQueue.shift();
        _activeCount++;
        _executeXhr(item);
    }
}

function _executeXhr(item) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", "http://127.0.0.1:3000/render", true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        _activeCount--;
        if (xhr.status === 200) {
            try {
                var resp = JSON.parse(xhr.responseText);
                var record = _toRecord(resp);
                if (record === null) {
                    _settle(item.cacheKey, { success: false, error: "响应缺少图片数据" });
                } else {
                    set(item.cacheKey, record);
                    _settle(item.cacheKey, { success: true, lines: record.lines, widths: record.widths,
                                             heights: record.heights, gap: record.gap,
                                             renderer: resp.renderer || 1 });
                }
            } catch (e) {
                _settle(item.cacheKey, { success: false, error: "解析响应失败" });
            }
        } else {
            try {
                var errMsg = JSON.parse(xhr.responseText).error || ("HTTP " + xhr.status);
                // 失败不入缓存：调用方可以重试。
                _settle(item.cacheKey, { success: false, error: errMsg, status: xhr.status });
            } catch (e) {
                _settle(item.cacheKey, { success: false, error: "HTTP " + xhr.status, status: xhr.status });
            }
        }
        _drainQueue(); // 处理下一个排队请求
    };
    // screenWidth 让服务端知道气泡可用宽度：服务端按 screenWidth - 20 出图，而气泡单行实际只能
    // 显示 maxWidth - 8（MathBubble._availableWidth），所以这里要传 maxWidth + 12 让两边对齐；
    // 续行还要再扣 continuationIndent，由 MathBubble 按 lineScale 缩小。
    xhr.send(JSON.stringify({ latex: item.latex, display: item.display, screenWidth: item.maxWidth + 12 }));
}

// 服务端响应 → 缓存记录。旧版服务只有单张图，也按一行处理。
function _toRecord(resp) {
    var lines = [];
    var widths = [];
    var heights = [];
    if (resp.lines && resp.lines.length > 0) {
        for (var i = 0; i < resp.lines.length; i++) {
            var line = resp.lines[i];
            if (!line || typeof line.data !== "string" || line.data.length === 0)
                return null;
            lines.push("data:image/png;base64," + line.data);
            widths.push(line.width || 0);
            heights.push(line.height || 0);
        }
    } else if (typeof resp.data === "string" && resp.data.length > 0) {
        lines.push("data:image/png;base64," + resp.data);
        widths.push(resp.width || 0);
        heights.push(resp.height || 0);
    } else {
        return null;
    }
    return {
        lines: lines,
        widths: widths,
        heights: heights,
        gap: resp.gap || 4
    };
}
