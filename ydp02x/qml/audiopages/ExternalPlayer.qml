import "../commons"
import "../components"
import "../i18n"
import QtQuick 2.12
import com.github.penuniverse 1.0
import com.youdao.pen 1.0

YBackButtonAudioPage {
    id: id_external_player
    pageIndex: PageIndex.ExternalPlayer

    // onCurrentPopIdChanged: {
    //     videoPlayer.onStatusChanged('stopped');
    // }

    YVerticalTitleBar {
        id: id_title_bar
        onCallBack: backButtonClicked()
    }

}
