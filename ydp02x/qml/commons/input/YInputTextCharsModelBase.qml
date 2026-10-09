import QtQuick 2.12

import "../../commons"

// 字符键盘的公共基类：按“行”渲染按键。
//
// 之所以不用 Flow 而是用 Column + Row，是因为紧凑布局下需要精确控制
// QWERTY 每行的按键数量（10/9/7），Flow 无法强制换行。
Column {
    id: id_input_text_chars_model_base_view
    width: 300
    spacing: rowSpacing

    readonly property alias containerItem: id_input_text_chars_model_base_view

    // 行数据：每个元素是一行，行内每个元素是按键文本字符串。
    // 也允许特殊按键使用对象描述（例如符号页的空格键），此时渲染图标。
    property var rows: []

    // 是否使用紧凑布局（按键更小、每行更多）
    property bool compact: compactLayout

    // 紧凑布局下每行的列数（用于计算按键宽度）
    property int columns: 5

    property real keySpacing: compact ? 3 : 5
    property real rowSpacing: compact ? 3 : 5
    property real keyWidth: compact ? (300 - (columns - 1) * keySpacing) / columns : 56
    property real keyHeight: compact ? 30 : 46
    property bool centerRows: compact

    // 全局布局开关，来自 keyBoard 后端
    readonly property bool compactLayout: (typeof keyBoard !== 'undefined')
                                          && (keyBoard !== null)
                                          && keyBoard.keyboardLayout === "compact"

    property bool skipPressedAction: false // 为了能够区别对待小写字母按钮，我们需要一个判断条件（特定于 qml/commons/input/YInputTextLowerChars.qml）

    signal keyClicked(string text)
    signal enterSpace()

    function charTriggered(text) {
        if (!skipPressedAction) {
            id_input_text_title_area.enterChar(text);
        }
    }

    function charPressed(text, posX, posY) {
        // 注意：id_highlight_item.width/height 绑定到 visible 属性，
        // 在此函数被调用时绑定的值尚未重新求值（仍为 0），
        // 因此直接使用常量 66/2=33, 56/2=28
        id_highlight_item_content.text = text;
        id_highlight_item.x = posX - 33;
        id_highlight_item.y = posY - 28;
    }

    function charRelessed() {
        id_highlight_item_content.text = "";
    }

    Repeater {
        model: id_input_text_chars_model_base_view.rows

        delegate: Row {
            spacing: id_input_text_chars_model_base_view.keySpacing
            anchors.left: id_input_text_chars_model_base_view.centerRows ? undefined : id_input_text_chars_model_base_view.left
            anchors.horizontalCenter: id_input_text_chars_model_base_view.centerRows ? id_input_text_chars_model_base_view.horizontalCenter : undefined

            Repeater {
                model: modelData

                delegate: YInputTextItem {
                    readonly property bool isSpecialKey: modelData !== null && typeof modelData === "object"

                    width: id_input_text_chars_model_base_view.keyWidth
                    height: id_input_text_chars_model_base_view.keyHeight

                    text: isSpecialKey ? "" : modelData
                    iconMode: isSpecialKey
                    iconName: "input/ic_space"

                    onClicked: {
                        if (isSpecialKey)
                            id_input_text_chars_model_base_view.enterSpace();
                        else
                            id_input_text_chars_model_base_view.keyClicked(text);
                    }
                }
            }
        }
    }
}
