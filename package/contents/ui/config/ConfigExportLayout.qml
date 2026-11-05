import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs as QtDialogs
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

import ".." as TiledMenu
import "../lib" as Lib
import "../lib/LiveTileSecurity.js" as LiveTileSecurity

ColumnLayout {
	id: page

	// A wrong file is easy to pick with no filetype filter. Reading stops here so
	// that a huge one can't fill memory; the cut-off text then fails to parse.
	readonly property int maxLayoutFileBytes: 10 * 1024 * 1024
	// One shell command can't be longer than 128 KiB, and a character takes at
	// most 4 bytes once quoted, so longer layouts are written in several commands.
	readonly property int writeChunkLength: 20000

	Lib.XdgUserDir {
		id: xdgUserDir
	}

	// QML can't write local files, or read them without an environment variable
	// set, so file access goes through the shell.
	P5Support.DataSource {
		id: fileShell
		engine: "executable"
		connectedSources: []
		property var callbacks: ({})

		function run(command, callback) {
			callbacks[command] = callback
			connectSource(command)
		}

		onNewData: function(sourceName, data) {
			var callback = callbacks[sourceName]
			delete callbacks[sourceName]
			disconnectSource(sourceName)
			if (callback) {
				callback(data)
			}
		}
	}

	function shellQuote(text) {
		return "'" + text.replace(/'/g, "'\\''") + "'"
	}

	// Empty for anything that isn't a local file.
	function localPath(fileUrl) {
		var url = fileUrl.toString()
		return url.startsWith("file://") ? decodeURIComponent(url.substring("file://".length)) : ""
	}

	function showFileError(title, message) {
		fileErrorDialog.title = title
		fileErrorDialog.subtitle = message
		fileErrorDialog.open()
	}

	function saveLayoutFile(fileUrl) {
		var path = localPath(fileUrl)
		if (!path) {
			showFileError(i18n("The layout couldn't be saved"), i18n("Layouts can only be saved to local files."))
			return
		}
		// The layout in use, not the text area, which could hold a half-typed edit.
		writeLayoutChunk(path, exportData.parseValue(exportData.defaultValue) + "\n", 0)
	}

	function writeLayoutChunk(path, text, start) {
		var end = Math.min(start + writeChunkLength, text.length)
		// Don't split a surrogate pair across two commands.
		var lastChar = text.charCodeAt(end - 1)
		if (end < text.length && lastChar >= 0xD800 && lastChar <= 0xDBFF) {
			end--
		}
		var redirect = start === 0 ? " > " : " >> "
		var command = "printf %s " + shellQuote(text.substring(start, end)) + redirect + shellQuote(path)
		fileShell.run(command, function(data) {
			if (data["exit code"] !== 0) {
				showFileError(i18n("The layout couldn't be saved"), (data["stderr"] || "").trim() || path)
			} else if (end < text.length) {
				writeLayoutChunk(path, text, end)
			}
		})
	}

	function importLayoutFile(fileUrl) {
		var path = localPath(fileUrl)
		if (!path) {
			showFileError(i18n("This file can't be imported"), i18n("Layouts can only be imported from local files."))
			return
		}
		var command = "head -c " + maxLayoutFileBytes + " -- " + shellQuote(path)
		fileShell.run(command, function(data) {
			if (data["exit code"] !== 0) {
				showFileError(i18n("This file can't be imported"), (data["stderr"] || "").trim() || path)
			} else {
				importLayoutText(data["stdout"] || "", path)
			}
		})
	}

	function importLayoutText(text, path) {
		var newValue = null
		try {
			newValue = JSON.parse(text)
		} catch (e) {
			// Handled below, the same as any other JSON that isn't a layout.
		}
		if (!newValue || typeof newValue !== "object" || Array.isArray(newValue)) {
			showFileError(i18n("This file can't be imported"), i18n("%1 doesn't contain a layout. Nothing was saved.", path))
			return
		}
		// Changing the text sends the layout through exportData.serialize(), which
		// runs the same checks as a layout pasted into the text area.
		exportData.setValue(newValue)
	}

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

	RowLayout {
		Button {
			text: i18n("Save Layout As...")
			icon.name: "document-save-as"
			onClicked: fileDialogLoader.openDialog(true)
		}
		Button {
			text: i18n("Import Layout")
			icon.name: "document-import"
			onClicked: fileDialogLoader.openDialog(false)
		}
	}

	// Creates a new dialog each time, so that it always starts in the home directory.
	Loader {
		id: fileDialogLoader
		visible: false // Takes no space in the layout.
		active: false
		property bool saving: false

		function openDialog(forSaving) {
			saving = forSaving
			active = true
		}

		sourceComponent: QtDialogs.FileDialog {
			visible: false
			modality: Qt.WindowModal
			title: fileDialogLoader.saving ? i18n("Save Layout As") : i18n("Import Layout")
			fileMode: fileDialogLoader.saving ? QtDialogs.FileDialog.SaveFile : QtDialogs.FileDialog.OpenFile
			currentFolder: xdgUserDir.home
			onAccepted: {
				var file = selectedFile
				var saving = fileDialogLoader.saving
				fileDialogLoader.active = false
				if (saving) {
					page.saveLayoutFile(file)
				} else {
					page.importLayoutFile(file)
				}
			}
			onRejected: fileDialogLoader.active = false
			Component.onCompleted: visible = true
		}
	}

	Kirigami.PromptDialog {
		id: fileErrorDialog
		standardButtons: Kirigami.Dialog.Ok
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
