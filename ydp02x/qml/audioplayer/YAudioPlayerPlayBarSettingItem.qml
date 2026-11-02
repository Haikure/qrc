import QtQuick 2.12

import "../commons"

YButtonBase {
    id: id_icon_label_button_bg
    implicitWidth: 160
    implicitHeight: 42
    mouseAreaMargins: 0
    radius: 10
    color: YColors.grayButton

    property alias imageName: id_button_icon.imageName
    property alias sourceSize: id_button_icon.sourceSize

    property int spacing: 8
    property alias text: id_label.text
    readonly property alias textItem: id_label

    YImage {
        id: id_button_icon
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        sourceSize: Qt.size(26, 26)
    }

    YText {
        id: id_label
        anchors.left: id_button_icon.right
        anchors.leftMargin: spacing
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        font.family: qmlGlobal.fontFamily
        font.pixelSize: 16
        elide: Text.ElideRight
    }
}
