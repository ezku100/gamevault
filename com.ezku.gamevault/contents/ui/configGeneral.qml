import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
import org.kde.kirigami as Kirigami

Item {
    id: page
    implicitWidth: 560
    implicitHeight: 600

    property var cfg_excludePatterns: []
    property bool cfg_followAccent: true
    property string cfg_bgColor: "#12131c"
    property string cfg_accentColor: "#ffffff"
    property string cfg_textColor: "#e6e6eb"
    property double cfg_bgOpacity: 0.93
    property int cfg_cornerRadius: 14
    property bool cfg_mouseEnabled: false

    function addPattern() {
        var text = newPatternField.text.trim()
        if (text.length === 0) return
        cfg_excludePatterns = cfg_excludePatterns.concat([text])
        newPatternField.text = ""
    }

    function removePattern(index) {
        var updated = cfg_excludePatterns.slice()
        updated.splice(index, 1)
        cfg_excludePatterns = updated
    }

    QQC2.ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        Kirigami.FormLayout {
            id: form
            width: scroll.availableWidth

        QQC2.Label {
            text: "Excluded games"
            font.bold: true
        }

        QQC2.Label {
            Kirigami.FormData.label: "Patterns:"
            text: "Games whose name contains any of these (case-insensitive) will be hidden from the drawer."
            wrapMode: Text.WordWrap
            bottomPadding: 15
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: page.cfg_excludePatterns

                delegate: RowLayout {
                    Layout.fillWidth: true

                    QQC2.Label {
                        text: modelData
                        Layout.fillWidth: true
                    }

                    QQC2.ToolButton {
                        icon.name: "edit-delete"
                        onClicked: page.removePattern(index)
                    }
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Add pattern:"

            QQC2.TextField {
                id: newPatternField
                placeholderText: "e.g. Proton"
                Layout.fillWidth: true
                onAccepted: page.addPattern()
            }

            QQC2.Button {
                text: "Add"
                onClicked: page.addPattern()
            }
        }

        QQC2.Label {
            text: "Theme"
            font.bold: true
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: "Accent:"
            text: "Follow system accent (KDE)"
            checked: page.cfg_followAccent
            onCheckedChanged: page.cfg_followAccent = checked
        }

        QQC2.Label {
            text: "Manual colors apply only when the above is off."
            opacity: 0.6
        }

        RowLayout {
            Kirigami.FormData.label: "Background:"
            enabled: !page.cfg_followAccent

            Rectangle {
                width: 28
                height: 28
                radius: 6
                color: page.cfg_bgColor
                border.color: Kirigami.Theme.textColor
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    onClicked: bgDialog.open()
                }
            }

            QQC2.TextField {
                text: page.cfg_bgColor
                Layout.fillWidth: true
                onTextChanged: page.cfg_bgColor = text
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Accent:"
            enabled: !page.cfg_followAccent

            Rectangle {
                width: 28
                height: 28
                radius: 6
                color: page.cfg_accentColor
                border.color: Kirigami.Theme.textColor
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    onClicked: accentDialog.open()
                }
            }

            QQC2.TextField {
                text: page.cfg_accentColor
                Layout.fillWidth: true
                onTextChanged: page.cfg_accentColor = text
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Text:"
            enabled: !page.cfg_followAccent

            Rectangle {
                width: 28
                height: 28
                radius: 6
                color: page.cfg_textColor
                border.color: Kirigami.Theme.textColor
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    onClicked: textDialog.open()
                }
            }

            QQC2.TextField {
                text: page.cfg_textColor
                Layout.fillWidth: true
                onTextChanged: page.cfg_textColor = text
            }
        }

        Dialogs.ColorDialog {
            id: bgDialog
            selectedColor: page.cfg_bgColor
            onAccepted: page.cfg_bgColor = selectedColor.toString()
        }

        Dialogs.ColorDialog {
            id: accentDialog
            selectedColor: page.cfg_accentColor
            onAccepted: page.cfg_accentColor = selectedColor.toString()
        }

        Dialogs.ColorDialog {
            id: textDialog
            selectedColor: page.cfg_textColor
            onAccepted: page.cfg_textColor = selectedColor.toString()
        }

        QQC2.Label {
            text: "Look"
            font.bold: true
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: "Opacity:"
            from: 20
            to: 100
            value: Math.round(page.cfg_bgOpacity * 100)
            onValueChanged: page.cfg_bgOpacity = value / 100
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: "Corners:"
            from: 0
            to: 24
            value: page.cfg_cornerRadius
            onValueChanged: page.cfg_cornerRadius = value
        }

        QQC2.Label {
            text: "Input"
            font.bold: true
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: "Mouse:"
            text: "Enable hover, click and wheel"
            checked: page.cfg_mouseEnabled
            onCheckedChanged: page.cfg_mouseEnabled = checked
        }
        }
    }
}
