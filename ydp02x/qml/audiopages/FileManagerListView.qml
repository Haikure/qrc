import QtQuick 2.12
import "../commons"

// Keep the same visible file at the same pixel offset after a model reset.
YBaseListView {
    id: view
    property var directoryPositions: ({})
    property var refreshPosition: null
    property int navigationDirection: 1
    signal navigated()
    clip: true
    interactive: !arrival.running
    transform: Translate { id: slide }

    function capturePosition() {
        var row = indexAt(1, contentY + 1);
        if (row < 0)
            row = indexAt(1, contentY + spacing + 1);
        var item = row >= 0 ? itemAt(1, contentY + 1) : null;
        if (!item && row >= 0)
            item = itemAt(1, contentY + spacing + 1);
        return { name: fileManager.fileNameAt(row), row: row,
                 offset: item ? item.y - contentY : 0, y: contentY };
    }

    function restorePosition(position) {
        forceLayout();
        if (!position) {
            positionViewAtBeginning();
            return;
        }
        while (position.row >= count && fileManager.hasMore)
            fileManager.loadMore();
        var row = fileManager.indexOfFile(position.name);
        if (row < 0)
            row = Math.min(position.row, count - 1);
        if (row >= 0) {
            currentIndex = row;
            positionViewAtIndex(row, ListView.Beginning);
            forceLayout();
            var item = currentItem;
            contentY = item ? item.y - position.offset : position.y;
        } else {
            contentY = position.y;
        }
        contentY = Math.max(originY, Math.min(contentY,
                            originY + Math.max(0, contentHeight - height)));
    }

    YTextBase {
        anchors.centerIn: parent
        visible: view.count === 0 && !view.busying
        text: "空文件夹"
        color: "#929AA5"
        font.pixelSize: 16
    }

    ParallelAnimation {
        id: arrival
        NumberAnimation { target: slide; property: "x"; to: 0; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: view; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }

    Connections {
        target: fileManager
        function onRefreshing() { view.refreshPosition = view.capturePosition(); }
        function onRefreshed() { view.restorePosition(view.refreshPosition); }
        function onDirectoryAboutToChange(backwards) {
            view.directoryPositions[fileManager.getCurrentPathString()] = view.capturePosition();
            view.navigationDirection = backwards ? -1 : 1;
            arrival.stop();
        }
        function onDirectoryLoaded() {
            view.restorePosition(view.directoryPositions[fileManager.getCurrentPathString()]);
            slide.x = view.navigationDirection * 24;
            view.opacity = 0.35;
            arrival.restart();
            view.navigated();
        }
    }
}
