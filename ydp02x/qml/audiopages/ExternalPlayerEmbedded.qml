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
 * 底部进度条由插件自己绘制（progressBarEnabled），拖动时用 progressBarPosition 显示预览。
 * 退出走 exitRequested 信号，由外层页面负责真的返回上一页。
 */
Item {
    id: id_page

    signal exitRequested()

    readonly property bool   playing: id_player.playbackState === FFmpegPlayer.VideoPlayer.PlayingState
    readonly property bool   paused: id_player.playbackState === FFmpegPlayer.VideoPlayer.PausedState
    readonly property real   shownPosition: id_page.seeking ? id_page.previewPosition : id_player.position
    readonly property bool   hasSubtitle: id_player.subtitleSource.toString() !== ""
    readonly property string rateText: id_player.playbackRate.toFixed(1) + "x"

    property bool   osdVisible: true
    property bool   seeking: false
    property bool   boosting: false
    property real   previewPosition: 0
    property string notice: ""

    Component.onCompleted: osdHideTimer.start()

    function formatTime(seconds) {
        if (!isFinite(seconds) || seconds < 0) seconds = 0;
        var total = Math.floor(seconds);
        var minutes = Math.floor(total / 60);
        var rest = total % 60;
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
        source: externalPlayer.path
        subtitleSource: externalPlayer.subtitlePath
        subtitleFontFile: "file:///usr/lib/fonts/NotoSansSC-Regular.otf"
        autoPlay: true
        progressBarEnabled: true
        progressBarHeight: 2
        progressBarColor: "#80cfff"
        progressBarBackgroundColor: "#40000000"
        // -1 = 跟随播放进度；拖动时给一个非负值只做预览，不改变实际播放位置
        progressBarPosition: id_page.seeking ? id_page.previewPosition : -1

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
        pressAndHoldInterval: 400

        property bool held: false
        property bool moved: false
        property bool swipeSeeking: false
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
            held = false;
            moved = true;
            id_player.endBoost();
        }

        onPressed: {
            held = false;
            moved = false;
            swipeSeeking = false;
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
                return;
            }
            swipeSeeking = false;
        }

        onCanceled: cancelGesture()

        onClicked: {
            if (held || moved) return;
            osdHideTimer.restart();
            if (!id_page.osdVisible) {
                // 控件已隐藏时，这一下只用来唤出控件（顺便露出返回按钮），不改播放状态
                id_page.osdVisible = true;
                return;
            }
            if (id_player.playbackState === FFmpegPlayer.VideoPlayer.PlayingState) id_player.pause();
            else id_player.play();
        }
    }

    // ─── OSD ────────────────────────────────────────────────────
    Item {
        id: id_osd
        anchors.fill: parent
        opacity: id_page.osdVisible ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Row {
            id: id_osd_row
            anchors.top: parent.top
            anchors.topMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 8
            spacing: 5

            YVideoOsdButton {
                text: id_page.playing ? "暂停" : "播放"
                onTapped: {
                    if (id_page.playing) id_player.pause();
                    else id_player.play();
                    osdHideTimer.restart();
                }
            }
            YVideoOsdButton { text: "-10s"; onTapped: { id_player.seekBackward(10); osdHideTimer.restart(); } }
            YVideoOsdButton { text: "+10s"; onTapped: { id_player.seekForward(10); osdHideTimer.restart(); } }
            YVideoOsdButton { text: id_page.rateText; active: id_player.playbackRate !== 1.0; onTapped: { id_page.cycleRate(); osdHideTimer.restart(); } }
            YVideoOsdButton { text: "字幕"; active: id_page.hasSubtitle && id_player.subtitlesEnabled; onTapped: { id_page.toggleSubtitle(); osdHideTimer.restart(); } }
        }

        // 标题 + 时间（左下，避开左侧返回条与底部进度条）
        Rectangle {
            id: id_meta_pill
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.left: parent.left
            anchors.leftMargin: 60
            // 文件名可能很长，宽度封顶在屏幕内，超出部分由文字自己省略
            width: Math.min(parent.width - 68, id_meta.implicitWidth + 14)
            height: 20
            radius: 10
            color: YColors.grayNormal
            opacity: 0.75

            YText {
                id: id_meta
                anchors.centerIn: parent
                width: parent.width - 12
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 12
                text: externalPlayer.title + "   " + id_page.formatTime(id_page.shownPosition) + " / " + id_page.formatTime(id_player.duration)
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
        anchors.bottom: parent.bottom
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
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
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
        onTriggered: if (id_page.playing && !id_page.seeking && !id_page.boosting) id_page.osdVisible = false
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
