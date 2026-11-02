import QtQuick 2.12
import QtQml.Models 2.12
import com.youdao.pen 1.0
import com.github.penuniverse 1.0

import "../commons"
import "../i18n"

Item {
    id: id_content_container
    anchors.fill: parent
    anchors.leftMargin: 54
    anchors.rightMargin: 10
    readonly property bool isPlaying: YEnum.PLAYING === mediaPlayerManager.playState
    readonly property int bottomInset: 12
    readonly property bool customLyrics: musicPlayer.hasTimeline
    readonly property bool lyricsAvailable: customLyrics || mediaPlayerManager.hasLrc
    LyricClock {
        id: lyricClock
        sourcePosition: Math.max(0, mediaPlayerManager.currentPos)
        playbackRate: mediaPlayerManager.playbackRate
        playing: id_content_container.isPlaying
        running: isShowing && customLyrics && !noLrcTip && id_content_container.visible && playing
    }
    Connections {
        target: musicPlayer
        function onLyricsChanged() {
            lyricClock.reset()
            id_lrc_main_show.resumeFollowing()
        }
    }
    readonly property int activeLine: customLyrics ? musicPlayer.lyricIndex(lyricClock.position) : mediaPlayerManager.currentSentenceId
    function escapeText(value) {
        return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    readonly property bool noLrcTip: isShowing && ((lrcStateList && lrcStateIndex < lrcStateList.length && YEnum.LS_HIDE === lrcStateList[lrcStateIndex])
    || !lyricsAvailable)

    function show() {
        id_delay_show_lrc_timer.restart()
        id_delay_play_state_pause_confirm_timer.restart()
    }

    function playStatePauseConfirm() {
        if (!isPlaying) {
            id_player_state_mask_show.restart()
        }
    }

    onNoLrcTipChanged: {
        if (noLrcTip) {
            id_delay_show_tip_timer.restart()
        } else {
            id_delay_show_tip_timer.stop()
            id_delay_show_tip.visible = false
        }
    }

    YAudioPlayerLyricView {
        id: id_lrc_main_show
        anchors.fill: parent
        anchors.bottomMargin: bottomInset
        lyricsVisible: !noLrcTip
        backgroundColor: YColors.black
        title: mediaPlayerManager.title
        fontFamily: qmlGlobal.fontFamilyZhCn
        titleColor: YColors.grayText
        activeIndex: activeLine
        model: id_lrc_filter_model
        onTapped: id_player_state_mask_show.show()
    }

    DelegateModel {
        id: id_lrc_filter_model
        model: customLyrics ? musicPlayer.lyricRows : mediaPlayerManager

        delegate: Item {
            id: id_delegate_item
            width: id_lrc_main_show.width
            height: id_sentence_column.implicitHeight
            // 提取数据，减少深层属性访问
            readonly property var modelData: model.modelData || ({})
            readonly property string mainLrc: modelData.mainLrc || ""
            readonly property string transLrc: modelData.transLrc || ""
            readonly property bool isCurrentLrc: customLyrics ? index === activeLine : modelData.id !== undefined && modelData.id === activeLine
            readonly property bool hasKeyPoint: !customLyrics && !!modelData.hasKeyPoint

            readonly property real readingOffset: customLyrics ? nativeLine.focusY : 0
            onReadingOffsetChanged: {
                if (isCurrentLrc) id_lrc_main_show.followCurrent()
            }
            readonly property string currentFontFamily: qmlGlobal.fontFamilyZhCn

            Column {
                id: id_sentence_column
                spacing: 3
                width: parent.width

                LyricLineItem {
                    id: nativeLine
                    width: parent.width
                    height: visible ? implicitHeight : 0
                    line: customLyrics ? id_delegate_item.modelData : ({})
                    font.family: currentFontFamily
                    font.pixelSize: 21
                    pendingColor: index < activeLine ? YColors.blueText : (isCurrentLrc ? "#8c939f" : YColors.white)
                    playedColor: YColors.blueText
                    active: isCurrentLrc
                    position: active ? lyricClock.position : -1
                    opacity: isCurrentLrc ? 1 : 0.42
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    visible: customLyrics && isShowing && lyricsAvailable &&
                        (YEnum.LS_BILINGUAL === lrcStateList[lrcStateIndex] || YEnum.LS_ORIGINAL === lrcStateList[lrcStateIndex])
                }

                YText {
                    id: id_sentence_main_lrc
                    width: parent.width
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 26
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: 20
                    textFormat: YText.RichText
                    opacity: isCurrentLrc ? 1.0 : 0.42
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    font.family: currentFontFamily

                    visible: !customLyrics && isShowing && !id_delay_show_lrc_timer.running && lyricsAvailable &&
                    ((YEnum.LS_BILINGUAL === lrcStateList[lrcStateIndex]) || (YEnum.LS_ORIGINAL === lrcStateList[lrcStateIndex]))

                    text: {
                        if (!visible) return ""
                        if (customLyrics) {
                            if (isCurrentLrc)
                                return musicPlayer.lyricText(index, mediaPlayerManager.currentPos, YColors.blueText, YColors.white)
                            return escapeText(mainLrc)
                        }

                            if (isCurrentLrc) {
                                let endIndex = mediaPlayerManager.sentencePlayingEnd > 0 ? mediaPlayerManager.sentencePlayingEnd :
                                (hasKeyPoint ? 0 : mainLrc.length)

                                let played = escapeText(mainLrc.substring(0, endIndex))
                                let unplayed = endIndex < mainLrc.length ? escapeText(mainLrc.substring(endIndex)) : ""

                                return `<span style="font-family: ${currentFontFamily}; color:${YColors.blueText}">${played}</span>` +
                                (unplayed ? `<span style="font-family: ${currentFontFamily}; color:${YColors.white}">${unplayed}</span>` : "")
                            } else {
                                return escapeText(mainLrc)
                            }
                    }
                }

                YText {
                    id: id_sentence_trans_lrc
                    width: parent.width
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 20
                    wrapMode: Text.Wrap
                    font.pixelSize: 15
                    font.family: currentFontFamily
                    textFormat: Text.PlainText
                    color: (isCurrentLrc || (customLyrics && index < activeLine))
                        ? (lrcStateList[lrcStateIndex] === YEnum.LS_TRANS ? YColors.blueText : YColors.grayText)
                        : YColors.white
                    opacity: isCurrentLrc ? 1.0 : 0.42
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    visible: isShowing && (customLyrics || !id_delay_show_lrc_timer.running) && lyricsAvailable &&
                    ((YEnum.LS_BILINGUAL === lrcStateList[lrcStateIndex]) || (YEnum.LS_TRANS === lrcStateList[lrcStateIndex])) &&
                    transLrc.length > 0
                    text: visible ? transLrc : ""
                }
            }
        }
    }

    YTimer {
        id: id_delay_show_lrc_timer
        interval: 900
    }

    YTimer {
        id: id_delay_play_state_pause_confirm_timer
        interval: 120
        onTriggered: {
            playStatePauseConfirm()
        }
    }

    Item {
        id: id_content_column
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: id_lrc_main_show.contentTop; bottom: parent.bottom; bottomMargin: bottomInset }
        clip: true
        YTimer {
            id: id_delay_show_tip_timer
            interval: 500
            onTriggered: {
                if (noLrcTip) {
                    id_delay_show_tip.visible = true
                }
            }
        }

        YSpacingForColumn {
            id: id_delay_show_tip
            anchors.fill: parent
            visible: false

            YMouseArea {
                anchors.fill: parent
                objectName: "YAudioPlayer.qml_id_no_any_lrc"
                enabled: !id_player_state_mask_container.visible
                onClicked: {
                    id_player_state_mask_show.show()
                }
            }

            Item {
                id: id_no_lrc_show_container
                anchors.centerIn: parent

                width: id_label.width
                implicitHeight: 24

                YText {
                    id: id_label
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    color: YColors.grayText
                    width: paintedWidth
                    height: paintedHeight
                    text: {
                        if (lrcStateList && lrcStateIndex < lrcStateList.length && YEnum.LS_HIDE === lrcStateList[lrcStateIndex]) {
                            return YTranslateText.subtitleHidden
                        }
                        if (!lyricsAvailable) {
                            return YTranslateText.noSubtitles
                        }
                        return ""
                    }
                }

                YAudioPlayerLrcMouseArea {
                    objectName: "YAudioPlayer.qml_YText_noLrc_YMouseArea"
                }
            }
        }
    }

    Item {
        id: id_player_state_mask_container
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: id_lrc_main_show.contentTop; bottom: parent.bottom; bottomMargin: bottomInset }
        clip: true
        visible: false

        Rectangle {
            id: id_player_state_mask
            anchors.fill: parent
            enabled: false
            color: YColors.black
            radius: 0

            QtObject {
                id: id_player_state_mask_show

                function show() {
                    mediaPlayerManager.onClickedPause()
                    restart()
                }

                function restart() {
                    id_player_state_mask_container.visible = true
                    id_player_state_mask.opacity = 0.8
                    id_player_state_center_indicator.opacity = 1
                    id_player_state_mask.enabled = true
                }
            }

            SequentialAnimation {
                id: id_player_state_mask_hide
                ScriptAction {
                    script: {
                        id_player_state_mask.enabled = false
                    }
                }
                ParallelAnimation {
                    NumberAnimation { target: id_player_state_mask; property: "opacity"; to: 0; duration: 1200 }
                    NumberAnimation { target: id_player_state_center_indicator; property: "opacity"; to: 0; duration: 1200 }
                }
                ScriptAction { script: id_player_state_mask_container.visible = false }
            }
        }

        Rectangle {
            id: id_player_state_center_indicator
            implicitWidth: 44
            implicitHeight: 44
            anchors.centerIn: parent
            radius: height/2
            color: YColors.red

            YImage {
                id: id_play_button
                sourceSize: Qt.size(40, 40)
                anchors.centerIn: parent
                imageName: !isPlaying ? "audioplayer/pause" : "audioplayer/play"
            }

            YMouseArea {
                anchors.fill: parent
                anchors.margins: -10
                onClicked: {
                    mediaPlayerManager.onClickedPlay()
                }
            }

            YImage {
                id: id_play_previous_button
                sourceSize: Qt.size(40, 40)
                anchors.right: parent.left
                anchors.rightMargin: 40
                anchors.verticalCenter: parent.verticalCenter
                imageName: "audioplayer/previous54"

                YMouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: {
                        console.log("YAudioPlayerLrcContent.qml === id_play_previous_button.onClicked")
                        mediaPlayerManager.onClickedPrev()
                        // 修复：添加 id_play_bar 存在的判断，防止 crash
                        if (typeof id_play_bar !== "undefined") {
                            id_play_bar.updatePlaybackRate()
                            id_play_bar.truncateAudioState = YEnum.TAS_STOP
                        }
                    }
                }
            }

            YImage {
                id: id_play_next_button
                sourceSize: Qt.size(40, 40)
                anchors.left: parent.right
                anchors.leftMargin: 40
                anchors.verticalCenter: parent.verticalCenter
                imageName: "audioplayer/next54"

                YMouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: {
                        console.log("YAudioPlayerLrcContent.qml === id_play_next_button.onClicked")
                        mediaPlayerManager.onClickedNext()
                        // 修复：添加 id_play_bar 存在的判断
                        if (typeof id_play_bar !== "undefined") {
                            id_play_bar.updatePlaybackRate()
                            id_play_bar.truncateAudioState = YEnum.TAS_STOP
                        }
                    }
                }
            }
        }
    }

    function openOnlineLyrics() {
        if (musicPlayer.canFetchLyrics()) onlineLyrics.open()
    }

    z: onlineLyrics.visible ? 10 : 0
    YOnlineLyricsPanel {
        id: onlineLyrics
        anchors.leftMargin: -54
        anchors.rightMargin: -10
    }
    readonly property bool playerShowing: isShowing
    onPlayerShowingChanged: {
        if (!playerShowing) onlineLyrics.close()
    }
    Connections {
        target: mediaPlayerManager
        function onTitleChanged() { onlineLyrics.close() }
    }

    onIsPlayingChanged: {
        if (isPlaying) {
            id_player_state_mask_hide.restart()
        }
        else {
            id_player_state_mask_show.restart()
        }
    }
}
