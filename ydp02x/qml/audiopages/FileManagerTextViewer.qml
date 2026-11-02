import QtQuick 2.12
import com.youdao.pen 1.0

import "../commons"
import "../components"
import "../i18n"
import "../assistant/messages"

YBackButtonAudioPage {
    id: id_container_index

    // ── 内容数据 ──
    property variant stringList: {
        var content = (textReader && textReader.content) ? textReader.content : "";
        if (content === "" || (textReader.isMarkdown && _hasMath))
            return [];

        if (!textReader.isMarkdown) {
            return content.split(/\r?\n/);
        }
        return [content];
    }

    readonly property real _contentWidth: id_container_index.width - 54 - 10
    readonly property bool _hasMath: textReader && textReader.isMarkdown
            && /(?:\$|\\\(|\\\[)/.test(textReader.content || "")

    property bool _mathServerAvailable: false
    property int _mathProbeSequence: 0
    property var _mathProbeRequest: null
    property string _renderSessionId: "file:" + textReader.title

    // ── 自动启动数学公式渲染服务器 ──
    function _tryStartMathServer() {
        if (typeof chatbot === "undefined" || chatbot === null)
            return;
        if (!chatbot.mathRenderEnabled)
            return;
        chatbot.startMathServer();
    }

    Component.onCompleted: {
        if (_hasMath)
            _tryStartMathServer();
    }

    Connections {
        target: chatbot
        function onMathRenderConfigChanged() {
            ++_mathProbeSequence;
            if (_mathProbeRequest !== null) {
                _mathProbeRequest.abort();
                _mathProbeRequest = null;
            }
            _mathServerAvailable = false;
            if (_hasMath && chatbot.mathRenderEnabled) {
                _tryStartMathServer();
                mathServerProbe.restart();
            } else {
                mathServerProbe.stop();
            }
        }
    }

    Component.onDestruction: {
        ++_mathProbeSequence;
        if (_mathProbeRequest !== null) _mathProbeRequest.abort();
    }

    // ── 数学服务器健康检查 ──
    Timer {
        id: mathServerProbe
        interval: 5000
        repeat: true
        running: _hasMath && chatbot.mathRenderEnabled && !_mathServerAvailable
        triggeredOnStart: true
        onTriggered: {
            _tryStartMathServer();
            var sequence = ++_mathProbeSequence;
            var xhr = new XMLHttpRequest();
            _mathProbeRequest = xhr;
            xhr.open("GET", "http://127.0.0.1:3000/health", true);
            xhr.timeout = 2000;
            xhr.onreadystatechange = function () {
                if (sequence !== _mathProbeSequence) return;
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    _mathProbeRequest = null;
                    _mathServerAvailable = chatbot.mathRenderEnabled && (xhr.status === 200);
                }
            };
            xhr.ontimeout = function () {
                if (sequence !== _mathProbeSequence) return;
                _mathProbeRequest = null;
                _mathServerAvailable = false;
            };
            try {
                xhr.send();
            } catch (e) {
                _mathServerAvailable = false;
            }
        }
    }

    YVerticalTitleBar {
        id: id_title_bar
        z: 2
        onCallBack: backButtonClicked()
    }

    // ══════════════════════════════════════════
    // 模式 1：纯文本 / 无公式 Markdown
    // ══════════════════════════════════════════
    ListView {
        id: id_content
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 54
        anchors.rightMargin: 10

        clip: true
        visible: !(textReader && textReader.isMarkdown && _hasMath)

        model: stringList
        spacing: 6

        delegate: Text {
            width: ListView.view.width

            text: model.modelData
            font.pixelSize: 16
            font.family: qmlGlobal.fontFamilyZhCn

            textFormat: textReader.isMarkdown ? Text.MarkdownText : Text.PlainText
            wrapMode: Text.WrapAnywhere
            color: YColors.white

            lineHeight: 1.2
        }

        header: id_header_component

        Component {
            id: id_header_component
            Item {
                width: id_content.width
                height: header_text.implicitHeight + 20

                YTextBase {
                    id: header_text
                    color: YColors.grayText
                    font.pixelSize: 16
                    anchors.centerIn: parent
                    width: parent.width
                    elide: YTextBase.ElideRight
                    text: textReader.title
                    horizontalAlignment: Text.AlignLeft
                }
            }
        }
    }

    // ══════════════════════════════════════════
    // 模式 2：Markdown 含数学公式
    // ══════════════════════════════════════════
    Flickable {
        id: id_mathContent
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        clip: true
        visible: textReader && textReader.isMarkdown && _hasMath
        contentHeight: id_mathColumn.height + 20

        Column {
            id: id_mathColumn
            width: id_mathContent.width
            spacing: 8
            topPadding: 10
            bottomPadding: 10

            // 标题
            YTextBase {
                width: parent.width
                color: YColors.grayText
                font.pixelSize: 16
                elide: YTextBase.ElideRight
                text: textReader.title
                horizontalAlignment: Text.AlignLeft
            }

            Loader {
                active: id_container_index._hasMath
                width: parent.width
                onLoaded: {
                    item.rawText = Qt.binding(function() { return textReader.content || ""; });
                    item.isComplete = true;
                }
                sourceComponent: MixedContentBubble {
                    // File previews do not own a chat session. Keep their geometry local;
                    // parsed Markdown and formula images still use the shared bounded caches.
                    savedState: ({height: 0, signature: "", blocks: [], expanded: null})
                    messageId: "document"
                    sessionId: id_container_index._renderSessionId
                    serverAvailable: id_container_index._mathServerAvailable
                    maxWidth: id_container_index._contentWidth
                    fontFamily: qmlGlobal.fontFamilyZhCn
                    layoutBusy: id_mathContent.moving
                    scrolledUp: true
                }
            }
        }
    }

    // ══════════════════════════════════════════
    // 共享的滚动条
    // ══════════════════════════════════════════
    Item {
        id: id_scrollbar_track
        anchors.right: parent.right
        anchors.top: id_content.top
        anchors.bottom: id_content.bottom
        width: 4
        visible: {
            var listViewOk = id_content.visible && id_content.visibleArea.heightRatio < 1.0;
            var mathViewOk = id_mathContent.visible && id_mathContent.contentHeight > id_mathContent.height;
            return (listViewOk || mathViewOk) && id_scrollbar_thumb.opacity > 0.01;
        }

        Rectangle {
            id: id_scrollbar_thumb
            width: parent.width
            radius: 2
            color: YColors.grayText ? YColors.grayText : "#808080"
            opacity: 0.7

            height: {
                if (id_content.visible)
                    return Math.max(20, id_scrollbar_track.height * id_content.visibleArea.heightRatio);
                else
                    return Math.max(20, id_scrollbar_track.height * (id_mathContent.height / id_mathContent.contentHeight));
            }
            y: {
                if (id_content.visible)
                    return id_scrollbar_track.height * id_content.visibleArea.yPosition;
                else
                    return id_scrollbar_track.height * (id_mathContent.contentY / id_mathContent.contentHeight);
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 500
                }
            }
        }

        Timer {
            id: id_scrollbar_hide_timer
            interval: 2000
            repeat: false
            onTriggered: id_scrollbar_thumb.opacity = 0.0
        }

        function show() {
            id_scrollbar_thumb.opacity = 0.7;
            id_scrollbar_hide_timer.restart();
        }
    }

    Connections {
        target: id_content
        function onContentYChanged() {
            id_scrollbar_track.show();
        }
        function onMovementStarted() {
            id_scrollbar_track.show();
        }
        function onMovementEnded() {
            id_scrollbar_hide_timer.restart();
        }
    }

    Connections {
        target: id_mathContent
        function onContentYChanged() {
            id_scrollbar_track.show();
        }
        function onMovementStarted() {
            id_scrollbar_track.show();
        }
        function onMovementEnded() {
            id_scrollbar_hide_timer.restart();
        }
    }
}
