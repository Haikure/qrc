import "../commons"
import "../components"
import "../i18n"
import QtQuick 2.12
import com.youdao.pen 1.0

YPage {
    id: id_container_index

    // 文件选择器的属性
    property string selectedFilePath: ""
    property string selectedFileName: ""
    property bool allowMultiSelect: false
    property var selectedFiles: []
    property var fileExtensions: [] // 允许的文件扩展名，空表示所有文件
    signal fileSelected(string filePath)
    signal fileSelectionCancelled()

    // 从 FileManagerPageComponent 继承的属性
    readonly property int kNormal: 0
    readonly property int kDelete: 1
    readonly property int kRename: 2
    property int currentMode: kNormal
    property string operatingFileName: ""
    property bool operatingIsDir: false

    Component.onCompleted: {
        fileManager.changeDir("");
    }

    onBackButtonClicked: fileSelectionCancelled()

    // 多选确认：构建绝对路径（; 拼接），与单选共用 fileSelected 信号。
    function confirmSelection() {
        if (!allowMultiSelect || selectedFiles.length === 0)
            return;
        var paths = [];
        for (var i = 0; i < selectedFiles.length; i++)
            paths.push(fileManager.getCurrentPathString() + "/" + selectedFiles[i]);
        selectedFilePath = paths.join(";");
        fileSelected(selectedFilePath);
        backButtonClicked();
    }

    YVerticalTitleBar {
        id: id_title_bar
        onCallBack: {
            id_error_tip.visible = false;
            if (visible && fileManager.canCdUp()) {
                fileManager.changeDir('..');
            } else {
                backButtonClicked();
                fileManager.reset();
            }
        }
    }

    FileManagerBreadcrumb {
        anchors.left: parent.left
        anchors.leftMargin: 54
        anchors.right: parent.right
        anchors.rightMargin: 10
    }

    FileManagerListView {
        id: id_files_view
        onNavigated: id_error_tip.visible = false
        anchors.fill: parent
        anchors.topMargin: 46
        anchors.leftMargin: 54
        // 多选时左侧栏多一个打勾按钮（与文件管理器左侧操作栏一致），列表左边距已留 54。
        anchors.rightMargin: 10
        spacing: 8
        model: fileManager

        cacheBuffer: 200

        onMovingChanged: {
            if (!moving && atYEnd && fileManager.hasMore)
                fileManager.loadMore();
        }
        footer: fileManager.hasMore ? id_listview_loading_footer : id_listview_loaded_footer
        Component {
            id: id_listview_loading_footer
            YListViewLoadMoreFooter {}
        }

        Component {
            id: id_listview_loaded_footer
            YSpacing {
                width: id_files_view.width
                implicitHeight: 12
            }
        }

        delegate: Item {
            width: id_files_view.width
            implicitHeight: 50

            FileManagerPageComponentViewItem {
                id: fileItem
                implicitHeight: parent.implicitHeight
                title: model.fileName
                // 简化绑定
                value: (currentMode == kNormal && !isDir) ? model.sizeStr : ''

                iconComponent.source: {
                    // kNormal Mode - 显示选择指示器
                    if (selectedFiles.indexOf(model.fileName) !== -1) {
                        return res.getDisk('settings/info_selected');
                    }
                    // kNormal
                    return isDir ? res.getDisk('settings/info_more_arrow') : '';
                }

                onClicked: {
                    operatingFileName = model.fileName;
                    operatingIsDir = isDir;

                    // 文件选择逻辑
                    if (isDir) {
                        fileManager.changeDir(model.fileName);
                    } else if (model.isSymLink) {
                        // 如果是软链接，尝试进入链接指向的目录
                        if (!fileManager.changeDir(model.fileName)) {
                            // 如果不能切换目录（说明不是目录），则按文件处理
                            // 检查文件扩展名是否符合要求
                            if (fileExtensions.length > 0 && fileExtensions.indexOf(model.extName) === -1) {
                                qmlGlobal.showToast("不支持的文件格式", YColors.yellow);
                                return;
                            }

                            if (allowMultiSelect) {
                                // 多选模式
                                var index = selectedFiles.indexOf(model.fileName);
                                // 必须整体重新赋值：property var 数组原地 push/splice 不会发 changed，
                                // 确认按钮的 selectedFiles.length 绑定会一直停在 0（按钮因此永远不可用）。
                                if (index === -1)
                                    selectedFiles = selectedFiles.concat([model.fileName]);
                                else
                                    selectedFiles = selectedFiles.filter(function(name) { return name !== model.fileName; });

                            } else {
                                // 单选模式
                                selectedFilePath = fileManager.getCurrentPathString() + "/" + model.fileName;
                                fileSelected(selectedFilePath);
                                backButtonClicked();
                            }
                        }
                    } else {
                        // 检查文件扩展名是否符合要求
                        if (fileExtensions.length > 0 && fileExtensions.indexOf(model.extName) === -1) {
                            qmlGlobal.showToast("不支持的文件格式", YColors.yellow);
                            return;
                        }

                        if (allowMultiSelect) {
                            // 多选模式
                            var index = selectedFiles.indexOf(model.fileName);
                            // 必须整体重新赋值：property var 数组原地 push/splice 不会发 changed，
                            // 确认按钮的 selectedFiles.length 绑定会一直停在 0（按钮因此永远不可用）。
                            if (index === -1)
                                selectedFiles = selectedFiles.concat([model.fileName]);
                            else
                                selectedFiles = selectedFiles.filter(function(name) { return name !== model.fileName; });

                        } else {
                            // 单选模式
                                selectedFilePath = fileManager.getCurrentPathString() + "/" + model.fileName;
                                fileSelected(selectedFilePath);
                                backButtonClicked();
                        }
                    }
                }
            }
        }
    }

    // 多选操作放在左侧栏（与文件管理器编辑文件名时的侧栏按钮一致），不再占用底栏。
    // 左上角返回 = 取消；打勾 = 确认；勾下方是已选数量。
    Item {
        id: id_multi_actions
        visible: allowMultiSelect
        width: 30
        anchors {
            left: parent.left
            leftMargin: 10
            verticalCenter: parent.verticalCenter
        }

        YIconButton {
            id: id_confirm_button
            width: 30
            height: 30
            radius: 6
            anchors.horizontalCenter: parent.horizontalCenter
            source: "textbook/select-check"
            sourceSize: Qt.size(20, 20)
            enabled: selectedFiles.length > 0
            opacity: enabled ? 1.0 : 0.35
            onValidClicked: id_container_index.confirmSelection()
        }

        Text {
            id: id_selected_count
            anchors {
                top: id_confirm_button.bottom
                topMargin: 3
                horizontalCenter: parent.horizontalCenter
            }
            text: selectedFiles.length
            color: selectedFiles.length > 0 ? "#E6EDF3" : "#8A9BAE"
            font.pixelSize: 11
            font.family: qmlGlobal.fontFamilyZhCn
            horizontalAlignment: Text.AlignHCenter
        }
    }

    YText {
        id: id_error_tip
        anchors.centerIn: parent
        color: YColors.white
        visible: false
        font.pixelSize: 20
        // 如果错误提示不含 HTML，使用 PlainText
        textFormat: Text.PlainText

        Connections {
            target: fileManager
            function onException(msg) {
                id_error_tip.visible = true;
                id_error_tip.text = msg;
            }
        }
    }


    // 多选只在当前目录内有效：换目录时清空已选，避免确认时用新目录路径拼旧文件名。
    Connections {
        target: fileManager
        function onDirectoryLoaded() {
            if (selectedFiles.length > 0)
                selectedFiles = [];
        }
    }

}