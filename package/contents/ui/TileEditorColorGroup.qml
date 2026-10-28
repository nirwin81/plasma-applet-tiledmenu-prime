import org.kde.plasma.components as PlasmaComponents3
import QtQuick
import QtQuick.Layouts

TileEditorGroupBox {
	id: tileEditorColorField
	title: "Label"
	implicitWidth: parent.implicitWidth
	Layout.fillWidth: true
	property alias placeholderText: colorField.placeholderText
	property alias isGroupEnabled: colorField.enabled
	property string key: ''

	PlasmaComponents3.TextField {
		id: colorField
		anchors.left: parent.left
		anchors.right: parent.right
		text: key && appObj.tile && appObj.tile[key] ? appObj.tile[key] : ''
		property bool updateOnChange: false
		onTextChanged: {
			if (key && updateOnChange) {
				if (text) {
					appObj.tile[key] = text
				} else {
					delete appObj.tile[key]
				}
				appObj.tileChanged()
				tileGrid.tileModelChanged()
			}
		}
	}

	Connections {
		target: appObj

		function onTileChanged() {
			if (key && tile) {
				colorField.updateOnChange = false
				colorField.text = appObj.tile[key] || ''
				colorField.updateOnChange = true
			}
		}
	}
}
