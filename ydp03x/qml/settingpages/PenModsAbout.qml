import "../common"
import "../components"
import "../i18n"
import QtQuick 2.12
import com.youdao.pen 1.0

YSettingItemPage {
    id: id_setting_item
    objectName: "YPage===PenModsAbout.qml"

    Flickable {
        id: id_setting_item_view
        anchors.fill: parent
        anchors.leftMargin: 90
        anchors.rightMargin: 16
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "关于 PenMods"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            PenModsSettingRow {
                title: "版本"
                value: mod.version
            }

            DescribedClickableTextBox {
                opacityChangableWhenPressed: false
                describeItem.width: 200
                title: "构建信息"
                describe: mod.buildInfo
            }

            PenModsSettingRow {
                title: "已缓存符号计数"
                value: "" + mod.cachedSymCount
            }

            PenModsSettingRow {
                title: "GitHub"
                value: "PenUniverse"
            }

            DescribedClickableTextBox {
                opacityChangableWhenPressed: false
                describeItem.width: 200
                title: "Telegram 社群"
                describe: "https://t.me/PenUniverse"
            }

            DescribedClickableTextBox {
                opacityChangableWhenPressed: false
                describeItem.width: 200
                title: "特别鸣谢"
                describe: "Dobby (Hook Framework)\nQt Project\nNetease Youdao\nRedbeanW (Developer)\nAll Sponsors..."
            }

            PenModsSettingRow {
                title: "捐助项目发展"
                value: ""
                onClicked: {
                    baseSignals.showToast("感谢支持 PenMods（捐助入口见 GitHub）", YColors.yellow)
                }
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }
}
