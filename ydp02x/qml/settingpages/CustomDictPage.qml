import QtQuick 2.12
import com.github.penuniverse 1.0

import "../commons"
import "../components"
import "../dicts/YDictPenModsBlocks.js" as PenModsBlocks

/**
 * 自造词典：查看 /userdisk/PenMods/dicts/ 里装了哪些词典，单独查一个词。
 *
 * 装进来的词典在**主查询（扫描/查词翻译）里也会自动一起显示**，这里主要用于查看和管理；
 * 容器格式与生成工具见 doc/DICT_FORMAT_ANALYSIS.md 与 tools/dict-probe/：
 *     python3 tools/dict-probe/dat_probe.py build 词典V2.dat entries.jsonl
 */
YBackButtonPage {
    id: id_custom_dict_page
    objectName: "YPage===CustomDictPage.qml"

    function openKeyboard() {
        var component = qmlCreateComponent("YInputPage");
        if (Component.Ready !== component.status)
            return;
        var incubator = component.incubateObject(id_dict_pop.containerItem);
        if (incubator.status !== Component.Ready) {
            incubator.onStatusChanged = function(status) {
                if (status === Component.Ready)
                    id_dict_pop.inputPageCreated(incubator.object);
            };
        } else {
            id_dict_pop.inputPageCreated(incubator.object);
        }
    }

    /// 当前命中的记录切成 block 列表（排版交给 YCustomDictContentView）
    readonly property var recordBlocks: {
        if (customDict.record.length <= 0)
            return [];
        try {
            return PenModsBlocks.blocks(JSON.parse(customDict.record));
        } catch (e) {
            return [{"type": "raw", "text": customDict.record}]; // 不是 JSON：原样显示
        }
    }

    Component.onCompleted: customDict.refresh()

    Item {
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        anchors.topMargin: 14
        anchors.bottomMargin: 8

        Column {
            id: id_header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 6

            YText {
                width: parent.width
                height: 20
                font.pixelSize: 16
                font.italic: true
                color: YColors.grayText
                text: "自造词典"
            }

            // 词典选择：一本一个圆角卡片
            ListView {
                id: id_dict_list
                width: parent.width
                height: 24
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                model: customDict.dictionaries

                delegate: Rectangle {
                    width: Math.min(id_dict_name.implicitWidth + 20, 168)
                    height: 24
                    radius: 12
                    color: index === customDict.index ? YColors.red : YColors.grayNormal

                    YText {
                        id: id_dict_name
                        anchors.centerIn: parent
                        font.pixelSize: 13
                        elide: YText.ElideRight
                        maximumLineCount: 1
                        text: modelData.name + " · " + modelData.words
                    }

                    YMouseArea {
                        anchors.fill: parent
                        onClicked: customDict.index = index
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: parent.width - 58
                    height: 28
                    radius: 12
                    color: YColors.grayNormal

                    YText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        font.pixelSize: 14
                        elide: YText.ElideRight
                        color: customDict.word.length > 0 ? YColors.white : YColors.grayText
                        text: customDict.word.length > 0 ? customDict.word : "点这里输入要查的词"
                    }

                    YMouseArea {
                        anchors.fill: parent
                        onClicked: id_custom_dict_page.openKeyboard()
                    }
                }

                Rectangle {
                    width: 50
                    height: 28
                    radius: 12
                    color: YColors.red

                    YText {
                        anchors.centerIn: parent
                        font.pixelSize: 14
                        text: "查询"
                    }

                    YMouseArea {
                        anchors.fill: parent
                        onClicked: customDict.lookup()
                    }
                }
            }
        }

        Flickable {
            id: id_result_view
            anchors.top: id_header.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: id_status.top
            anchors.bottomMargin: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: id_result_text.height + 16 // 底部留出安全距离

            // 和结果页用同一套排版（含发音按钮）
            YCustomDictContentView {
                id: id_result_text
                width: id_result_view.width
                blocks: id_custom_dict_page.recordBlocks
            }

            YText {
                visible: id_custom_dict_page.recordBlocks.length === 0
                width: id_result_view.width
                font.pixelSize: 13
                lineHeight: 18
                lineHeightMode: YText.FixedHeight
                wrapMode: YText.Wrap
                color: YColors.grayText
                text: "把 .dat 放进\n/userdisk/PenMods/dicts/"
            }
        }

        YText {
            id: id_status
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 16
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 12
            elide: YText.ElideRight
            color: YColors.grayText
            text: customDict.status
        }
    }

    YPagePopHelper {
        id: id_dict_pop
        isShowing: qmlGlobal.inputPageShowing
        objectName: "from_CustomDictPage.qml"

        function inputPageCreated(keyboardPage) {
            keyboardPage.placeHolderText = "输入要查的词";
            keyboardPage.backButtonClicked.connect(function() {
                qmlGlobal.inputPageShowing = false;
                keyboardPage.todoDestroy();
            });
            keyboardPage.inputFinished.connect(function(input) {
                qmlGlobal.inputPageShowing = false;
                keyboardPage.todoDestroy();
                if (input !== null)
                    customDict.lookupWord(input);
            });
            if (customDict.word.length > 0)
                keyboardPage.enterText(customDict.word);
            keyboardPage.show();
            qmlGlobal.inputPageShowing = true;
        }
    }
}
