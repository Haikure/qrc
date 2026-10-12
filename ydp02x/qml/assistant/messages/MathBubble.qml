import QtQuick 2.12
import "MathCache.js" as MathCache

// 单个数学公式渲染气泡，调用本地 MathJax 服务（127.0.0.1:3000）
//
// 尺寸约定由服务端保证：所有公式都按同一个基准字号出图；一条式子放不下时服务端
// 在顶层运算符处拆成多行，每行仍是同一个字号，这里只做竖排（续行缩进）。因此
// 客户端不再按气泡宽度拉伸图片——那会让短公式变大、长公式变小。
Item {
    id: root

    property string latex: ""
    property bool display: true          // true=块级，false=行内
    property bool serverAvailable: false
    property real maxWidth: 300
    property var fontFamily
    // 用户正在翻看历史时不播放高度动画：动画会把内容高度拆成 120ms 的连续变化，
    // 公式一多就会让列表反复重排。
    property bool animateHeight: true
    // 续行缩进（换行显示时，第二行起向右缩进，表明是同一式子的延续）
    property real continuationIndent: 14

    property int _state: MathCache.IDLE
    property var _lines: []              // data URI 列表
    property var _widths: []
    property var _heights: []
    property real _gap: 4
    property var _pendingLines: []
    property var _pendingWidths: []
    property var _pendingHeights: []
    property real _pendingGap: 4
    property int _attempts: 0

    signal layoutAboutToChange

    readonly property bool _multiLine: _lines.length > 1
    // 多行时第二行起要缩进 continuationIndent，每行的可用宽度必须先把缩进扣掉：
    // 否则最宽可达 (maxWidth - 8) + 14 = maxWidth + 6，linesBox（左缩进 8）右边缘
    // 到 maxWidth + 14，被外层 aiBubble.clip 裁掉最右侧的字符。
    readonly property real _availableWidth: Math.max(40, maxWidth - 8 - (root._multiLine ? continuationIndent : 0))

    // 每行只在放不下时整体缩小（一般正好是 1:1）
    function _scaleFor(lineWidth) {
        if (!lineWidth || lineWidth <= 0)
            return 1;
        return Math.min(1, _availableWidth / lineWidth);
    }
    function _lineWidth(index) {
        return Math.max(1, (_widths[index] || 0) * _scaleFor(_widths[index]));
    }
    function _lineHeight(index) {
        return Math.max(1, (_heights[index] || 0) * _scaleFor(_widths[index]));
    }
    function _lineY(index) {
        var total = 0;
        for (var i = 0; i < index; i++)
            total += _lineHeight(i) + _gap;
        return total;
    }
    readonly property real _contentWidth: {
        var widest = 0;
        for (var i = 0; i < _lines.length; i++)
            widest = Math.max(widest, _lineWidth(i) + (i > 0 ? continuationIndent : 0));
        return widest;
    }
    readonly property real _contentHeight: {
        if (_lines.length === 0)
            return 0;
        var total = 0;
        for (var i = 0; i < _lines.length; i++)
            total += _lineHeight(i);
        return total + _gap * (_lines.length - 1);
    }

    Timer {
        id: commitTimer
        interval: 150
        repeat: false
        onTriggered: root._commitLines()
    }

    // 按服务端能承受的节奏排队（见 MathCache.reserveSendSlot）
    Timer {
        id: slotTimer
        interval: 0
        repeat: false
        onTriggered: root._enqueue()
    }

    // 服务端限流（HTTP 429）或瞬时失败时重试，避免公式永久停在原文状态。
    Timer {
        id: retryTimer
        interval: 260
        repeat: false
        onTriggered: root._fetchSvg()
    }

    implicitWidth: {
        if (_state === MathCache.DONE)
            return Math.min(_contentWidth + 8, Math.max(maxWidth, 40));
        if (_state === MathCache.ERROR || !serverAvailable)
            return root.display ? maxWidth : Math.min(fallbackText.implicitWidth + 16, maxWidth);
        return 60;
    }
    implicitHeight: {
        if (_state === MathCache.DONE)
            return _contentHeight + 8;
        if (_state === MathCache.ERROR || !serverAvailable)
            return fallbackText.implicitHeight + 12;
        // 占位比最终图矮：高度只会增长。反过来（先高后矮）会让列表在内容收缩时把
        // 视口钳回底部，用户正在往上翻也会被拽下去。
        return 12;
    }

    Behavior on implicitHeight {
        enabled: root.animateHeight
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    onLatexChanged: _reset()
    onServerAvailableChanged: {
        if (serverAvailable && _state === MathCache.IDLE && latex !== "")
            _fetchSvg();
    }
    Component.onCompleted: _reset()

    function _reset() {
        commitTimer.stop();
        retryTimer.stop();
        slotTimer.stop();
        root._pendingLines = [];
        root._pendingWidths = [];
        root._pendingHeights = [];
        root._pendingGap = 4;
        root._state = MathCache.IDLE;
        root._lines = [];
        root._widths = [];
        root._heights = [];
        root._attempts = 0;
        if (root.latex !== "" && root.serverAvailable)
            _fetchSvg();
    }

    function _commitLines() {
        commitTimer.stop();
        if (root._pendingLines.length === 0)
            return;
        root.layoutAboutToChange();
        root._lines = root._pendingLines;
        root._widths = root._pendingWidths;
        root._heights = root._pendingHeights;
        root._gap = root._pendingGap;
        root._pendingLines = [];
        root._pendingWidths = [];
        root._pendingHeights = [];
        root._state = MathCache.DONE;
    }

    function _fetchSvg() {
        if (root.latex === "")
            return;
        if (!root.serverAvailable) {
            // 重试期间服务端变得不可用：必须落到回退态，否则会永远停在加载动画上
            // （回调不会再来，也没有定时器再触发）。
            if (root._state === MathCache.LOADING) {
                root.layoutAboutToChange();
                root._lines = [];
                root._state = MathCache.ERROR;
            }
            return;
        }
        root._state = MathCache.LOADING;
        var wait = MathCache.reserveSendSlot(root.latex, root.display, root.maxWidth);
        if (wait > 0) {
            slotTimer.interval = wait;
            slotTimer.restart();
            return;
        }
        root._enqueue();
    }

    function _enqueue() {
        if (root._state !== MathCache.LOADING)
            return;
        MathCache.enqueueRequest(root.latex, root.display, root.maxWidth, function (result) {
            if (root == null || root._state !== MathCache.LOADING)
                return;
            if (result.success) {
                root._attempts = 0;
                root._pendingLines = result.lines;
                root._pendingWidths = result.widths;
                root._pendingHeights = result.heights;
                root._pendingGap = result.gap;
                // 翻看历史时不延迟提交，高度立即定型。
                // 缓存命中（翻回去重新看到同一个公式）立即显示，不再等 150ms
                if (result.fromCache || !root.animateHeight)
                    root._commitLines();
                else
                    commitTimer.restart();
            } else if (root._attempts < 3) {
                // 指数退避 + 抖动：旧服务端是固定 1 秒窗口，重试必须跨过窗口才有效
                root._attempts++;
                retryTimer.interval = 300 * Math.pow(2, root._attempts - 1) + Math.round(Math.random() * 200);
                retryTimer.restart();
            } else {
                root.layoutAboutToChange();
                root._lines = [];
                root._state = MathCache.ERROR;
            }
        });
    }

    Text {
        id: fallbackText
        visible: root._state === MathCache.ERROR || (!root.serverAvailable && root._state !== MathCache.LOADING)
        text: root.display ? ("$$" + root.latex + "$$") : ("$" + root.latex + "$")
        color: "#A0B8D0"
        font.pixelSize: 13
        font.family: root.fontFamily || ""
        wrapMode: Text.Wrap
        // 块级公式宽度占满行、左对齐；行内公式用自然宽度（居中显示）。
        // 行内必须按 maxWidth 封顶：天然宽度可以到几百 px（实测 1339px），而气泡宽度被
        // implicitWidth 钳在 maxWidth 上，超出的部分会被外层 aiBubble.clip 从两侧裁掉，
        // 只看得到中间一截原文。封顶后交给 wrapMode 折行。
        width: root.display ? Math.max(1, root.maxWidth - 16)
                            : Math.min(Math.max(1, implicitWidth), Math.max(1, root.maxWidth - 16))
        anchors.left: root.display ? parent.left : undefined
        anchors.leftMargin: root.display ? 8 : 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: root.display ? undefined : parent.horizontalCenter
    }

    Row {
        visible: root._state === MathCache.LOADING
        anchors.centerIn: parent
        spacing: 4
        Repeater {
            model: 3
            Rectangle {
                width: 5
                height: 5
                radius: 2.5
                color: "#62A8EA"
                SequentialAnimation on opacity {
                    running: root._state === MathCache.LOADING
                    loops: Animation.Infinite
                    PauseAnimation {
                        duration: index * 160
                    }
                    NumberAnimation {
                        from: 0.3
                        to: 1.0
                        duration: 260
                    }
                    NumberAnimation {
                        from: 1.0
                        to: 0.3
                        duration: 260
                    }
                    PauseAnimation {
                        duration: (2 - index) * 160
                    }
                }
            }
        }
    }

    // 公式行：单行时就是一张图；服务端换行后是多张图竖排，续行缩进
    Item {
        id: linesBox
        visible: root._state === MathCache.DONE && root._lines.length > 0
        width: root._contentWidth
        height: root._contentHeight
        anchors.left: root.display ? parent.left : undefined
        anchors.leftMargin: root.display ? 8 : 0
        anchors.horizontalCenter: root.display ? undefined : parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            model: root._lines
            delegate: Image {
                readonly property real lineScale: root._scaleFor(root._widths[index])
                x: index > 0 ? root.continuationIndent : 0
                y: root._lineY(index)
                width: Math.max(1, (root._widths[index] || 0) * lineScale)
                height: Math.max(1, (root._heights[index] || 0) * lineScale)
                source: modelData
                // lineScale == 1 时 1:1 显示、不做重采样，小字号也能看清晰；
                // lineScale < 1（服务端按 _availableWidth 出图，续行还要再扣缩进）时必须让
                // Image 真正重采样 —— Image.Pad 不缩放，只会居中裁掉公式两端。
                fillMode: lineScale < 1 ? Image.Stretch : Image.Pad
                smooth: lineScale < 1
            }
        }
    }
}
