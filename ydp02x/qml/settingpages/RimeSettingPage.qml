import QtQuick 2.12
import com.youdao.pen 1.0

import "../commons"
import "../components"
import "../i18n"

// Rime 输入法设置（第二层）
YSettingItemPage {
    id: id_setting_item
    objectName: "YPage===RimeSettingPage.qml"

    // 把当前方案的 id 显示为更友好的名称
    function currentSchemaName() {
        var current = rime.currentSchemaId;
        if (!current || current.length === 0)
            return "";

        try {
            var list = JSON.parse(rime.schemaListJson());
            for (var i = 0; i < list.length; i++) {
                if (list[i].id === current)
                    return list[i].name || current;
            }
        } catch (e) {
            console.log("RimeSettingPage: parse schema list failed: " + e);
        }
        return current;
    }

    Component.onCompleted: {
        rime.refreshCurrentSchema();
    }

    Connections {
        target: rime

        onDeployFinished: {
            qmlGlobal.showToast(success ? "重新部署完成，请重新打开输入页" : "重新部署失败", success ? YColors.green : YColors.yellow);
        }

        onSyncFinished: {
            qmlGlobal.showToast(success ? "用户数据已同步" : "同步失败", success ? YColors.green : YColors.yellow);
        }
    }

    Flickable {
        id: id_setting_item_view
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "Rime 输入法"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            YSettingAboutClickableItem {
                title: "输入方案"
                value: currentSchemaName()
                imageName: "settings/info_more_arrow"
                onClicked: {
                    openSettingPage("RimeSchemaPage");
                }
            }

            DescribedClickableTextBox {
                title: rime.deploying ? "正在重新部署…" : "重新部署"
                describe: "重新编译并加载输入方案与词库。首次使用或修改方案文件后执行。完成后需重新打开输入页。"
                opacityChangableWhenPressed: false
                enabled: !rime.deploying && !rime.syncing
                onClicked: {
                    rime.redeploy();
                }
            }

            DescribedClickableTextBox {
                title: rime.syncing ? "正在同步…" : "同步用户数据"
                describe: "合并并保存用户词典、词频等用户数据。"
                opacityChangableWhenPressed: false
                enabled: !rime.deploying && !rime.syncing
                onClicked: {
                    rime.syncUserData();
                }
            }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }
}
