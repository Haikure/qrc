import QtQuick 2.12

import "../common"

// PenMods3 QWERTY 键盘按键
// 用法:
//   YQwertyKey { text: "q"; onKeyPressed: ... }
//   YQwertyKey { text: "⇧"; accent: true; isChecked: shiftOn; onKeyLongPressed: togglePinyin() }
YMouseArea {
    id: id_key
    objectName: "YQwertyKey.qml_YMouseArea"
    width: 74
    height: 34

    property string text: ""      // 按键显示的字符 / 点击后插入的字符
    property string icon: ""      // 非空时用图标代替文字（image://icons 名，如 "input/ic_delete"）
    property bool accent: false   // 特殊键（shift/功能键）深色底
    property bool isChecked: false // 激活态（shift 大写、拼音模式等）绿色底

    signal keyPressed(string text)
    signal keyLongPressed()

    property bool _longHeld: false

    onPressed: {
        _longHeld = false
    }
    onPressAndHold: {
        _longHeld = true
        keyLongPressed()
    }
    onReleased: {
        if (!_longHeld) {
            keyPressed(id_key.text)
        }
        _longHeld = false
    }
    onCanceled: {
        _longHeld = false
    }

    // 按键底
    Rectangle {
        id: id_key_bg
        anchors.fill: parent
        radius: 10
        color: id_key.isChecked ? YColors.green
                                : (id_key.accent ? YColors.buttonNormal : YColors.grayNormal)
    }

    // 按下高亮
    Rectangle {
        anchors.fill: parent
        radius: 10
        color: "#4A4B52"
        visible: id_key.pressed
    }

    // 键面图标
    YImage {
        id: id_key_icon
        anchors.centerIn: parent
        sourceSize: Qt.size(28, 28)
        imageName: id_key.icon
        visible: id_key.icon.length > 0
    }

    // 键面文字（按下放大）
    YTextMedium {
        anchors.centerIn: parent
        font.pixelSize: id_key.pressed ? 26 : 22
        color: YColors.white
        text: id_key.text
        visible: id_key.icon.length === 0
    }
}
