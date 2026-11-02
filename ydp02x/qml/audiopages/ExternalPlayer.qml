import "../commons"
import "../components"
import "../i18n"
import QtQuick 2.12
import com.github.penuniverse 1.0
import com.youdao.pen 1.0

/**
 * 文件管理里打开视频时进入的页面。
 *
 * 内嵌播放器插件（/userdata/PenMods/qml/FFmpegPlayer/）在就位时加载
 * ExternalPlayerEmbedded.qml —— 视频画在本应用的场景图里，跟随左右手旋转、
 * 有画面内控件与字幕；插件没部署时保持老行为：ExternalPlayer::open() 会拉起
 * 独立的 mpv 进程画在上面，本页只留一个返回按钮的占位页。
 */
YBackButtonAudioPage {
    id: id_external_player
    pageIndex: PageIndex.ExternalPlayer

    property bool embedded: externalPlayer.hasEmbeddedPlayer
    property bool embeddedLoadFailed: false
    property bool fallbackAttempted: false
    property bool fallbackFailed: false

    function useMpvFallback() {
        if (id_external_player.fallbackAttempted) return;
        id_external_player.fallbackAttempted = true;
        id_external_player.embeddedLoadFailed = true;
        id_external_player.embedded = false;
        id_external_player.fallbackFailed = !externalPlayer.fallbackToMpv();
    }

    Loader {
        id: id_embedded_loader
        anchors.fill: parent
        // 路径写死成常量字符串，避免 QML 在 hasEmbeddedPlayer 变化时重新解析
        source: id_external_player.embedded && !id_external_player.embeddedLoadFailed
                ? "ExternalPlayerEmbedded.qml" : ""
        onLoaded: {
            item.exitRequested.connect(id_external_player.backButtonClicked);
            item.openRequested.connect(function() { id_external_player.show(); });
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                Qt.callLater(function() {
                    if (id_embedded_loader.status === Loader.Error && id_external_player.embedded)
                        id_external_player.useMpvFallback();
                });
            }
        }
    }

    // 没有内嵌播放器时（mpv 在画面上）：只提供返回按钮
    YVerticalTitleBar {
        visible: !id_external_player.embedded
        onCallBack: backButtonClicked()
    }

    Text {
        anchors.centerIn: parent
        visible: id_external_player.fallbackFailed
        text: "内嵌播放器加载失败，独立播放器也无法启动"
        color: "white"
        font.pixelSize: 13
        wrapMode: Text.Wrap
        width: parent.width - 24
        horizontalAlignment: Text.AlignHCenter
    }

    Connections {
        target: externalPlayer
        function onMediaChanged() {
            id_external_player.embeddedLoadFailed = false;
            id_external_player.fallbackAttempted = false;
            id_external_player.fallbackFailed = false;
            id_external_player.embedded = externalPlayer.hasEmbeddedPlayer;
        }
    }

}
