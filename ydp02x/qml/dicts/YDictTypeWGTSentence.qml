import QtQuick 2.12

import "../commons"

YDictTypeBase {
    id: sentence
    readonly property bool usingAi: id_dict_page.pureTranslation && aiTranslation.enabled
                                   && aiTranslation.source === resultManager.currentQuery
                                   && aiTranslation.target === resultManager.dstLang
                                   && aiTranslation.text.length > 0
    pronunciationContent: usingAi ? aiTranslation.text : content
    Column {
        width: parent.width
        height: implicitHeight
        spacing: 5
        YText {
            width: parent.width
            height: visible ? contentHeight : 0
            visible: id_dict_page.pureTranslation && aiTranslation.enabled && text.length > 0
            text: aiTranslation.status
            textFormat: Text.PlainText
            font.pixelSize: 12
            color: YColors.grayText
            wrapMode: Text.Wrap
        }
        YTextMedium {
            id: id_dict_content
            width: parent.width
            wrapMode: YText.Wrap
            textFormat: Text.PlainText
            height: contentHeight
            lineHeightMode: Text.FixedHeight
            lineHeight: 26
            text: sentence.usingAi ? aiTranslation.text : content
            font.family: qmlGlobal.getFontFamilyNameByLangName(resultManager.dstLang)
        }
    }
}
