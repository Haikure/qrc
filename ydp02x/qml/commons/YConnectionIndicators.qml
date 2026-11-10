import QtQuick 2.12

Row {
    id: indicators
    property bool bluetoothHeadset: blueToothManager.link
    property var headsetBattery: bluetoothBattery.percentages[String(blueToothManager.addr).toUpperCase()]
    spacing: 2
    height: 18

    YImage {
        sourceSize: Qt.size(18, 18)
        imageName: "settings/bluetooth-headset"
        visible: blueToothManager.link || systemBase.digHeadset
    }

    Item {
        objectName: "BluetoothHeadsetBattery"
        width: 9
        height: 18
        visible: indicators.bluetoothHeadset

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 2
            width: 3
            height: 1
            radius: 0.5
            color: YColors.white
            opacity: 0.7
        }

        Rectangle {
            objectName: "BluetoothHeadsetBatteryBar"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 4
            width: 7
            height: 11
            radius: 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.7)
            antialiasing: true

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 2
                width: 3
                height: indicators.headsetBattery === undefined ? 0
                        : Math.round(7 * Math.max(0, Math.min(100, indicators.headsetBattery)) / 100)
                radius: 1
                color: indicators.headsetBattery <= 20 ? YColors.red : YColors.white
                antialiasing: true
            }
        }

        YText {
            objectName: "BluetoothHeadsetBatteryUnknown"
            anchors.centerIn: parent
            text: "?"
            color: YColors.white
            opacity: 0.7
            font.pixelSize: 8
            visible: indicators.headsetBattery === undefined
        }
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
