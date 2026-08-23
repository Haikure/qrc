import QtQuick 2.12
import com.youdao.pen 1.0

import BaseQml 1.0
import "../common"
import "../i18n"

// 网络与代理：应用级代理（Socks5/HTTP）+ 本机网络信息
YSettingItemPage {
    id: id_network
    objectName: "YPage===PenModsNetwork.qml"

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 90
        anchors.rightMargin: 16
        contentHeight: id_title_container.height + id_column.height

        YSettingItemTitle {
            id: id_title_container
            title: "网络与代理"
        }

        Column {
            id: id_column
            anchors.top: id_title_container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            PenModsSwitchRow {
                title: "启用代理"
                checked: networkSettings.proxyEnabled
                onRowToggled: networkSettings.proxyEnabled = checked
            }
            PenModsSettingRow {
                title: "代理类型"
                value: networkSettings.proxyType === networkSettings.Socks5 ? "Socks5" : "HTTP"
                onClicked: {
                    networkSettings.proxyType = (networkSettings.proxyType === networkSettings.Socks5)
                                                ? networkSettings.HTTP : networkSettings.Socks5
                }
            }
            PenModsSettingRow {
                title: "代理地址"
                value: networkSettings.proxyHostName
                onClicked: {
                    // 简化：循环改地址不便输入，这里提示
                    baseSignals.showToast("代理地址/端口请修改配置文件", YColors.yellow)
                }
            }
            PenModsSettingRow { title: "代理端口"; value: "" + networkSettings.proxyPort }
            PenModsSettingRow { title: "本机 IP"; value: networkSettings.localIpAddress }
            PenModsSettingRow { title: "网关"; value: networkSettings.netGateway }
            PenModsSettingRow { title: "DNS"; value: networkSettings.dns }

            YSpacingForColumn {
                implicitHeight: 4
            }
        }
    }
}
