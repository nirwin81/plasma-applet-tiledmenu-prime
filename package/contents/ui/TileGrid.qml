import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.draganddrop as DragAndDrop
import "Utils.js" as Utils

DropArea {
	id: tileGrid

	property int cellSize: 60 * config.scaleFactor
	property real cellMargin: 3 * config.scaleFactor
	property real cellPushedMargin: 6 * config.scaleFactor
	property int cellBoxSize: cellMargin + cellSize + cellMargin
	property int hoverOutlineSize: 2 * config.scaleFactor

	property int minColumns: Math.floor(width / cellBoxSize)
	property int minRows: Math.floor(height / cellBoxSize)

	property int maxColumn: 0
	property int maxRow: 0
	property int maxWidth: 0
	property int maxHeight: 0
	property int columns: Math.max(minColumns, maxColumn)
	property int rows: Math.max(minRows, maxRow)


	//--- Drag and Drop properties
	property bool isDragging: false
	property var addedItem: null
	readonly property bool adding: addedItem
	property int draggedIndex: -1
	readonly property var draggedItem: draggedIndex >= 0 ? tileModel[draggedIndex] : null
	property bool editing: isDragging && draggedItem || adding
	property int dropHoverX: -1
	property int dropHoverY: -1
	property int dropOffsetX: 0
	property int dropOffsetY: 0
	readonly property int dropWidth: draggedItem ? draggedItem.w : addedItem ? addedItem.w : 0
	readonly property int dropHeight: draggedItem ? draggedItem.h : addedItem ? addedItem.h : 0
	property bool canDrop: false
	readonly property bool hasDrag: tileGrid.editing && dropHoverX >= 0 && dropHoverY >= 0
	readonly property bool isDraggingGroup: hasDrag && draggedItem && draggedItem.tileType == "group"
	readonly property var draggedGroupRect: {
		if (isDraggingGroup) {
			return getGroupAreaRect(draggedItem)
		} else {
			return null
		}
	}
	readonly property bool dynamicPusher: config.dynamicTilePusher

	//--- Drag and Drop events
	// onContainsDragChanged: console.log('containsDrag', containsDrag)
	onEntered: drag => {
		// console.log('onEntered', drag)
		dragTick(drag)
	}
	onPositionChanged: drag => {
		// console.log('onPositionChanged', drag)
		dragTick(drag)
	}
	onExited: drag => {
		// console.log('onExited')
		resetDragHover()
	}
	onDropped: drop => {
		dragTick(drop)
		console.log('onDropped', drop)
		if (canDrop) {
			if (draggedItem) {
				tileGrid.moveTile(draggedItem, dropHoverX, dropHoverY)
				tileGrid.resetDrag()
				// event.accept(Qt.MoveAction)
			} else if (addedItem) {
				addedItem.x = dropHoverX
				addedItem.y = dropHoverY
				tileGrid.tileModel.push(addedItem)
				tileGrid.tileModelChanged()
				tileGrid.resetDrag()
			}
		}
		for (var index = 0; index < pushedTiles.length; ++index) {
			if (pushedTiles[index]) {
				console.log('Resetting pushedFrom values 1')
				pushedTiles[index].pushedFromX = -1
				pushedTiles[index].pushedFromY = -1
			}
		}
		pushedTiles = []
		tileGrid.resetDrag()
	}

	// Drag and Drop functions
	function resetDragHover() {
		dropHoverX = -1
		dropHoverY = -1
		scrollUpArea.containsDrag = false
		scrollDownArea.containsDrag = false
		addedItem = null
	}
	function resetDrag() {
		// Restore coordinate bindings for group members before draggedIndex is cleared
		for (var i = 0; i < draggedGroupMembers.length; i++) {
			var idx = tileModel.indexOf(draggedGroupMembers[i])
			if (idx >= 0) {
				var memberItem = tileModelRepeater.itemAt(idx)
				if (memberItem) memberItem.fixCoordinateBindings()
			}
		}
		draggedGroupMembers = []
		resetDragHover()
		isDragging = false
		draggedIndex = -1
	}
	property var draggedItemOriginalGroup: null
	property var draggedGroupMembers: []
	property int draggedGroupContentHeight: 0

	function startDrag(index) {
		draggedIndex = index
		dropHoverX = draggedItem.x
		dropHoverY = draggedItem.y
		isDragging = true
		for (var i = 0; i < tileModel.length; ++i) {
			if (tileModel[i].pushedFromX === undefined) tileModel[i].pushedFromX = -1
			if (tileModel[i].pushedFromY === undefined) tileModel[i].pushedFromY = -1
		}
		draggedItemOriginalGroup = null
		for (var i = 0; i < tileModel.length; ++i) {
			var t = tileModel[i]
			if (t.tileType === 'group' && isTileInGroup(t, draggedItem)) {
				draggedItemOriginalGroup = t
				break
			}
		}
		// Capture group members by reference at drag start (before any positions change)
		draggedGroupMembers = []
		draggedGroupContentHeight = 0
		if (draggedItem && draggedItem.tileType === 'group') {
			var memberArea = getGroupAreaRect(draggedItem)
			draggedGroupContentHeight = memberArea.h
			for (var i = 0; i < tileModel.length; ++i) {
				if (i === draggedIndex) continue
				if (tileWithin(tileModel[i], memberArea.x1, memberArea.y1, memberArea.x2, memberArea.y2)) {
					draggedGroupMembers.push(tileModel[i])
				}
			}
		}
	}

	function tileWithin(tile, x1, y1, x2, y2) {
		var tileX2 = tile.x + tile.w - 1
		var tileY2 = tile.y + tile.h - 1
		return (x1 <= tileX2
			&& tile.x <= x2
			&& y1 <= tileY2
			&& tile.y <= y2
		)
		return isAreaWithinArea(tile.x, tile.y, tile.x+tile.w-1, tile.y+tile.h-1, x1, y1, x2, y2)
	}

	function isAreaWithinArea(a1x1, a1y1, a1x2, a1y2, a2x1, a2y1, a2x2, a2y2) {
		return (a2x1 <= a1x2
			&& a1x1 <= a2x2
			&& a2y1 <= a1y2
			&& a1y1 <= a2y2
		)
	}

	function getGroupAreaRect(groupTile, tileToExclude) {
		if (!groupTile) {
			console.log('groupTile was invalid when calculating area in getGroupAreaRect')
			return { x1: 0, y1: 0, x2: -1, y2: -1, w: 0, h: 0 }
		}
		var x1 = groupTile.x
		var x2 = groupTile.x + groupTile.w - 1
		var y1 = groupTile.y + groupTile.h
		// Build a set of rows that are occupied within the group's column span.
		// A row is occupied if any tile covers at least one cell in [x1, x2] on that row.
		var occupiedRows = {}
		var groupHeaderRows = {}
		for (var i = 0; i < tileModel.length; i++) {
			var tile = tileModel[i]
			if (isNaN(tile.x) || isNaN(tile.y) || tile.x === null || tile.y === null) continue
			if (tile === groupTile) continue
			if (tileToExclude !== null && tile === tileToExclude) continue
			// Check if tile overlaps the group's column span
			if (tile.x <= x2 && tile.x + tile.w - 1 >= x1 && tile.y >= y1) {
				for (var row = tile.y; row < tile.y + tile.h; row++) {
					occupiedRows[row] = true
				}
				if (tile.tileType === 'group') {
					for (var row = tile.y; row < tile.y + tile.h; row++) {
						groupHeaderRows[row] = true
					}
				}
			}
		}

		// Walk down row by row from y1; stop at the first blank row or group header row
		var y2 = y1 - 1
		for (var row = y1; occupiedRows[row] && !groupHeaderRows[row]; row++) {
			y2 = row
		}

		return {
			x1: x1,
			y1: y1,
			x2: x2,
			y2: y2,
			w: x2 - x1 + 1,
			h: y2 - y1 + 1,
		}
	}

	function moveGroupContents(groupTile, deltaX, deltaY) {
		if (groupTile === draggedItem && draggedGroupMembers.length > 0) {
			for (var mi = 0; mi < draggedGroupMembers.length; mi++) {
				draggedGroupMembers[mi].x += deltaX
				draggedGroupMembers[mi].y += deltaY
			}
			return
		}

		var area = getGroupAreaRect(groupTile)

		// Move tiles below group label
		for (var i = 0; i < tileModel.length; i++) {
			var tile = tileModel[i]
			if (tile === draggedItem) continue
			if (tileWithin(tile, area.x1, area.y1, area.x2, area.y2)) {
				tile.x += deltaX
				tile.y += deltaY
			}
		}

		// We call this in moveTile so no need to duplicate work.
		// tileGrid.tileModelChanged()
	}

	function moveGroupContentsAnimated(groupTile, deltaX, deltaY) {
		var area = getGroupAreaRect(groupTile, draggedItem)

		// Move tiles below group label
		for (var i = 0; i < tileModel.length; i++) {
			var tile = tileModel[i]
			if (tile === draggedItem) continue
			if (draggedGroupMembers.indexOf(tile) >= 0) continue
			if (tile.y >= area.y1 && tileWithin(tile, area.x1, area.y1, area.x2, area.y2)) {
				var item = i >= 0 ? tileModelRepeater.itemAt(i) : null
				if (item) {
					item.targetX = (tile.x + deltaX) * cellBoxSize
					item.targetY = (tile.y + deltaY) * cellBoxSize
				}
				tile.x = tile.x + deltaX
				tile.y = tile.y + deltaY
			}
		}

		// We call this in moveTile so no need to duplicate work.
		// tileGrid.tileModelChanged()
	}


	function getGroupForTile(tile) {
		for (var i = 0; i < tileModel.length; i++) {
			var t = tileModel[i]
			if (t.tileType === 'group' && isTileInGroup(t, tile)) {
				return t
			}
		}
		return null
	}

	function isTileInGroup(groupTile, tile) {
		var area = getGroupAreaRect(groupTile)
		for (var i = 0; i < tileModel.length; i++) {
			var tileInGroup = tileModel[i]
			if (tileInGroup.y >= area.y1 && tileWithin(tileInGroup, area.x1, area.y1, area.x2, area.y2)) {
				if (tileInGroup == tile) {
					return true
				}
			}

		}
		return false
	}

	function moveTile(tile, cellX, cellY) {
		if (isNaN(cellX) || isNaN(cellY) || cellX === null || cellY === null) {
			return
		}
		if (tile.tileType == "group") {
			moveGroupContents(tile, cellX - tile.x, cellY - tile.y)
		}
		tile.x = cellX
		tile.y = cellY
		tile.pushedFromX = -1
		tile.pushedFromY = -1
		tileGrid.tileModelChanged()
	}

	property var pushedTiles: new Array(32)

	function moveTileAnimated(tile, cellX, cellY) {
		if (isNaN(cellX) || isNaN(cellY) || cellX === null || cellY === null) {
			return
		}
		if (tile.tileType == "group") {
			moveGroupContentsAnimated(tile, cellX - tile.x, cellY - tile.y)
		}
		var idx = tileModel.indexOf(tile)
		var item = idx >= 0 ? tileModelRepeater.itemAt(idx) : null
		if (item) {
			item.targetX = cellX * cellBoxSize
			item.targetY = cellY * cellBoxSize
		}
		tile.x = cellX
		tile.y = cellY
		updateSize()
	}

	function pushTile(tile, cellX, cellY) {
		if (isNaN(cellX) || isNaN(cellY) || cellX === null || cellY === null) {
			return
		}
		if (tile.pushedFromX === -1) tile.pushedFromX = tile.x
		if (tile.pushedFromY === -1) tile.pushedFromY = tile.y
		if (tile.tileType == "group") {
			moveGroupContentsAnimated(tile, cellX - tile.x, cellY - tile.y)
		}
		var idx = tileModel.indexOf(tile)
		var item = idx >= 0 ? tileModelRepeater.itemAt(idx) : null
		if (item) {
			item.targetX = cellX * cellBoxSize
			item.targetY = cellY * cellBoxSize	
		}
		tile.x = cellX
		tile.y = cellY
		updateSize()
	}

	function snapbackTile(tile) {
		if (!tile) {
			return
		}
		if (tile.pushedFromX == -1 || tile.pushedFromY == -1) {
			return
		}
		var groupToIgnore = tile.tileType === 'group' ? tile : null
		if (groupToIgnore === null && isTileInGroup(tile)) {
			groupToIgnore = getGroupForTile(tile)
		}
		var snapAreaRect = (tile.tileType === 'group') ? getGroupAreaRect(tile, draggedItem) : null
		var snapCheckH = tile.h + (snapAreaRect ? snapAreaRect.h : 0)

		if (!hits(tile.pushedFromX, tile.pushedFromY, tile.w, snapCheckH, tile, groupToIgnore, null)) {
			moveTileAnimated(tile, tile.pushedFromX, tile.pushedFromY)
			tile.pushedFromX = -1
			tile.pushedFromY = -1
			pushedTiles.splice(pushedTiles.indexOf(tile), 1)
			updateSize()
			return
		}

		// Find out how far back the tile can snap
		var maxXDelta = tile.pushedFromX - tile.x
		var maxYDelta = tile.pushedFromY - tile.y
		var xDeltaStep = 0
		var yDeltaStep = 0
		if (maxXDelta < 0) xDeltaStep = -1
		else if (maxXDelta > 0) xDeltaStep = 1
		else if (maxYDelta < 0) yDeltaStep = -1
		else if (maxYDelta > 0) yDeltaStep = 1;
		var maxDistance = Math.max(Math.abs(maxXDelta), Math.abs(maxYDelta))		
		var distanceMoved = 0
		var xPosToUse = -1
		var yPosToUse = -1
		while (distanceMoved <= maxDistance) {
			var testX = tile.x + xDeltaStep * (distanceMoved + 1)
			var testY = tile.y + yDeltaStep * (distanceMoved + 1)

			// Did we hit something?
			if (hits(testX, testY, tile.w, snapCheckH, tile, groupToIgnore, null)) {
				//Yes? Can't go any further then
				break;
			} else {
				xPosToUse = testX
				yPosToUse = testY
			}

			++distanceMoved
		}

		// Snap it back to the appropriate place
		if (xPosToUse !== -1 && yPosToUse !== -1) {
			moveTileAnimated(tile, xPosToUse, yPosToUse)
			onExited
		}
		updateSize()
	}

	function applyTilePush(tile) {
		pushedFromX = -1
		pushedFromY = -1
	}

	// QQuickDropEvent
	// https://github.com/qt/qtdeclarative/blob/a4aa8d9ade44d75cb5a1d84bd7c1773fadc73095/src/quick/items/qquickdroparea_p.h#L63
	function dragTick(event) {
		//console.log('dragTick', event.x, event.y)
		var dragX = event.x + dropOffsetX
		var dragY = event.y + dropOffsetY + scrollView.scrollTop
		var modelX = Math.max(0, Math.round(dragX / cellBoxSize - dropWidth / 2))
		var modelY = Math.max(0, Math.round(dragY / cellBoxSize - dropHeight / 2))
		var globalPoint = popup.mapFromItem(tileGrid, event.x, event.y)
		// console.log('onDragMove', event.x, event.y, modelX, modelY, globalPoint)
		scrollUpArea.checkContains(event)
		scrollDownArea.checkContains(event)

		var tileGroup = null
		if (draggedItem) {
			if (draggedItem.tileType == "group") {
				tileGroup = draggedItem
			}
		} else if (addedItem) {
			if (addedItem.tileType == "group") {
				tileGroup = addedItem
			}
		} else if (event && event.hasUrls && event.urls) {
			if (event.keys && event.keys.indexOf('favoriteId') >= 0) {
				var url = event.getDataAsString('favoriteId')
				url = Utils.parseDropUrl(url)
			} else {
				var url = event.urls[0].toString()
				// console.log('new addedItem', event.urls, url)
				url = Utils.parseDropUrl(url)
			}
			// console.log('new addedItem')
			// console.log('\t', 'urls', event.urls)
			// console.log('\t', 'url', url)
			// console.log('\t', 'keys', event.keys)
			// for (var i = 0; i < event.keys.length; i++) {
			// 	var key = event.keys[i]
			// 	var value = event.getDataAsString(key)
			// 	console.log('\t', 'mimeData', key, value)
			// }

			addedItem = newTile(url)
			dropHoverX = modelX
			dropHoverY = modelY

			// Firefox/Chromium url dropped
			if (event.keys.indexOf('_NETSCAPE_URL') >= 0) {
				var netscapeUrl = event.getDataAsString('_NETSCAPE_URL')
				var tokens = netscapeUrl.split('\n')
				if (tokens.length >= 2) {
					var title = tokens[1].trim()
					if (title) {
						addedItem.label = title
						addedItem.icon = 'internet-web-browser'
					}
				}
			}
		} else {
			return
		}

		// Update hover position first so snapbacks can check against current cursor
		dropHoverX = Math.max(0, Math.min(modelX, columns - dropWidth))
		dropHoverY = Math.max(0, modelY)

		// First try to 'snapback' anything that was being pushed
		if (dynamicPusher) {
			for (var pushedIndex = pushedTiles.length-1; pushedIndex >= 0; --pushedIndex) {
				var pushedTile = pushedTiles[pushedIndex]
				if( pushedTile ) {
					if (snapbackTile(pushedTile)) {
						pushedTiles.splice(pushedTiles.indexOf(pushedTile), 1)
					}
				}
			}
		}

		// Check if we can drop item at this location
		// Use draggedGroupContentHeight (captured at drag start) rather than dynamically
		// re-computing getGroupAreaRect(draggedItem), which can be corrupted when pushed
		// groups land in the dragged group's original column range.
		var dropHeightToCheck = dropHeight
		if (draggedItem && draggedItem.tileType == "group" && draggedGroupContentHeight > 0) {
			dropHeightToCheck += draggedGroupContentHeight
		}

		canDrop = !hits(dropHoverX, dropHoverY, dropWidth, dropHeightToCheck, null, tileGroup, dynamicPusher)

		// Move group members to follow the dragged group header
		if (isDraggingGroup) {
			var deltaX = dropHoverX - draggedItem.x
			var deltaY = dropHoverY - draggedItem.y
			for (var mi = 0; mi < draggedGroupMembers.length; mi++) {
				var member = draggedGroupMembers[mi]
				var memberIdx = tileModel.indexOf(member)
				var memberItem = memberIdx >= 0 ? tileModelRepeater.itemAt(memberIdx) : null
				if (memberItem) {
					memberItem.targetX = (member.x + deltaX) * cellBoxSize
					memberItem.targetY = (member.y + deltaY) * cellBoxSize
				}
			}
		}
	}

	property var hitBox: [] // hitBox[y][x]
	function updateSize() {
		var c = 0;
		var r = 0;
		var w = 1;
		var h = 1;
		for (var i = 0; i < tileModel.length; i++) {
			var tile = tileModel[i]
			if (isNaN(tile.y) || isNaN(tile.h) || isNaN(tile.x) || isNaN(tile.w)) {
				continue
			}
			c = Math.max(c, tile.x + tile.w)
			r = Math.max(r, tile.y + tile.h)
			w = Math.max(w, tile.w)
			h = Math.max(h, tile.h)
		}
		// Add extra rows when dragging so we can drop scrolled down
		var groupItem = null
		if (draggedItem && draggedItem.tileType == "group")
		{
			groupItem = draggedItem
		}
		if (draggedItem) {
			// c += draggedItem.w
			r += draggedItem.h
		}

		// Rebuild hitBox (2D grid of tile locations)
		var hbColumns = Math.max(minColumns, c)
		var hbRows = Math.max(minRows, r)
		var hb = new Array(hbRows)
		for (var i = 0; i < hbRows; i++) {
			hb[i] = new Array(hbColumns)
		}
		for (var i = 0; i < tileModel.length; ++i) {
			var tile = tileModel[i]
			if (i == draggedIndex) {
				continue;	// Don't mark the dragged header's space as in use
			}
			if (draggedGroupMembers.length > 0 && draggedGroupMembers.indexOf(tile) >= 0) {
				continue;	// Don't mark dragged group's members as in use either
			}
			for (var j = tile.y; j < tile.y + tile.h; j++) {
				for (var k = tile.x; k < tile.x + tile.w; k++) {
					hb[j][k] = true
				}
			}
		}

		// Update Properties
		hitBox = hb
		maxColumn = c
		maxRow = r
		maxWidth = w
		maxHeight = h
	}
	function update() {
		var urlList = []
		for (var i = 0; i < tileModel.length; i++) {
			var tile = tileModel[i]
			if (tile.url) {
				urlList.push(tile.url)
			}
		}
		appsModel.tileGridModel.favorites = urlList
		updateSize()
	}
	onDraggedItemChanged: update()
	onTileModelChanged: update()
	property var tileModel: []

	function tryPushGroup(tileXPos, tileYPos, avoidX, avoidY, avoidW, avoidH) {
		return tryPushTile(tileXPos, tileYPos, avoidX, avoidY, avoidW, avoidH, true)
	}

	function tryPushTile(tileXPos, tileYPos, avoidX, avoidY, avoidW, avoidH, respectGroups = false) {
		var smallestDistance = 0
		var bestXPos = -1
		var bestYPos = -1
		var tile = getTileAt( tileXPos, tileYPos )
		if (!tile) {
			return false
		}
		var tileWidth = tile.w
		var tileHeight = tile.h
		if (respectGroups && tile.tileType == 'group') {
			tileHeight = tile.h + getGroupAreaRect(tile, draggedItem).h
		}

		var tileGroupHeader = getGroupForTile(tile)

		// Logging info
		var clearAreaX1, clearAreaX2, clearAreaY1, clearAreaY2

		// There is far too much code duplication when checking the 4 directions, but I don't think lambdas are supported, and functions can't take reference parameters. Could try a function with a complex return object?
		// Check left
		var steps = 0
		for( var xPos = tileXPos-1; xPos >= 0 && (steps < smallestDistance || smallestDistance == 0); --xPos )
		{
			++steps
			if ( isAreaEmpty(xPos, tileYPos, tileWidth, tileHeight, tile) &&
				!isAreaWithinArea(xPos, tileYPos, xPos+tileWidth-1, tileYPos+tileHeight-1, avoidX, avoidY, avoidX+avoidW-1, avoidY+avoidH-1) &&
				(!isDraggingGroup || !isAreaInAnyGroup(xPos, tileYPos, tileWidth, tileHeight, tileGroupHeader)) )
			{
				smallestDistance = steps
				bestXPos = xPos
				bestYPos = tileYPos

				clearAreaX1 = xPos
				clearAreaY1 = tileYPos
				clearAreaX2 = xPos+tileWidth-1
				clearAreaY2 = tileYPos+tileHeight-1

				break
			}
		}
		// Check right
		steps = 0
		for( var xPos = tileXPos+1; xPos+tileWidth-1 < columns && (steps < smallestDistance || smallestDistance == 0); ++xPos )
		{
			++steps
			if (smallestDistance !== 0 && steps >= smallestDistance)
				break
			if ( isAreaEmpty(xPos, tileYPos, tileWidth, tileHeight, tile) &&
				!isAreaWithinArea(xPos, tileYPos, xPos+tileWidth-1, tileYPos+tileHeight-1, avoidX, avoidY, avoidX+avoidW-1, avoidY+avoidH-1) &&
				(!isDraggingGroup || !isAreaInAnyGroup(xPos, tileYPos, tileWidth, tileHeight, tileGroupHeader)) )
			{
				smallestDistance = steps
				bestXPos = xPos
				bestYPos = tileYPos

				clearAreaX1 = xPos
				clearAreaY1 = tileYPos
				clearAreaX2 = xPos+tileWidth-1
				clearAreaY2 = tileYPos+tileHeight-1

				break
			}
		}
		// Check up
		steps = 0
		for( var yPos = tileYPos-1; yPos >= 0 && (steps < smallestDistance || smallestDistance == 0); --yPos )
		{
			++steps
			if (smallestDistance !== 0 && steps >= smallestDistance)
				break
			if (tileGroupHeader && isAreaWithinArea(tileXPos, yPos, tileXPos+tileWidth-1, yPos+tileHeight-1, tileGroupHeader.x, tileGroupHeader.y, tileGroupHeader.x+tileGroupHeader.w-1, tileGroupHeader.y+tileGroupHeader.h-1)) {
				break
			}
			if ( isAreaEmpty(tileXPos, yPos, tileWidth, tileHeight, tile) &&
				!isAreaWithinArea(tileXPos, yPos, tileXPos+tileWidth-1, yPos+tileHeight-1, avoidX, avoidY, avoidX+avoidW-1, avoidY+avoidH-1) &&
				(!isDraggingGroup || !isAreaInAnyGroup(tileXPos, yPos, tileWidth, tileHeight, tile.tileType == 'group' ? tile : tileGroupHeader)) )
			{
				smallestDistance = steps
				bestXPos = tileXPos
				bestYPos = yPos

				clearAreaX1 = tileXPos
				clearAreaY1 = yPos
				clearAreaX2 = tileXPos+tileWidth-1
				clearAreaY2 = yPos+tileHeight-1

				break
			}
		}
		// Check down
		steps = 0
		var heightToCheck = (tile.tileType === 'group' && !respectGroups) ? (tile.h + getGroupAreaRect(tile).h) : tileHeight
		for( var yPos = tileYPos+1; yPos+heightToCheck-1 < (rows + heightToCheck) && (steps < smallestDistance || smallestDistance == 0); ++yPos )
		{
			++steps
			if (smallestDistance !== 0 && steps >= smallestDistance)
				break
			if ( isAreaEmpty(tileXPos, yPos, tileWidth, heightToCheck, tile) &&
				!isAreaWithinArea(tileXPos, yPos, tileXPos+tileWidth-1, yPos+heightToCheck-1, avoidX, avoidY, avoidX+avoidW-1, avoidY+avoidH-1) &&
				(!isDraggingGroup || !isAreaInAnyGroup(tileXPos, yPos, tileWidth, heightToCheck, tile.tileType == 'group' ? tile : tileGroupHeader)) )
			{
				smallestDistance = steps
				bestXPos = tileXPos
				bestYPos = yPos

				clearAreaX1 = tileXPos
				clearAreaY1 = yPos
				clearAreaX2 = tileXPos+tileWidth-1
				clearAreaY2 = yPos+heightToCheck-1

				break
			}
		}

		if(smallestDistance > 0) {
			pushTile(tile, bestXPos, bestYPos)
			return true
		}
		return false
	}

	function isAreaInAnyGroup(x, y, w, h, excludeGroup) {
		for (var i = 0; i < tileModel.length; i++) {
			var t = tileModel[i]
			if (t.tileType !== 'group') continue
			if (t === excludeGroup || t === draggedItem) continue
			var area = getGroupAreaRect(t)
			if (area.h > 0 && isAreaWithinArea(x, y, x+w-1, y+h-1, area.x1, area.y1, area.x2, area.y2)) {
				return true
			}
		}
		return false
	}

	function isAreaEmpty( x, y, w, h, tileToIgnore ) {
		for (var localX = x; localX < x+w; ++localX) {
			for (var localY = y; localY < y+h; ++localY) {
				if (localY < 0 || localX < 0 || localX >= hitBox[0].length) {
					return false  // Above or outside column bounds — invalid
				}
				if (localY >= hitBox.length) {
					continue  // Below current tile extent — genuinely empty
				}
				if (hitBox[localY][localX]) {
					if (tileToIgnore == null) {
						return false
					} else if (getTileAt(localX, localY) !== tileToIgnore) {
						if (tileToIgnore.tileType !== 'group' || !isTileInGroup(tileToIgnore, getTileAt(localX, localY))) {
							return false
						}
					}
				}
			}
		}
		return true
	}

	function getTileItem(tileData) {
		for (var i = 0; i < tileModel.length; i++) {
			if (tileModel[i] === tileData) {
				return tileModelRepeater.itemAt(i)
			}
		}
		return null
	}

	function hits(x, y, w, h, tileToIgnore, tileGroupToIgnore, allowPushing) {
		// console.log('hits', [columns,rows], [x,y,w,h], hitBox)
		for (var j = y; j < y + h; j++) {
			if (j < 0 || j >= hitBox.length) {
				continue; // Should we return true when out of bounds?
			}
			for (var k = x; k < x + w; k++) {
				if (k < 0 || k >= hitBox[j].length) {
					continue; // Should we return true when out of bounds?
				}
				if (hitBox[j][k]) {
					var hitTile = getTileAt(k,j)	// We will always want to look at the tiles top-left position
					
					// Ignore any tiles/groups specified
					if(hitTile == tileToIgnore) {
						continue;
					}
					if(tileGroupToIgnore && (hitTile == tileGroupToIgnore || draggedGroupMembers.indexOf(hitTile) >= 0 || isTileInGroup(tileGroupToIgnore, hitTile))) {
						continue;
					}

					// Handle pushing if necessary
					if( !allowPushing ) {
						return true
					} else {
						var hitTileGroupHeader = getGroupForTile(hitTile)
						// When dragging a group, push other groups as whole units (header + members together)
						if ((draggedItem && draggedItem.tileType == 'group') && (hitTile.tileType === 'group' || hitTileGroupHeader)) {
							var groupToPush = (hitTile.tileType === 'group') ? hitTile : hitTileGroupHeader
							if( !tryPushGroup(groupToPush.x, groupToPush.y, x, y, w, h) ) {
								return true
							} else {
								if (pushedTiles.indexOf(groupToPush) == -1) {
									pushedTiles.push( groupToPush )
								}
							}
						} else {
							if( !tryPushTile(hitTile.x, hitTile.y, x, y, w, h) ) {
								return true
							} else {
								if (pushedTiles.indexOf(hitTile) == -1) {
									pushedTiles.push( hitTile )
								}
							}
						}
					}
				}
			}
		}
		return false
	}

	function getTileAt(cellX, cellY) {
		for (var i = 0; i < tileModel.length; i++) {
			if (i === draggedIndex) continue
			if (draggedGroupMembers.length > 0 && draggedGroupMembers.indexOf(tileModel[i]) >= 0) continue
			var tile = tileModel[i]
			if (tileWithin(tile, cellX, cellY, cellX, cellY)) {
				return tile
			}
		}
		return null
	}

	function getTilesInArea(area) {
		var tileList = []

		// Move tiles below group label
		for (var i = 0; i < tileModel.length; i++) {
			var tile = tileModel[i]
			if (tileWithin(tile, area.x1, area.y1, area.x2, area.y2)) {
				tileList.push(tile)
			}
		}

		return tileList
	}

	function getTileLabel(tile) {
		if (tile.url) {
			var app = appsModel.tileGridModel.getApp(tile.url)
			var labelText = tile.label || app.display || app.url || ""
			return labelText
		} else {
			return ""
		}
	}
	function sortGroupTiles(groupTile) {
		var area = getGroupAreaRect(groupTile)
		var tileList = getTilesInArea(area)

		var cursorX = groupTile.x
		var cursorY = groupTile.y + groupTile.h
		var rowH = 0
		tileList.sort(function(a, b) {
			var aLabel = getTileLabel(a)
			var bLabel = getTileLabel(b)
			return aLabel.localeCompare(bLabel)
		})

		for (var i = 0; i < tileList.length; i++) {
			var tile = tileList[i]
			var tileX2 = cursorX + tile.w - 1

			// If there's not enough room on this row
			if (tileX2 > area.x2) {
				// Move to the next row
				cursorX = groupTile.x
				cursorY += rowH
			}

			tile.x = cursorX
			tile.y = cursorY
			rowH = Math.max(rowH, tile.h)
			cursorX += tile.w
		}

		// We call this in moveTile so no need to duplicate work.
		tileGrid.tileModelChanged()
	}

	QQC2.ScrollView {
		id: scrollView
		anchors.fill: parent

		readonly property int scrollTop: scrollFlickable.contentY
		readonly property int scrollHeight: scrollFlickable.contentHeight
		readonly property int scrollTopAtBottom: Math.max(0, scrollHeight - scrollFlickable.height)
		readonly property bool scrollAtTop: scrollTop == 0
		readonly property bool scrollAtBottom: scrollTop >= scrollTopAtBottom

		function scrollBy(deltaY) {
			scrollFlickable.contentY = Math.max(0, Math.min(scrollTop + deltaY, scrollTopAtBottom))
		}

		Flickable {
			id: scrollFlickable
			anchors.fill: parent
			contentWidth: scrollItem.width
			contentHeight: scrollItem.height
			clip: true

			QQC2.ScrollBar.vertical: QQC2.ScrollBar {
				parent: scrollView
				anchors.top: scrollView.top
				anchors.right: scrollView.right
				anchors.bottom: scrollView.bottom
				policy: QQC2.ScrollBar.AsNeeded
			}

			Item {
				id: scrollItem

				width: columns * cellBoxSize
				height: rows * cellBoxSize

				// Rectangle {
				// 	anchors.fill: parent
				// 	color: "#88336699"
				// }

				Repeater {
					id: cellRepeater
					readonly property int cellCount: columns * rows
					onCellCountChanged: {
						if (!isDragging) {
							model = cellCount
						}
					}
					model: 0

					Item {
						id: cellItem
						property int modelX: modelData % columns
						property int modelY: Math.floor(modelData / columns)
						x: modelX * cellBoxSize
						y: modelY * cellBoxSize
						width: cellBoxSize
						height: cellBoxSize

						readonly property bool tileHovered: (hasDrag
							&& dropHoverX <= modelX && modelX < dropHoverX + dropWidth
							&& dropHoverY <= modelY && modelY < dropHoverY + dropHeight
						)
						readonly property bool groupAreaHovered: {
							if (isDraggingGroup) {
								var groupX1 = dropHoverX
								var groupY1 = dropHoverY + dropHeight
								var groupX2 = groupX1 + draggedGroupRect.w - 1
								var groupY2 = groupY1 + draggedGroupRect.h - 1
								return groupX1 <= modelX && modelX <= groupX2
									&& groupY1 <= modelY && modelY <= groupY2
							} else {
								return false
							}
						}

						Rectangle {
							anchors.fill: parent
							anchors.margins: cellMargin
							color: {
								if (cellItem.groupAreaHovered || cellItem.tileHovered) {
									if (canDrop) {
										return "#88336699"
									} else {
										return "#88880000"
									}
								} else if (cellItem.groupAreaHovered) {
									return "#8848395d" // purple
								} else {
									return "transparent"
								}
							}
							border.width: 1
							border.color: tileGrid.editing ? "#44000000" : "transparent"
						}

						MouseArea {
							anchors.fill: parent
							acceptedButtons: Qt.RightButton
							onClicked: function(mouse) {
								if (mouse.button == Qt.RightButton) {
									cellContextMenu.cellX = cellItem.modelX
									cellContextMenu.cellY = cellItem.modelY
									var pos = mapToItem(scrollItem, mouse.x, mouse.y) // cellContextMenu is a child of scrollItem
									cellContextMenu.open(pos.x, pos.y)
								}
							}

						}
					}
				}
				PlasmaExtras.Menu {
					id: cellContextMenu
					property int cellX: -1
					property int cellY: -1

					PlasmaExtras.MenuItem {
						icon: "group-new"
						text: i18n("New Group")
						visible: !plasmoid.configuration.tilesLocked
						onClicked: {
							var tile = tileGrid.addGroup(cellContextMenu.cellX, cellContextMenu.cellY)
							tileGrid.editTile(tile)
						}
					}

					TileGridPresets {
						id: tileGridPresets
						visible: !plasmoid.configuration.tilesLocked
					}

					PlasmaExtras.MenuItem {
						icon: plasmoid.configuration.tilesLocked ? "object-unlocked" : "object-locked"
						text: plasmoid.configuration.tilesLocked ? i18n("Unlock Tiles") : i18n("Lock Tiles")
						onClicked: {
							plasmoid.configuration.tilesLocked = !plasmoid.configuration.tilesLocked
						}
					}
				}

				Repeater {
					id: tileModelRepeater
					model: tileModel
					// onCountChanged: console.log('onCountChanged', count)
					
					TileItem {
						id: tileItem
					}	
				}
			}
		} // Flickable
	}

	Loader {
		id: tileGridSplashLoader
		anchors.centerIn: parent
		active: tileModel.length == 0 && !tileGrid.editing
		visible: active && width <= parent.width
		source: "TileGridSplash.qml"
		property alias tileGridPresets: tileGridPresets
		property int maxWidth: parent.width
	}

	/* Scroll on hover with drag */
	property int scrollAreaTickDelta: cellBoxSize
	property int scrollAreaTickInterval: 200
	property int scrollAreaSize: Math.min(cellBoxSize * 1.5, scrollView.height / 5) // 20vh or 90pt

	Item {
		id: scrollUpArea
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: parent.top
		height: scrollAreaSize
		property bool active: !scrollView.scrollAtTop
		property bool containsDrag: false
		property bool ticking: active && containsDrag

		function checkContains(event) {
			containsDrag = scrollUpArea.contains(Qt.point(event.x, event.y))
		}

		Timer {
			id: scrollUpTicker
			interval: scrollAreaTickInterval
			repeat: true
			running: parent.ticking
			onTriggered: {
				scrollView.scrollBy(-scrollAreaTickDelta)
			}
		}

		Rectangle {
			anchors.fill: parent
			opacity: parent.ticking ? 1 : 0
			gradient: Gradient {
				GradientStop { position: 0.0; color: Kirigami.Theme.highlightColor }
				GradientStop { position: 0.3; color: "transparent" }
			}
		}
	}

	Item {
		id: scrollDownArea
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		height: scrollAreaSize
		property bool active: !scrollView.scrollAtBottom
		property bool containsDrag: false
		property bool ticking: active && containsDrag

		function checkContains(event) {
			var mouseY = event.y - (parent.height - height)
			containsDrag = scrollDownArea.contains(Qt.point(event.x, mouseY))
		}

		Timer {
			id: scrollDownTicker
			interval: scrollAreaTickInterval
			repeat: true
			running: parent.ticking
			onTriggered: {
				scrollView.scrollBy(scrollAreaTickDelta)
			}
		}

		Rectangle {
			anchors.fill: parent
			opacity: parent.ticking ? 1 : 0
			gradient: Gradient {
				GradientStop { position: 0.7; color: "transparent" }
				GradientStop { position: 1.0; color: Kirigami.Theme.highlightColor }
			}
		}
	}

	function newTile(url) {
		return {
			"x": 0,
			"y": 0,
			"w": 2,
			"h": 2,
			"url": url,
		}
	}

	function removeIndex(i) {
		tileModel.splice(i, 1) // remove 1 item at index
		tileModelChanged()
	}

	function removeApp(url) {
		var removedCount = 0
		for (var i = tileModel.length - 1; i >= 0; i--) {
			var tile = tileModel[i]
			if (tile.url == url) {
				removedCount += 1
				tileModel.splice(i, 1) // remove 1 item at index
			}
		}
		if (removedCount > 0) {
			tileModelChanged()
		}
	}

	function findOpenPos(w, h) {
		for (var y = 0; y < rows; y++) {
			for (var x = 0; x < columns - (w-1); x++) {
				if (hits(x, y, w, h))
					continue

				// Room open for
				return {
					x: x,
					y: y,
				}
			}
		}

		// Current grid has no room.
		// Add to new row.
		return {
			x: 0,
			y: rows
		}
	}

	function parseTileXY(tile, x, y) {
		if (typeof x !== "undefined" && typeof y !== "undefined") {
			tile.x = x
			tile.y = y
		} else {
			var openPos = findOpenPos(tile.w, tile.h)
			tile.x = openPos.x
			tile.y = openPos.y
		}
	}
	function addApp(url, x, y) {
		url = Utils.parseDropUrl(url)
		var tile = newTile(url)
		parseTileXY(tile, x, y)
		tileModel.push(tile)
		tileModelChanged()
		return tile
	}

	function hasAppTile(url) {
		for (var i = 0; i < tileModel.length; i++) {
			var tile = tileModel[i]
			if (tile.url == url) {
				return true
			}
		}
		return false
	}

	function limit(minValue, value, maxValue) {
		return Math.max(minValue, Math.min(value, maxValue))
	}

	function addTile(x, y, props) {
		var tile = newTile("")
		parseTileXY(tile, x, y)
		if (typeof props !== "undefined") {
			var keys = Object.keys(props)
			for (var i = 0; i < keys.length; i++) {
				var key = keys[i]
				var value = props[key]
				tile[key] = value
			}
		}
		tileModel.push(tile)
		tileModelChanged()
		return tile
	}

	function addGroup(x, y, props) {
		var groupProps = {
			tileType: "group",
			label: i18nc("default group label", "Group"),
			w: limit(2, columns-x, 6), // 6 unless we have less columns.
			h: 1,
		}
		if (typeof props !== "undefined") {
			var keys = Object.keys(props)
			for (var i = 0; i < keys.length; i++) {
				var key = keys[i]
				var value = props[key]
				groupProps[key] = value
			}
		}
		return addTile(x, y, groupProps)
	}

	// Use for quickly testing on widget load
	function addDefaultTiles() {
		tileGridPresets.addDefault()
	}

	signal editTile(var tile)
}
