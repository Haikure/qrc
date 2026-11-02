import QtQuick 2.15

Item {
    id: root
    visible: false
    property var view
    property var model
    // following | reading | locating
    property string mode: "reading"
    property var anchor: null
    property string targetId: ""
    property int epoch: 0
    property bool applying: false
    property int ticks: 0
    readonly property bool interacting: view && (view.dragging || view.flicking)

    function indexForId(id) {
        for (var i = 0; i < model.count; ++i)
            if (model.get(i).messageId === id) return i;
        return -1;
    }
    function capture() {
        if (!view || interacting || applying || mode === "following") return;
        var index = view.probeViewportIndex();
        var item = index >= 0 ? view.itemAtIndex(index) : null;
        if (!item) return;
        anchor = {id: item.messageId, point: item.readingPoint(view.contentY - item.y)};
    }
    function gestureStarted() {
        ++epoch;
        settle.stop();
        followMotion.stop();
        targetId = "";
        anchor = null;
        mode = "reading";
    }
    function gestureEnded() {
        mode = view.atYEnd ? "following" : "reading";
        capture();
        schedule();
    }
    function beforeLayout() {
        if (interacting || applying) return;
        if (mode === "reading" && !anchor) capture();
        schedule();
    }
    function schedule() {
        if (interacting) return;
        ticks = 0;
        if (!settle.running) settle.start();
    }
    function follow() {
        ++epoch;
        mode = "following";
        targetId = "";
        anchor = null;
        apply();
        schedule();
    }
    function locate(index) {
        if (index < 0 || index >= model.count) return;
        ++epoch;
        followMotion.stop();
        mode = "locating";
        targetId = model.get(index).messageId;
        anchor = {id: targetId, point: {block: -1, offset: 0, row: true}};
        apply();
        schedule();
    }
    function apply() {
        if (!view || interacting || applying) return false;
        applying = true;
        view.forceLayout();
        var restored = false;
        if (mode === "following") {
            var bottom = Math.max(view.originY, view.originY + view.contentHeight - view.height);
            if (Math.abs(view.contentY - bottom) < 0.5) {
                followMotion.stop();
                view.contentY = bottom;
            } else if (!followMotion.running || Math.abs(followMotion.to - bottom) > 0.5) {
                followMotion.stop();
                followMotion.from = view.contentY;
                followMotion.to = bottom;
                followMotion.start();
            }
            restored = true;
        } else if (anchor) {
            var index = indexForId(anchor.id);
            if (index >= 0) {
                var item = view.itemAtIndex(index);
                if (!item) {
                    view.positionViewAtIndex(index, ListView.Beginning);
                    view.forceLayout();
                    item = view.itemAtIndex(index);
                }
                if (item) {
                    var y = item.y + item.readingOffset(anchor.point);
                    var maxY = Math.max(view.originY, view.originY + view.contentHeight - view.height);
                    view.contentY = Math.max(view.originY, Math.min(y, maxY));
                    restored = true;
                }
            }
        }
        applying = false;
        return restored;
    }
    NumberAnimation {
        id: followMotion
        target: root.view
        property: "contentY"
        duration: 110
        easing.type: Easing.OutCubic
    }
    onModeChanged: { if (mode !== "following") followMotion.stop(); }
    Component.onDestruction: followMotion.stop()

    Timer {
        id: settle
        interval: 16
        repeat: true
        onTriggered: {
            root.apply();
            // Later layout notifications restart this same controller. A gesture
            // cancels it immediately; no old task can reposition the list later.
            // Follow/reading layouts already notify schedule() when geometry
            // changes. Only a locate needs retries to instantiate a distant row.
            if (++root.ticks >= (root.mode === "locating" ? 4 : 1)) {
                stop();
                if (root.mode === "locating") {
                    root.mode = "reading";
                    root.capture();
                }
            }
        }
    }
}
