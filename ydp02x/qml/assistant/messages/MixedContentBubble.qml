import QtQuick 2.12
import "MessageLayoutCache.js" as MessageLayoutCache

Item {
    id: root

    property string rawText: ""
    property bool isComplete: false
    property bool serverAvailable: false
    property real maxWidth: 300
    property var fontFamily
    property bool layoutBusy: false
    // 用户正在翻看历史：此时公式为就位不再做高度动画，避免内容高度反复抖动。
    property bool scrolledUp: false
    // 流式期间只渲染尾部文本。
    property bool streamTailOnly: false
    property int parseDelay: 16
    readonly property bool renderReady: _renderReady && !crossFadeAnimation.running

    width: maxWidth
    implicitHeight: !isComplete ? streamingText.implicitHeight
                                : (_renderReady ? richContentColumn.implicitHeight : placeholderHeight)

    property var _blocks: []
    property int _renderGeneration: 0
    property int _loadedBlocks: 0
    property int _visibleBlockCount: 0
    property bool _renderReady: false
    property bool _showSkeleton: true
    property bool _useFastPath: false
    property string _fastHtml: ""
    property real _cachedHeight: 0
    property string _parseRequestId: ""
    property bool _parsePending: false
    property bool _commitPending: false
    // 当前 _blocks 是否来自 C++ 解析器（chatbot.parseMarkdownAsync / MessageLayoutCache）。
    // 它保留下来但四个标志位全为 false 的片段，说明解析器已判定其中没有强调标记，
    // 里面的 * _ 都是字面量，渲染时不能再按正则处理一遍（见 _markersResolved）。
    property bool _nativeBlocks: false
    property string _renderSource: ""
    property bool _hasRenderSource: false
    readonly property real placeholderHeight: streamingText.implicitHeight

    signal renderCommitStarted

    function _commitRender() {
        if (_renderReady)
            return;
        if (layoutBusy) {
            _commitPending = true;
            return;
        }
        _commitPending = false;
        renderWatchdog.stop();
        commitSettleTimer.begin();
    }

    function _finishRenderCommit() {
        if (_renderReady)
            return;
        if (layoutBusy) {
            _commitPending = true;
            return;
        }
        _commitPending = false;
        renderCommitStarted();
        _renderReady = true;
        richContentColumn.opacity = 0;
        _cachedHeight = richContentColumn.implicitHeight;
        MessageLayoutCache.setHeight(rawText, maxWidth, _cachedHeight);
        crossFadeAnimation.restart();
    }

    onLayoutBusyChanged: {
        if (layoutBusy) {
            blockBatchTimer.stop();
            if (_blocks.length === 0) {
                parseTimer.stop();
                if (isComplete && !_renderReady)
                    _parsePending = true;
            }
            return;
        }
        // Commit a completed block tree before a deferred parse.
        if (_commitPending || (_blocks.length > 0 && _loadedBlocks >= _blocks.length)) {
            _parsePending = false;
            _commitRender();
        } else if (_parsePending) {
            _parsePending = false;
            parseTimer.restart();
        } else if (_visibleBlockCount < _blocks.length) {
            blockBatchTimer.restart();
        }
    }

    function _cancelParseRequest() {
        if (_parseRequestId !== "" && typeof chatbot !== "undefined" && chatbot !== null
                && chatbot.cancelMarkdownParse)
            chatbot.cancelMarkdownParse(_parseRequestId);
        _parseRequestId = "";
    }

    function _scheduleParse() {
        if (!isComplete)
            return;

        // Avoid restarting the same parse for the same rawText.
        if (_hasRenderSource && _renderSource === rawText
                && (_renderReady || parseTimer.running || _parsePending || _parseRequestId !== ""
                    || _blocks.length > 0 || _useFastPath || commitSettleTimer.running
                    || _commitPending || renderWatchdog.running))
            return;

        _renderSource = rawText;
        _hasRenderSource = true;
        _cancelParseRequest();
        _renderGeneration++;
        _loadedBlocks = 0;
        _visibleBlockCount = 0;
        _renderReady = false;
        commitSettleTimer.stop();
        _parsePending = false;
        _commitPending = false;
        _showSkeleton = true;
        _useFastPath = false;
        _fastHtml = "";
        _cachedHeight = MessageLayoutCache.getHeight(rawText, maxWidth);
        crossFadeAnimation.stop();
        skeletonPlaceholder.opacity = 1;
        richContentColumn.opacity = 0;
        _blocks = [];
        renderWatchdog.restart();
        if (layoutBusy)
            _parsePending = true;
        else
            parseTimer.restart();
    }

    function _blockLoaded(generation) {
        if (generation !== _renderGeneration)
            return;
        _loadedBlocks++;
        if (_loadedBlocks >= _blocks.length)
            _commitRender();
    }

    onIsCompleteChanged: {
        if (isComplete)
            _scheduleParse();
        else {
            _cancelParseRequest();
            parseTimer.stop();
            blockBatchTimer.stop();
            renderWatchdog.stop();
            _renderGeneration++;
            _blocks = [];
            _renderReady = false;
            commitSettleTimer.stop();
            _parsePending = false;
            _commitPending = false;
            _showSkeleton = false;
            crossFadeAnimation.stop();
        }
    }
    onRawTextChanged: {
        if (isComplete)
            _scheduleParse();
    }
    Component.onCompleted: {
        if (isComplete)
            _scheduleParse();
    }
    Component.onDestruction: _cancelParseRequest()

    Timer {
        id: parseTimer
        interval: root.parseDelay
        repeat: false
        onTriggered: root._parse(root._renderGeneration)
    }

    Timer {
        id: commitSettleTimer
        property real lastHeight: -1
        property int stableFrames: 0
        property int ticks: 0
        interval: 16
        repeat: true

        function begin() {
            if (running)
                return;
            lastHeight = -1;
            stableFrames = 0;
            ticks = 0;
            restart();
        }

        onTriggered: {
            if (root._renderReady) {
                stop();
                return;
            }
            if (root.layoutBusy) {
                stop();
                root._commitPending = true;
                return;
            }

            var currentHeight = richContentColumn.implicitHeight;
            if (lastHeight >= 0 && Math.abs(currentHeight - lastHeight) <= 0.5)
                stableFrames++;
            else
                stableFrames = 0;
            lastHeight = currentHeight;
            ticks++;

            if ((currentHeight > 0 || root.rawText.length === 0) && stableFrames >= 1) {
                stop();
                root._finishRenderCommit();
            } else if (ticks >= 8) {
                stop();
                root._commitPending = true;
                renderWatchdog.restart();
            }
        }
    }

    Timer {
        id: renderWatchdog
        interval: 800
        repeat: false
        onTriggered: {
            if (!root.isComplete || root._renderReady)
                return;
            if (root.layoutBusy) {
                restart();
            } else if (root._useFastPath
                       || (root._blocks.length > 0 && root._loadedBlocks >= root._blocks.length)) {
                root._commitRender();
            } else if (root._blocks.length > 0) {
                if (!blockBatchTimer.running)
                    blockBatchTimer.restart();
                restart();
            } else if (root._parseRequestId !== "") {
                restart();
            } else {
                root._parsePending = false;
                parseTimer.restart();
                restart();
            }
        }
    }

    Connections {
        target: typeof chatbot !== "undefined" ? chatbot : null
        ignoreUnknownSignals: true

        function onMarkdownParsed(requestId, blocksJson) {
            if (requestId !== root._parseRequestId)
                return;
            root._parseRequestId = "";
            var blocks;
            try {
                blocks = JSON.parse(blocksJson);
            } catch (error) {
                parseTimer.restart();
                return;
            }
            MessageLayoutCache.set(root.rawText, blocks, true);
            root._blocks = blocks;
            root._visibleBlockCount = Math.min(3, blocks.length);
            if (blocks.length === 0)
                root._commitRender();
            else
                blockBatchTimer.restart();
        }
    }

    Timer {
        id: blockBatchTimer
        interval: 16
        repeat: true
        onTriggered: {
            if (root.layoutBusy)
                return;
            var remaining = root._blocks.length - root._visibleBlockCount;
            var batchSize = remaining > 24 ? 4 : 3;
            root._visibleBlockCount = Math.min(root._visibleBlockCount + batchSize, root._blocks.length);
            if (root._visibleBlockCount >= root._blocks.length)
                stop();
        }
    }

    SequentialAnimation {
        id: crossFadeAnimation
        ParallelAnimation {
            NumberAnimation {
                target: skeletonPlaceholder
                property: "opacity"
                to: 0
                duration: 140
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: richContentColumn
                property: "opacity"
                to: 1
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction { script: root._showSkeleton = false }
    }

    // ── 阶段 1：流式加载中，纯文本 ──
    Text {
        id: streamingText
        opacity: root.isComplete ? 0 : 1
        width: root.maxWidth
        text: root.streamTailOnly && root.rawText.length > 1500 ? root.rawText.slice(-1500) : root.rawText
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        color: "#FFFFFF"
        font.pixelSize: 14
        font.family: root.fontFamily || ""
        lineHeight: 1.3
    }

    // 完成态的纯文本占位。
    Item {
        id: skeletonPlaceholder
        visible: root.isComplete && root._showSkeleton
        width: root.maxWidth
        height: root.placeholderHeight
        clip: true

        Text {
            anchors.fill: parent
            text: root.rawText
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            color: "#D7E3EE"
            font.pixelSize: 14
            font.family: root.fontFamily || ""
            lineHeight: 1.3
        }
    }

    Column {
        id: richContentColumn
        visible: root.isComplete
        width: root.maxWidth
        spacing: 6
        opacity: 0
        onImplicitHeightChanged: {
            if (!root._renderReady)
                return;
            root._cachedHeight = implicitHeight;
            MessageLayoutCache.setHeight(root.rawText, root.maxWidth, implicitHeight);
        }

        Text {
            id: fastRichText
            visible: root._useFastPath
            width: root.maxWidth
            text: root._fastHtml
            textFormat: Text.RichText
            wrapMode: Text.WrapAnywhere
            color: "#FFFFFF"
            font.pixelSize: 14
            font.family: root.fontFamily || ""
            lineHeight: 1.3
            linkColor: "#62A8EA"
        }

        Repeater {
            model: root.isComplete && !root._useFastPath ? root._blocks.length : 0

            delegate: Loader {
                property int renderGeneration: root._renderGeneration
                property var blockData: root._blocks[index]
                property int reportedGeneration: -1
                // 不要给 Loader 设 width/height：Qt 会把加载项强制设成 Loader 的尺寸，
                // 覆盖它自己算出来的宽度（块级组件都自己设了 width: root.maxWidth）。
                active: index < root._visibleBlockCount

                function reportLoaded() {
                    if (reportedGeneration === renderGeneration)
                        return;
                    reportedGeneration = renderGeneration;
                    root._blockLoaded(renderGeneration);
                }
                asynchronous: false
                sourceComponent: {
                    switch (blockData.type) {
                    case "math_block": return blockMathComponent;
                    case "code_block": return codeBlockComponent;
                    case "heading": return headingComponent;
                    case "list_block": return listBlockComponent;
                    case "blockquote": return blockquoteComponent;
                    case "hr": return hrComponent;
                    case "table": return tableComponent;
                    default: return paragraphComponent;
                    }
                }

                onLoaded: {
                    switch (blockData.type) {
                    case "math_block":
                        item.mContent = blockData.content;
                        break;
                    case "code_block":
                        item.mCode = blockData.content;
                        item.mLanguage = blockData.language || "";
                        break;
                    case "heading":
                        item.mLevel = blockData.level;
                        item.mSegments = blockData.segments;
                        break;
                    case "list_block":
                        item.mItems = blockData.items;
                        item.mOrdered = blockData.ordered || false;
                        break;
                    case "blockquote":
                        item.mSegments = blockData.segments;
                        break;
                    case "hr":
                        break;
                    case "table":
                        item.mHeaders = blockData.headers;
                        item.mRows = blockData.rows;
                        break;
                    default:
                        item.mSegments = blockData.segments;
                        break;
                    }
                    reportLoaded();
                }
                onStatusChanged: {
                    if (status === Loader.Error)
                        reportLoaded();
                }
            }
        }
    }

    // 【A】块级公式
    Component {
        id: blockMathComponent
        MathBubble {
            property string mContent: ""
            latex: mContent
            display: true
            serverAvailable: root.serverAvailable
            maxWidth: root.maxWidth
            animateHeight: !root.scrolledUp
            fontFamily: root.fontFamily
            onLayoutAboutToChange: root.renderCommitStarted()
        }
    }

    // 【B】代码块
    Component {
        id: codeBlockComponent
        Rectangle {
            property string mCode: ""
            property string mLanguage: ""

            width: root.maxWidth
            height: codeLabel.implicitHeight + 16
            radius: 6
            color: "#1E1E1E"
            border.color: "#333333"
            border.width: 1

            Text {
                id: codeLabel
                anchors.fill: parent
                anchors.margins: 8
                text: parent.mCode
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                color: "#D4D4D4"
                font.pixelSize: 12
                font.family: "Courier New, Consolas, monospace"
                lineHeight: 1.4
            }
        }
    }

    // 【C】标题
    Component {
        id: headingComponent
        Flow {
            id: headingFlow
            property int mLevel: 1
            property var mSegments: []
            width: root.maxWidth
            spacing: 2

            Repeater {
                model: mSegments
                delegate: Loader {
                    property real contentWidth: headingFlow.width
                    sourceComponent: modelData.type === "math" ? inlineMathComponent : headingTextComponent
                    onLoaded: {
                        root._applySegment(item, modelData);
                        if (item.mLevel !== undefined)
                            item.mLevel = headingFlow.mLevel;
                    }
                }
            }
        }
    }

    // 【C.1】标题文字
    Component {
        id: headingTextComponent
        Text {
            property string mContent: ""
            property int mLevel: 1
            property bool mBold: false
            property bool mItalic: false
            property bool mCode: false
            property bool mStrike: false

            text: _renderInlineText(mContent, mCode, root._markersResolved(mBold, mItalic, mCode, mStrike))
            textFormat: Text.RichText
            width: Math.min(implicitWidth, root.maxWidth)
            wrapMode: Text.WrapAnywhere
            color: mCode ? "#E8A0BF" : "#FFFFFF"
            font.pixelSize: _headingSize(mLevel)
            font.bold: true
            font.italic: mItalic
            font.strikeout: mStrike
            font.family: mCode ? "Consolas, monospace" : (root.fontFamily || "")
            lineHeight: 1.3

            function _headingSize(level) {
                switch (level) {
                    case 1: return 22;
                    case 2: return 18;
                    case 3: return 16;
                    default: return 15;
                }
            }
        }
    }

    // 【D】列表
    Component {
        id: listBlockComponent
        Column {
            id: listBlockRoot
            property var mItems: []
            property bool mOrdered: false
            width: root.maxWidth
            spacing: 4

            Repeater {
                model: mItems
                delegate: Flow {
                    width: root.maxWidth
                    spacing: 4

                    Text {
                        text: listBlockRoot.mOrdered ? (index + 1) + "." : "•"
                        color: "#AAAAAA"
                        font.pixelSize: 14
                        font.family: root.fontFamily || ""
                        width: listBlockRoot.mOrdered ? 20 : 12
                    }

                    Flow {
                        width: root.maxWidth - (listBlockRoot.mOrdered ? 24 : 16)
                        spacing: 4

                        Repeater {
                            model: modelData
                            delegate: Loader {
                                // 不要给 Loader 设 width：Qt 会把加载项强制缩放成 Loader 的宽度，
                                // 行内公式会被撑满整行、被迫换行。宽度由内容自己决定。
                                property real contentWidth: parent.width
                                sourceComponent: modelData.type === "math" ? inlineMathComponent : textComponent
                                onLoaded: {
                                    if (modelData.type === "math")
                                        item.maxWidth = Math.min(item.maxWidth, contentWidth);
                                    else
                                        item.availableWidth = contentWidth;
                                    root._applySegment(item, modelData);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 【E】引用块
    Component {
        id: blockquoteComponent
        Row {
            property var mSegments: []
            width: root.maxWidth
            // Row 会接管子项的 x，左边距只能用 spacing 表达（写在子项上的 x 会被忽略）。
            spacing: 8

            Rectangle {
                width: 3
                height: quoteFlow.implicitHeight
                color: "#555555"
                radius: 1
            }

            // 必须用 Flow 而不是 Column：引用块里文字与行内公式是同一段话的片段，
            // 用 Column 会让每个片段各占一行（"例2的关键是先用" / 公式 / "与" / 公式 …）。
            Flow {
                id: quoteFlow
                width: parent.width - 11
                spacing: 4

                Repeater {
                    model: parent.parent.mSegments
                    delegate: Loader {
                        property real contentWidth: quoteFlow.width
                        sourceComponent: modelData.type === "math" ? inlineMathComponent : quoteTextComponent
                        onLoaded: {
                            if (modelData.type === "math")
                                item.maxWidth = Math.min(item.maxWidth, contentWidth);
                            else if (item.availableWidth !== undefined)
                                item.availableWidth = contentWidth;
                            root._applySegment(item, modelData);
                        }
                    }
                }
            }
        }
    }

    // 【E.1】引用文字
    Component {
        id: quoteTextComponent
        Text {
            property string mContent: ""
            property bool mBold: false
            property bool mItalic: false
            property bool mCode: false
            property bool mStrike: false
            // 与单元格同理：parent 是 Loader，宽度必须由引用块容器传入。
            property real availableWidth: root.maxWidth

            text: _renderInlineText(mContent, mCode, root._markersResolved(mBold, mItalic, mCode, mStrike))
            textFormat: Text.RichText
            width: Math.min(implicitWidth, availableWidth)
            wrapMode: Text.WrapAnywhere
            color: mCode ? "#E8A0BF" : "#AAAAAA"
            font.pixelSize: 14
            font.family: mCode ? "Consolas, monospace" : (root.fontFamily || "")
            font.bold: mBold
            font.italic: !mCode
            font.strikeout: mStrike
            lineHeight: 1.3
        }
    }

    // 【F】分割线
    Component {
        id: hrComponent
        Rectangle {
            width: root.maxWidth
            height: 1
            color: "#444444"
        }
    }

    // 【G】表格：320px 宽的屏幕放不下多列并排
    //   一律按「每条记录一行一个字段」渲染：字段名（表头）作为浅色标签跟在内容前面，
    //   内容用满整行宽度。分成几列时每格只剩几十像素，公式会被整体压小、文字被挤成
    //   一词一行 —— 屏幕太小，列式表格在这里没有可读性。
    //   空单元格不生成委托；整张表全空时不渲染；行位置在 JS 里累加（定位器在这种嵌套
    //   层次里不会重算隐式尺寸）。
    Component {
        id: tableComponent
        Rectangle {
            id: tableRoot

            property var mHeaders: []
            property var mRows: []
            property var mTableRows: []

            readonly property bool empty: mTableRows.length === 0

            function _rebuildRows() {
                var rows = [];
                var headerCells = _packCells(mHeaders, false);
                if (headerCells.length > 0)
                    rows.push({"header": true, "stripe": false, "cells": headerCells});
                for (var r = 0; r < mRows.length; r++) {
                    var packed = _packCells(mRows[r] || []);
                    if (packed.length > 0)
                        rows.push({"header": false, "stripe": r % 2 === 0, "cells": packed});
                }
                mTableRows = rows;
                Qt.callLater(_relayoutLater);
            }

            function _relayoutLater() {
                tableColumn.relayout();
            }

            // 单元格 → { segments }，空单元格剔除；表头文字作为 label 片段拼在内容前面
            function _packCells(source, withLabel) {
                var packed = [];
                for (var c = 0; c < source.length; c++) {
                    if (root._cellText(source[c]).length === 0)
                        continue;
                    var segments = root._cellSegments(source[c]).slice();
                    var label = (withLabel !== false && mHeaders.length > 1)
                            ? root._cellText(mHeaders[c] || "") : "";
                    if (label.length > 0)
                        segments.unshift({"type": "label", "content": label});
                    packed.push({"column": c, "segments": segments});
                }
                return packed;
            }

            width: root.maxWidth
            // 不能用 visible 隐藏空表：不可见的子树不会走布局，内部高度会一直停在 0，
            // 之后即使有了内容也长不回来。空表用 0 高度 + 无底无边表示。
            height: empty ? 0 : tableColumn.contentHeight + 10
            radius: 4
            color: empty ? "transparent" : "#1A1A1A"
            border.color: "#333333"
            border.width: empty ? 0 : 1

            Component.onCompleted: _rebuildRows()
            onMHeadersChanged: _rebuildRows()
            onMRowsChanged: _rebuildRows()

            Item {
                id: tableColumn
                x: 5
                y: 5
                width: root.maxWidth - 14

                property real contentHeight: 0
                function relayout() {
                    var used = 0;
                    var count = 0;
                    for (var r = 0; r < rowsRepeater.count; r++) {
                        var item = rowsRepeater.itemAt(r);
                        if (!item)
                            continue;
                        item.y = used;
                        used += item.implicitHeight + 7;
                        count++;
                    }
                    contentHeight = count > 0 ? Math.max(0, used - 7) : 0;
                }

                Repeater {
                    id: rowsRepeater
                    model: tableRoot.mTableRows.length

                    delegate: Column {
                        id: recordRow
                        property var mRow: tableRoot.mTableRows[index] || ({})
                        width: tableColumn.width
                        spacing: 3
                        onImplicitHeightChanged: tableColumn.relayout()

                        Rectangle {
                            // 用高度而不是 visible：定位器不会因为子项 visible 变化重算隐式尺寸
                            width: parent.width
                            height: recordRow.mRow.header === true
                                    ? 0
                                    : (recordRow.mRow.stripe === true ? 1 : 0)
                            color: "#2A2A2A"
                        }

                        Repeater {
                            model: (recordRow.mRow.cells || []).length

                            delegate: Flow {
                                id: recordField
                                property var cellData: (recordRow.mRow.cells || [])[index] || ({})
                                width: tableColumn.width
                                spacing: 3

                                Repeater {
                                    model: recordField.cellData.segments || []

                                    delegate: Loader {
                                        // 单元格文字宽度必须由容器传进去：Loader 的宽度跟随 item 的
                                        // 隐式宽度（item 又读 parent.width），读到的是 0，中文会一个字
                                        // 一行竖着堆起来。contentWidth 就是本 Flow 的实际宽度。
                                        property real contentWidth: recordField.width
                                        property bool forceBold: recordRow.mRow.header === true
                                        sourceComponent: modelData.type === "math" ? inlineMathComponent
                                                     : (modelData.type === "label" ? labelTextComponent
                                                                                   : cellTextComponent)
                                        onLoaded: {
                                            if (modelData.type === "math")
                                                item.maxWidth = Math.min(item.maxWidth, contentWidth);
                                            else if (item.availableWidth !== undefined)
                                                item.availableWidth = contentWidth;
                                            root._applySegment(item, modelData);
                                            if (forceBold && item.mBold !== undefined)
                                                item.mBold = true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    // 【2】普通段落
    Component {
        id: paragraphComponent
        Flow {
            property var mSegments: []
            width: root.maxWidth
            spacing: 4

            Repeater {
                model: mSegments
                delegate: Loader {
                    property real contentWidth: root.maxWidth
                    sourceComponent: modelData.type === "math" ? inlineMathComponent : textComponent
                    onLoaded: {
                        if (modelData.type === "math")
                            item.maxWidth = Math.min(item.maxWidth, contentWidth);
                        else
                            item.availableWidth = contentWidth;
                        root._applySegment(item, modelData);
                    }
                }
            }
        }
    }

    // 【2.1】行内公式
    Component {
        id: inlineMathComponent
        MathBubble {
            property string mContent: ""
            latex: mContent
            display: mDisplay
            property bool mDisplay: false
            serverAvailable: root.serverAvailable
            maxWidth: root.maxWidth
            animateHeight: !root.scrolledUp
            fontFamily: root.fontFamily
            onLayoutAboutToChange: root.renderCommitStarted()
        }
    }

    // 【2.2】文字
    Component {
        id: textComponent
        Text {
            property string mContent: ""
            property real availableWidth: root.maxWidth
            property bool mBold: false
            property bool mItalic: false
            property bool mCode: false
            property bool mStrike: false

            text: _renderInlineText(mContent, mCode, root._markersResolved(mBold, mItalic, mCode, mStrike))
            textFormat: Text.RichText
            width: Math.min(implicitWidth, availableWidth)
            wrapMode: Text.WrapAnywhere
            color: mCode ? "#E8A0BF" : "#FFFFFF"
            font.pixelSize: mCode ? 12 : 14
            font.family: mCode ? "Consolas, monospace" : (root.fontFamily || "")
            font.bold: mBold
            font.italic: mItalic
            font.strikeout: mStrike
            lineHeight: 1.3
            linkColor: "#62A8EA"
            verticalAlignment: Text.AlignVCenter
        }
    }

    // 【2.3】表格里的表头标签（跟内容同一行，内容因此能用满整行宽度）
    Component {
        id: labelTextComponent
        Text {
            property string mContent: ""
            // 由承载它的 Flow 通过 Loader.onLoaded 传入；表头很长时按容器宽度换行而不是溢出。
            property real availableWidth: root.maxWidth
            text: mContent + "："
            color: "#9FB2C4"
            font.pixelSize: 11
            font.family: root.fontFamily || ""
            wrapMode: Text.WrapAnywhere
            width: Math.min(implicitWidth, availableWidth)
        }
    }

    // 【2.3.1】表格单元格文字
    Component {
        id: cellTextComponent
        Text {
            property string mContent: ""
            property bool mBold: false
            property bool mItalic: false
            property bool mCode: false
            property bool mStrike: false
            // 和 textComponent 一样由容器（单元格 Flow）传入可用宽度。这里不能读
            // parent.width：parent 是 Loader，Loader 的宽度又跟随本项，创建时算成 0。
            property real availableWidth: root.maxWidth

            text: _renderInlineText(mContent, mCode, root._markersResolved(mBold, mItalic, mCode, mStrike))
            textFormat: Text.RichText
            width: Math.min(implicitWidth, availableWidth)
            wrapMode: Text.WrapAnywhere
            color: mCode ? "#E8A0BF" : (mBold ? "#FFFFFF" : "#DDDDDD")
            font.pixelSize: mCode ? 10 : 11
            font.family: mCode ? "Consolas, monospace" : (root.fontFamily || "")
            font.bold: mBold
            font.italic: mItalic
            font.strikeout: mStrike
            lineHeight: 1.2
        }
    }

    // ── 行内 Markdown 渲染 ──
    // 解析器（chatbot.parseMarkdownAsync）会把粗体/斜体/行内代码转成片段标志位，
    // 这类片段的标记已被消费，不能再按正则处理一遍，否则 `**$x$**` 会残留 `**`。
    // 注意「四个标志位全是 false」不等于「没有解析过」：C++ 解析器只在标志为真时才
    // 输出该字段，正文里的字面量 `*`/`_`（`2 * 3 * 4`、`snake_case_name`、`\*`）同样
    // 是这种片段。按正则再处理一遍会把这些字面量吃成斜体（实测 “2 * 3 * 4” 渲染成
    // “2 3 4”）—— 所以判据是「片段来自哪个解析器」，_nativeBlocks 由 _parse 写入。
    function _markersResolved(bold, italic, code, strike) {
        return _nativeBlocks || bold === true || italic === true || code === true || strike === true;
    }

    function _escapeHtml(raw) {
        return raw.replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
    }

    function _renderInlineText(raw, isCode, markersResolved) {
        if (!raw || raw.length === 0)
            return "";
        if (isCode)
            return '<code style="background:#3a3a3a;padding:1px 4px;border-radius:3px;font-family:Consolas,monospace;font-size:12px;color:#E8A0BF">'
                    + _escapeHtml(raw) + '</code>';
        return _renderMarkdownInline(raw, markersResolved === true);
    }

    // 把解析器给出的片段标志写进委托。
    function _applySegment(item, segment) {
        if (!item || !segment)
            return;
        if (segment.type === "math") {
            if (item.mDisplay !== undefined)
                item.mDisplay = segment.display === true;
            item.mContent = segment.content;
            return;
        }
        item.mContent = segment.content;
        if (item.mBold !== undefined)
            item.mBold = segment.bold === true;
        if (item.mItalic !== undefined)
            item.mItalic = segment.italic === true;
        if (item.mCode !== undefined)
            item.mCode = segment.code === true;
        if (item.mStrike !== undefined)
            item.mStrike = segment.strike === true;
    }

    // 单元格纯文本（判断是否空单元格、以及表头标签）
    function _cellText(cell) {
        var segments = _cellSegments(cell);
        var text = "";
        for (var i = 0; i < segments.length; i++)
            text += segments[i].content || "";
        return text.trim();
    }

    // 兼容旧解析路径（无 chatbot 时的 JS 解析器）给出的纯字符串单元格。
    function _cellSegments(cell) {
        if (cell === undefined || cell === null)
            return [];
        if (typeof cell === "string")
            return cell.length > 0 ? [{
                "type": "text",
                "content": cell
            }] : [];
        return cell;
    }

    function _renderMarkdownInline(raw, emphasisResolved) {
        if (!raw || raw.length === 0)
            return "";

        var t = _escapeHtml(raw);

        var codeSpans = [];
        if (!emphasisResolved) {
            t = t.replace(/`([^`\n]+?)`/g, function (match, code) {
                var ph = "\x00C" + codeSpans.length + "\x00";
                codeSpans.push('<code style="background:#3a3a3a;padding:1px 4px;border-radius:3px;font-family:Consolas,monospace;font-size:12px;color:#E8A0BF">' + code + '</code>');
                return ph;
            });
        }

        t = t.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<a href="$2" style="color:#62A8EA">[$1]</a>');
        t = t.replace(/\[([^\]]+?)\]\(([^)]+?)\)/g, '<a href="$2" style="color:#62A8EA;text-decoration:none">$1</a>');
        if (!emphasisResolved) {
            t = t.replace(/\*\*\*(.+?)\*\*\*/g, '<b><i>$1</i></b>');
            t = t.replace(/___(.+?)___/g, '<b><i>$1</i></b>');
            t = t.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
            t = t.replace(/__(.+?)__/g, '<b>$1</b>');
            t = t.replace(/\*(.+?)\*/g, '<i>$1</i>');
            t = t.replace(/_(.+?)_/g, '<i>$1</i>');
        }
        t = t.replace(/~~(.+?)~~/g, '<s>$1</s>');
        t = t.replace(/==(.+?)==/g, '<span style="background:#FFFF0033">$1</span>');

        for (var i = 0; i < codeSpans.length; i++) {
            t = t.replace("\x00C" + i + "\x00", codeSpans[i]);
        }

        return t;
    }

    function _requiresBlockLayout(text) {
        return text.indexOf("```") !== -1
                || text.indexOf("$") !== -1
                || text.indexOf("\\(") !== -1
                || text.indexOf("\\[") !== -1
                || /(^|\n)\s*\|.+\|\s*(\n|$)/.test(text);
    }

    function _renderMarkdownDocument(raw) {
        var cachedHtml = MessageLayoutCache.getHtml(raw);
        if (cachedHtml !== null)
            return cachedHtml;
        var html = "";
        if (typeof chatbot !== "undefined" && chatbot !== null && chatbot.markdownToHtml)
            html = chatbot.markdownToHtml(raw);
        if (!html || html.length === 0)
            html = _renderMarkdownInline(raw).replace(/\n/g, "<br>");
        MessageLayoutCache.setHtml(raw, html);
        return html;
    }

    // ── 解析器 ──
    function _parse(generation) {
        if (generation !== _renderGeneration)
            return;
        _parsePending = false;
        var text = rawText;
        if (!text || text.length === 0) {
            _blocks = [];
            _commitRender();
            return;
        }

        var asyncParserAvailable = typeof chatbot !== "undefined" && chatbot !== null
                                   && chatbot.parseMarkdownAsync;
        if (asyncParserAvailable) {
            _useFastPath = false;
            _fastHtml = "";
            var asyncCached = MessageLayoutCache.get(text);
            if (asyncCached !== null) {
                // 缓存里的块可能来自 JS 兜底解析器，来源要跟着缓存一起取回来。
                _nativeBlocks = MessageLayoutCache.getNative(text);
                _blocks = asyncCached;
                _visibleBlockCount = Math.min(3, asyncCached.length);
                if (asyncCached.length === 0)
                    _commitRender();
                else
                    blockBatchTimer.restart();
                return;
            }
            // 交给 C++ 解析器，产出带强调标志位的块。
            _nativeBlocks = true;
            _parseRequestId = String(_renderGeneration) + ":" + String(Date.now()) + ":" + String(Math.random());
            chatbot.parseMarkdownAsync(text, _parseRequestId);
            return;
        }

        if (!_requiresBlockLayout(text)) {
            _useFastPath = true;
            _fastHtml = _renderMarkdownDocument(text);
            _blocks = [];
            _commitRender();
            return;
        }

        _useFastPath = false;
        _fastHtml = "";
        var cached = MessageLayoutCache.get(text);
        if (cached !== null) {
            // 同上：缓存可能来自 JS 兜底解析器，来源要一起取回来。
            _nativeBlocks = MessageLayoutCache.getNative(text);
            _blocks = cached;
            _visibleBlockCount = Math.min(3, cached.length);
            if (cached.length === 0)
                _commitRender();
            else
                blockBatchTimer.restart();
            return;
        }

        // 下面这段 JS 解析器只输出 {type, content}，没有强调标志位，必须靠正则兜底。
        _nativeBlocks = false;
        var blocks = [];
        var currentSegments = [];
        var i = 0;
        var textStart = 0;

        function flushParagraph() {
            if (currentSegments.length > 0) {
                blocks.push({ type: "paragraph", segments: currentSegments });
                currentSegments = [];
            }
        }

        function lineEnd(from) {
            var pos = text.indexOf("\n", from);
            return pos === -1 ? text.length : pos;
        }

        function isLineStart(pos) {
            if (pos === 0) return true;
            for (var j = pos - 1; j >= 0; j--) {
                if (text[j] === "\n") return true;
                if (text[j] !== " " && text[j] !== "\t") return false;
            }
            return true;
        }

        while (i < text.length) {

            // ── 1. 围栏代码块 ``` ──
            if (text.substr(i, 3) === "```") {
                var afterTick = i + 3;
                var langEnd = lineEnd(afterTick);
                var lang = text.slice(afterTick, langEnd).trim();
                var codeStart = langEnd + 1;
                var closing = text.indexOf("\n```", codeStart);
                if (closing !== -1) {
                    if (i > textStart) {
                        _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                    }
                    flushParagraph();
                    blocks.push({ type: "code_block", content: text.slice(codeStart, closing), language: lang });
                    i = closing + 4;
                    textStart = i;
                    continue;
                }
            }

            // ── 2a. 块级公式 $$ ──
            if (text.substr(i, 2) === "$$") {
                var endD = text.indexOf("$$", i + 2);
                if (endD !== -1) {
                    if (i > textStart)
                        _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                    flushParagraph();
                    blocks.push({ type: "math_block", content: text.slice(i + 2, endD).trim() });
                    i = endD + 2;
                    textStart = i;
                    continue;
                }
            }

            // ── 2b. 块级公式 \[ ──
            if (text.substr(i, 2) === "\\[") {
                var endD2 = text.indexOf("\\]", i + 2);
                if (endD2 !== -1) {
                    if (i > textStart)
                        _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                    flushParagraph();
                    blocks.push({ type: "math_block", content: text.slice(i + 2, endD2).trim() });
                    i = endD2 + 2;
                    textStart = i;
                    continue;
                }
            }

            // ── 行首结构 ──
            if (isLineStart(i)) {
                var le = lineEnd(i);
                var currentLine = text.slice(i, le);

                // ── 3. 标题 ──
                var hm = currentLine.match(/^(#{1,6})\s+(.+)$/);
                if (hm) {
                    if (i > textStart)
                        _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                    flushParagraph();
                    var headingText = hm[2].trim().replace(/\s+#+\s*$/, "");
                    blocks.push({ type: "heading", level: hm[1].length, segments: [{ type: "text", content: headingText }] });
                    i = le + 1;
                    textStart = i;
                    continue;
                }

                // ── 4. 分割线 ──
                if (/^(\*{3,}|-{3,}|_{3,})\s*$/.test(currentLine)) {
                    if (i > textStart)
                        _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                    flushParagraph();
                    blocks.push({ type: "hr" });
                    i = le + 1;
                    textStart = i;
                    continue;
                }

                // ── 5. 引用块 ──
                if (/^>\s?/.test(currentLine)) {
                    if (i > textStart)
                        _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                    flushParagraph();
                    var bqSegs = [];
                    while (i < text.length && isLineStart(i) && /^>\s?/.test(text.slice(i, lineEnd(i)))) {
                        var bqLine = text.slice(i, lineEnd(i));
                        var bqContent = bqLine.replace(/^>\s?/, "").trim();
                        bqSegs.push({ type: "text", content: bqContent.length > 0 ? bqContent : "\n" });
                        i = lineEnd(i) + 1;
                    }
                    textStart = i;
                    if (bqSegs.length > 0)
                        blocks.push({ type: "blockquote", segments: bqSegs });
                    continue;
                }

                // ── 6. 无序列表 ──
                if (/^[\-\*\+]\s+/.test(currentLine)) {
                    if (i > textStart)
                        _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                    flushParagraph();
                    var ulItems = [];
                    while (i < text.length && isLineStart(i)) {
                        var ulLe = lineEnd(i);
                        var ulLine = text.slice(i, ulLe);
                        if (!/^[\-\*\+]\s+/.test(ulLine)) break;
                        ulItems.push([{ type: "text", content: ulLine.replace(/^[\-\*\+]\s+/, "").trim() }]);
                        i = ulLe + 1;
                    }
                    textStart = i;
                    blocks.push({ type: "list_block", ordered: false, items: ulItems });
                    continue;
                }

                // ── 7. 有序列表 ──
                if (/^\d+\.\s+/.test(currentLine)) {
                    if (i > textStart)
                        _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                    flushParagraph();
                    var olItems = [];
                    while (i < text.length && isLineStart(i)) {
                        var olLe = lineEnd(i);
                        var olLine = text.slice(i, olLe);
                        if (!/^\d+\.\s+/.test(olLine)) break;
                        olItems.push([{ type: "text", content: olLine.replace(/^\d+\.\s+/, "").trim() }]);
                        i = olLe + 1;
                    }
                    textStart = i;
                    blocks.push({ type: "list_block", ordered: true, items: olItems });
                    continue;
                }

                // ── 8. 表格 ──
                if (/^\|/.test(currentLine)) {
                    var tableLines = [];
                    var tableStartIdx = i;
                    while (i < text.length && isLineStart(i) && /^\|/.test(text.slice(i, lineEnd(i)))) {
                        tableLines.push(text.slice(i, lineEnd(i)));
                        i = lineEnd(i) + 1;
                    }

                    if (tableLines.length >= 2) {
                        var headerCells = _parseTableRow(tableLines[0]);
                        var sepCells = _parseTableRow(tableLines[1]);
                        var isSep = true;
                        for (var s = 0; s < sepCells.length; s++) {
                            if (!/^:?-+:?$/.test(sepCells[s])) { isSep = false; break; }
                        }

                        if (isSep && headerCells.length > 0) {
                            if (tableStartIdx > textStart)
                                _appendText(text.slice(textStart, tableStartIdx), currentSegments, flushParagraph);
                            flushParagraph();
                            var dataRows = [];
                            for (var r = 2; r < tableLines.length; r++)
                                dataRows.push(_parseTableRow(tableLines[r]));
                            for (var dr = 0; dr < dataRows.length; dr++) {
                                while (dataRows[dr].length < headerCells.length)
                                    dataRows[dr].push("");
                                dataRows[dr] = dataRows[dr].slice(0, headerCells.length);
                            }
                            blocks.push({ type: "table", headers: headerCells, rows: dataRows });
                            textStart = i;
                            continue;
                        }
                    }

                    _appendText(text.slice(tableStartIdx, i), currentSegments, flushParagraph);
                    textStart = i;
                    continue;
                }
            }

            // ── 9. 行内公式 \( ──
            if (text.substr(i, 2) === "\\(") {
                var endI = text.indexOf("\\)", i + 2);
                if (endI !== -1) {
                    if (i > textStart)
                        _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                    currentSegments.push({ type: "math", content: text.slice(i + 2, endI).trim() });
                    i = endI + 2;
                    textStart = i;
                    continue;
                }
            }

            // ── 10. 行内公式 $ ──
            if (text[i] === "$" && text.substr(i, 2) !== "$$") {
                if (i + 1 < text.length && text[i + 1] !== " " && text[i + 1] !== "\n") {
                    var endI2 = -1;
                    var sf = i + 1;
                    while (sf < text.length) {
                        var found = text.indexOf("$", sf);
                        if (found === -1) break;
                        if (found + 1 < text.length && text[found + 1] === "$") { sf = found + 2; continue; }
                        if (found > i + 1 && text[found - 1] !== " ") { endI2 = found; break; }
                        sf = found + 1;
                    }
                    if (endI2 !== -1) {
                        if (i > textStart)
                            _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                        currentSegments.push({ type: "math", content: text.slice(i + 1, endI2).trim() });
                        i = endI2 + 1;
                        textStart = i;
                        continue;
                    }
                }
            }

            // ── 11. 行内代码 ` ──
            if (text[i] === "`" && text.substr(i, 3) !== "```") {
                var endC = text.indexOf("`", i + 1);
                if (endC !== -1 && endC > i + 1) {
                    if (i > textStart)
                        _appendText(text.slice(textStart, i), currentSegments, flushParagraph);
                    currentSegments.push({ type: "text", content: text.slice(i, endC + 1) });
                    i = endC + 1;
                    textStart = i;
                    continue;
                }
            }

            i++;
        }

        // 尾部
        if (textStart < text.length)
            _appendText(text.slice(textStart), currentSegments, flushParagraph);
        flushParagraph();

        if (generation !== _renderGeneration)
            return;
        MessageLayoutCache.set(text, blocks, false);
        _blocks = blocks;
        _visibleBlockCount = Math.min(3, blocks.length);
        if (blocks.length === 0)
            _commitRender();
        else blockBatchTimer.restart();
    }

    function _parseTableRow(line) {
        var cells = [];
        var trimmed = line.replace(/^\s*\|/, "").replace(/\|\s*$/, "");
        var parts = trimmed.split("|");
        for (var p = 0; p < parts.length; p++)
            cells.push(parts[p].trim());
        return cells;
    }

    function _appendText(text, segments, flushFn) {
        if (!text || text.length === 0) return;
        var lines = text.split(/\r?\n/);
        for (var l = 0; l < lines.length; l++) {
            if (lines[l] !== "")
                segments.push({ type: "text", content: lines[l] });
            if (l < lines.length - 1)
                flushFn();
        }
    }
}
