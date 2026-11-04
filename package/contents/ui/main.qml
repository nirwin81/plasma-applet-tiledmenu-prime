import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg

import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker
import org.kde.coreaddons as KCoreAddons
// import org.kde.kquickcontrolsaddons 2.0 as KQuickControlsAddons

import "lib"

PlasmoidItem {
	id: widget
	property bool fullscreenVisible: false

	function prepareMenu(popupItem) {
		popupItem.syncTiles()
		search.query = ""
		search.applyDefaultFilters()
		popupItem.searchView.searchField.forceActiveFocus()
		popupItem.searchView.showDefaultView()
		justOpenedTimer.start()
	}

	function openFullscreenMenu() {
		fullscreenVisible = true
		if (widget.Window.window && widget.Window.window.screen) {
			fullscreenWindow.screen = widget.Window.window.screen
		}
		fullscreenPopup.syncTiles() // Before showing, to avoid a flash of stale tiles.
		fullscreenWindow.showMaximized()
		Qt.callLater(function() { prepareMenu(fullscreenPopup) })
	}

	function closeMenu() {
		expanded = false
		fullscreenVisible = false
		fullscreenWindow.hide()
	}

	function toggleMenu() {
		if (plasmoid.configuration.fullscreen) {
			if (fullscreenVisible) {
				closeMenu()
			} else {
				openFullscreenMenu()
			}
		} else {
			expanded = !expanded
		}
	}

	Logger {
		id: logger
		name: 'tiledmenu'
		// showDebug: true
	}

	// Shared by every notification live tile. Lives here because tiles get
	// rebuilt; see live/NotificationHistory.qml. Failing to load (e.g. the
	// library's API changed) only disables the notification count.
	Loader {
		id: notificationHistoryLoader
		source: "live/NotificationHistory.qml"
		onStatusChanged: {
			if (status === Loader.Error) {
				console.warn("[tiledmenu] Failed to load the notification history. Notification counts are disabled.")
			}
		}
	}

	SearchModel {
		id: search
		Component.onCompleted: {
			search.applyDefaultFilters()
		}
	}

	property alias rootModel: appsModel.rootModel
	AppsModel {
		id: appsModel
	}

	Item {
		// https://invent.kde.org/frameworks/kcoreaddons/-/blob/master/src/qml/kuserproxy.h
		// https://invent.kde.org/frameworks/kcoreaddons/-/blob/master/src/qml/kuserproxy.cpp
		KCoreAddons.KUser {
			id: kuser
			// faceIconUrl is an empty QUrl 'object' when ~/.face.icon doesn't exist.
			// Cast it to string first before checking if it's empty by casting to bool.
			readonly property bool hasFaceIcon: (''+faceIconUrl)
		}

		Kicker.DragHelper {
			id: dragHelper

			dragIconSize: Kirigami.Units.iconSizes.medium

			// Used when we only have a string and don't have a QIcon.
			// DragHelper.startDrag(...) requires a QIcon. See Issue #75.
			// property var defaultIconItem: KQuickControlsAddons.QIconItem {
			// 	id: defaultIconItem
			// }
			// property alias defaultIcon: defaultIconItem.icon
		}

		Kicker.ProcessRunner {
			id: processRunner
			// .runMenuEditor() to run kmenuedit
		}
	}

	AppletConfig {
		id: config
	}

	function logListModel(label, listModel) {
		console.log(label + '.count', listModel.count);
		// logObj(label, listModel);
		for (var i = 0; i < listModel.count; i++) {
			var item = listModel.modelForRow(i);
			var itemLabel = label + '[' + i + ']';
			console.log(itemLabel, item);
			logObj(itemLabel, item);
			if (('' + item).indexOf('Model') >= 0) {
				logListModel(itemLabel, item);
			}
		}
	}
	function logObj(label, obj) {
		// if (obj && typeof obj === 'object') {
		//  console.log(label, Object.keys(obj))
		// }
		
		for (var key in obj) {
			var val = obj[key];
			if (typeof val !== 'function') {
				var itemLabel = label + '.' + key;
				console.log(itemLabel, typeof val, val);
				if (('' + val).indexOf('Model') >= 0) {
					logListModel(itemLabel, val);
				}
			}
		}
	}

	toolTipMainText: ""
	toolTipSubText: ""

	compactRepresentation: LauncherIcon {
		id: panelItem
		iconSource: plasmoid.configuration.icon || "start-here-kde-symbolic"
	}

	hideOnWindowDeactivate: !widget.userConfiguring
	activationTogglesExpanded: true
	onExpandedChanged: function(expanded) {
		if (expanded) {
			if (plasmoid.configuration.fullscreen) {
				widget.expanded = false
				Qt.callLater(openFullscreenMenu)
				return
			}
			prepareMenu(fullRepresentationItem)

			// Debug TileEditorView
			// fullRepresentationItem.tileGrid.addDefaultTiles()
			// var testTile = fullRepresentationItem.tileGrid.getTileAt(0, 1)
			// fullRepresentationItem.tileGrid.editTile(testTile)

		}
	}

	Connections {
		target: plasmoid.configuration
		function onFullscreenChanged() {
			widget.closeMenu()
		}
	}
	Timer {
		id: justOpenedTimer
		repeat: false
		interval: 600
	}

	Window {
		id: fullscreenWindow
		title: i18n("Tiled Menu Prime")
		flags: Qt.Window | Qt.FramelessWindowHint
		color: fullscreenBackground.color
		onActiveChanged: {
			if (visible && !active && !widget.userConfiguring) {
				widget.closeMenu()
			}
		}

		Shortcut {
			sequence: "Escape"
			onActivated: widget.closeMenu()
		}

		// Fallback if the Plasma theme has no dialog background image.
		Rectangle {
			id: fullscreenBackground
			anchors.fill: parent
			color: Kirigami.Theme.backgroundColor
		}

		// The normal popup's look comes from the Plasma theme's dialog
		// background image, not a theme colour (e.g. Oxygen's window colour is
		// pure black). Draw the centre of the opaque variant of that image.
		// It is rendered at 1/8 size and scaled up, because rendering it at
		// fullscreen size can exceed Qt's 256MB image allocation limit.
		KSvg.SvgItem {
			readonly property int downscale: 8
			imagePath: "opaque/dialogs/background"
			elementId: "center"
			width: Math.ceil(parent.width / downscale)
			height: Math.ceil(parent.height / downscale)
			transformOrigin: Item.TopLeft
			scale: downscale
			smooth: true
		}

		Popup {
			id: fullscreenPopup
			anchors.fill: parent
		}
	}

	// property alias searchResultsView: popup.searchView.searchResultsView
	// width: popup.width
	// height: popup.height

	fullRepresentation: Popup {
		id: popup

		Layout.minimumWidth: config.leftSectionWidth
		Layout.minimumHeight: config.minimumHeight
		Layout.preferredWidth: config.popupWidth
		Layout.preferredHeight: config.popupHeight

		// Layout.minimumHeight: 600 // For quickly testing as a desktop widget
		// Layout.minimumWidth: 800

		onWidthChanged: {
			// console.log('popup.size', width, height, 'width')
			// resizeToFit.run()
		}
		onHeightChanged: {
			// console.log('popup.size', width, height, 'height')
			// resizeHeight.restart()
		}

		// Make popup resizeable like default Kickoff widget.
		// The FullRepresentation must have an appletInterface property.
		// https://invent.kde.org/plasma/plasma-desktop/-/commit/23c4e82cdcb6c7f251c27c6eefa643415c8c5927
		// https://invent.kde.org/frameworks/plasma-framework/-/merge_requests/500/diffs
		readonly property var appletInterface: Plasmoid.self

		Timer {
			id: resizeHeight
			interval: 200
			onTriggered: {
				if (!plasmoid.configuration.fullscreen) {
					// Need to Math.ceil when writing to fix (Issue #71)
					var dPR = scaleFactor
					var pH2 = height / dPR
					var pH3 = Math.ceil(pH2)
					// console.log('pH.set', 'dPR='+dPR, 'pH1='+height, 'pH2='+pH2, 'pH3='+pH3)
					if (plasmoid.configuration.popupHeight != pH3) {
						plasmoid.configuration.popupHeight = pH3
					}
				}
			}
		}
		Timer {
			id: resizeToFit
			interval: attemptsLeft == attempts ? 200 : 100
			repeat: attemptsLeft > 0
			property int attempts: 10
			property int attemptsLeft: 10

			function run() {
				restart()
				attemptsLeft = attempts
			}

			onTriggered: {
				if (plasmoid.configuration.fullscreen) {
					attemptsLeft = 0
				} else {
					var favWidth = Math.max(0, widget.width - config.leftSectionWidth) // 398 // 888-60-430
					// console.log(favWidth, widget.width, config.leftSectionWidth)
					// console.log(favWidth / config.cellBoxSize)
					// var cols = Math.floor(favWidth / config.favColWidth) * 2
					var cols = Math.floor(favWidth / config.cellBoxSize)
					if (plasmoid.configuration.favGridCols != cols) {
						// console.log(plasmoid.configuration.favGridCols, cols)
						plasmoid.configuration.favGridCols = cols
					}
					// Force a reflow since Meta+RightClick+Drag resizing doesn't really play nice with PlasmaCore.Dialog.
					config.popupWidthChanged()
					widget.Layout.preferredWidthChanged()
					attemptsLeft -= 1
				}
			}
		}
		// Layout.onPreferredWidthChanged: console.log('popup.size', width, height)
		// Layout.onPreferredHeightChanged: console.log('popup.size', width, height)


		onFocusChanged: {
			if (focus) {
				popup.searchView.searchField.forceActiveFocus()
			}
		}
	}

	Plasmoid.contextualActions: [
		PlasmaCore.Action {
			text: i18n("System Info")
			icon.name: "hwinfo"
			onTriggered: appsModel.launch('org.kde.kinfocenter')
		},
		PlasmaCore.Action {
			text: i18n("Terminal")
			icon.name: "utilities-terminal"
			onTriggered: appsModel.launch(plasmoid.configuration.terminalApp) // TODO: Read SystemSettings
		},
		PlasmaCore.Action {
			isSeparator: true
		},
		PlasmaCore.Action {
			text: i18n("Task Manager")
			icon.name: "utilities-system-monitor"
			onTriggered: appsModel.launch(plasmoid.configuration.taskManagerApp)
		},
		PlasmaCore.Action {
			text: i18n("System Settings")
			icon.name: "systemsettings"
			onTriggered: appsModel.launch('systemsettings')
		},
		PlasmaCore.Action {
			text: i18n("File Manager")
			icon.name: "folder"
			onTriggered: appsModel.launch(plasmoid.configuration.fileManagerApp) // TODO: Read SystemSettings
		},
		PlasmaCore.Action {
			isSeparator: true
		},
		PlasmaCore.Action {
			text: i18n("Edit Applications...")
			icon.name: "kmenuedit"
			onTriggered: processRunner.runMenuEditor()
		}
	]

	Component.onCompleted: {
		// Plasmoid.internalAction("configure").trigger() // Uncomment to open the config window on load.
	}
}
