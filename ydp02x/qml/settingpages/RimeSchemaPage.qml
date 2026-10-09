import QtQuick 2.12
import com.youdao.pen 1.0

import "../commons"
import "../components"
import "../i18n"

// Rime 输入方案选择
YSettingItemPage {
    id: id_setting_item
    objectName: "YPage===RimeSchemaPage.qml"

    property var schemaList: []

    function refreshSchemas() {
        try {
            schemaList = JSON.parse(rime.schemaListJson());
        } catch (e) {
            console.log("RimeSchemaPage: parse schema list failed: " + e);
            schemaList = [];
        }
    }

    function selectSchema(schemaId) {
        if (rime.selectSchema(schemaId)) {
            refreshSchemas();
            qmlGlobal.showToast("已切换输入方案", YColors.green);
        } else {
            qmlGlobal.showToast("切换失败，请先重新部署", YColors.yellow);
        }
    }

    Component.onCompleted: {
        refreshSchemas();
        rime.refreshCurrentSchema();
    }

    Flickable {
        id: id_setting_item_view
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: id_column.height + 20
        clip: true

        Column {
            id: id_column
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            YSettingItemTitle {
                title: "选择输入方案"
            }

            Repeater {
                model: id_setting_item.schemaList

                delegate: DescribedClickableTextBox {
                    readonly property bool isActive: modelData.id === rime.currentSchemaId

                    title: modelData.name || modelData.id
                    describe: isActive ? "使用中" : modelData.id
                    describeItem.color: isActive ? YColors.blueText : YColors.grayText
                    opacityChangableWhenPressed: false

                    onClicked: {
                        if (!isActive)
                            id_setting_item.selectSchema(modelData.id);
                    }
                }
            }

            YText {
                width: parent.width
                color: YColors.grayText
                font.pixelSize: 14
                wrapMode: YText.Wrap
                visible: id_setting_item.schemaList.length === 0
                text: "没有发现可用输入方案。请将 Rime 方案与词库放入 /userdisk/Music/Rime，再执行“重新部署”。"
            }
        }
    }
}
