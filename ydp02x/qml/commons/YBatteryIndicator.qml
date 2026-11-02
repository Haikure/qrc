import QtQuick 2.12

Rectangle {
    id: root

    property int percentage: 0
    property bool charging: false
    readonly property int level: Math.max(0, Math.min(100, percentage))

    implicitWidth: 28
    implicitHeight: 14
    border.width: 2
    border.color: YColors.white
    color: "transparent"
    radius: 10
    smooth: true

    Item {
        id: fillArea
        width: 22
        height: 8
        anchors.centerIn: parent

        Item {
            anchors.fill: parent
            anchors.rightMargin: (100 - root.level) * fillArea.width / 100
            smooth: true
            clip: true

            Rectangle {
                width: fillArea.width
                height: fillArea.height
                anchors.right: parent.right
                anchors.rightMargin: -parent.anchors.rightMargin
                color: root.charging && root.level < 100 ? "#00FF66"
                       : (root.level < 20 && !root.charging ? YColors.red : YColors.white)
                radius: height / 2
                smooth: true
            }
        }
    }
}
