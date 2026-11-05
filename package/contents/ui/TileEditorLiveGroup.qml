import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs as QtDialogs
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
			folderField.text = appObj.liveFolder
			shuffleCheckBox.checked = appObj.liveShuffle
			recursiveCheckBox.checked = appObj.liveRecursive
			mediaAppOnlyCheckBox.checked = appObj.liveMediaAppOnly
			notificationPreviewCheckBox.checked = appObj.liveNotificationPreview
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
				{ text: i18n("Slideshow"), value: "slideshow" },
				{ text: i18n("Media player"), value: "media" },
				{ text: i18n("Notification count"), value: "notifications" },
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
			visible: appObj.liveType === "slideshow"
			PlasmaComponents3.TextField {
				id: folderField
				Layout.fillWidth: true
				placeholderText: i18n("Image folder (default: Pictures)")
				onEditingFinished: if (liveGroup.updateOnChange && text !== appObj.liveFolder) liveGroup.setField('liveFolder', text)
			}
			PlasmaComponents3.Button {
				icon.name: "folder-open"
				onClicked: {
					// Commit a typed-but-unconfirmed path so the dialog opens there.
					if (folderField.text !== appObj.liveFolder) {
						liveGroup.setField('liveFolder', folderField.text)
					}
					folderDialogLoader.active = true
				}

				Loader {
					id: folderDialogLoader
					active: false
					sourceComponent: QtDialogs.FolderDialog {
						title: i18n("Choose an image folder")
						modality: Qt.WindowModal
						// Start in the current folder (Pictures when none is set).
						currentFolder: appObj.liveFolderUrl
						onAccepted: {
							var path = selectedFolder.toString().replace(/^file:\/\//, '')
							folderField.text = decodeURIComponent(path)
							liveGroup.setField('liveFolder', folderField.text)
							folderDialogLoader.active = false
						}
						onRejected: folderDialogLoader.active = false
						Component.onCompleted: open()
					}
				}
			}
		}

		PlasmaComponents3.CheckBox {
			id: recursiveCheckBox
			visible: appObj.liveType === "slideshow"
			text: i18n("Include subfolders")
			onToggled: liveGroup.setField('liveRecursive', checked)
		}

		PlasmaComponents3.CheckBox {
			id: mediaAppOnlyCheckBox
			visible: appObj.liveType === "media"
			text: i18n("Only show this app's player")
			onToggled: liveGroup.setField('liveMediaAppOnly', checked)
		}

		PlasmaComponents3.CheckBox {
			id: notificationPreviewCheckBox
			visible: appObj.liveType === "notifications"
			text: i18n("Show the latest notifications' text (2×2 and larger)")
			onToggled: liveGroup.setField('liveNotificationPreview', checked)
		}

		PlasmaComponents3.CheckBox {
			id: shuffleCheckBox
			visible: appObj.liveType === "slideshow"
			text: i18n("Shuffle")
			onToggled: liveGroup.setField('liveShuffle', checked)
		}

		RowLayout {
			visible: appObj.liveType === "command" || appObj.liveType === "slideshow"
			PlasmaComponents3.Label {
				text: appObj.liveType === "slideshow" ? i18n("Change image every (seconds):") : i18n("Refresh every (seconds):")
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
