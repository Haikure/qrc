import QtQuick 2.12
import "../commons"

Rectangle {
    id: panel
    anchors.fill: parent
    color: YColors.bg
    visible: false
    z: 100
    readonly property bool previewVisible: previewing && musicPlayer.lyricPreview.length > 0
    property bool previewing: false
    property string keyword: ""

    function open() {
        previewing = false
        keyword = musicPlayer.lyricSearchKeyword()
        visible = true
        musicPlayer.searchOnlineLyrics(keyword)
        results.positionViewAtBeginning()
    }

    function close() {
        musicPlayer.cancelOnlineLyrics()
        visible = false
    }

    function editKeyword() {
        let component = qmlCreateComponent("YInputPage")
        if (component.status === Component.Ready) {
            let page = component.createObject(keyboardHelper.containerItem)
            if (!page) return
            page.backButtonClicked.connect(function() {
                qmlGlobal.inputPageShowing = false
                page.todoDestroy()
            })
            page.inputFinished.connect(function(content) {
                panel.keyword = content
                musicPlayer.searchOnlineLyrics(content)
            })
            page.enterText(panel.keyword)
            page.show()
            qmlGlobal.inputPageShowing = true
        }
    }

    onVisibleChanged: {
        if (!visible) musicPlayer.cancelOnlineLyrics()
    }

    YMouseArea {
        anchors.fill: parent
        objectName: "onlineLyricsBackground"
    }

    YVerticalTitleBar {
        onCallBack: {
            if (panel.previewVisible) panel.previewing = false
            else panel.close()
        }
    }

    YBaseListView {
        id: results
        visible: !panel.previewVisible
        enabled: visible
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        clip: true
        spacing: 6
        cacheBuffer: 150
        model: musicPlayer.lyricCandidates
        headerPositioning: ListView.InlineHeader

        header: Item {
            width: results.width
            height: searchField.height + statusText.implicitHeight + 16

            YButtonBase {
                id: searchField
                anchors.left: parent.left
                anchors.right: retryButton.left
                anchors.rightMargin: 6
                height: 42
                radius: 10
                color: YColors.surface
                enabled: !musicPlayer.lyricBusy
                onClicked: panel.editKeyword()

                YText {
                    x: 10
                    y: 3
                    width: parent.width - 20
                    text: "网络歌词 · 点击修改关键词"
                    font.family: qmlGlobal.fontFamily
                    font.pixelSize: 11
                    color: YColors.grayText
                    elide: Text.ElideRight
                }
                YText {
                    x: 10
                    y: 19
                    width: parent.width - 20
                    text: panel.keyword || "输入歌名或歌手"
                    font.family: qmlGlobal.fontFamily
                    font.pixelSize: 16
                    color: YColors.textPrimary
                    elide: Text.ElideRight
                }
            }

            YButton {
                id: retryButton
                anchors.right: parent.right
                width: 48
                height: searchField.height
                radius: 10
                text: musicPlayer.lyricBusy ? "获取中" : "重试"
                pixelSize: 13
                textFamily: qmlGlobal.fontFamily
                textItem.textFormat: Text.PlainText
                color: YColors.grayButton
                textColor: YColors.textPrimary
                enabled: !musicPlayer.lyricBusy && panel.keyword.trim().length > 0
                onClicked: musicPlayer.searchOnlineLyrics(panel.keyword)
            }

            YText {
                id: statusText
                anchors.top: searchField.bottom
                anchors.topMargin: 8
                width: parent.width
                text: musicPlayer.lyricStatus
                font.family: qmlGlobal.fontFamily
                font.pixelSize: 12
                color: YColors.grayText
                wrapMode: Text.Wrap
            }
        }

        delegate: YButtonBase {
            width: results.width
            height: 52
            radius: 10
            color: YColors.surface
            enabled: !musicPlayer.lyricBusy
            onClicked: {
                panel.previewing = true
                musicPlayer.saveOnlineLyrics(index)
            }

            YText {
                x: 10
                y: 4
                width: parent.width - 20
                text: modelData.title
                font.family: qmlGlobal.fontFamily
                font.pixelSize: 16
                color: YColors.textPrimary
                elide: Text.ElideRight
            }
            YText {
                x: 10
                y: 29
                width: parent.width - 20
                text: modelData.detail
                font.family: qmlGlobal.fontFamily
                font.pixelSize: 12
                color: YColors.grayText
                elide: Text.ElideRight
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        color: YColors.bg
        visible: panel.previewVisible

        // Paint alone does not consume touches; gaps must never reach the search layer.
        YMouseArea {
            anchors.fill: parent
            objectName: "onlineLyricsPreviewBackground"
        }
        YButton {
            id: previewSave
            anchors.left: parent.left
            anchors.right: parent.right
            y: 5; height: 44
            radius: 10
            text: "保存歌词"; pixelSize: 16
            color: YColors.grayButton; textColor: YColors.textPrimary
            enabled: !musicPlayer.lyricBusy
            onClicked: musicPlayer.commitOnlineLyrics()
        }
        Flickable {
            anchors { left: parent.left; right: parent.right; top: previewSave.bottom; topMargin: 6; bottom: parent.bottom; bottomMargin: 5 }
            clip: true
            contentHeight: previewColumn.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: previewColumn
                width: parent.width; spacing: 8
                YText {
                    width: parent.width
                    text: musicPlayer.lyricStatus; textFormat: Text.PlainText
                    font.pixelSize: 12; color: YColors.grayText; wrapMode: Text.Wrap
                }
                YText {
                    width: parent.width
                    text: musicPlayer.lyricPreview; textFormat: Text.PlainText
                    font.pixelSize: 16; color: YColors.textPrimary; wrapMode: Text.Wrap
                }
            }
        }
    }

    Connections {
        target: musicPlayer
        function onOnlineLyricsChanged() {
            // Bring progress, errors and the save result into view after selecting a song.
            if (panel.visible) results.positionViewAtBeginning()
        }
    }

    YPagePopHelper {
        id: keyboardHelper
        isShowing: qmlGlobal.inputPageShowing
        objectName: "onlineLyricsKeyboard"
    }
}
