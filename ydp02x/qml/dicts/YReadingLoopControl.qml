import QtQuick 2.12
import "../commons"

// An explicit, result-local action. No global settings and no auto-play adoption.
YTextBase {
    id: control
    property var monitor: typeof readingLoop !== "undefined" ? readingLoop : null
    property string contentKey: ""
    property var playOnce: null // Synchronous: returns the new host sequence, or zero on failure.
    property string actionText: "循环发音"
    property bool looping: false
    property bool launching: false
    property double playId: 0
    property double epoch: -1
    readonly property bool available: monitor !== null
                                         && (typeof mediaSession === "undefined" || !mediaSession.active)
    width: parent.width
    height: 34
    font.pixelSize: 16
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: looping ? YColors.red : YColors.grayText
    text: looping ? "停止循环" : actionText + "：关"

    function ownsAudio() {
        return playId > 0 && Number(soundCenter.currentPlayId) === playId
                && monitor && epoch === monitor.interruptionEpoch
    }
    function cancel(stopOwned) {
        var stop = stopOwned && ownsAudio()
        looping = false
        replay.stop()
        if (monitor) monitor.release(playId)
        playId = 0
        if (stop) soundCenter.stop()
    }
    function startOne() {
        if (!looping || !visible || !available || !contentKey || !playOnce) {
            cancel(false)
            return
        }
        launching = true
        var previousId = playId
        var nextId = 0
        try { nextId = Number(playOnce()) } catch (e) { console.log("Reading loop: playback failed") }
        epoch = monitor.interruptionEpoch
        playId = nextId
        launching = false
        if (ownsAudio()) monitor.claim(playId)
        else {
            monitor.release(previousId)
            cancel(false)
        }
    }
    onVisibleChanged: if (!visible) cancel(true)
    onContentKeyChanged: cancel(true)
    Component.onDestruction: cancel(true)
    MouseArea {
        anchors.fill: parent
        enabled: control.available
        onClicked: {
            if (control.looping) control.cancel(true)
            else {
                control.looping = true
                control.startOne()
            }
        }
    }
    Timer {
        id: replay
        interval: 350
        onTriggered: {
            if (control.ownsAudio()) control.startOne()
            else control.cancel(false)
        }
    }
    Connections {
        target: control.monitor
        function onInterruptionEpochChanged() {
            if (control.looping && !control.launching && !control.ownsAudio()) control.cancel(false)
        }
    }
    Connections {
        target: soundCenter
        function onCurrentPlayIdChanged() {
            if (control.looping && !control.launching && !control.ownsAudio()) control.cancel(false)
        }
        function onSoundSuspend(seq) {
            if (Number(seq) === control.playId) control.cancel(false)
        }
        function onSoundEnd(seq) {
            if (!control.looping || Number(seq) !== control.playId || !control.ownsAudio()) return
            replay.restart()
        }
    }
    Connections {
        target: typeof mediaSession !== "undefined" ? mediaSession : null
        function onActiveChanged() { if (mediaSession.active) control.cancel(true) }
    }
}
