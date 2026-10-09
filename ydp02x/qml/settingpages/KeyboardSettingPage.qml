import QtQuick 2.12
import com.youdao.pen 1.0

import "../commons"
import "../components"
import "../i18n"

// 键盘设置（第一层）：
//   ├── Rime 输入法   → RimeSettingPage
//   └── 键盘布局       → KeyboardLayoutSettingPage
YSettingItemPage {
    id: id_setting_item
    objectName: "YPage===KeyboardSettingPage.qml"

    Flickable {
        id: id_setting_item_view
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "键盘设置"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            YSettingAboutClickableItem {
                title: "Rime 输入法"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    openSettingPage("RimeSettingPage");
                }
            }

            YSettingAboutClickableItem {
                title: "键盘布局"
                value: keyBoard.keyboardLayout === "compact" ? "紧凑" : "原生"
                imageName: "settings/info_more_arrow"
                onClicked: {
                    openSettingPage("KeyboardLayoutSettingPage");
                }
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }
}
