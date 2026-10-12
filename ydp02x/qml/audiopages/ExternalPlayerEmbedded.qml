import "../commons"
import "../components"
import QtQuick 2.12
import com.github.penuniverse 1.0
import com.youdao.pen 1.0
import FFmpegPlayer 1.0 as FFmpegPlayer

/**
 * 内嵌 FFmpeg 播放器本体（由 ExternalPlayer.qml 在插件就位时加载）。
 *
 * 视频由 FFmpegPlayer 插件**画进本组件的场景图**，所以它跟随左右手模式的 180° 旋转、
 * 也能被本组件的 OSD 叠在上面（mpv/waylandsink 那种独立表面做不到）。
 * 控件与手势参考了上游 examples/Player.qml：
 *   单击     OSD 隐藏时唤出控件；已显示时播放/暂停
 *   长按     临时 2 倍速（松手恢复）
 *   横滑     快进/快退（整屏宽度 = 60s），松手才真正跳转
 *   上下滑   显示/隐藏 OSD
 *   缩放     按钮缩放，放大后可拖动画面
 * 底部进度条由插件自己绘制（progressBarEnabled），拖动时用 progressBarPosition 显示预览。
 * 退出走 exitRequested 信号，由外层页面负责真的返回上一页。
 */
Item {
    id: id_page
    clip: true

    signal exitRequested()

    readonly property bool   playing: id_player.playbackState === FFmpegPlayer.VideoPlayer.PlayingState
    readonly property bool   paused: id_player.playbackState === FFmpegPlayer.VideoPlayer.PausedState
    readonly property real   shownPosition: id_page.seeking ? id_page.previewPosition : id_player.position
    readonly property bool   hasSubtitle: id_player.subtitleSource.toString() !== ""
    readonly property string rateText: id_player.playbackRate.toFixed(1) + "x"

    property bool   osdVisible: true
    property bool   zoomMode: false
    property real   zoomLevel: 0
    property real   panX: 0
    property real   panY: 0
    property bool   seeking: false
    property bool   boosting: false
    property real   previewPosition: 0
    property string notice: ""

    Component.onCompleted: osdHideTimer.start()

    function setOsdVisible(visible) {
        osdHideTimer.stop();
        osdVisible = visible || zoomMode;
        if (osdVisible && playing && !zoomMode && !seeking && !boosting)
            osdHideTimer.restart();
    }

    function zoomIn() {
        id_gesture.cancelGesture();
        zoomMode = true;
        setOsdVisible(true);
        zoomLevel += 0.25;
    }

    function zoomOut() {
        id_gesture.cancelGesture();
        zoomLevel = Math.max(0, zoomLevel - 0.25);
        if (zoomLevel === 0)
            resetZoom();
    }

    function resetZoom() {
        zoomMode = false;
        zoomLevel = 0;
        panX = 0;
        panY = 0;
        setOsdVisible(true);
    }

    function formatTime(seconds) {
        if (!isFinite(seconds) || seconds < 0) seconds = 0;
        var total = Math.floor(seconds);
        var hours = Math.floor(total / 3600);
        var minutes = Math.floor(total / 60);
        var rest = total % 60;
        if (hours > 0) {
            minutes %= 60;
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (rest < 10 ? "0" : "") + rest;
        }
        return (minutes < 10 ? "0" : "") + minutes + ":" + (rest < 10 ? "0" : "") + rest;
    }

    function showNotice(text) {
        notice = text;
        noticeTimer.restart();
    }

    function cycleRate() {
        var rates = [0.5, 1.0, 1.5, 2.0];
        var current = id_player.playbackRate;
        var next = rates[0];
        for (var i = 0; i < rates.length; ++i) {
            if (Math.abs(rates[i] - current) < 0.05) {
                next = rates[(i + 1) % rates.length];
                break;
            }
        }
        id_player.playbackRate = next;
        showNotice("倍速 " + next.toFixed(1) + "x");
    }

    function toggleSubtitle() {
        if (!hasSubtitle) {
            showNotice("未找到同名字幕文件 (.ass/.lrc)");
            return;
        }
        id_player.subtitlesEnabled = !id_player.subtitlesEnabled;
        showNotice(id_player.subtitlesEnabled ? "字幕开" : "字幕关");
    }

    // ─── 视频本体 ───────────────────────────────────────────────
    FFmpegPlayer.VideoPlayer {
        id: id_player
        anchors.fill: parent
        scale: Math.pow(2, id_page.zoomLevel)
        transformOrigin: Item.Center
        transform: Translate { x: id_page.panX; y: id_page.panY }
        source: externalPlayer.path
        subtitleSource: externalPlayer.subtitlePath
        subtitleFontFile: "file:///usr/lib/fonts/NotoSansSC-Regular.otf"
        autoPlay: true
        progressBarEnabled: !id_page.zoomMode
        progressBarHeight: 2
        progressBarColor: "#39a9ff"
        progressBarBackgroundColor: "#40000000"
        // -1 = 跟随播放进度；拖动时给一个非负值只做预览，不改变实际播放位置
        progressBarPosition: id_page.seeking ? id_page.previewPosition : -1

        onSourceChanged: id_page.resetZoom()
        onErrorOccurred: id_page.showNotice("播放失败：" + error)
        onEndOfMedia: id_page.osdVisible = true
        onSubtitleErrorStringChanged: {
            if (subtitleErrorString.length > 0) id_page.showNotice("字幕：" + subtitleErrorString);
        }
    }

    // ─── 手势层 ─────────────────────────────────────────────────
    MouseArea {
        id: id_gesture
        anchors.fill: parent
        enabled: !id_page.zoomMode && !id_player.loading
        pressAndHoldInterval: 400

        property bool held: false
        property bool moved: false
        property bool swipeSeeking: false
        property bool verticalGesture: false
        property real startX: 0
        property real startY: 0
        property real startPosition: 0

        function updatePreview(x) {
            var span = 60; // 整屏宽度对应的秒数
            var delta = (x - startX) / Math.max(1, width) * span;
            id_page.previewPosition = Math.max(0, Math.min(id_player.duration, startPosition + delta));
        }

        function cancelGesture() {
            id_page.seeking = false;
            id_page.boosting = false;
            swipeSeeking = false;
            verticalGesture = false;
            held = false;
            moved = true;
            id_player.endBoost();
        }

        onEnabledChanged: if (!enabled) cancelGesture()
        onPressed: {
            osdHideTimer.stop();
            held = false;
            moved = false;
            swipeSeeking = false;
            verticalGesture = false;
            startX = mouse.x;
            startY = mouse.y;
            startPosition = id_player.position;
        }

        onPositionChanged: {
            if (!pressed) return;
            var dx = Math.abs(mouse.x - startX);
            var dy = Math.abs(mouse.y - startY);
            if (!moved && (dx > 12 || dy > 12)) {
                moved = true;
                if (held) {
                    // 长按后移动视为取消倍速，避免误触
                    cancelGesture();
                    return;
                }
                // 暂停时也允许拖动跳转（上游示例同样如此）：连续请求以最后一次为准，暂停状态保持
                if (dx > dy * 1.25 && id_player.duration > 0) swipeSeeking = true;
                else if (dy > dx * 1.25) verticalGesture = true;
            }
            if (swipeSeeking && moved) {
                id_page.seeking = true;
                updatePreview(mouse.x);
            }
        }

        onPressAndHold: {
            if (!moved && id_page.playing) {
                held = true;
                id_page.boosting = true;
                id_player.beginBoost();
            }
        }

        onReleased: {
            id_player.endBoost();
            id_page.boosting = false;
            if (swipeSeeking) {
                updatePreview(mouse.x);
                id_player.seek(id_page.previewPosition);
                id_page.seeking = false;
                swipeSeeking = false;
                showNotice(formatTime(id_page.previewPosition));
                osdHideTimer.restart();
                return;
            }
            var deltaX = mouse.x - startX;
            var deltaY = mouse.y - startY;
            if (verticalGesture && Math.abs(deltaY) >= Math.max(40, height * 0.07) &&
                    Math.abs(deltaY) > Math.abs(deltaX) * 1.25)
                id_page.setOsdVisible(deltaY > 0);
            swipeSeeking = false;
            verticalGesture = false;
            if (id_page.osdVisible && !id_page.zoomMode && id_page.playing)
                osdHideTimer.restart();
        }

        onCanceled: cancelGesture()

        onClicked: {
            if (held || moved) return;
            if (!id_page.osdVisible) {
                // 控件已隐藏时，这一下只用来唤出控件（顺便露出返回按钮），不改播放状态
                id_page.setOsdVisible(true);
                return;
            }
            osdHideTimer.restart();
            if (id_player.playbackState === FFmpegPlayer.VideoPlayer.PlayingState) id_player.pause();
            else id_player.play();
        }
    }

    MouseArea {
        id: id_zoom_pan_area
        anchors.fill: parent
        enabled: id_page.zoomMode

        property real lastX: 0
        property real lastY: 0

        onPressed: {
            lastX = mouse.x;
            lastY = mouse.y;
        }
        onPositionChanged: {
            if (!pressed) return;
            id_page.panX += mouse.x - lastX;
            id_page.panY += mouse.y - lastY;
            lastX = mouse.x;
            lastY = mouse.y;
        }
    }

    // ─── OSD ────────────────────────────────────────────────────
    Item {
        id: id_osd
        anchors.fill: parent
        opacity: id_page.osdVisible ? 1 : 0
        visible: opacity > 0.01
        enabled: id_page.osdVisible
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Rectangle {
            id: id_controls
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(parent.height, parent.height < 250 ? 92 : 108)
            visible: !id_page.zoomMode
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00151c26" }
                GradientStop { position: 0.35; color: "#80151c26" }
                GradientStop { position: 1.0; color: "#dc101620" }
            }

            Column {
                id: id_control_content
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: 3

                Item {
                    id: id_title_row
                    width: parent.width
                    height: parent.parent.height < 250 ? 18 : 22

                    YText {
                        anchors.fill: parent
                        text: externalPlayer.title
                        color: "#f4f6f8"
                        font.pixelSize: Math.max(12, Math.min(16, parent.height * 0.65))
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Item {
                    id: id_seek_row
                    width: parent.width
                    height: 20

                    Text {
                        id: id_elapsed_label
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42
                        text: id_page.formatTime(id_page.shownPosition)
                        color: "#e6eaf0"
                        font.pixelSize: 10
                        font.family: "monospace"
                        verticalAlignment: Text.AlignVCenter
                    }

                    Item {
                        id: id_seek_track
                        anchors.left: id_elapsed_label.right
                        anchors.right: id_duration_label.left
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 3
                            radius: 2
                            color: "#70dbe4ee"
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: id_player.duration > 0
                                   ? parent.width * Math.max(0, Math.min(1, id_page.shownPosition / id_player.duration))
                                   : 0
                            height: 3
                            radius: 2
                            color: "#39a9ff"
                        }

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            y: (parent.height - height) / 2
                            x: {
                                var fraction = id_player.duration > 0
                                        ? Math.max(0, Math.min(1, id_page.shownPosition / id_player.duration))
                                        : 0;
                                return Math.max(0, Math.min(parent.width - width, fraction * parent.width - width / 2));
                            }
                            color: "#39a9ff"
                        }

                        MouseArea {
                            id: id_seek_mouse_area
                            anchors.fill: parent
                            enabled: !id_player.loading && id_player.duration > 0

                            function updatePreview(mouseX) {
                                id_page.previewPosition = Math.max(0, Math.min(1, mouseX / Math.max(1, width))) * id_player.duration;
                            }

                            onPressed: {
                                osdHideTimer.stop();
                                id_page.seeking = true;
                                updatePreview(mouse.x);
                            }
                            onPositionChanged: if (pressed) updatePreview(mouse.x)
                            onReleased: {
                                updatePreview(mouse.x);
                                id_player.seek(id_page.previewPosition);
                                id_page.seeking = false;
                                osdHideTimer.restart();
                            }
                            onCanceled: {
                                id_page.seeking = false;
                                osdHideTimer.restart();
                            }
                        }
                    }

                    Text {
                        id: id_duration_label
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42
                        text: id_page.formatTime(id_player.duration)
                        color: "#e6eaf0"
                        font.pixelSize: 10
                        font.family: "monospace"
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Item {
                    id: id_transport_row
                    width: parent.width
                    height: parent.height - id_title_row.height - id_seek_row.height - parent.spacing * 2

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Repeater {
                            model: 3

                            delegate: Item {
                                property int direction: index - 1
                                width: id_page.height < 250 ? 36 : 44
                                height: id_page.height < 250 ? 32 : 40

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 5
                                    color: transportMouse.pressed ? "#dc263548" : "transparent"
                                }

                                Canvas {
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    property int direction: parent.direction
                                    property bool playing: id_page.playing
                                    onDirectionChanged: requestPaint()
                                    onPlayingChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        ctx.fillStyle = "#f4f6f8";
                                        if (direction === 0) {
                                            if (playing) {
                                                ctx.fillRect(4, 3, 4, 14);
                                                ctx.fillRect(12, 3, 4, 14);
                                            } else {
                                                ctx.beginPath();
                                                ctx.moveTo(5, 3);
                                                ctx.lineTo(17, 10);
                                                ctx.lineTo(5, 17);
                                                ctx.closePath();
                                                ctx.fill();
                                            }
                                            return;
                                        }
                                        ctx.save();
                                        if (direction < 0) {
                                            ctx.translate(width, 0);
                                            ctx.scale(-1, 1);
                                        }
                                        for (var i = 0; i < 2; ++i) {
                                            var x = 2 + i * 8;
                                            ctx.beginPath();
                                            ctx.moveTo(x, 4);
                                            ctx.lineTo(x + 8, 10);
                                            ctx.lineTo(x, 16);
                                            ctx.closePath();
                                            ctx.fill();
                                        }
                                        ctx.restore();
                                    }
                                }

                                MouseArea {
                                    id: transportMouse
                                    anchors.fill: parent
                                    onPressed: osdHideTimer.stop()
                                    onReleased: osdHideTimer.restart()
                                    onClicked: {
                                        if (parent.direction < 0) id_player.seekBackward(10);
                                        else if (parent.direction > 0) id_player.seekForward(10);
                                        else if (id_page.playing) id_player.pause();
                                        else id_player.play();
                                        osdHideTimer.restart();
                                    }
                                }
                            }
                        }
                    }

                    YVideoOsdButton {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "字幕"
                        active: id_page.hasSubtitle && id_player.subtitlesEnabled
                        enabled: id_page.hasSubtitle
                        onTapped: { id_page.toggleSubtitle(); osdHideTimer.restart(); }
                    }

                    YVideoOsdButton {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: id_page.rateText
                        active: id_player.playbackRate !== 1.0
                        onTapped: { id_page.cycleRate(); osdHideTimer.restart(); }
                    }
                }
            }
        }

        Column {
            id: id_zoom_controls
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 16
            anchors.topMargin: 10
            spacing: 8

            Repeater {
                model: id_page.zoomMode && id_page.zoomLevel > 0 ? 3 : 2

                delegate: Rectangle {
                    width: 28
                    height: 28
                    radius: 5
                    color: zoomControlMouse.pressed ? "#dc263548" : "#a6101620"

                    Text {
                        anchors.fill: parent
                        text: index === 0 ? "↺" : index === 1 ? "+" : "−"
                        color: "#f4f6f8"
                        font.pixelSize: 18
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    MouseArea {
                        id: zoomControlMouse
                        anchors.fill: parent
                        onPressed: osdHideTimer.stop()
                        onReleased: osdHideTimer.restart()
                        onClicked: {
                            if (index === 0) id_page.resetZoom();
                            else if (index === 1) id_page.zoomIn();
                            else id_page.zoomOut();
                            osdHideTimer.restart();
                        }
                    }
                }
            }
        }
    }

    // 拖动预览（左右滑动时显示目标时间）
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        visible: id_page.seeking
        width: id_preview_text.width + 18
        height: 24
        radius: 12
        color: YColors.black
        opacity: 0.75

        YText {
            id: id_preview_text
            anchors.centerIn: parent
            font.pixelSize: 14
            text: id_page.formatTime(id_page.previewPosition) + " / " + id_page.formatTime(id_player.duration)
        }
    }

    // 长按倍速提示
    Rectangle {
        anchors.bottom: id_controls.top
        anchors.bottomMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 8
        visible: id_page.boosting
        width: id_boost_text.width + 16
        height: 22
        radius: 11
        color: YColors.blueRect
        opacity: 0.85

        YText {
            id: id_boost_text
            anchors.centerIn: parent
            font.pixelSize: 13
            text: "长按 " + id_player.boostRate.toFixed(1) + "x"
        }
    }

    // 错误/提示
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: id_controls.top
        anchors.bottomMargin: id_page.boosting ? 38 : 10
        visible: id_page.notice.length > 0
        width: Math.min(parent.width - 80, id_notice_text.implicitWidth + 18)
        height: 24
        radius: 12
        color: YColors.grayNormal
        opacity: 0.85

        YText {
            id: id_notice_text
            anchors.centerIn: parent
            font.pixelSize: 13
            text: id_page.notice
        }
    }

    Timer {
        id: osdHideTimer
        interval: 3000
        repeat: false
        onTriggered: if (id_page.playing && !id_page.zoomMode && !id_page.seeking && !id_page.boosting) id_page.osdVisible = false
    }

    Timer {
        id: noticeTimer
        interval: 2200
        repeat: false
        onTriggered: id_page.notice = ""
    }

    // 返回按钮属于 OSD：隐藏时整条都不可见、也不接收点击，避免挡住画面
    Item {
        id: id_back_bar
        anchors.fill: parent
        opacity: id_page.osdVisible ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Item {
            anchors.fill: parent

            YVerticalTitleBar {
                id: id_title_bar
                onCallBack: {
                    id_player.stop();
                    id_page.exitRequested();
                }
            }

        }
    }

}
