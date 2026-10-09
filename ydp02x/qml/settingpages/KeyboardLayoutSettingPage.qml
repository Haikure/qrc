import QtQuick 2.12
import com.youdao.pen 1.0

import "../commons"
import "../components"
import "../i18n"

// 键盘布局设置（第二层）
YSettingItemPage {
    id: id_setting_item
    objectName: "YPage===KeyboardLayoutSettingPage.qml"

    readonly property bool isCompact: keyBoard.keyboardLayout === "compact"

    Flickable {
        id: id_setting_item_view
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: id_title_container.height + id_column.height
        clip: true

        YSettingItemTitle {
            id: id_title_container
            title: "键盘布局"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            Row {
                spacing: 8

                YPressedButton {
                    id: id_native_button
                    implicitWidth: 124
                    text: "原生"
                    clickable: id_setting_item.isCompact
                    checkedIndicatorScale: !id_setting_item.isCompact
                    onClicked: {
                        keyBoard.keyboardLayout = "native";
                    }
                }

                YPressedButton {
                    id: id_compact_button
                    implicitWidth: 124
                    text: "紧凑"
                    clickable: !id_setting_item.isCompact
                    checkedIndicatorScale: id_setting_item.isCompact
                    onClicked: {
                        keyBoard.keyboardLayout = "compact";
                    }
                }
            }

            YText {
                width: parent.width
                color: YColors.grayText
                font.pixelSize: 14
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 20
                text: "原生：全部按键保持原有大小，字母按 a-z 排列。\n紧凑：按键更小，字母改用 QWERTY 排列（qwertyuiop / asdfghjkl / zxcvbnm），更适合拼音输入。\n修改后重新打开输入页生效。"
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }
}
