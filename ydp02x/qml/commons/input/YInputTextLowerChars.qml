import QtQuick 2.12

YInputTextCharsModelBase {
    id: root
    skipPressedAction: true

    compact: compactLayout
    columns: 10

    // 原生布局：字母表顺序，每行 5 个
    readonly property var nativeRows: [
        ["a", "b", "c", "d", "e"],
        ["f", "g", "h", "i", "j"],
        ["k", "l", "m", "n", "o"],
        ["p", "q", "r", "s", "t"],
        ["u", "v", "w", "x", "y"],
        ["z"]
    ]

    // 紧凑布局：QWERTY 排列，常用字母集中在顶部
    readonly property var compactRows: [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    rows: compactLayout ? compactRows : nativeRows
}
