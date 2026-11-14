import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.draganddrop as DragAndDrop
import "Utils.js" as Utils

DropArea {
	id: tileGrid

	// ============================================================
	// Grid Size Properties
	// ============================================================

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

	// ============================================================
	// Drag State Properties
	// ============================================================

	property bool isDragging: false
	property var addedItem: null
	readonly property bool adding: addedItem !== null
	property int draggedIndex: -1
	readonly property var draggedItem: draggedIndex >= 0 ? tileModel[draggedIndex] : null
	property bool editing: (isDragging && draggedItem) || adding
	property int dropHoverX: -1
	property int dropHoverY: -1
	property int dropOffsetX: 0
	property int dropOffsetY: 0
	readonly property int dropWidth: draggedItem ? draggedItem.w : addedItem ? addedItem.w : 0
	readonly property int dropHeight: draggedItem ? draggedItem.h : addedItem ? addedItem.h : 0
	property bool canDrop: false
	readonly property bool hasDrag: editing && dropHoverX >= 0 && dropHoverY >= 0
	readonly property bool isDraggingGroup: hasDrag && draggedItem && draggedItem.tileType === "group"
	readonly property bool dynamicPusher: config.dynamicTilePusher

	property var draggedGroupMembers: []
	property int draggedGroupContentHeight: 0
	property var draggedItemOriginalGroup: null

	readonly property var draggedGroupRect: isDraggingGroup ? getGroupContentRect(draggedItem) : null

	// ============================================================
	// Drop Event Handlers
	// ============================================================

	onEntered: drag => { dragTick(drag) }
	onPositionChanged: drag => { dragTick(drag) }
	onExited: drag => { cancelDragHover() }
	onDropped: drop => {
		dragTick(drop)
		if (canDrop) {
			if (draggedItem) {
				commitMove(draggedItem, dropHoverX, dropHoverY)
			} else if (addedItem) {
				addedItem.x = dropHoverX
				addedItem.y = dropHoverY
				tileModel.push(addedItem)
				tileModelChanged()
			}
			clearAllSnapbacks()
		} else {
			snapbackAll()
			clearAllSnapbacks()
		}
		resetDrag()
	}

	// ============================================================
	// Section 1: Geometry Helpers
	// ============================================================

	function makeRect(x, y, w, h) {
		return { x1: x, y1: y, x2: x + w - 1, y2: y + h - 1 }
	}

	function rectsOverlap(a, b) {
		return a.x1 <= b.x2 && b.x1 <= a.x2 && a.y1 <= b.y2 && b.y1 <= a.y2
	}

	// ============================================================
	// Section 2: Group Utilities
	// ============================================================

	// Group membership frozen at drag start: [{ group, members }] (null when not dragging)
	property var frozenGroups: null

	function frozenMembersOf(groupTile) {
		for (var i = 0; i < frozenGroups.length; i++) {
			if (frozenGroups[i].group === groupTile) return frozenGroups[i].members
		}
		return []
	}

	function getGroupContentRect(groupTile) {
		// Returns the bounding rect of all content tiles below the group header.
		// Stops at the first empty row within the group's column span, or at another group header.
		if (!groupTile) {
			return { x1: 0, y1: 0, x2: -1, y2: -1, w: 0, h: 0 }
		}

		var colX1 = groupTile.x
		var colX2 = groupTile.x + groupTile.w - 1
		var startY = groupTile.y + groupTile.h

		if (frozenGroups) {
			var fm = frozenMembersOf(groupTile)
			var fy2 = startY - 1
			for (var f = 0; f < fm.length; f++) fy2 = Math.max(fy2, fm[f].y + fm[f].h - 1)
			return { x1: colX1, y1: startY, x2: colX2, y2: fy2, w: colX2 - colX1 + 1, h: fy2 - startY + 1 }
		}

		var occupiedRows = {}
		for (var i = 0; i < tileModel.length; i++) {
			var t = tileModel[i]
			if (t === groupTile) continue
			if (i === draggedIndex) continue
			if (draggedGroupMembers.length > 0 && draggedGroupMembers.indexOf(t) >= 0) continue
			if (isNaN(t.x) || isNaN(t.y)) continue
			if (t.x > colX2 || t.x + t.w - 1 < colX1) continue
			if (t.y < startY) continue
			if (t.tileType === 'group') continue  // Another group header is a boundary

			for (var row = t.y; row < t.y + t.h; row++) {
				occupiedRows[row] = true
			}
		}

		// Walk down from startY; stop at first empty row
		var y2 = startY - 1
		for (var row = startY; occupiedRows[row]; row++) {
			y2 = row
		}

		if (y2 < startY) {
			return { x1: colX1, y1: startY, x2: colX2, y2: startY - 1, w: colX2 - colX1 + 1, h: 0 }
		}
		return {
			x1: colX1, y1: startY,
			x2: colX2, y2: y2,
			w: colX2 - colX1 + 1, h: y2 - startY + 1,
		}
	}

	// Legacy alias used by AppObject.qml
	function getGroupAreaRect(groupTile, tileToExclude) {
		return getGroupContentRect(groupTile)
	}

	function getGroupFullHeight(groupTile) {
		var content = getGroupContentRect(groupTile)
		return groupTile.h + content.h
	}

	function isTileInGroup(groupTile, tile) {
		// Per spec: tile's leftmost column within group's column span,
		// and tile's top is within the group's connected content rows.
		if (!groupTile || !tile || tile === groupTile) return false
		if (frozenGroups) return frozenMembersOf(groupTile).indexOf(tile) >= 0
		if (tile.x < groupTile.x || tile.x > groupTile.x + groupTile.w - 1) return false
		var content = getGroupContentRect(groupTile)
		return content.h > 0 && tile.y >= content.y1 && tile.y <= content.y2
	}

	function getGroupForTile(tile) {
		if (!tile) return null
		for (var i = 0; i < tileModel.length; i++) {
			// The dragged item's model position is stale until the drop (other
			// items may have been pushed into its old area), so it owns nothing.
			if (i === draggedIndex) continue
			var t = tileModel[i]
			if (t.tileType === 'group' && t !== tile && isTileInGroup(t, tile)) {
				return t
			}
		}
		return null
	}

	function getHoverGroup(hoverX, hoverY, hoverH) {
		// Returns the group (if any) whose column span contains hoverX and
		// whose area (header + content) overlaps the hover Y range.
		for (var i = 0; i < tileModel.length; i++) {
			var t = tileModel[i]
			if (i === draggedIndex) continue
			if (t.tileType !== 'group') continue
			if (hoverX < t.x || hoverX > t.x + t.w - 1) continue
			var groupBottom = t.y + getGroupFullHeight(t) - 1
			if (hoverY > groupBottom || hoverY + hoverH - 1 < t.y) continue
			return t
		}
		return null
	}

	// ============================================================
	// Section 3: Hitbox (Spatial Index)
	// ============================================================

	property var hitbox: []  // hitbox[y][x] = tile reference (or undefined)
	property var hitBox: hitbox  // Legacy alias

	function rebuildHitbox() {
		var maxC = 0
		var maxR = 0
		var maxW = 1
		var maxH = 1
		for (var i = 0; i < tileModel.length; i++) {
			var t = tileModel[i]
			if (isNaN(t.x) || isNaN(t.y) || t.x === null || t.y === null) continue
			maxC = Math.max(maxC, t.x + t.w)
			maxR = Math.max(maxR, t.y + t.h)
			maxW = Math.max(maxW, t.w)
			maxH = Math.max(maxH, t.h)
		}

		if (draggedItem) maxR += draggedItem.h  // Extra rows to allow drag-to-bottom

		maxColumn = maxC
		maxRow = maxR
		maxWidth = maxW
		maxHeight = maxH

		var cols = Math.max(minColumns, maxC)
		var numRows = Math.max(minRows, maxR)

		var hb = []
		for (var j = 0; j < numRows; j++) {
			hb.push(new Array(cols))
		}

		for (var i = 0; i < tileModel.length; i++) {
			if (i === draggedIndex) continue
			if (draggedGroupMembers.length > 0 && draggedGroupMembers.indexOf(tileModel[i]) >= 0) continue
			var t = tileModel[i]
			if (isNaN(t.x) || isNaN(t.y) || t.x === null || t.y === null) continue
			for (var j = t.y; j < t.y + t.h && j < numRows; j++) {
				for (var k = t.x; k < t.x + t.w && k < cols; k++) {
					hb[j][k] = t
				}
			}
		}

		hitbox = hb
	}

	function getTileAtCell(cx, cy) {
		if (cy < 0 || cy >= hitbox.length) return null
		if (!hitbox[cy] || cx < 0 || cx >= hitbox[cy].length) return null
		return hitbox[cy][cx] || null
	}

	// Legacy alias
	function getTileAt(cx, cy) { return getTileAtCell(cx, cy) }

	function isRectFree(x, y, w, h, ignoreSet) {
		// Returns true if all cells in the rect are empty or occupied only by tiles in ignoreSet
		// (groups in ignoreSet also implicitly cover their members)
		for (var j = y; j < y + h; j++) {
			for (var k = x; k < x + w; k++) {
				if (k < 0 || j < 0) return false
				if (j >= hitbox.length || !hitbox[j] || k >= hitbox[j].length) continue
				var t = hitbox[j][k]
				if (!t) continue
				if (!ignoreSet) return false
				if (ignoreSet.indexOf(t) >= 0) continue
				// Check if t is a member of any ignored group
				var ignored = false
				for (var ig = 0; ig < ignoreSet.length; ig++) {
					if (ignoreSet[ig].tileType === 'group' && isTileInGroup(ignoreSet[ig], t)) {
						ignored = true
						break
					}
				}
				if (!ignored) return false
			}
		}
		return true
	}

	// ============================================================
	// Section 4: Animation
	// ============================================================

	function animateTileTo(tile, newX, newY) {
		if (!tile || isNaN(newX) || isNaN(newY)) return
		var deltaX = newX - tile.x
		var deltaY = newY - tile.y
		if (deltaX === 0 && deltaY === 0) return

		if (tile.tileType === 'group') {
			animateGroupMembersBy(tile, deltaX, deltaY)
		}

		var idx = tileModel.indexOf(tile)
		var item = idx >= 0 ? tileModelRepeater.itemAt(idx) : null
		if (item) {
			item.targetX = newX * cellBoxSize
			item.targetY = newY * cellBoxSize
		}
		tile.x = newX
		tile.y = newY
		rebuildHitbox()
	}

	function animateGroupMembersBy(groupTile, deltaX, deltaY) {
		// Animate all member tiles of a group by (deltaX, deltaY)
		if (groupTile === draggedItem && draggedGroupMembers.length > 0) {
			for (var i = 0; i < draggedGroupMembers.length; i++) {
				var m = draggedGroupMembers[i]
				var idx = tileModel.indexOf(m)
				var item = idx >= 0 ? tileModelRepeater.itemAt(idx) : null
				if (item) {
					item.targetX = (m.x + deltaX) * cellBoxSize
					item.targetY = (m.y + deltaY) * cellBoxSize
				}
				m.x += deltaX
				m.y += deltaY
			}
			return
		}

		// Collect members before moving any of them: membership is derived from
		// positions, so moving members one at a time can make tiles below the
		// group look like members (and get dragged along) mid-loop.
		var members = []
		for (var i = 0; i < tileModel.length; i++) {
			var t = tileModel[i]
			if (t === groupTile || t === draggedItem) continue
			if (draggedGroupMembers.indexOf(t) >= 0) continue
			if (isTileInGroup(groupTile, t)) members.push(i)
		}
		for (var m = 0; m < members.length; m++) {
			var t = tileModel[members[m]]
			var item = tileModelRepeater.itemAt(members[m])
			if (item) {
				item.targetX = (t.x + deltaX) * cellBoxSize
				item.targetY = (t.y + deltaY) * cellBoxSize
			}
			t.x += deltaX
			t.y += deltaY
			// A member pushed within its group keeps its offset when the group moves
			var e = getPushedEntry(t)
			if (e) { e.origX += deltaX; e.origY += deltaY }
		}
	}

	// ============================================================
	// Section 5: Push Tracking
	// ============================================================

	property var pushedItems: []  // Array of { tile, origX, origY, pusher, cascadeDir }

	function getPushedEntry(tile) {
		for (var i = 0; i < pushedItems.length; i++) {
			if (pushedItems[i].tile === tile) return pushedItems[i]
		}
		return null
	}

	function recordPush(tile, pusher, cascadeDir) {
		// Save tile's current position as its pre-push origin (only on first push).
		// `pusher` is set for tiles moved by a cascade: the item whose vertical push
		// shoved them along, and `cascadeDir` the direction (1 = down, -1 = up).
		// Their snapback follows that item (see attemptSnapback).
		if (!getPushedEntry(tile)) {
			pushedItems.push({
				tile: tile, origX: tile.x, origY: tile.y,
				pusher: pusher || null, cascadeDir: cascadeDir || 0,
			})
		}
	}

	// ============================================================
	// Section 6: Push Logic
	// ============================================================

	function buildIgnoreSet(tile) {
		// The set of tiles that should be ignored when checking if a push destination is free
		var ignore = [tile]
		if (tile.tileType === 'group') {
			for (var i = 0; i < tileModel.length; i++) {
				if (isTileInGroup(tile, tileModel[i])) ignore.push(tileModel[i])
			}
		}
		return ignore
	}

	function findPushSteps(tile, startX, startY, effectiveH, direction, avoidRect, ignoreSet) {
		// Returns the minimum number of steps to move tile from (startX, startY) in the
		// given direction to a free position (not overlapping avoidRect). -1 if not possible.
		var tx = startX, ty = startY
		var tw = tile.w

		for (var steps = 1; steps <= 64; steps++) {
			var nx = tx, ny = ty
			if (direction === 'right') nx = tx + steps
			else if (direction === 'left') nx = tx - steps
			else if (direction === 'up') ny = ty - steps
			else ny = ty + steps  // down

			// Boundary checks (grid does not expand horizontally)
			if (nx < 0 || ny < 0) return -1
			if ((direction === 'right') && nx + tw > columns) return -1
			if ((direction === 'left') && nx < 0) return -1
			if ((direction === 'up') && ny < 0) return -1
			// Down: no upper bound (grid extends vertically)

			// Skip positions that overlap the avoid area
			if (avoidRect && rectsOverlap(makeRect(nx, ny, tw, effectiveH), avoidRect)) continue

			if (isRectFree(nx, ny, tw, effectiveH, ignoreSet)) {
				return steps
			}
		}
		return -1
	}

	function findDownPushSteps(tile, effectiveH, avoidRect) {
		// Down push is always possible (grid extends); find min steps clear of avoidRect.
		if (!avoidRect) return 1
		for (var steps = 1; steps <= 64; steps++) {
			if (!rectsOverlap(makeRect(tile.x, tile.y + steps, tile.w, effectiveH), avoidRect)) {
				return steps
			}
		}
		return 1
	}

	function getItemHeight(item) {
		return item.tileType === 'group' ? getGroupFullHeight(item) : item.h
	}

	function planUpCascade(tile, startX, startY, effectiveH, avoidRect, ignoreSet) {
		// Plan moving tile up from (startX, startY) just far enough to clear avoidRect,
		// shoving anything in its way up as well (recursively; gaps above are used up
		// before anything further up has to move). Nothing may be pushed above row 0.
		// Returns { x, y, steps, cascade: [{ item, delta, pusher }] } or null.
		var steps = avoidRect ? startY + effectiveH - avoidRect.y1 : 1
		if (avoidRect && (startX > avoidRect.x2 || startX + tile.w - 1 < avoidRect.x1)) steps = 1
		steps = Math.max(1, steps)
		if (startY - steps < 0) return null

		var rootGroup = tile.tileType === 'group' ? null : getGroupForTile(tile)

		// Every planned item, root first. `from`/`top` are its current/planned top rows.
		var plan = [{ item: tile, x: startX, from: startY, top: startY - steps, h: effectiveH, ignore: ignoreSet, pusher: null }]

		function ownedByPlan(t) {
			for (var p = 0; p < plan.length; p++) if (plan[p].ignore.indexOf(t) >= 0) return true
			return false
		}
		function plannedRect(P) {
			return makeRect(P.x, P.top, P.item.w, P.h)
		}

		// Grow the plan until nothing overlaps: tops only ever decrease, so this settles.
		for (var pass = 0; pass < 64; pass++) {
			var changed = false
			for (var i = 0; i < plan.length; i++) {
				var P = plan[i]
				if (P.top < 0) return null

				// Planned items are judged at their new positions: the upper one yields.
				for (var q = 0; q < plan.length; q++) {
					var Q = plan[q]
					if (Q === P || Q.from >= P.from) continue
					if (rectsOverlap(plannedRect(P), plannedRect(Q))) {
						Q.top = P.top - Q.h
						Q.pusher = P.item
						changed = true
					}
				}

				// Unplanned items in the way join the plan.
				for (var j = P.top; j < P.top + P.h; j++) {
					for (var k = P.x; k < P.x + P.item.w; k++) {
						var hit = getTileAtCell(k, j)
						if (!hit || ownedByPlan(hit)) continue

						// Resolve to the item that has to move: groups move as a unit,
						// except siblings within the root tile's own group.
						var item = hit
						if (hit.tileType !== 'group') {
							var grp = getGroupForTile(hit)
							if (grp && grp !== rootGroup) item = grp
						}
						if (item === rootGroup) return null  // Would have to push its own group
						if (item.tileType === 'group') {
							for (var m = 0; m < plan.length; m++) {
								if (isTileInGroup(item, plan[m].item)) return null
							}
						}

						var h = getItemHeight(item)
						plan.push({
							item: item, x: item.x, from: item.y, top: Math.min(item.y, P.top - h), h: h,
							ignore: buildIgnoreSet(item), pusher: P.item,
						})
						changed = true
					}
				}
			}
			if (!changed) break
		}
		for (var r = 0; r < plan.length; r++) {
			if (plan[r].top < 0) return null
		}

		var cascade = []
		for (var c = 1; c < plan.length; c++) {
			cascade.push({ item: plan[c].item, delta: plan[c].from - plan[c].top, pusher: plan[c].pusher })
		}
		return { x: startX, y: startY - steps, steps: steps, cascade: cascade }
	}

	function findPushOption(tile, startX, startY, effectiveH, avoidRect, ignoreSet) {
		// Closest way out of avoidRect from (startX, startY): a free spot to the Right
		// or Left, or an Up push that cascades whatever is above (tiebreak R>L>U).
		// Returns { x, y, steps, cascade? } or null.
		var best = null
		var dirs = ['right', 'left']
		for (var d = 0; d < dirs.length; d++) {
			var steps = findPushSteps(tile, startX, startY, effectiveH, dirs[d], avoidRect, ignoreSet)
			if (steps < 0) continue
			if (best !== null && steps >= best.steps) continue
			best = { x: startX + (dirs[d] === 'right' ? steps : -steps), y: startY, steps: steps }
		}
		var up = planUpCascade(tile, startX, startY, effectiveH, avoidRect, ignoreSet)
		if (up && (best === null || up.steps < best.steps)) best = up
		return best
	}

	function applyUpCascade(cascade) {
		// Move the planned items topmost first, so each one moves into space that
		// has already been vacated (and group membership isn't disturbed mid-way).
		cascade.sort(function(a, b) { return a.item.y - b.item.y })
		for (var i = 0; i < cascade.length; i++) {
			var c = cascade[i]
			recordPush(c.item, c.pusher, -1)
			animateTileTo(c.item, c.item.x, c.item.y - c.delta)
		}
	}

	function tryPushItem(tile, avoidRect) {
		// Push tile out of avoidRect. Right/Left/Up (closest, tiebreak R>L>U) are
		// always preferred; Down is the last resort because it cascades everything
		// below. Up cascades too, but only shoves what is actually in the way and
		// only if that fits below row 0. Returns true if the push succeeded.
		var effectiveH = tile.tileType === 'group' ? getGroupFullHeight(tile) : tile.h
		var ignoreSet = buildIgnoreSet(tile)

		var spot = findPushOption(tile, tile.x, tile.y, effectiveH, avoidRect, ignoreSet)

		// betterOption: an already-pushed item may find a spot that is closer to
		// where it was pushed from (its pushedFrom position) than the one found
		// from its current, already displaced, position.
		var entry = getPushedEntry(tile)
		var origX = entry ? entry.origX : tile.x
		var origY = entry ? entry.origY : tile.y
		if (origX !== tile.x || origY !== tile.y) {
			var fromOrig = findPushOption(tile, origX, origY, effectiveH, avoidRect, ignoreSet)
			if (fromOrig && (!spot
					|| Math.abs(fromOrig.x - origX) + Math.abs(fromOrig.y - origY)
					 < Math.abs(spot.x - origX) + Math.abs(spot.y - origY))) {
				spot = fromOrig
			}
		}

		recordPush(tile)

		if (spot) {
			// Anything this item cascaded earlier is free to snap back now that it
			// has moved out of the way (see attemptSnapback / pusher).
			if (spot.cascade) applyUpCascade(spot.cascade)
			animateTileTo(tile, spot.x, spot.y)
			return true
		}

		// Down: cascade push everything below the tile's current extent
		var downSteps = findDownPushSteps(tile, effectiveH, avoidRect)
		var fromY = tile.y + effectiveH
		cascadePushDown(tile.x, tile.x + tile.w - 1, fromY, downSteps, ignoreSet, tile)
		animateTileTo(tile, tile.x, tile.y + downSteps)
		return true
	}

	function cascadePushDown(colX1, colX2, fromY, delta, ignoreSet, pusher) {
		// Push everything in columns [colX1..colX2] whose effective bottom is at y >= fromY
		// down by delta. If a tile is a group member, push the whole group instead.
		// An item wider than the range pushes what lies below it in its extra columns
		// too, so the cascade spreads sideways as needed (gaps are preserved).
		// `pusher` is the item whose down-push caused this cascade.
		var toMove = []
		// Siblings of a tile pushed within its own group move individually; moving
		// their group would drag the pusher (and its pushed position) along too.
		var pusherGroup = pusher && pusher.tileType !== 'group' ? getGroupForTile(pusher) : null

		// colFrom[c]: rows >= this in column c are moving down
		var colFrom = {}
		for (var c = colX1; c <= colX2; c++) colFrom[c] = fromY

		function reachesCascade(item) {
			var bottom = item.y + getItemHeight(item) - 1
			for (var c = item.x; c < item.x + item.w; c++) {
				if (colFrom[c] !== undefined && bottom >= colFrom[c]) return true
			}
			return false
		}

		for (var pass = 0; pass < 64; pass++) {
			var changed = false
			for (var i = 0; i < tileModel.length; i++) {
				var t = tileModel[i]
				if (i === draggedIndex) continue
				if (draggedGroupMembers.indexOf(t) >= 0) continue
				if (ignoreSet && ignoreSet.indexOf(t) >= 0) continue
				if (t === pusherGroup) continue  // Its content reaches below, but it holds the pusher

				var itemToMove = t
				if (t.tileType !== 'group') {
					var grp = getGroupForTile(t)
					if (grp && grp !== pusherGroup) {
						if (ignoreSet && ignoreSet.indexOf(grp) >= 0) continue
						itemToMove = grp
					}
				}
				if (toMove.indexOf(itemToMove) >= 0) continue
				if (!reachesCascade(itemToMove)) continue

				toMove.push(itemToMove)
				for (var c = itemToMove.x; c < itemToMove.x + itemToMove.w; c++) {
					if (colFrom[c] === undefined || itemToMove.y < colFrom[c]) colFrom[c] = itemToMove.y
				}
				changed = true
			}
			if (!changed) break
		}

		// Move bottom-most items first to avoid cascading into each other
		toMove.sort(function(a, b) { return b.y - a.y })

		for (var i = 0; i < toMove.length; i++) {
			recordPush(toMove[i], pusher, 1)
			animateTileTo(toMove[i], toMove[i].x, toMove[i].y + delta)
		}
	}

	// ============================================================
	// Section 7: Collision Detection
	// ============================================================

	function findFirstConflict(x, y, w, h, tileGroupToIgnore) {
		// Returns the first tile in the hitbox that occupies the rect (x, y, w, h)
		// and is not the dragged group header or one of its pre-captured members.
		for (var j = y; j < y + h; j++) {
			if (j < 0 || j >= hitbox.length) continue
			for (var k = x; k < x + w; k++) {
				if (k < 0 || !hitbox[j] || k >= hitbox[j].length) continue
				var hitTile = hitbox[j][k]
				if (!hitTile) continue
				if (tileGroupToIgnore) {
					if (hitTile === tileGroupToIgnore) continue
					if (draggedGroupMembers.indexOf(hitTile) >= 0) continue
					// Note: do NOT use isTileInGroup(tileGroupToIgnore, hitTile) here —
					// that check uses the dragged group's stale model position and would
					// falsely skip tiles that were pushed into the dragged group's original
					// area, allowing overlaps.
				}
				return hitTile
			}
		}
		return null
	}

	function resolvePushTarget(hitTile, hoverGroupTile) {
		// Determines the actual item to push when hitTile is in the way.
		// - Dragging a group: push other groups as whole units; push standalone tiles individually.
		// - Hover inside a group: push tiles within that group individually; push other groups whole.
		// - Hover outside any group: push whole groups; push standalone tiles individually.
		if (isDraggingGroup) {
			if (hitTile.tileType === 'group') return hitTile
			return getGroupForTile(hitTile) || hitTile
		}

		if (hoverGroupTile) {
			if (isTileInGroup(hoverGroupTile, hitTile)) return hitTile
			if (hitTile.tileType === 'group') return hitTile
			return getGroupForTile(hitTile) || hitTile
		}

		if (hitTile.tileType === 'group') return hitTile
		return getGroupForTile(hitTile) || hitTile
	}

	function checkAndPushCollisions(x, y, w, h, tileGroupToIgnore) {
		// Checks if the rect (x, y, w, h) is clear of obstacles.
		// If dynamicPusher is enabled, tries to push conflicting items.
		// Returns true if the area is blocked (cannot be cleared).
		if (!dynamicPusher) {
			return findFirstConflict(x, y, w, h, tileGroupToIgnore) !== null
		}

		var avoidRect = makeRect(x, y, w, h)
		var hoverGroupTile = getHoverGroup(x, y, h)

		var maxIterations = 20
		for (var iter = 0; iter < maxIterations; iter++) {
			var conflict = findFirstConflict(x, y, w, h, tileGroupToIgnore)
			if (!conflict) return false  // Area is clear

			var itemToPush = resolvePushTarget(conflict, hoverGroupTile)
			if (!tryPushItem(itemToPush, avoidRect)) {
				return true  // Push failed — area is blocked
			}
			// Push succeeded; hitbox was rebuilt in animateTileTo — retry
		}

		return true  // Exceeded iterations — treat as blocked
	}

	// Legacy compatibility
	function hits(x, y, w, h, tileToIgnore, tileGroupToIgnore, allowPushing) {
		return checkAndPushCollisions(x, y, w, h, tileGroupToIgnore)
	}

	function isAreaWithinArea(a1x1, a1y1, a1x2, a1y2, a2x1, a2y1, a2x2, a2y2) {
		return a2x1 <= a1x2 && a1x1 <= a2x2 && a2y1 <= a1y2 && a1y1 <= a2y2
	}

	function tileWithin(tile, x1, y1, x2, y2) {
		return tile.x <= x2 && tile.x + tile.w - 1 >= x1 && tile.y <= y2 && tile.y + tile.h - 1 >= y1
	}

	// ============================================================
	// Section 8: Snapback
	// ============================================================

	function snapTargetOf(entry) {
		// Where a pushed tile should return to now: its origin, except that a
		// cascaded tile may only return as far as its pusher has returned, so the
		// spacing between them is kept. Otherwise it would close the gap below
		// (or above) a still-displaced group and get absorbed into it.
		var x = entry.origX, y = entry.origY
		if (entry.pusher) {
			var pusherEntry = getPushedEntry(entry.pusher)
			if (pusherEntry) {
				var pusherOffset = entry.pusher.y - pusherEntry.origY
				if (pusherOffset * entry.cascadeDir > 0) y += pusherOffset
			}
		}
		return { x: x, y: y, isFinal: x === entry.origX && y === entry.origY }
	}

	function snapPieces(tile, ignoreSet, membersToTargets) {
		// The rects that make up an item, relative to its current position: a tile
		// is one piece; a group is its header plus each member tile (not its whole
		// bounding box: the dragged tile may sit in a hole inside the content).
		// With membersToTargets, members that were pushed within the group are
		// placed at their own snapback targets, so the group and its displaced
		// members can return together (neither has to wait for the other).
		var pieces = [{ tile: tile, rx: 0, ry: 0, entry: null, target: null }]
		if (tile.tileType !== 'group') return pieces
		for (var i = 0; i < ignoreSet.length; i++) {
			var m = ignoreSet[i]
			if (m === tile) continue
			var e = membersToTargets ? getPushedEntry(m) : null
			var tgt = e ? snapTargetOf(e) : null
			var px = tgt ? tgt.x : m.x, py = tgt ? tgt.y : m.y
			pieces.push({ tile: m, rx: px - tile.x, ry: py - tile.y, entry: e, target: tgt })
		}
		// Members are ignored by the free-space checks, so make sure the
		// pieces don't land on each other.
		for (var a = 0; a < pieces.length; a++) {
			for (var b = a + 1; b < pieces.length; b++) {
				var A = pieces[a], B = pieces[b]
				if (rectsOverlap(makeRect(A.rx, A.ry, A.tile.w, A.tile.h), makeRect(B.rx, B.ry, B.tile.w, B.tile.h))) return null
			}
		}
		return pieces
	}

	function piecesFit(pieces, x, y, ignoreSet, forbiddenRect) {
		for (var i = 0; i < pieces.length; i++) {
			var p = pieces[i]
			var px = x + p.rx, py = y + p.ry
			if (px < 0 || py < 0 || px + p.tile.w > columns) return false
			if (!isRectFree(px, py, p.tile.w, p.tile.h, ignoreSet)) return false
			if (forbiddenRect && rectsOverlap(makeRect(px, py, p.tile.w, p.tile.h), forbiddenRect)) return false
		}
		return true
	}

	function attemptSnapback(entry) {
		// Try to return a pushed tile toward its original position.
		// Removes entry from pushedItems if fully snapped back.
		// Returns true if the tile moved.
		var tile = entry.tile

		if (tile.x === entry.origX && tile.y === entry.origY) {
			pushedItems.splice(pushedItems.indexOf(entry), 1)
			return false
		}

		var target = snapTargetOf(entry)
		var origX = target.x, origY = target.y
		if (tile.x === origX && tile.y === origY) return false

		var ignoreSet = buildIgnoreSet(tile)

		// The dragged item's current rect is "forbidden" — snapped tile must not land there
		var forbiddenRect = null
		if (hasDrag) {
			var dragH = dropHeight
			if (draggedItem && draggedItem.tileType === 'group' && draggedGroupContentHeight > 0) {
				dragH += draggedGroupContentHeight
			}
			forbiddenRect = makeRect(dropHoverX, dropHoverY, dropWidth, dragH)
		}

		// Prefer taking pushed members along to their own targets; fall back to
		// keeping members where they are relative to the group.
		var variants = [snapPieces(tile, ignoreSet, true)]
		if (tile.tileType === 'group') variants.push(snapPieces(tile, ignoreSet, false))

		var bestX = tile.x, bestY = tile.y, bestPieces = null
		for (var v = 0; v < variants.length && !bestPieces; v++) {
			var pieces = variants[v]
			if (!pieces) continue

			// Try full snapback first
			if (piecesFit(pieces, origX, origY, ignoreSet, forbiddenRect)) {
				bestX = origX; bestY = origY; bestPieces = pieces
				break
			}

			// Try partial snapback: scan all 4 directions for the reachable position
			// that is closest (Manhattan distance) to the origin.
			var bestDist = Math.abs(tile.x - origX) + Math.abs(tile.y - origY)
			var snapDirs = [
				{ dx:  1, dy:  0 },
				{ dx: -1, dy:  0 },
				{ dx:  0, dy: -1 },
				{ dx:  0, dy:  1 },
			]
			for (var d = 0; d < snapDirs.length; d++) {
				var dx = snapDirs[d].dx, dy = snapDirs[d].dy
				for (var s = 1; s <= 64; s++) {
					var testX = tile.x + dx * s
					var testY = tile.y + dy * s
					if (!piecesFit(pieces, testX, testY, ignoreSet, forbiddenRect)) break
					var dist = Math.abs(testX - origX) + Math.abs(testY - origY)
					if (dist < bestDist) {
						bestDist = dist
						bestX = testX
						bestY = testY
						bestPieces = pieces
					}
				}
			}
		}

		if (!bestPieces) return false

		// Moving a group carries its members and shifts their pushed origins
		// (animateGroupMembersBy); then place pushed members at their targets.
		var deltaX = bestX - tile.x, deltaY = bestY - tile.y
		animateTileTo(tile, bestX, bestY)
		if (bestX === entry.origX && bestY === entry.origY) {
			pushedItems.splice(pushedItems.indexOf(entry), 1)
		}
		for (var i = 1; i < bestPieces.length; i++) {
			var p = bestPieces[i]
			if (!p.entry) continue
			animateTileTo(p.tile, bestX + p.rx, bestY + p.ry)
			if (p.target.isFinal && p.entry.origX === p.tile.x && p.entry.origY === p.tile.y) {
				pushedItems.splice(pushedItems.indexOf(p.entry), 1)
			}
		}
		return true
	}

	function attemptAllSnapbacks() {
		// Iterate in reverse so removals during attemptSnapback don't skip entries.
		// Repeat while anything moves: a pusher returning (processed after the
		// tiles it cascaded) frees those tiles to follow on the next pass.
		for (var pass = 0; pass < 8; pass++) {
			var moved = false
			for (var i = pushedItems.length - 1; i >= 0; i--) {
				if (pushedItems[i] && attemptSnapback(pushedItems[i])) moved = true
			}
			if (!moved) break
		}
	}

	function snapbackAll() {
		// Immediately return all pushed tiles to their original positions
		for (var i = 0; i < pushedItems.length; i++) {
			var entry = pushedItems[i]
			animateTileTo(entry.tile, entry.origX, entry.origY)
		}
	}

	function clearAllSnapbacks() {
		pushedItems = []
	}

	// ============================================================
	// Section 9: Drag Lifecycle
	// ============================================================

	function startDrag(index) {
		draggedIndex = index
		dropHoverX = draggedItem.x
		dropHoverY = draggedItem.y
		isDragging = true
		draggedItemOriginalGroup = getGroupForTile(draggedItem)

		draggedGroupMembers = []
		draggedGroupContentHeight = 0
		if (draggedItem.tileType === 'group') {
			var contentRect = getGroupContentRect(draggedItem)
			draggedGroupContentHeight = contentRect.h
			// Build the list locally and assign it once: getGroupContentRect skips
			// tiles already in draggedGroupMembers, so pushing into it while
			// iterating shrinks the group's content area and drops later members.
			var members = []
			for (var i = 0; i < tileModel.length; i++) {
				if (i === draggedIndex) continue
				var t = tileModel[i]
				if (t.x < contentRect.x1 || t.x > contentRect.x2) continue
				if (t.tileType === 'group') continue
				if (contentRect.h > 0 && t.y >= contentRect.y1 && t.y <= contentRect.y2) {
					members.push(t)
				}
			}
			draggedGroupMembers = members
		}

		var frozen = []
		for (var g = 0; g < tileModel.length; g++) {
			var grp = tileModel[g]
			if (g === draggedIndex || grp.tileType !== 'group') continue
			var mem = []
			for (var i = 0; i < tileModel.length; i++) {
				if (i === draggedIndex || draggedGroupMembers.indexOf(tileModel[i]) >= 0) continue
				if (isTileInGroup(grp, tileModel[i])) mem.push(tileModel[i])
			}
			frozen.push({ group: grp, members: mem })
		}
		frozenGroups = frozen

		rebuildHitbox()
	}

	function dragTick(event) {
		var dragX = event.x + dropOffsetX
		var dragY = event.y + dropOffsetY + scrollView.scrollTop
		var modelX = Math.max(0, Math.round(dragX / cellBoxSize - dropWidth / 2))
		var modelY = Math.max(0, Math.round(dragY / cellBoxSize - dropHeight / 2))

		scrollUpArea.checkContains(event)
		scrollDownArea.checkContains(event)

		// Handle external drops (URLs, favorites dragged onto the grid)
		if (!draggedItem && !addedItem) {
			if (event && event.hasUrls && event.urls) {
				var url
				if (event.keys && event.keys.indexOf('favoriteId') >= 0) {
					url = Utils.parseDropUrl(event.getDataAsString('favoriteId'))
				} else {
					url = Utils.parseDropUrl(event.urls[0].toString())
				}
				addedItem = newTile(url)
				if (event.keys.indexOf('_NETSCAPE_URL') >= 0) {
					var netscapeUrl = event.getDataAsString('_NETSCAPE_URL')
					var tokens = netscapeUrl.split('\n')
					if (tokens.length >= 2 && tokens[1].trim()) {
						addedItem.label = tokens[1].trim()
						addedItem.icon = 'internet-web-browser'
					}
				}
			} else {
				return
			}
		}

		var tileGroupToIgnore = null
		if (draggedItem && draggedItem.tileType === 'group') {
			tileGroupToIgnore = draggedItem
		} else if (addedItem && addedItem.tileType === 'group') {
			tileGroupToIgnore = addedItem
		}

		dropHoverX = Math.max(0, Math.min(modelX, columns - dropWidth))
		dropHoverY = Math.max(0, modelY)

		// Attempt to return pushed items toward their original positions
		if (dynamicPusher) {
			attemptAllSnapbacks()
		}

		// Total height to check (groups include their content area)
		var checkH = dropHeight
		if (draggedItem && draggedItem.tileType === 'group' && draggedGroupContentHeight > 0) {
			checkH += draggedGroupContentHeight
		}

		canDrop = !checkAndPushCollisions(dropHoverX, dropHoverY, dropWidth, checkH, tileGroupToIgnore)

		// A push may have moved an item out of the way of tiles it cascaded earlier
		// (betterOption). Let those return now rather than on the next tick, which
		// may never come if this tick is the drop.
		if (dynamicPusher && pushedItems.length > 0) {
			attemptAllSnapbacks()
		}

		// Animate group members to visually follow the dragged group header
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

	function cancelDragHover() {
		dropHoverX = -1
		dropHoverY = -1
		scrollUpArea.containsDrag = false
		scrollDownArea.containsDrag = false
		addedItem = null
	}

	function resetDrag() {
		// If pushed items remain (drag was cancelled, not dropped), snap them back
		if (pushedItems.length > 0) {
			snapbackAll()
			clearAllSnapbacks()
		}

		// Restore group member coordinate bindings
		for (var i = 0; i < draggedGroupMembers.length; i++) {
			var idx = tileModel.indexOf(draggedGroupMembers[i])
			if (idx >= 0) {
				var memberItem = tileModelRepeater.itemAt(idx)
				if (memberItem) memberItem.fixCoordinateBindings()
			}
		}
		draggedGroupMembers = []
		frozenGroups = null
		cancelDragHover()
		isDragging = false
		draggedIndex = -1
	}

	// ============================================================
	// Section 10: Grid Operations
	// ============================================================

	function commitMove(tile, cellX, cellY) {
		// Permanently place tile at (cellX, cellY) — called on successful drop
		if (isNaN(cellX) || isNaN(cellY) || cellX === null || cellY === null) return
		if (tile.tileType === 'group') {
			var deltaX = cellX - tile.x
			var deltaY = cellY - tile.y
			// Move all group members (use captured draggedGroupMembers for dragged group).
			// Collect them before moving any, since membership is derived from positions.
			var members = (tile === draggedItem && draggedGroupMembers.length > 0)
				? draggedGroupMembers
				: null
			if (!members) {
				members = []
				for (var i = 0; i < tileModel.length; i++) {
					var t = tileModel[i]
					if (t !== tile && isTileInGroup(tile, t)) members.push(t)
				}
			}
			for (var i = 0; i < members.length; i++) {
				members[i].x += deltaX
				members[i].y += deltaY
			}
		}
		tile.x = cellX
		tile.y = cellY
		tileGrid.tileModelChanged()
	}

	// Legacy alias (used from external callers and internally)
	function moveTile(tile, cellX, cellY) {
		commitMove(tile, cellX, cellY)
	}

	function updateSize() { rebuildHitbox() }

	function update() {
		var urlList = []
		for (var i = 0; i < tileModel.length; i++) {
			if (tileModel[i].url) urlList.push(tileModel[i].url)
		}
		appsModel.tileGridModel.favorites = urlList
		rebuildHitbox()
		noTiles = (tileModel.length == 0)
		refreshTileViews()
	}

	// Qt >= 6.10 (Plasma 6.8) no longer tracks property changes made on plain
	// JavaScript objects inside QML bindings. When a tile is edited (size,
	// position, label, icon, background) the view has to be re-evaluated
	// manually, otherwise the changes never appear on screen.
	function refreshTileViews() {
		for (var i = 0; i < tileModelRepeater.count; i++) {
			var it = tileModelRepeater.itemAt(i)
			if (it && it.appObj) {
				it.appObj.updateFromTile()
			}
		}
	}

	onDraggedItemChanged: update()
	onTileModelChanged: update()
	property var tileModel: []

	// `tileModel` is a plain JS array, and Qt >= 6.10 (Plasma 6.8) doesn't
	// track its length in bindings. Update this property imperatively after
	// every change so the "no tiles" splash state stays correct.
	property bool noTiles: tileModel.length == 0

	function getTilesInArea(area) {
		var result = []
		for (var i = 0; i < tileModel.length; i++) {
			if (tileWithin(tileModel[i], area.x1, area.y1, area.x2, area.y2)) {
				result.push(tileModel[i])
			}
		}
		return result
	}

	function getTileLabel(tile) {
		if (tile.url) {
			var app = appsModel.tileGridModel.getApp(tile.url)
			return tile.label || app.display || app.url || ""
		}
		return ""
	}

	function sortGroupTiles(groupTile) {
		var area = getGroupContentRect(groupTile)
		var tileList = getTilesInArea(area)

		tileList.sort(function(a, b) {
			return getTileLabel(a).localeCompare(getTileLabel(b))
		})

		var cursorX = groupTile.x
		var cursorY = groupTile.y + groupTile.h
		var rowH = 0
		for (var i = 0; i < tileList.length; i++) {
			var tile = tileList[i]
			if (cursorX + tile.w - 1 > area.x2) {
				cursorX = groupTile.x
				cursorY += rowH
				rowH = 0
			}
			tile.x = cursorX
			tile.y = cursorY
			rowH = Math.max(rowH, tile.h)
			cursorX += tile.w
		}
		tileGrid.tileModelChanged()
	}

	function newTile(url) {
		return { x: 0, y: 0, w: 2, h: 2, url: url }
	}

	function removeIndex(i) {
		tileModel.splice(i, 1)
		tileModelChanged()
	}

	function removeApp(url) {
		var changed = false
		for (var i = tileModel.length - 1; i >= 0; i--) {
			// Plasma 6.8 Kicker favorite ids carry an "applications:" prefix; normalize both sides.
			if (Utils.normAppId(tileModel[i].url) === Utils.normAppId(url)) {
				tileModel.splice(i, 1)
				changed = true
			}
		}
		if (changed) tileModelChanged()
	}

	function findOpenPos(w, h) {
		for (var y = 0; y < rows; y++) {
			for (var x = 0; x <= columns - w; x++) {
				if (isRectFree(x, y, w, h, null)) {
					return { x: x, y: y, scrollToBottom: false }
				}
			}
		}
		// No space found — add a new row at the bottom
		return { x: 0, y: rows, scrollToBottom: true }
	}

	function parseTileXY(tile, x, y) {
		if (typeof x !== "undefined" && typeof y !== "undefined") {
			tile.x = x
			tile.y = y
		} else {
			var openPos = findOpenPos(tile.w, tile.h)
			tile.x = openPos.x
			tile.y = openPos.y
			if (openPos.scrollToBottom) {
				Qt.callLater(function() {
					scrollFlickable.contentY = Math.max(0, scrollView.scrollHeight - scrollFlickable.height)
				})
			}
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
			// Plasma 6.8 Kicker favorite ids carry an "applications:" prefix; normalize both sides.
			if (Utils.normAppId(tileModel[i].url) === Utils.normAppId(url)) return true
		}
		return false
	}

	function limit(minValue, value, maxValue) {
		return Math.max(minValue, Math.min(value, maxValue))
	}

	function addTile(x, y, props) {
		var tile = newTile("")
		parseTileXY(tile, x, y)
		if (props) {
			var keys = Object.keys(props)
			for (var i = 0; i < keys.length; i++) tile[keys[i]] = props[keys[i]]
		}
		tileModel.push(tile)
		tileModelChanged()
		return tile
	}

	function addGroup(x, y, props) {
		var groupProps = {
			tileType: "group",
			label: i18nc("default group label", "Group"),
			w: limit(2, columns - x, 6),
			h: 1,
		}
		if (props) {
			var keys = Object.keys(props)
			for (var i = 0; i < keys.length; i++) groupProps[keys[i]] = props[keys[i]]
		}
		return addTile(x, y, groupProps)
	}

	function addDefaultTiles() {
		tileGridPresets.addDefault()
	}

	// Qt >= 6.10 (Plasma 6.8) deep-copies object-typed signal arguments through
	// QVariant, so this carries the tile's *index* (a value type) instead of the
	// tile object. The editor resolves the real `tileModel[index]` element itself.
	signal editTile(int tileIndex)

	// ============================================================
	// UI: ScrollView + Grid
	// ============================================================

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
									var pos = mapToItem(scrollItem, mouse.x, mouse.y)
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
							if (tile) {
								tileGrid.editTile(tileModel.indexOf(tile))
							}
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
		active: tileGrid.noTiles && !tileGrid.editing
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
}
