import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../components"
import "../i18n"

// =====================================================================
// 外部播放器页 —— YDP03X 上媒体播放被重定向到独立进程 /userdisk/VideoPlayer。
// 本页通过 `externalPlayer.open(path)` 拉起外部播放器（path 为相对当前
// 文件管理目录的文件名；C++ 侧解析为绝对路径），自身仅作占位/回调页。
// =====================================================================
YBackButtonPage {
    id: id_external_player
    objectName: "YPage===ExternalPlayer.qml"

    // 需要打开的文件名（相对于当前文件管理目录），由调用方在 show 前设置。
    property string path: ""

    Component.onCompleted: {
        if (path !== "" && typeof externalPlayer !== "undefined" && externalPlayer !== null
            && typeof externalPlayer.open === "function") {
            externalPlayer.open(path);
        }
    }

    // 占位提示：外部播放器在独立进程中运行，本页不渲染内容。
    YText {
        anchors.centerIn: parent
        color: YColors.grayText
        font.pixelSize: 20
        text: "正在打开外部播放器…"
    }
}
