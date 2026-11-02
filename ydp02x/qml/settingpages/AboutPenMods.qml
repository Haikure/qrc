import "../commons"
import "../components"
import "../i18n"
import QtQuick 2.12
import com.youdao.pen 1.0

YSettingItemPage {
    id: id_setting_item

    objectName: "YPage===AboutPenMods.qml"

    Flickable {
        id: id_setting_item_view

        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        clip: true
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: qsTr("关于 PenMods")
        }

        Column {
            id: id_column

            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            YSettingAboutItem {
                implicitHeight: 36
                color: "transparent"
                titlePixelSize: 16
                titleColor: YColors.grayText
                title: qsTr("版本")
                value: mod.version
            }

            YSettingItemTitle {
                title: qsTr("项目与支持")
            }

            YSettingAboutItem {
                implicitHeight: 36
                color: "transparent"
                titlePixelSize: 16
                titleColor: YColors.grayText
                title: "GitHub"
                value: "PenUniverse"
            }

            Column {
                width: parent.width - 20
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                YText {
                    text: qsTr("Telegram 社群")
                    font.pixelSize: 16
                    color: YColors.grayText
                }

                YText {
                    width: parent.width
                    text: "https://t.me/PenUniverse"
                    font.pixelSize: 14
                    wrapMode: Text.Wrap
                }
            }

            YSettingAboutClickableItem {
                title: qsTr("捐助项目发展")
                imageName: "settings/info_more_arrow"
                onClicked: {
                    openSettingPage("AFDianQrCode");
                }
            }

            YSettingItemTitle {
                title: qsTr("特别鸣谢")
            }

            YText {
                width: parent.width - 20
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 14
                color: YColors.grayText
                wrapMode: Text.Wrap
                text: "Dobby (Hook Framework)\nQt Project\nNetease Youdao\nRedbeanW (Developer)\nAll Sponsors..."
            }

            YSettingItemTitle {
                title: qsTr("技术信息")
            }

            Column {
                width: parent.width - 20
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                YText {
                    text: qsTr("构建信息")
                    font.pixelSize: 16
                    color: YColors.grayText
                }

                YText {
                    width: parent.width
                    text: mod.buildInfo
                    font.pixelSize: 14
                    color: YColors.grayText
                    wrapMode: Text.WrapAnywhere
                }
            }

            YSettingAboutItem {
                implicitHeight: 36
                color: "transparent"
                titlePixelSize: 16
                titleColor: YColors.grayText
                title: qsTr("已缓存符号计数")
                value: mod.cachedSymCount
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }
}
