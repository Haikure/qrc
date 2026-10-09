import QtQuick 2.12

import "../commons"
import "../components"
import "../i18n"

YSettingItemPage {
    id: id_setting_item
    objectName: "YPage===QuerySettingPage.qml"

    Flickable {
        id: id_setting_item_view
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "扫描查询设置"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            DescribedSwitchItem {
                title: YTranslateText.continueScan
                description: "一次扫描后，若两秒内再次扫描则视为追加扫描。"
                switchOn: settingManager.isContinueScan
                interval: 0
                onTimerTriggered: {
                    settingManager.isContinueScan = switchOn
                }
            }

            DescribedSwitchItem {
                title: "手动输入内容查询"
                description: "在主菜单点击 \"查词翻译\" 时打开键盘。"
                switchOn: queryTweaks.typeByHand
                interval: 0
                onTimerTriggered: {
                    queryTweaks.typeByHand = switchOn
                }
            }

            YSettingSwitchItem {
                title: "扫描结果转到小写"
                switchOn: queryTweaks.lowerScan
                interval: 0
                onTimerTriggered: {
                    queryTweaks.lowerScan = switchOn
                }
            }

            YSpacingForColumn {
                implicitHeight: 4
            }

            YText {
                id: id_custom_dict_title
                font.pixelSize: 16
                font.italic: true
                color: YColors.grayText
                wrapMode: YText.Wrap
                lineHeightMode: YTextBase.FixedHeight
                lineHeight: 24
                width: parent.width
                text: "自定义词典"
            }

            DescribedClickableTextBox {
                title: "自造词典"
                describe: customDict.dictionaries.length > 0
                          ? "查询时与内置词典一起显示"
                          : "把 .dat 放到 /userdisk/PenMods/dicts/"
                value: customDict.dictionaries.length > 0
                       ? "%1 本".arg(customDict.dictionaries.length)
                       : "未安装"
                describeItem.width: width - 90
                onClicked: openSettingPage("CustomDictPage")
            }

            YSpacingForColumn {
                implicitHeight: 20
            }

        }

    }

}
