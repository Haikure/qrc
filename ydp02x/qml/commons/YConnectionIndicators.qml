import QtQuick 2.12

Row {
    spacing: 2
    height: 18

    YImage {
        sourceSize: Qt.size(18, 18)
        imageName: "settings/bluetooth-headset"
        visible: blueToothManager.link || systemBase.digHeadset
    }

    YImage {
        sourceSize: Qt.size(18, 18)
        imageName: "settings/bluetooth"
        visible: blueToothManager.onoff
    }

    YImage {
        sourceSize: Qt.size(18, 18)
        visible: wifiManager.onoff && wifiManager.link
        imageName: wifiManager.signalStrength > 70 ? "settings/wifi"
                 : (wifiManager.signalStrength > 30 ? "settings/wifi-medium" : "settings/wifi-low")
    }
}
