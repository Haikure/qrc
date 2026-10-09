import QtQuick 2.12

YInputTextCharsModelBase {
    id: root

    compact: compactLayout
    columns: 7

    // 用对象描述特殊按键（空格），基类会渲染成功能按钮
    readonly property var spaceKey: ({
        "space": true
    })

    // 原生布局：每行 5 个
    readonly property var nativeRows: [
        [spaceKey, ".", ",", "?", "!"],
        ["'", "-", "/", ":", ";"],
        ["(", ")", "$", "&", "@"],
        ["\"", "[", "]", "{", "}"],
        ["#", "%", "^", "*", "+"],
        ["=", "_", "\\", "|", "~"],
        ["<", ">", "￥"]
    ]

    // 紧凑布局：每行 7 个
    readonly property var compactRows: [
        [spaceKey, ".", ",", "?", "!", "'", "-"],
        ["/", ":", ";", "(", ")", "$", "&"],
        ["@", "\"", "[", "]", "{", "}", "#"],
        ["%", "^", "*", "+", "=", "_", "\\"],
        ["|", "~", "<", ">", "￥"]
    ]

    rows: compactLayout ? compactRows : nativeRows
}
