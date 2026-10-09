import QtQuick 2.12

YInputTextCharsModelBase {
    id: root

    compact: compactLayout
    columns: 10

    // 原生布局：字母表顺序，每行 5 个
    readonly property var nativeRows: [
        ["A", "B", "C", "D", "E"],
        ["F", "G", "H", "I", "J"],
        ["K", "L", "M", "N", "O"],
        ["P", "Q", "R", "S", "T"],
        ["U", "V", "W", "X", "Y"],
        ["Z"]
    ]

    // 紧凑布局：QWERTY 排列，常用字母集中在顶部
    readonly property var compactRows: [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]

    rows: compactLayout ? compactRows : nativeRows
}
