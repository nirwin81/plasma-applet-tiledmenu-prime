import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

import ".." as TiledMenu
import "../lib/LiveTileSecurity.js" as LiveTileSecurity

ColumnLayout {
	id: page

	ScrollView {
		Layout.fillWidth: true
		Layout.fillHeight: true
		// Not the height of the text, or a long layout would stretch the page
		// instead of scrolling in here.
		Layout.preferredHeight: Kirigami.Units.gridUnit * 10
		// The text wraps, so only the vertical scrollbar is ever needed.
		ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

		TextAreaBase64JsonString {
			id: exportData

			TiledMenu.Base64JsonString {
				id: configTileModel
				configKey: 'tileModel'
				writing: exportData.base64JsonString.writing
				defaultValue: []
			}

			property var ignoredKeys: [
				'tileScale',
				'searchResultsReversed',
				'searchResultsCustomSort',
			]
		
			defaultValue: {
				var data = {}
				var configKeyList = plasmoid.configuration.keys()
				for (var i = 0; i < configKeyList.length; i++) {
					var configKey = configKeyList[i]
					var configValue = plasmoid.configuration[configKey]
					if (typeof configValue === "undefined") {
						continue
					}
					if (ignoredKeys.indexOf(configKey) >= 0) {
						continue
					}
					// Filter KF5 5.78 default keys https://invent.kde.org/frameworks/kdeclarative/-/merge_requests/38
					if (configKey.endsWith('Default')) {
						var key2 = configKey.substr(0, configKey.length - 'Default'.length)
						if (typeof plasmoid.configuration[key2] !== 'undefined') {
							continue
						}
					}
					if (configKey == 'tileModel') {
						data.tileModel = configTileModel.value
					} else {
						data[configKey] = configValue
					}
				}
				return data
			}

			// Imported layout waiting on the live-command warning dialog.
			property var pendingValue: null

			function serialize() {
				var newValue = parseText(textArea.text)
				// Nothing changed (e.g. the text was just reloaded from config).
				if (JSON.stringify(newValue) === JSON.stringify(defaultValue)) {
					return
				}
				if (!LiveTileSecurity.isValidTileModel(newValue.tileModel)) {
					invalidLayoutDialog.open()
					return
				}
				var report = LiveTileSecurity.analyze(newValue.tileModel, configTileModel.value)
				if (LiveTileSecurity.needsReview(report)) {
					// Hold everything (not just tiles) until the user decides.
					pendingValue = newValue
					commandWarningDialog.report = report
					commandWarningDialog.open()
					return
				}
				applyImport(newValue)
			}

			function resolvePending(choice) {
				var newValue = pendingValue
				pendingValue = null
				if (!newValue) {
					return
				}
				if (choice === "cancel") {
					// Don't save anything; show the layout that's actually in use.
					setValue(defaultValue)
					return
				}
				// Blocked commands are stripped no matter which option was chosen.
				LiveTileSecurity.sanitize(newValue.tileModel, configTileModel.value, choice === "remove")
				applyImport(newValue)
				setValue(defaultValue)
			}

			function applyImport(newValue) {
				var configKeyList = plasmoid.configuration.keys()
				for (var i = 0; i < configKeyList.length; i++) {
					var configKey = configKeyList[i]
					var propValue = newValue[configKey]
					if (typeof propValue === "undefined") {
						continue
					}
					if (ignoredKeys.indexOf(configKey) >= 0) {
						continue
					}
					if (configKey == 'tileModel') {
						configTileModel.set(propValue)
						// set() suppresses its own reload; refresh so later imports
						// compare against (and trust) the layout just saved.
						configTileModel.load()
					} else {
						if (plasmoid.configuration[configKey] != propValue) {
							plasmoid.configuration[configKey] = propValue
						}
					}
				}
			}
		}
	}


	Kirigami.PromptDialog {
		id: invalidLayoutDialog
		title: i18n("This layout can't be imported")
		subtitle: i18n("Its \"tileModel\" value isn't a list of tiles, so its live tile commands can't be checked. Nothing was saved.")
		standardButtons: Kirigami.Dialog.Ok
		// Show the layout that's actually in use.
		onClosed: exportData.setValue(exportData.defaultValue)
	}

	Kirigami.Dialog {
		id: commandWarningDialog
		property var report: ({ blocked: [], caution: [], unknown: [] })
		title: i18n("This layout runs shell commands")
		standardButtons: Kirigami.Dialog.NoButton
		closePolicy: Popup.NoAutoClose
		showCloseButton: false
		preferredWidth: Kirigami.Units.gridUnit * 28
		padding: Kirigami.Units.largeSpacing

		customFooterActions: [
			// Safest choice first.
			Kirigami.Action {
				text: i18n("Remove commands")
				icon.name: "edit-delete-remove"
				onTriggered: {
					commandWarningDialog.close()
					exportData.resolvePending("remove")
				}
			},
			Kirigami.Action {
				text: i18n("Cancel")
				icon.name: "dialog-cancel"
				onTriggered: {
					commandWarningDialog.close()
					exportData.resolvePending("cancel")
				}
			},
			Kirigami.Action {
				text: i18n("Accept and proceed")
				icon.name: "dialog-warning"
				onTriggered: {
					commandWarningDialog.close()
					exportData.resolvePending("accept")
				}
			}
		]

		ColumnLayout {
			spacing: Kirigami.Units.largeSpacing

			Label {
				Layout.fillWidth: true
				wrapMode: Text.Wrap
				text: i18n("The imported layout contains live tiles that run shell commands every time the menu is open. A command can do anything your user account can do, including deleting files or sending your data elsewhere. Only accept commands you understand and trust.")
			}

			Label {
				visible: commandWarningDialog.report.unknown.length > 0
				font.bold: true
				text: i18n("New commands:")
			}
			Repeater {
				model: commandWarningDialog.report.unknown
				delegate: Label {
					required property string modelData
					Layout.fillWidth: true
					text: modelData
					font.family: "monospace"
					wrapMode: Text.WrapAnywhere
				}
			}

			Label {
				visible: commandWarningDialog.report.caution.length > 0
				font.bold: true
				text: i18n("New commands that write files or run inline scripts:")
			}
			Repeater {
				model: commandWarningDialog.report.caution
				delegate: Label {
					required property string modelData
					Layout.fillWidth: true
					text: modelData
					font.family: "monospace"
					color: Kirigami.Theme.neutralTextColor
					wrapMode: Text.WrapAnywhere
				}
			}

			Label {
				visible: commandWarningDialog.report.blocked.length > 0
				font.bold: true
				text: i18n("Dangerous commands (these are always removed):")
			}
			Repeater {
				model: commandWarningDialog.report.blocked
				delegate: Label {
					required property string modelData
					Layout.fillWidth: true
					text: modelData
					font.family: "monospace"
					font.strikeout: true
					color: Kirigami.Theme.negativeTextColor
					wrapMode: Text.WrapAnywhere
				}
			}
		}
	}
}
