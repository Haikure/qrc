import "../commons"
import "../i18n"
import QtQuick 2.12
import com.github.penuniverse 1.0

Item {
    property color portraitBorderColor: YColors.black
    readonly property bool needReloadUserPortrait: (wifiManager.internetConnect && loginManager.isLogin && !qmlGlobal.fileExists(loginManager.iconPath))

    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: 10
    onNeedReloadUserPortraitChanged: {
        if (needReloadUserPortrait)
            id_reload_user_portrait_timer.restart();
    }
    Component.onCompleted: {
        if (needReloadUserPortrait)
            id_reload_user_portrait_timer.restart();
    }

    YUserPortrait {
        id: id_portrait_icon

        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 30
        sourceSize: Qt.size(30, 30)
        defaultIconSource: "image://icons/portrait.png"

        // 将颜色设为透明以去除边框
        borderColor: "transparent"

        YMouseArea {
            anchors.fill: parent
            anchors.margins: -6
            onClicked: {
                if (loginManager.isLogin)
                    logManager.sendHttpLog("action=home_account_click");
                else
                    logManager.sendHttpLog("action=home_login_click");
                qmlGlobal.showLoginPage();
            }
            objectName: "YMainTitleBar.qml_id_login_button"
        }
    }

    Row {
        id: id_icon_container

        spacing: 6
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: id_battary_value.left
        anchors.rightMargin: 18
        height: 18

        YConnectionIndicators {}

        YText {
            id: id_time

            //anchors.centerIn: parent
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 16
            text: timeManager.currentTime
            width: paintedWidth
            height: paintedHeight
        }
    }

    YText {
        id: id_battary_value

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: id_battary_icon_border.left
        anchors.rightMargin: 12
        font.pixelSize: 16
        text: ("%1%").arg(battaryPercentage)
        width: paintedWidth
        height: paintedHeight
    }

    YBatteryIndicator {
        id: id_battary_icon_border

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: battaryChanging ? id_charging_icon.left : parent.right
        percentage: battaryPercentage
        charging: battaryChanging
    }

    YImage {
        id: id_charging_icon

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        sourceSize: Qt.size(14, 14)
        imageName: "ic_battery_flash"
        visible: battaryChanging
    }

    YTimer {
        id: id_reload_user_portrait_timer

        interval: 3000
        onTriggered: {
            if (needReloadUserPortrait)
                loginManager.queryUserInfo();
            else
                console.warn("YMainTitleBar.qml===no need reload");
        }
        objectName: "YMainTitleBar.qml_id_reload_user_portrait_timer"
    }

}
