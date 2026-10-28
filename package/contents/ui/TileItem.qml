import QtQuick
import QtQuick.Controls as QQC2
import org.kde.plasma.core as PlasmaCore

Item {
	id: tileItem
	property int pushedFromX: -1
	property int pushedFromY: -1
	// Width/height/position are read through appObj (QML properties) rather than
	// a plain JS object, because Qt >= 6.10 (Plasma 6.8) no longer tracks
	// JS-object property changes in bindings. appObj re-emits its `tile`
	// changed signal (AppObject.updateFromTile) when a tile is edited.
	width: appObj.tileW * cellBoxSize
	height: appObj.tileH * cellBoxSize

	//For push/snapback animations
	property real targetX: appObj.tileX * cellBoxSize
	property real targetY: appObj.tileY * cellBoxSize
	x: targetX
	y: targetY
	Behavior on targetX { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
	Behavior on targetY { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

	function fixCoordinateBindings() {
		targetX = Qt.binding(function(){ return appObj.tileX * cellBoxSize })
		targetY = Qt.binding(function(){ return appObj.tileY * cellBoxSize })
		x = Qt.binding(function(){ return targetX })
		y = Qt.binding(function(){ return targetY })
		z = 0
	}

	// IMPORTANT (Qt >= 6.10 / Plasma 6.8): the Repeater's `modelData` is a
	// C++-side copy of the tile object (different reference, reconstructed via
	// QVariant), NOT the element in the `tileModel` JS array. Mutating or
	// comparing it never touches the array that gets saved. Always use the
	// real element: `tileModel[index]`.
	AppObject {
		id: appObj
		tile: tileModel[index]
	}
	readonly property alias app: appObj.app

	readonly property bool faded: tileGrid.editing || tileMouseArea.isLeftPressed
	readonly property int fadedWidth: width - cellPushedMargin
	opacity: faded ? 0.75 : 1
	scale: faded ? fadedWidth / width : 1
	Behavior on opacity { NumberAnimation { duration: 200 } }
	Behavior on scale { NumberAnimation { duration: 200 } }

	//--- View Start
	TileItemView {
		id: tileItemView
		anchors.fill: parent
		anchors.margins: cellMargin
		width: appObj.tileW * cellBoxSize
		height: appObj.tileH * cellBoxSize
		readonly property int minSize: Math.min(width, height)
		readonly property int maxSize: Math.max(width, height)
		hovered: tileMouseArea.containsMouse
	}

	HoverOutlineEffect {
		id: hoverOutlineEffect
		anchors.fill: parent
		anchors.margins: cellMargin
		hoverRadius: {
			if (appObj.isGroup) {
				return tileItemView.maxSize
			} else {
				return tileItemView.minSize
			}
		}
		hoverOutlineSize: tileGrid.hoverOutlineSize
		mouseArea: tileMouseArea
	}
	//--- View End

	MouseArea {
		id: tileMouseArea
		anchors.fill: parent
		hoverEnabled: true
		acceptedButtons: Qt.LeftButton | Qt.RightButton
		cursorShape: editing ? Qt.ClosedHandCursor : Qt.ArrowCursor
		readonly property bool isLeftPressed: pressedButtons & Qt.LeftButton

		property int pressX: -1
		property int pressY: -1
		onPressed: function(mouse) {
			pressX = mouse.x
			pressY = mouse.y
		}

		drag.target: plasmoid.configuration.tilesLocked ? undefined : tileItem
		// drag.onActiveChanged: console.log('drag.active', drag.active)

		// This MouseArea will spam "QQuickItem::ungrabMouse(): Item is not the mouse grabber."
		// but there's no other way of having a clickable drag area.
		onClicked: function(mouse) {
			mouse.accepted = true
			tileGrid.resetDrag()
			if (mouse.button == Qt.LeftButton) {
				if (tileEditorView && tileEditorView.tile) {
					openTileEditor()
				} else if (appObj.tile && appObj.tile.url) {
					appsModel.tileGridModel.runApp(appObj.tile.url)
				}
			} else if (mouse.button == Qt.RightButton) {
				appContextMenu.open(mouse.x, mouse.y)
			}
		}
	}

	Drag.dragType: Drag.Automatic
	Drag.proposedAction: Qt.MoveAction
	Drag.hotSpot.x: width / 2
	Drag.hotSpot.y: height / 2

	// We use this drag pattern to use the internal drag with events.
	// https://stackoverflow.com/a/24729837/947742
	property bool dragActive: tileMouseArea.drag.active
	onDragActiveChanged: {
		if (dragActive) {
			// console.log("drag started")
			// console.log('onDragStarted', JSON.stringify(modelData), index, tileModel.length)
			tileGrid.startDrag(index)
			tileGrid.dropOffsetX = 0
			// tileGrid.dropOffsetY = 0
			tileItem.z = 1
			Drag.start()
		} else {
			console.log("drag finished")
			console.log('DragArea.onDrop', draggedItem)
			Qt.callLater(tileGrid.resetDrag)
			Qt.callLater(tileItem.fixCoordinateBindings)
			Drag.drop() // Breaks QML context.
			// We need to use callLater to call functions after Drag.drop().
		}
	}

	QQC2.ToolTip {
		id: control
		visible: tileItemView.hovered && !(dragActive || appContextMenu.opened) && appObj.tile.w == 1 && appObj.tile.h == 1
		text: appObj.labelText
		delay: 0
		x: parent.width + rightPadding
		y: (parent.height - height) / 2
	}

	Loader {
		id: groupEffectLoader
		visible: tileMouseArea.containsMouse
		active: appObj.isGroup && visible
		sourceComponent: Rectangle {
			id: groupOutline
			color: "transparent"
			border.width: Math.max(1, Math.round(1 * Screen.devicePixelRatio))
			border.color: "#80ffffff"
			y: appObj.tileH * cellBoxSize
			z: 100
			width: appObj.groupRect.w * cellBoxSize
			height: appObj.groupRect.h * cellBoxSize
		}
	}

	AppContextMenu {
		id: appContextMenu
		visualParent: tileItem
		tileIndex: index
		onPopulateMenu: function(menu) {   
			appObj.addActionList(menu)

			if (!plasmoid.configuration.tilesLocked) {
				menu.addPinToMenuAction(appObj.tile ? appObj.tile.url : '')
				if (appObj.isGroup) {
					var menuItem = menu.newMenuItem()
					menuItem.text = i18n("Sort Tiles")
					menuItem.icon = 'sort-name'
					menuItem.onClicked.connect(function(){
						tileGrid.sortGroupTiles(appObj.tile)
					})
				}
				var menuItem = menu.newMenuItem()
				menuItem.text = i18n("Edit Tile")
				menuItem.icon = 'rectangle-shape'
				menuItem.onClicked.connect(function(){
					tileItem.openTileEditor()
				})
			}
		}
	}

	function openTileEditor() {
		// Pass the index (a value type) across the signal boundary. In Qt >= 6.10
		// (Plasma 6.8) object-typed signal arguments are deep-copied through
		// QVariant, so passing the tile object itself hands the editor a clone
		// whose edits can never reach the `tileModel` array that gets saved.
		tileGrid.editTile(index)
	}
	function closeTileEditor() {

	}
}
