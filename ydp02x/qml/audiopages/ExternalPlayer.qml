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

    readonly property bool embedded: externalPlayer.hasEmbeddedPlayer

    Loader {
        id: id_embedded_loader
        anchors.fill: parent
        // 路径写死成常量字符串，避免 QML 在 hasEmbeddedPlayer 变化时重新解析
        source: id_external_player.embedded ? "ExternalPlayerEmbedded.qml" : ""
        onLoaded: item.exitRequested.connect(id_external_player.backButtonClicked)
    }

    // 没有内嵌播放器时（mpv 在画面上）：只提供返回按钮
    YVerticalTitleBar {
        visible: !id_external_player.embedded
        onCallBack: backButtonClicked()
    }

}
