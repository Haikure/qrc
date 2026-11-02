import QtQuick 2.12

Rectangle {
    id: root

    property string rawText: ""
    property bool isComplete: false
    property bool richText: false
    property real maxWidth: 300
    property var fontFamily
    property bool animateStreaming: true
    property string _html: ""
    property string _requestId: ""
    readonly property bool renderReady: _requestId === ""

    function scheduleRender() {
        if (_requestId !== "") chatbot.cancelMarkdownParse(_requestId);
        _requestId = "";
        _html = "";
        renderTimer.restart();
    }
    onRawTextChanged: scheduleRender()
    onIsCompleteChanged: scheduleRender()
    onRichTextChanged: scheduleRender()
    Component.onCompleted: scheduleRender()
    Component.onDestruction: {
        if (_requestId !== "") chatbot.cancelMarkdownParse(_requestId);
    }
    Timer {
        id: renderTimer
        interval: 16
        onTriggered: {
            if (!root.richText || !root.isComplete || !root.rawText) return;
            root._requestId = "html:" + Date.now() + ":" + Math.random();
            chatbot.parseMarkdownAsync(root.rawText, root._requestId, true);
        }
    }
    Connections {
        target: typeof chatbot !== "undefined" ? chatbot : null
        function onMarkdownHtmlParsed(requestId, html) {
            if (requestId !== root._requestId) return;
            root._html = html;
            root._requestId = "";
            reveal.restart();
        }
    }
    NumberAnimation { id: reveal; target: messageText; property: "opacity"; from: 0.65; to: 1; duration: 120 }

    function readingPoint(y) { return sourcePosition.point(y - 9, messageText.implicitHeight); }
    function readingOffset(point) { return 9 + sourcePosition.offset(point, messageText.implicitHeight); }

    TextPosition {
        id: sourcePosition
        width: messageText.width
        sourceText: root.rawText
        font.family: root.fontFamily || ""
    }

    readonly property string renderedText: _html !== "" ? _html : rawText

    width: Math.min(maxWidth, messageText.implicitWidth + 26)
    height: Math.max(messageText.implicitHeight + 18, 36)
    implicitWidth: width
    implicitHeight: height
    radius: 16
    color: "#182533"
    clip: true

    Behavior on height {
        enabled: root.animateStreaming && !root.isComplete
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }
    Behavior on width {
        enabled: root.animateStreaming && !root.isComplete
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    StreamingText {
        id: messageText
        anchors.fill: parent
        anchors.leftMargin: 13
        anchors.rightMargin: 13
        anchors.topMargin: 9
        anchors.bottomMargin: 9
        rawText: root.rawText
        richHtml: root._html
        streaming: !root.isComplete
        animateAppend: root.animateStreaming
        wrapMode: Text.WrapAnywhere
        color: "#FFFFFF"
        font.pixelSize: 14
        font.family: root.fontFamily || ""
        lineHeight: 1.3
        linkColor: "#62A8EA"
    }
}
