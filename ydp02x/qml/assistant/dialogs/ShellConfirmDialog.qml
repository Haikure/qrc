import QtQuick 2.12
import "../../commons"

Item {
    id: root
    anchors.fill: parent
    visible: active
    z: 3000

    property string toolCallId: ""
    property string command: ""
    property var fontFamily
    property bool active: false
    property var queue: []
    property var audit: ({})

    signal approved(string toolCallId)
    signal denied(string toolCallId)

    onActiveChanged: {
        if (active) confirmDialog.show();
        else confirmDialog.close();
    }

    function warningsText() {
        return audit && audit.warnings ? audit.warnings.join("\n") : "";
    }

    function refreshAudit(cmd) {
        audit = ({});
        if (typeof chatbot === "undefined" || !chatbot || typeof chatbot.auditShellCommand !== "function")
            return;
        try {
            audit = JSON.parse(chatbot.auditShellCommand(cmd));
        } catch (e) {
            audit = ({});
        }
    }

    function show(tcId, cmd) {
        if (active) {
            queue = queue.concat([{"toolCallId": tcId, "command": cmd}]);
            return;
        }
        toolCallId = tcId;
        command = cmd;
        refreshAudit(cmd);
        commandScroll.contentY = 0;
        active = true;
    }

    function clear() {
        queue = [];
        active = false;
        toolCallId = "";
        command = "";
        audit = ({});
    }

    function processNext() {
        if (queue.length > 0) {
            var next = queue[0];
            queue = queue.slice(1);
            toolCallId = next.toolCallId;
            command = next.command;
            refreshAudit(next.command);
            commandScroll.contentY = 0;
        } else {
            clear();
        }
    }

    function resolve(allow) {
        if (!active) return;
        var id = toolCallId;
        // 先推进队列，避免同步回调清空队列后又错误地处理下一项。
        processNext();
        if (allow) root.approved(id);
        else root.denied(id);
    }

    YTwoButtonDialog {
        id: confirmDialog
        anchors.fill: parent
        // 原生组件左侧 buttonItemConfirm 是取消，右侧 buttonItemCancel 是确认。
        buttonItemConfirm.text: "拒绝"
        buttonItemCancel.text: "执行"
        tipItem.text: ""
        onClickedConfirm: root.resolve(true)
        onClickedCancel: root.resolve(false)
        onClosed: {
            root.resolve(false);
            if (root.active) show();
        }
    }

    Flickable {
        id: commandScroll
        parent: confirmDialog.tipItem
        anchors.fill: parent
        contentWidth: width
        contentHeight: commandColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: commandColumn
            width: commandScroll.width
            spacing: 4

            YText {
                width: parent.width
                text: "AI 请求执行命令" + (root.queue.length > 0 ? "（待处理 " + root.queue.length + "）" : "")
                font.pixelSize: 13
                font.bold: true
                font.family: qmlGlobal.fontFamilyZhCn
                wrapMode: Text.Wrap
            }

            YText {
                width: parent.width
                text: root.command
                textFormat: Text.PlainText
                font.pixelSize: 12
                font.family: qmlGlobal.fontFamilyZhCn
                wrapMode: Text.WrapAnywhere
            }

            YText {
                width: parent.width
                visible: text !== ""
                text: root.warningsText()
                textFormat: Text.PlainText
                font.pixelSize: 11
                font.family: qmlGlobal.fontFamilyZhCn
                wrapMode: Text.Wrap
            }
        }
    }
}
