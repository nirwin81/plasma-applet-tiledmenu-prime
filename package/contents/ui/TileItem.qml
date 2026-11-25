import QtQuick
import QtQuick.Controls as QQC2
import org.kde.plasma.core as PlasmaCore

Item {
	id: tileItem
	// Width/height/position are read through appObj (QML properties) rather than
	// a plain JS object, because Qt >= 6.10 (Plasma 6.8) no longer tracks
	// JS-object property changes in bindings. appObj re-emits its `tile`
	// changed signal (AppObject.updateFromTile) when a tile is edited.
	width: appObj.tileW * cellBoxSize
	height: appObj.tileH * cellBoxSize
	readonly property real itemMargin: appObj.isGroup ? groupMargin : cellMargin

	//For push/snapback animations
	property real targetX: appObj.tileX * cellBoxSize
	property real targetY: appObj.tileY * cellBoxSize
	x: targetX
	y: targetY
	// Extended group backgrounds sit behind their tiles, and behind the grid
	// cells (z 0) so the cells' drop highlight stays visible on top of them.
	// That holds while dragging too, or the background would cover the group's
	// own tiles; such a group is only raised above the other backgrounds. A group
	// with nothing painted behind its tiles is raised above everything.
	readonly property bool extendGroup: appObj.isGroup && config.extendGroupBackground
	readonly property bool paintsBehindTiles: extendGroup
		&& !!appObj.groupRect && appObj.groupRect.h > 0
		&& (appObj.backgroundImage !== "" || appObj.backgroundColor.a > 0)
	readonly property real restingZ: extendGroup ? -1 : 0
	readonly property real draggedZ: paintsBehindTiles ? -0.5 : 1
	z: dragActive ? draggedZ : restingZ
	Behavior on targetX { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
	Behavior on targetY { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

	function fixCoordinateBindings() {
		targetX = Qt.binding(function(){ return appObj.tileX * cellBoxSize })
		targetY = Qt.binding(function(){ return appObj.tileY * cellBoxSize })
		x = Qt.binding(function(){ return targetX })
		y = Qt.binding(function(){ return targetY })
		z = Qt.binding(function(){ return tileItem.dragActive ? tileItem.draggedZ : tileItem.restingZ })
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

	function refresh() {
		appObj.updateFromTile()
	}

	readonly property bool faded: tileGrid.editing || tileMouseArea.isLeftPressed
	readonly property int fadedWidth: width - (appObj.isGroup ? groupMargin * 2 : cellPushedMargin)
	opacity: faded ? 0.75 : 1
	scale: faded ? fadedWidth / width : 1
	transformOrigin: extendGroup ? Item.Top : Item.Center
	Behavior on opacity { NumberAnimation { duration: 200 } }
	Behavior on scale { NumberAnimation { duration: 200 } }

	//--- View Start
	TileItemView {
		id: tileItemView
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: parent.top
		anchors.margins: itemMargin
		// The icon and label stay within the tile itself (a group's title). When
		// extended, a group's background continues through every row that belongs
		// to the group.
		faceHeight: appObj.tileH * cellBoxSize - 2 * itemMargin
		height: faceHeight + (tileItem.extendGroup && appObj.groupRect ? appObj.groupRect.h * cellBoxSize : 0)
		readonly property int minSize: Math.min(width, height)
		readonly property int maxSize: Math.max(width, height)
		hovered: tileMouseArea.containsMouse
	}

	HoverOutlineEffect {
		id: hoverOutlineEffect
		anchors.fill: parent
		anchors.margins: itemMargin
		hoverRadius: {
			// An extended group view is taller than its title. The effect
			// covers only the title, which is the tile item itself.
			if (extendGroup) {
				return Math.max(tileItem.width, tileItem.height) - 2 * itemMargin
			} else if (appObj.isGroup) {
				return tileItemView.maxSize
			} else {
				return tileItemView.minSize
			}
		}
		// A group gets one outline around its title and tiles (groupOutline)
		hoverOutlineSize: appObj.isGroup ? 0 : tileGrid.hoverOutlineSize
		radius: tileItemView.cornerRadius
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

	// Outlines the group as drawn: its title and tiles, inset by the group margin.
	// Lives next to the tiles rather than in this one, so the group's own tiles
	// don't cover it. It has to copy this tile's position and scale instead.
	Loader {
		id: groupEffectLoader
		parent: tileItem.parent
		x: tileItem.x
		y: tileItem.y
		z: 2 // Above a dragged tile
		opacity: tileItem.opacity
		transform: Scale {
			origin.x: tileItem.width / 2
			origin.y: tileItem.extendGroup ? 0 : tileItem.height / 2 // See transformOrigin
			xScale: tileItem.scale
			yScale: tileItem.scale
		}
		visible: tileMouseArea.containsMouse
		active: appObj.isGroup && visible
		sourceComponent: Item {
			Rectangle {
				id: groupOutline
				color: "transparent"
				border.width: Math.max(1, Math.round(1 * Screen.devicePixelRatio))
				border.color: hoverOutlineEffect.borderColor
				radius: tileItemView.cornerRadius
				x: itemMargin
				y: itemMargin
				width: tileItem.width - 2 * itemMargin
				height: (appObj.tileH + appObj.groupRect.h) * cellBoxSize - 2 * itemMargin
			}
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
				if (!appObj.isGroup) {
					tileItem.addTileSizeMenu(menu)
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

	// Icons are local SVGs; QMenu resolves the icon string via the icon
	// loader, which accepts an absolute file path (not a file:// URL).
	function tileSizeIconPath(name) {
		return Qt.resolvedUrl("../icons/" + name + ".svg").toString().replace(/^file:\/\//, '')
	}

	function addTileSizeMenu(menu) {
		var sizeMenuItem = menu.newSubMenuItem()
		if (!sizeMenuItem) {
			return
		}
		sizeMenuItem.text = i18n("Tile size")
		sizeMenuItem.icon = 'transform-scale'

		var sizes = [
			{ w: 1, h: 1 },
			{ w: 2, h: 1 },
			{ w: 2, h: 2 },
		]
		sizes.forEach(function(size) {
			var sizeItem = sizeMenuItem.newMenuItem()
			sizeItem.text = ''
			sizeItem.icon = tileSizeIconPath('tile-size-' + size.w + 'x' + size.h)
			sizeItem.checkable = true
			sizeItem.checked = appObj.tileW == size.w && appObj.tileH == size.h
			sizeItem.clicked.connect(function() {
				tileItem.setTileSize(size.w, size.h)
			})
		})
		// Items created with a Menu as parent are added to it automatically.
	}

	function setTileSize(w, h) {
		// Mutate the real array element (see note on AppObject above), then
		// notify like TileEditorRectField does.
		var tile = tileModel[index]
		if (!tile || (tile.w == w && tile.h == h)) {
			return
		}
		tile.w = w
		tile.h = h
		appObj.tileChanged()
		tileGrid.tileModelChanged()
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
