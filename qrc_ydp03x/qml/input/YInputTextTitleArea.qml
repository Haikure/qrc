import QtQuick 2.12

import "../i18n"
import "../common"

// PenMods3 输入区 — 多行编辑，高度随内容增长：
//   height = max(110, TextEdit.contentHeight + 20)
//   配合输入页整页纵向滚动：行数变多时输入区变高，键盘保持在内容底部。
Item {
    id: id_title_area_root
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(110, id_input_core.contentHeight + 20)

    readonly property bool acceptabled: id_input_core.length
    property alias text: id_input_core.text
    property alias placeHolderText: id_placeholder_text.text

    signal backed()
    signal accepted()
    signal textEdited()

    function delChar() {
        id_input_core.remove(Math.max(0, id_input_core.cursorPosition - 1),
                             id_input_core.cursorPosition)
        if (!id_input_core.activeFocus) {
            id_input_core.forceActiveFocus()
        }
    }

    function delToStart() {
        if (id_input_core.cursorPosition > 0) {
            id_input_core.remove(id_input_core.cursorPosition, 0)
        }
    }

    function enterSpacing() {
        id_input_core.insert(id_input_core.cursorPosition, " ")
        if (!id_input_core.activeFocus) {
            id_input_core.forceActiveFocus()
        }
    }

    function enterChar(text) {
        id_input_core.insert(id_input_core.cursorPosition, text)
        if (!id_input_core.activeFocus) {
            id_input_core.forceActiveFocus()
        }
    }

    function clear() {
        id_input_core.clear()
    }

    // 预填初始文本并把光标放到末尾（重命名等场景直接接着编辑）
    function setInitialText(newText) {
        id_input_core.text = newText
        id_input_core.cursorPosition = newText.length
        if (!id_input_core.activeFocus) {
            id_input_core.forceActiveFocus()
        }
    }

    // 扫描（OCR）结果拼接到已有内容末尾（由 keyBoard.scanFinished 触发）
    function appendScanText(content) {
        if (content.length === 0) {
            return
        }
        id_input_core.insert(id_input_core.text.length, content)
        id_input_core.cursorPosition = id_input_core.text.length
        if (!id_input_core.activeFocus) {
            id_input_core.forceActiveFocus()
        }
    }

    // 文本编辑区（左侧，占满剩余宽度；右缘让给按钮列）
    TextEdit {
        id: id_input_core
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: id_buttons_column.left
        anchors.rightMargin: 8
        font.family: fontManager.fontFamily
        font.pixelSize: 26
        color: YColors.white
        cursorDelegate: id_cursor_delegate
        wrapMode: TextEdit.WrapAnywhere
        selectByMouse: false
        onTextChanged: {
            id_title_area_root.textEdited()
        }

        YTextBase {
            id: id_placeholder_text
            anchors.fill: parent
            verticalAlignment: YText.AlignTop
            opacity: !id_input_core.length && !id_input_core.inputMethodComposing ? 1 : 0
            color: YColors.grayText
            font: id_input_core.font
            wrapMode: YText.Wrap
            text: YBaseTranslateText.inputTip
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    // 右侧按钮列：返回 + 完成
    Column {
        id: id_buttons_column
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 56
        spacing: 4

        YIconButton {
            id: id_back_button_bg
            width: 44
            height: 44
            anchors.horizontalCenter: parent.horizontalCenter
            radius: 22
            icon: "ic_back"
            iconSourceSize: Qt.size(32, 32)

            YBackButtonBase {
                anchors.fill: parent
                anchors.margins: -14
                onTriggered: {
                    backed()
                }
            }
        }

        Item {
            width: 44
            height: 44
            anchors.horizontalCenter: parent.horizontalCenter

            YIconButton {
                id: id_accepted_button_background
                anchors.fill: parent
                radius: 22
                color: YColors.grayNormal
                enabled: id_title_area_root.acceptabled
                imageName: "input/ic_selected"
                sourceSize: Qt.size(32, 32)
                onClicked: {
                    accepted()
                }
            }
        }
    }

    // 扫描（OCR）结果拦截：输入页显示时，按压笔头扫描的内容拼接进来
    Connections {
        target: keyBoard
        ignoreUnknownSignals: true
        function onScanFinished(content) {
            id_title_area_root.appendScanText(content)
        }
    }

    Component {
        id: id_cursor_delegate
        YCursorDelegateItem {
            implicitHeight: 30
            color: YColors.red
            running: !id_input_core.readOnly && id_input_core.activeFocus
        }
    }
}
