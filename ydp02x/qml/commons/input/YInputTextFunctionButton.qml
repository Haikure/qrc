import QtQuick 2.12

import "../../commons"

YPressedBaseButton {
    id: id_function_button
    radius: 12
    implicitWidth: 56
    implicitHeight: 46

    // 不沿用整键变暗：选中的红色键也要能清楚看到按下反馈。
    readonly property bool feedbackActive: pressed || tapFeedback.running
    opacity: enabled ? 1 : 0.6
    onPressedChanged: {
        if (pressed)
            tapFeedback.restart();
    }
    onEnabledChanged: {
        if (!enabled)
            tapFeedback.stop();
    }

    Timer {
        id: tapFeedback
        interval: 160
    }

    Connections {
        target: id_function_button.mouseAreaItem
        function onCanceled() {
            tapFeedback.stop();
        }
    }

    // 纯视觉层，不接管 MouseArea，保留长按清空、取消和点击语义。
    Rectangle {
        anchors.fill: parent
        radius: id_function_button.radius
        z: 1
        color: id_function_button.feedbackActive ? "#40FFFFFF" : "transparent"
        border.width: id_function_button.feedbackActive ? 2 : 0
        border.color: "#FFFFFF"
    }
}
