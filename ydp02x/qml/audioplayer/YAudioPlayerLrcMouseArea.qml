import QtQuick 2.12
import "../commons"

// Empty/hidden-lyrics state only. Keep its hit area inside the owning item.
YMouseArea {
    anchors.fill: parent
    enabled: !id_player_state_mask_hide.running
    property real pressX: 0
    property real pressY: 0
    property bool moved: false
    onPressed: {
        pressX = mouse.x
        pressY = mouse.y
        moved = false
    }
    onPositionChanged: {
        if (pressed && (Math.abs(mouse.x - pressX) > 8 || Math.abs(mouse.y - pressY) > 8))
            moved = true
    }
    onCanceled: moved = true
    onClicked: {
        if (!moved) id_player_state_mask_show.show()
    }
}
