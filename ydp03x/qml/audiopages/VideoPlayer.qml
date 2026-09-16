import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../components"
import "../i18n"

// =====================================================================
// 视频播放页 —— YDP03X 上视频播放被重定向到独立进程 /userdisk/VideoPlayer。
// 本页通过 `videoPlayer.open(fileName)` 拉起外部播放器（fileName 为相对
// 当前文件管理目录的文件名），`videoPlayer.getOpeningPath()` 返回 file://
// 绝对路径。不再使用 QtMultimedia 内嵌播放器（2 代实现）。
// =====================================================================
YBackButtonPage {
    id: id_video_player
    objectName: "YPage===VideoPlayer.qml"

    // 需要打开的文件名（相对于当前文件管理目录），由调用方在 show 前设置。
    property string fileName: ""

    Component.onCompleted: {
        if (fileName !== "" && typeof videoPlayer !== "undefined" && videoPlayer !== null
            && typeof videoPlayer.open === "function") {
            videoPlayer.open(fileName);
        }
    }

    // 占位提示：外部播放器在独立进程中运行，本页不渲染视频内容。
    YText {
        anchors.centerIn: parent
        color: YColors.grayText
        font.pixelSize: 20
        text: "正在打开视频播放器…"
    }
}
