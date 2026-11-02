import QtQuick 2.15

// Two glyph runs share a layout: existing text stays opaque while only the
// appended run fades. Opacity animates without rebuilding markup every frame.
Text {
    id: root
    property string rawText: ""
    property string richHtml: ""
    property bool streaming: true
    property bool animateAppend: true
    property string _previous: ""
    property string _prefix: ""
    property string _suffix: ""
    property bool _ready: false

    function escapeText(value) {
        return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                    .replace(/ /g, "&#160;").replace(/\t/g, "&#160;&#160;&#160;&#160;").replace(/\n/g, "<br>");
    }
    function updateText() {
        appendFade.stop();
        var append = _ready && streaming && animateAppend && _previous.length > 0
                     && rawText.length > _previous.length && rawText.indexOf(_previous) === 0;
        _prefix = append ? _previous : rawText;
        _suffix = append ? rawText.slice(_previous.length) : "";
        _previous = rawText;
        if (append) appendFade.restart();
    }
    onRawTextChanged: updateText()
    onStreamingChanged: { if (!streaming) updateText(); }
    Component.onCompleted: { updateText(); _ready = true; }
    Component.onDestruction: appendFade.stop()

    text: richHtml !== "" ? richHtml : (_suffix === "" ? rawText
          : escapeText(_prefix) + '<font color="#00000000">' + escapeText(_suffix) + '</font>')
    textFormat: richHtml !== "" ? Text.RichText : (_suffix === "" ? Text.PlainText : Text.StyledText)
    wrapMode: Text.WrapAnywhere
    color: "#FFFFFF"
    font.pixelSize: 14
    lineHeight: 1.3

    Text {
        id: incoming
        visible: root._suffix !== "" && root.richHtml === ""
        width: root.width
        text: visible ? '<font color="#00000000">' + root.escapeText(root._prefix)
                        + '</font>' + root.escapeText(root._suffix) : ""
        textFormat: Text.StyledText
        wrapMode: root.wrapMode
        color: root.color
        font: root.font
        lineHeight: root.lineHeight
    }
    NumberAnimation {
        id: appendFade
        target: incoming
        property: "opacity"
        from: 0.15
        to: 1
        duration: 110
        easing.type: Easing.OutQuad
    }
}
