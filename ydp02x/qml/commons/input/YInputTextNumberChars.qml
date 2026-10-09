import QtQuick 2.12

YInputTextCharsModelBase {
    id: root

    compact: compactLayout
    columns: 7

    // 原生布局：每行 5 个
    readonly property var nativeRows: [
        ["1", "2", "3", "4", "5"],
        ["6", "7", "8", "9", "0"],
        [".", ",", "?", "!", "'"],
        ["-", "/", ":", "(", ")"],
        ["@"]
    ]

    // 紧凑布局：每行 7 个
    readonly property var compactRows: [
        ["1", "2", "3", "4", "5", "6", "7"],
        ["8", "9", "0", ".", ",", "?", "!"],
        ["'", "-", "/", ":", "(", ")", "@"]
    ]

    rows: compactLayout ? compactRows : nativeRows
}
