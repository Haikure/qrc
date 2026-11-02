import QtQuick 2.12
import com.github.penuniverse 1.0

// Both video backends expose play/pause/stop/seek, but use different time units.
Item {
    id: session
    property var player
    property string ownerId
    property string title
    property bool playing: false
    property bool paused: false
    property real millisecondsPerUnit: 1
    property bool revoking: false
    readonly property bool ownsSession: mediaSession.active && mediaSession.ownerPluginId === ownerId

    signal openRequested()

    function syncMetadata() {
        if (!ownsSession || revoking) return;
        mediaSession.title = title;
        mediaSession.duration = Math.round(player.duration * millisecondsPerUnit);
        mediaSession.position = Math.round(player.position * millisecondsPerUnit);
    }

    function syncState() {
        if (revoking || !player) return;
        if (playing && !ownsSession) mediaSession.begin(ownerId);
        if (!ownsSession) return;
        syncMetadata();
        mediaSession.playState = playing ? MediaSession.Playing
                                        : paused ? MediaSession.Paused : MediaSession.Stopped;
    }

    function stopAndRelease() {
        // stop() emits state notifications synchronously on some backends.
        revoking = true;
        player.stop();
        mediaSession.end(ownerId);
        revoking = false;
    }

    function play() {
        console.log("[VideoMediaSession] play", ownerId, player.playbackState);
        player.play();
    }

    function pause() {
        console.log("[VideoMediaSession] pause", ownerId, player.playbackState);
        player.pause();
    }

    function skip(seconds) {
        player.seek(Math.max(0, Math.min(player.duration,
                    player.position + seconds * 1000 / millisecondsPerUnit)));
    }

    onPlayingChanged: syncState()
    onPausedChanged: syncState()
    onTitleChanged: syncMetadata()
    Component.onCompleted: syncState()
    Component.onDestruction: stopAndRelease()

    Connections {
        target: session.player
        function onPositionChanged() { session.syncMetadata(); }
        function onDurationChanged() { session.syncMetadata(); }
    }

    Connections {
        target: mediaSession
        enabled: session.ownsSession
        function onPlayRequested() { session.play(); }
        function onPauseRequested() { session.pause(); }
        function onToggleRequested() {
            if (session.playing) session.pause();
            else session.play();
        }
        function onNextRequested() { session.skip(10); }
        function onPrevRequested() { session.skip(-10); }
        function onSeekRequested(position) { session.player.seek(position / session.millisecondsPerUnit); }
        function onStopRequested() { session.stopAndRelease(); }
        function onOpenRequested() { session.openRequested(); }
        function onSessionRevoked() { session.stopAndRelease(); }
    }
}
