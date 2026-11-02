import QtQuick 2.12

// Fixed title and clipped lyric viewport. The tap area is a Flickable descendant,
// so native vertical drags can take the grab and cancel a pending tap.
Item {
    id: root
    property string title: ""
    property string fontFamily: ""
    property color titleColor: "#9096a0"
    property color backgroundColor: "black"
    property bool lyricsVisible: true
    property real fadeHeight: 8
    readonly property real contentTop: list.y
    readonly property real contentBottom: list.y + list.height
    property int activeIndex: -1
    property bool browsing: false
    property alias model: list.model
    property alias delegate: list.delegate
    readonly property alias view: list
    readonly property alias titleItem: heading
    signal tapped()

    function followCurrent() {
        if (!visible || browsing || list.dragging || list.flicking || tap.pressed || activeIndex < 0)
            return
        list.forceLayout()
        var item = list.currentItem
        if (!item) return
        var inset = Math.min(root.fadeHeight, 6)
        var available = list.height - inset * 2
        var focus = item.readingOffset !== undefined ? item.readingOffset : 0
        var target = item.height > available
            ? item.y + Math.min(Math.max(0, focus - available * 0.3), item.height - available) - inset
            : item.y - Math.max(inset, (list.height - item.height) * 0.3)
        if (item.height > available) {
            // Keep the end of a bilingual row (translation included) inside the
            // fade area when its singing focus is near the start of a long row.
            target = Math.max(target, item.y + item.height - (list.height - inset))
        }
        target = Math.max(list.originY, Math.min(target, Math.max(list.originY, list.originY + list.contentHeight - list.height)))
        followMotion.stop()
        followMotion.from = list.contentY
        followMotion.to = target
        followMotion.start()
    }
    onActiveIndexChanged: Qt.callLater(followCurrent)
    onBrowsingChanged: {
        if (!browsing) Qt.callLater(followCurrent)
    }
    function beginBrowsing() {
        followMotion.stop()
        resume.stop()
        browsing = true
    }
    function resumeFollowing() {
        resume.stop()
        browsing = false
        list.cancelFlick()
        Qt.callLater(followCurrent)
    }
    function scheduleResume() {
        if (browsing && !list.dragging && !list.flicking && !tap.pressed)
            resume.restart()
    }
    onVisibleChanged: {
        if (!visible) {
            followMotion.stop()
            resumeFollowing()
        } else Qt.callLater(followCurrent)
    }

    Text {
        id: heading
        x: 0; y: 4; width: parent.width; height: 26
        verticalAlignment: Text.AlignVCenter
        text: root.title
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: 16
        color: root.titleColor
        elide: Text.ElideRight
    }

    ListView {
        id: list
        objectName: "lyricViewport"
        anchors { left: parent.left; right: parent.right; top: heading.bottom; topMargin: 0; bottom: parent.bottom }
        visible: root.lyricsVisible
        clip: true
        spacing: 8
        cacheBuffer: 120
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        currentIndex: root.browsing ? -1 : root.activeIndex
        highlightFollowsCurrentItem: false
        highlightRangeMode: ListView.NoHighlightRange
        preferredHighlightBegin: height * 0.4
        preferredHighlightEnd: preferredHighlightBegin + 1
        highlightMoveDuration: 220
        header: Item { width: list.width; height: 6 }
        footer: Item { width: list.width; height: list.height * 0.5 }
        onCurrentItemChanged: Qt.callLater(root.followCurrent)
        onContentHeightChanged: Qt.callLater(root.followCurrent)
        onHeightChanged: Qt.callLater(root.followCurrent)
        onDraggingChanged: {
            if (dragging) root.beginBrowsing()
            else root.scheduleResume()
        }
        onFlickingChanged: {
            if (flicking) root.beginBrowsing()
            else root.scheduleResume()
        }
        onMovementEnded: root.scheduleResume()
    }

    // Background-colour overlays avoid a full offscreen texture pass on the pen.
    Rectangle {
        objectName: "lyricTopFade"
        x: list.x; y: list.y; width: list.width
        height: Math.min(root.fadeHeight, list.height / 2)
        visible: root.lyricsVisible
        gradient: Gradient {
            GradientStop { position: 0; color: root.backgroundColor }
            GradientStop { position: 1; color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g, root.backgroundColor.b, 0) }
        }
    }
    Rectangle {
        objectName: "lyricBottomFade"
        x: list.x; y: list.y + list.height - height; width: list.width
        height: Math.min(root.fadeHeight, list.height / 2)
        visible: root.lyricsVisible
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g, root.backgroundColor.b, 0) }
            GradientStop { position: 1; color: root.backgroundColor }
        }
    }

    MouseArea {
        id: tap
        objectName: "lyricTapArea"
        parent: list.contentItem
        x: 0; y: list.contentY; width: list.width; height: list.height
        z: 100
        acceptedButtons: Qt.LeftButton
        preventStealing: false
        property real pressX: 0
        property real pressY: 0
        property bool moved: false
        onPressed: {
            followMotion.stop()
            pressX = mouse.x
            pressY = mouse.y
            moved = false
            resume.stop()
        }
        onPositionChanged: {
            if (pressed && (Math.abs(mouse.x - pressX) > 8 || Math.abs(mouse.y - pressY) > 8)) {
                moved = true
                root.beginBrowsing()
            }
        }
        onClicked: {
            if (!moved) root.tapped()
            root.scheduleResume()
        }
        onCanceled: {
            moved = true
            root.scheduleResume()
        }
        onReleased: root.scheduleResume()
    }

    NumberAnimation {
        id: followMotion
        target: list
        property: "contentY"
        duration: 220
        easing.type: Easing.OutCubic
    }

    Timer {
        id: resume
        interval: 3000
        onTriggered: {
            if (!list.dragging && !list.flicking && !tap.pressed)
                root.resumeFollowing()
        }
    }
}
