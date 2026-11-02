import QtQuick 2.12
import com.github.penuniverse 1.0

import "../commons"
import "../components"
import "../i18n"
import "../settingpages"

YBackButtonPage {
    id: id_model_page
    objectName: "YPage===ModelManagePage.qml"

    // 列表页只需要摘要（id/name/provider/capabilities/isActive 等），不再让 C++ 每次全量序列化整份配置
    property var modelList: []
    // 编辑页组件缓存：第一次异步加载，之后复用，避免每次点击都在 UI 线程同步 parse/compile 整页 QML
    property var detailComponent: null
    property bool detailOpening: false
    property double detailOpenStart: 0

    function refreshModels() {
        var parsed = null;
        try {
            parsed = JSON.parse(chatbot.getModelSummaries());
        } catch (e) {
            console.error("ModelManagePage: 读取模型摘要失败:", e);
        }
        modelList = (parsed && parsed.models) ? parsed.models : [];
    }

    function describeOf(model) {
        var text = model.provider || model.modelId || "";
        if (model.isActive) text = "使用中  ·  " + text;
        if (model.hasWarning) text += "  ·  配置待修正";
        return text;
    }

    function ensureDetailComponent() {
        if (detailComponent) return detailComponent;
        detailComponent = Qt.createComponent("qrc:/qml/settingpages/ModelDetailPage.qml", Component.Asynchronous);
        if (detailComponent && detailComponent.status === Component.Error)
            console.error("ModelManagePage: 编辑页组件加载失败:", detailComponent.errorString());
        return detailComponent;
    }

    function attachDetailPage(page) {
        if (!page) {
            detailOpening = false;
            showToast("编辑页加载失败", 2);
            return;
        }
        console.log("[ModelEditor] edit page ready in", Math.round(Date.now() - detailOpenStart), "ms",
                    "component cached:", detailComponent !== null);
        page.modelSaved.connect(function() {
            refreshModels();
            detailOpening = false;
        });
        page.modelDeleted.connect(function() {
            refreshModels();
            detailOpening = false;
        });
        page.backButtonClicked.connect(function() {
            page.todoDestroy();
            detailOpening = false;
        });
        page.show();
    }

    function incubateDetailPage(component, targetModelId) {
        var parentItem = id_model_page.parent || id_model_page;
        var incubator = component.incubateObject(parentItem, { "modelId": targetModelId }, Qt.Asynchronous);
        if (!incubator) {
            detailOpening = false;
            showToast("编辑页加载失败", 2);
            return;
        }
        if (incubator.status === Component.Ready) {
            attachDetailPage(incubator.object);
            return;
        }
        incubator.onStatusChanged = function(status) {
            if (status === Component.Ready) {
                attachDetailPage(incubator.object);
            } else if (status === Component.Error) {
                detailOpening = false;
                console.error("ModelManagePage: 编辑页实例化失败:", incubator.errorString ? incubator.errorString() : "");
                showToast("编辑页加载失败", 2);
            }
        };
    }

    // summary 为空 / 无 id 表示新建模型；否则编辑已配置模型（列表里每行都是一次点击直接进编辑页）
    function openDetailPage(summary) {
        if (detailOpening) return;
        detailOpening = true;
        detailOpenStart = Date.now();

        var targetModelId = (summary && summary.id) ? summary.id : "";
        console.log("[ModelEditor] openDetailPage id=", targetModelId,
                    "component status:", detailComponent ? detailComponent.status : -1);
        var component = ensureDetailComponent();
        if (!component) {
            detailOpening = false;
            showToast("编辑页组件不可用", 2);
            return;
        }

        if (component.status === Component.Ready) {
            incubateDetailPage(component, targetModelId);
            return;
        }
        if (component.status === Component.Error) {
            detailOpening = false;
            console.error("ModelManagePage: 编辑页组件加载失败:", component.errorString());
            showToast("编辑页加载失败", 2);
            return;
        }

        // 组件还在异步加载：等它就绪后再孵化页面（期间给用户一个明确反馈，避免误以为没反应）
        showToast("正在打开编辑页…");
        var handled = false;
        var onComponentStatusChanged = function() {
            if (handled) return;
            console.log("[ModelEditor] detail component status:", component.status,
                        "elapsed:", Math.round(Date.now() - detailOpenStart), "ms");
            if (component.status === Component.Ready) {
                handled = true;
                incubateDetailPage(component, targetModelId);
            } else if (component.status === Component.Error) {
                handled = true;
                detailOpening = false;
                console.error("ModelManagePage: 编辑页组件加载失败:", component.errorString());
                showToast("编辑页加载失败", 2);
            }
        };
        component.statusChanged.connect(onComponentStatusChanged);
    }

    property string toastMsg: ""
    property bool toastVisible: false
    property int toastType: 0

    function showToast(msg, type) {
        toastMsg = msg;
        toastType = type || 0;
        toastVisible = true;
        id_toast_timer.restart();
    }

    Timer {
        id: id_toast_timer
        interval: 2500
        onTriggered: toastVisible = false
    }

    Component.onCompleted: {
        refreshModels();
    }

    onVisibleChanged: {
        if (visible) refreshModels();
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: toastVisible ? 16 : -40
        width: Math.min(id_toast_text.implicitWidth + 32, parent.width - 20)
        height: 30
        radius: 6
        color: toastType === 2 ? "#4A1A1D" : toastType === 1 ? "#1A3A2A" : "#1A2A3A"
        z: 2000
        visible: opacity > 0
        opacity: toastVisible ? 1 : 0

        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            id: id_toast_text
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 16)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: toastMsg
            color: toastType === 2 ? "#FF6B6B" : toastType === 1 ? "#4CAF50" : YColors.grayText
            font.pixelSize: 12
            font.family: qmlGlobal.fontFamilyZhCn
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 10
        contentHeight: id_content_col.height + 20
        clip: true

        Column {
            id: id_content_col
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            YSettingItemTitle {
                title: "模型管理"
            }

            Repeater {
                model: modelList

                DescribedClickableTextBox {
                    readonly property var modelItem: modelData || ({})
                    readonly property bool isActive: modelItem.isActive === true

                    title: modelItem.name || modelItem.id || ""
                    describe: describeOf(modelItem)
                    describeItem.color: isActive ? YColors.blueText : YColors.grayText
                    opacityChangableWhenPressed: false

                    onClicked: openDetailPage(modelItem)
                }
            }

            DescribedClickableTextBox {
                title: "添加模型"
                describe: "配置新的 AI 模型"
                describeItem.color: YColors.grayText
                opacityChangableWhenPressed: false
                onClicked: openDetailPage({})
            }
        }
    }
}
