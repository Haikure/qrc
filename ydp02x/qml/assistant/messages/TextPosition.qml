import QtQuick 2.15

// Character positions bridge streaming/plain text and the completed block tree.
// This object measures only instantiated delegates and has no visual geometry.
TextEdit {
    id: root
    visible: false
    readOnly: true
    textFormat: TextEdit.PlainText
    wrapMode: TextEdit.WrapAnywhere
    font.pixelSize: 14
    function point(y, displayedHeight) {
        var scale = displayedHeight > 0 && contentHeight > 0 ? displayedHeight / contentHeight : 1;
        var position = positionAt(0, Math.max(0, y / scale));
        return {block: -1, offset: y, source: position,
                lineOffset: y - positionToRectangle(position).y * scale};
    }
    function offset(point, displayedHeight) {
        if (point.source === undefined) return point.offset;
        var scale = displayedHeight > 0 && contentHeight > 0 ? displayedHeight / contentHeight : 1;
        return positionToRectangle(Math.min(text.length, point.source)).y * scale + (point.lineOffset || 0);
    }
}
