import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3

// Live tile settings: type selector plus the per-type fields.
TileEditorGroupBox {
	id: liveGroup
	title: i18n("Live Tile")
	Layout.fillWidth: true
	visible: appObj.isLauncher

	function setField(key, value) {
		if (!appObj.tile) {
			return
		}
		if (value === "" || value === null || typeof value === "undefined") {
			delete appObj.tile[key]
		} else {
			appObj.tile[key] = value
		}
		appObj.tileChanged()
		tileGrid.tileModelChanged()
	}

	property bool updateOnChange: false

	Connections {
		target: appObj

		function onTileChanged() {
			if (!appObj.tile) {
				return
			}
			liveGroup.updateOnChange = false
			typeComboBox.currentIndex = Math.max(0, typeComboBox.indexOfValue(appObj.liveType))
			cycleCheckBox.checked = appObj.liveCycle
			formatField.text = appObj.liveFormat
			commandField.text = appObj.liveCommand
			intervalSpinBox.value = appObj.liveInterval
			liveGroup.updateOnChange = true
		}
	}

	ColumnLayout {
		anchors.left: parent.left
		anchors.right: parent.right

		PlasmaComponents3.ComboBox {
			id: typeComboBox
			Layout.fillWidth: true
			textRole: "text"
			valueRole: "value"
			model: [
				{ text: i18n("None"), value: "" },
				{ text: i18n("Clock"), value: "clock" },
				{ text: i18n("Command output"), value: "command" },
			]
			onActivated: liveGroup.setField('liveType', currentValue)
		}

		PlasmaComponents3.CheckBox {
			id: cycleCheckBox
			visible: appObj.isLive
			text: i18n("Alternate with the normal tile face")
			onToggled: liveGroup.setField('liveCycle', checked)
		}

		PlasmaComponents3.TextField {
			id: formatField
			visible: appObj.liveType === "clock"
			Layout.fillWidth: true
			placeholderText: i18n("Time format, e.g. hh:mm:ss (default: locale)")
			onTextChanged: if (liveGroup.updateOnChange) liveGroup.setField('liveFormat', text)
		}

		PlasmaComponents3.TextField {
			id: commandField
			visible: appObj.liveType === "command"
			Layout.fillWidth: true
			placeholderText: i18n("Command, e.g. uptime -p")
			// Only commit on Enter / focus loss so we don't run a half-typed
			// command on every keystroke.
			onEditingFinished: if (liveGroup.updateOnChange && text !== appObj.liveCommand) liveGroup.setField('liveCommand', text)
		}

		RowLayout {
			visible: appObj.liveType === "command"
			PlasmaComponents3.Label {
				text: i18n("Refresh every (seconds):")
			}
			PlasmaComponents3.SpinBox {
				id: intervalSpinBox
				Layout.fillWidth: true
				from: 1
				to: 86400
				value: 60
				onValueModified: liveGroup.setField('liveInterval', value)
			}
		}
	}
}
