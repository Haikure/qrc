import "./commons"
import "./components"
import "./i18n"
import "./settingpages"
import QtQuick 2.12
import com.youdao.pen 1.0

YPage {
    id: id_setting_page
    pageIndex: YEnum.PageIndex.Setting

    property int currentShowIndex: -1

    // Array order controls the menu; settingIndex is only the legacy navigation key.
    // This registry describes navigation entries, not the values owned by individual pages.
    readonly property var settingRegistry: [
        { id: "network", settingIndex: YEnum.SettingIndex.Network, label: YTranslateText.network,
            group: qsTr("网络与连接"), icon: res.getDisk("settings/ic_network"),
            page: "settingpages/YSettingWifi", logAction: "network" },
        { id: "bluetooth", settingIndex: YEnum.SettingIndex.Bluetooth, label: YTranslateText.bluetooth,
            group: qsTr("网络与连接"), icon: res.getDisk("settings/ic_bluetooth"),
            page: "settingpages/YSettingBluetooth", logAction: "bluetooth" },
        { id: "screen", settingIndex: YEnum.SettingIndex.Brightness, label: qsTr("屏幕"),
            group: qsTr("显示与输入"), icon: res.get("setting/screen"),
            page: "settingpages/YSettingBrightness", logAction: "brightness", refreshVolumeAndLcd: true },
        { id: "volume", settingIndex: YEnum.SettingIndex.Volume, label: YTranslateText.volume,
            group: qsTr("显示与输入"), icon: res.getDisk("settings/ic_sounds"),
            page: "settingpages/YSettingVolume", logAction: "sound", refreshVolumeAndLcd: true },
        { id: "handedness", settingIndex: YEnum.SettingIndex.Handedness, label: YTranslateText.handedness,
            group: qsTr("显示与输入"), icon: res.getDisk("settings/ic_handedness"),
            page: "settingpages/YSettingHandedness", logAction: "direction" },
        { id: "keyboard", settingIndex: 209, label: qsTr("键盘设置"),
            group: qsTr("显示与输入"), icon: res.get("setting/advanced"),
            page: "settingpages/KeyboardSettingPage", hideWhenAntiEmbs: true },
        { id: "wallpaper", settingIndex: 208, label: qsTr("壁纸"),
            group: qsTr("显示与输入"), icon: res.get("setting/background"),
            page: "settingpages/WallpaperSettingPage", hideWhenAntiEmbs: true },
        // Keep the LED and scan-query controls available in antiEmbs mode, as before.
        { id: "torch", settingIndex: 207, label: qsTr("笔头 LED"),
            group: qsTr("显示与输入"), icon: res.get("setting/torch"), page: "settingpages/Torch" },
        { id: "translate", settingIndex: YEnum.SettingIndex.Translate, label: YTranslateText.translate,
            group: qsTr("语言与学习"), icon: res.getDisk("settings/ic_translate"),
            page: "settingpages/YSettingTranslate", logAction: "translate",
            available: qmlGlobal.checkFeature(YEnum.FEATURE_LANG_JPN)
                || qmlGlobal.checkFeature(YEnum.FEATURE_LANG_KOR)
                || qmlGlobal.checkFeature(YEnum.FEATURE_LANG_ES) },
        { id: "dictionary", settingIndex: YEnum.SettingIndex.Dict, label: YTranslateText.dictionary,
            group: qsTr("语言与学习"), icon: res.getDisk("settings/ic_dict"),
            page: "settingpages/YSettingDict", logAction: "dict" },
        { id: "pronunciation", settingIndex: YEnum.SettingIndex.Pronunc, label: YTranslateText.pronunc,
            group: qsTr("语言与学习"), icon: res.getDisk("settings/ic_pronunc"),
            page: "settingpages/YSettingPronunc", logAction: "pronounce" },
        { id: "language", settingIndex: YEnum.SettingIndex.Language, label: YTranslateText.deviceLanguage,
            group: qsTr("语言与学习"), icon: res.getDisk("settings/ic_language"),
            page: "settingpages/YSettingLanguage", logAction: "language",
            available: !qmlGlobal.checkFeature(YEnum.FEATURE_SERIAL_D2) },
        { id: "query", settingIndex: 205, label: qsTr("扫描查询"),
            group: qsTr("语言与学习"), icon: res.get("setting/scan"), page: "settingpages/QuerySettingPage" },
        { id: "battery", settingIndex: 201, label: qsTr("电池信息"),
            group: qsTr("系统"), icon: res.get("setting/battery"),
            page: "settingpages/BatteryInfoPage", hideWhenAntiEmbs: true },
        { id: "security", settingIndex: 206, label: qsTr("安全"),
            group: qsTr("系统"), icon: res.get("setting/lock"),
            page: "settingpages/LockSettingPage", needsPassword: true, hideWhenAntiEmbs: true },
        { id: "tweaks", settingIndex: 203, label: qsTr("系统微调"),
            group: qsTr("系统"), icon: res.get("setting/sys_tweak"),
            page: "settingpages/SystemTweakSettingPage", hideWhenAntiEmbs: true },
        { id: "update", settingIndex: YEnum.SettingIndex.Update, label: YTranslateText.update,
            group: qsTr("系统"), icon: res.getDisk("settings/ic_update"),
            page: "settingpages/YSettingUpdate", logAction: "update" },
        { id: "about", settingIndex: YEnum.SettingIndex.About, label: YTranslateText.about,
            group: qsTr("系统"), icon: res.getDisk("settings/ic_about"),
            page: "settingpages/YSettingAbout", logAction: "about" },
        // Retain the host's direct navigation target without adding a menu entry.
        { id: "multiline", settingIndex: YEnum.SettingIndex.MultiLines, label: YTranslateText.multi,
            group: qsTr("语言与学习"), icon: "", showInMenu: false,
            page: "settingpages/YSettingMultiLines", logAction: "multiline" }
    ]

    function settingAvailable(entry) {
        return entry.available !== false && !(antiEmbs.active && entry.hideWhenAntiEmbs);
    }

    function showSettingPage(settingPage, needPwd, scene, popThisPage) {
        if (needPwd && locker.enabled && !(scene && !locker.getScene(scene))) {
            requestKeyboard(settingPage, popThisPage);
            return null;
        }

        var page = navigate(settingPage, {}, {
            "animation": true,
            "cache": false
        });
        if (!page)
            return null;

        if (popThisPage && page.hasOwnProperty("backButtonClicked")) {
            page.backButtonClicked.connect(function() {
                const navigator = id_setting_page.navigator;
                if (!navigator)
                    return;
                navigator.afterTransition(function() {
                    if (navigator.currentItem === id_setting_page)
                        navigator.pop();
                });
            });
        }
        if (settingPage === "settingpages/YSettingUpdate"
                && wifiManager.internetConnect
                && typeof page.checkUpdate === "function") {
            page.checkUpdate();
        }
        return page;
    }

    function requestKeyboard(page, popThisPage) {
        let component = qmlCreateComponent("YInputPage");
        if (Component.Ready === component.status) {
            var incubator = component.incubateObject(id_page_pop_helper.containerItem);
            if (incubator.status !== Component.Ready)
                incubator.onStatusChanged = function(status) {
                if (status === Component.Ready)
                    id_page_pop_helper.inputPageCreated(incubator.object, page, popThisPage);

            };
            else
                id_page_pop_helper.inputPageCreated(incubator.object, page, popThisPage);
        }
    }

    function settingItemClicked(index, popThisPage = false) {
        for (var i = 0; i < settingRegistry.length; ++i) {
            var entry = settingRegistry[i];
            if (entry.settingIndex !== index)
                continue;
            if (!settingAvailable(entry))
                return;
            currentShowIndex = index;
            if (entry.logAction)
                logManager.sendHttpLog("action=settings_" + entry.logAction + "_click");
            if (entry.refreshVolumeAndLcd)
                settingManager.updateVolumeAndLcd();
            showSettingPage(entry.page, entry.needsPassword === true, undefined, popThisPage);
            return;
        }
    }

    objectName: "YPage===YSettingPage.qml"
    Component.onDestruction: {
        console.log("YSettingPage.qml===Component.onDestruction===called");
    }
    Item {
        id: id_setting_views

        anchors.fill: parent

        ListView {
            id: id_setting_listview

            anchors.fill: parent
            anchors.leftMargin: 54
            anchors.rightMargin: 10
            clip: true
            section.property: "settingGroup"
            section.criteria: ViewSection.FullString
            section.delegate: YSettingItemTitle {
                width: id_setting_listview.width
                title: section
            }
            model: id_setting_model
            cacheBuffer: 1000

            delegate: YMouseArea {
                id: id_item_delegate

                width: id_setting_listview.width
                height: 58
                objectName: "YSettingPage.qml_setting_" + settingId
                onClicked: {
                    settingItemClicked(settingIndex);
                }

                Rectangle {
                    width: parent.width
                    height: parent.height - 8
                    color: YColors.grayNormal
                    opacity: parent.pressed ? 0.6 : 1
                    radius: 12

                    YImage {
                        id: id_icon

                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        source: settingIcon
                        sourceSize: Qt.size(24, 24)
                    }

                    YTextMedium {
                        id: id_label

                        anchors.left: id_icon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        text: settingLabel
                        elide: YText.ElideRight
                    }

                }

            }

            header: YSpacing {
                width: id_setting_listview.width
                implicitHeight: 12
            }

            footer: YSpacing {
                width: id_setting_listview.width
                implicitHeight: 12
            }

        }

    }

    YVerticalTitleBar {
        id: id_title_bar

        onCallBack: {
            backButtonClicked();
        }

        YButtonBase {
            id: id_portrait_icon_bg

            implicitWidth: 30
            implicitHeight: 30
            mouseAreaMargins: -10
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.bottom: parent.bottom
            opacity: id_title_bar.backButtonItem.pressed || !enabled ? 0.6 : 1
            color: YColors.grayNormal
            radius: height / 2
            onClicked: {
                if (loginManager.isLogin)
                    logManager.sendHttpLog("action=settings_account_click");
                else
                    logManager.sendHttpLog("action=settings_login_click");
                qmlGlobal.showLoginPage();
            }

            YUserPortrait {
                id: id_portrait_icon

                width: 30
                height: 30
                anchors.centerIn: parent
                sourceSize: Qt.size(30, 30)
                defaultIconSource: "image://icons/portrait.png"
                borderColor: YColors.black
            }

        }

    }

    YPagePopHelper {
        id: id_page_pop_helper

        function inputPageCreated(keyboardPage, page, popThisPage) {
            keyboardPage.backButtonClicked.connect(function() {
                qmlGlobal.inputPageShowing = false;
                keyboardPage.todoDestroy();
                keyboardPage = null;
            });
            keyboardPage.inputFinished.connect(function(content) {
                if (content === locker.password) {
                    showSettingPage(page, false, undefined, popThisPage);
                } else {
                    qmlGlobal.showToast("密码错误，请重试", YColors.yellow);
                    requestKeyboard(page, popThisPage);
                }
            });
            keyboardPage.placeHolderText = "请输入密码...";
            keyboardPage.show();
            qmlGlobal.inputPageShowing = true;
        }

        isShowing: qmlGlobal.inputPageShowing
        objectName: "from_YSettingPage.qml"
    }

    function refreshSettingModel() {
        if (!id_setting_model)
            return;
        id_setting_model.clear();
        for (var i = 0; i < settingRegistry.length; ++i) {
            var entry = settingRegistry[i];
            if (entry.showInMenu === false || !settingAvailable(entry))
                continue;
            id_setting_model.append({
                "settingIndex": entry.settingIndex,
                "settingIcon": entry.icon,
                "settingLabel": entry.label,
                "settingGroup": entry.group,
                "settingId": entry.id
            });
        }
    }

    onSettingRegistryChanged: refreshSettingModel()

    Connections {
        target: antiEmbs
        function onActiveChanged() {
            refreshSettingModel();
        }
    }

    ListModel {
        id: id_setting_model
        Component.onCompleted: refreshSettingModel()
    }

}
