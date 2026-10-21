import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs as QtDialogs
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.iconthemes as KIconThemes

ColumnLayout {
	id: tileEditorView
	Layout.alignment: Qt.AlignTop

	AppObject {
		id: appObj
	}
	property alias tile: appObj.tile

	function resetView() {
		tile = null
	}

	function resetTile() {
		delete appObj.tile.showIcon
		delete appObj.tile.showLabel
		delete appObj.tile.label
		delete appObj.tile.icon
		delete appObj.tile.backgroundColor
		delete appObj.tile.backgroundImage
		appObj.tileChanged()
		tileGrid.tileModelChanged()
	}


	RowLayout {
		PlasmaExtras.Heading {
			Layout.fillWidth: true
			level: 2
			text: i18n("Edit Tile")
		}

		PlasmaComponents3.Button {
			text: i18n("Reset Tile")
			onClicked: resetTile()
		}

		PlasmaComponents3.Button {
			text: i18n("Close")
			onClicked: {
				tileEditorView.close()
			}
		}
	}


	PlasmaComponents3.ScrollView {
		id: scrollView
		Layout.fillHeight: true
		Layout.fillWidth: true

		ColumnLayout {
			id: scrollContent
			Layout.fillWidth: true
			width: scrollView.availableWidth

			TileEditorField {
				title: i18n("Url")
				key: 'url'
			}

			TileEditorField {
				id: labelField
				title: i18n("Label")
				placeholderText: appObj.appLabel
				key: 'label'
				checkedKey: 'showLabel'
			}

			TileEditorField {
				id: iconField
				title: i18n("Icon")
				key: 'icon'
				checkedKey: 'showIcon'
				checkedDefault: appObj.defaultShowIcon

				PlasmaComponents3.Button {
					icon.name: "document-open"
					onClicked: iconDialog.open()
				}
			}

			TileEditorFileField {
				id: backgroundImageField
				title: i18n("Background Image")
				key: 'backgroundImage'
				onTextChanged: {
					if (text) {
						labelField.checked = false
						iconField.checked = false
					}
				}
				onDialogOpen: function(dialog) {
					dialog.title = i18n("Choose an image")
					dialog.nameFilters.unshift(i18n("Image Files (*.png *.jpg *.jpeg *.bmp *.svg *.svgz)"))
				}
			}

			TileEditorPresetTiles {
				title: i18n("Preset Tiles")
			}

			TileEditorColorGroup {
				title: i18n("Background Color")
				placeholderText: config.defaultTileColor
				key: 'backgroundColor'
			}

			TileEditorRectField {
				title: i18n("Position / Size")
			}

			Item { // Consume the extra space below
				Layout.fillHeight: true
			}
		}
	}

	// Moved to top level — nesting inside a Button crashes on Plasma 6.8
	KIconThemes.IconDialog {
		id: iconDialog
		onIconNameChanged: iconField.text = iconName
	}

	function show() {
		if (stackView.currentItem != tileEditorView) {
			stackView.replace(tileEditorView)
		}
	}

	function open(tileIndex) {
		resetView()
		if (typeof tileIndex !== "number" || tileIndex < 0 || tileIndex >= tileGrid.tileModel.length) {
			return
		}
		tileEditorView.tile = tileGrid.tileModel[tileIndex]
		show()
	}

	function close() {
		searchView.showDefaultView()
	}


	Connections {
		target: stackView

		function onCurrentItemChanged() {
			if (stackView.currentItem != tileEditorView) {
				tileEditorView.resetView()
			}
		}
	}


	Connections {
		target: config.tileModel

		function onLoaded() {
			tileEditorView.close()
		}
	}

}
