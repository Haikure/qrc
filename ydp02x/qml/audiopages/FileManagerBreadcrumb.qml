import QtQuick 2.12
import "../commons"

Flickable {
    id: trail
    height: 46
    contentWidth: crumbs.width
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    function revealCurrent() {
        contentX = Math.max(0, contentWidth - width);
    }
    onContentWidthChanged: Qt.callLater(revealCurrent)
    onWidthChanged: Qt.callLater(revealCurrent)

    Row {
        id: crumbs
        height: trail.height
        Repeater {
            model: fileManager.breadcrumbs
            delegate: Item {
                width: label.width + 18
                height: trail.height
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 7
                    anchors.bottomMargin: 7
                    radius: 6
                    color: "#303842"
                    visible: click.pressed
                }
                YTextBase {
                    id: label
                    anchors.centerIn: parent
                    text: (index > 0 ? "›  " : "") + modelData
                    textFormat: Text.PlainText
                    font.pixelSize: 15
                    color: index === fileManager.breadcrumbs.length - 1 ? "white" : "#91BDE8"
                }
                MouseArea {
                    id: click
                    anchors.fill: parent
                    enabled: index < fileManager.breadcrumbs.length - 1
                    onClicked: fileManager.navigateToAncestor(index)
                }
            }
        }
    }
}
