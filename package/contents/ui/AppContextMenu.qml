// Based off kicker's ActionMenu
import QtQuick
import org.kde.plasma.extras as PlasmaExtras

Item {
	id: root

	property QtObject menu
	property Item visualParent
	property bool opened: false
	property int tileIndex: -1

	signal closed
	signal populateMenu(var menu)

	onOpenedChanged: {
		if (!opened) {
			closed()
		}
	}

	onClosed: destroyMenu()

	function open(x, y) {
		refreshMenu()
		if (!menu) {
			console.log('AppContextMenu.open: menu is null, returning')
			return
		}
		if (menu.content.length === 0) {
			console.log('AppContextMenu.open: content empty, returning')
			return
		}
		opened = true
		if (x && y) {
			menu.open(x, y)
		} else {
			menu.open()
		}
	}

	function destroyMenu() {
		if (menu) {
			menu.destroy()
			menu = null
		}
		if (opened) {
			opened = false
		}
	}

	function refreshMenu() {
		destroyMenu()
		menu = contextMenuComponent.createObject(root)
		if (!menu) {
			console.log('AppContextMenu.refreshMenu: createObject returned null')
			return
		}
		populateMenu(menu)
	}

	Component {
		id: menuItemComponent
		PlasmaExtras.MenuItem {}
	}

	Component {
		id: menuSeparatorComponent
		PlasmaExtras.MenuItem { separator: true }
	}

	Component {
		id: contextMenuComponent

		PlasmaExtras.Menu {
			id: contextMenu
			visualParent: root.visualParent

			function newSeperator() {
				return menuSeparatorComponent.createObject(contextMenu)
			}

			function newMenuItem() {
				return menuItemComponent.createObject(contextMenu)
			}

			function addPinToMenuAction(favoriteId) {
				var menuItem = menu.newMenuItem()
				if (!menuItem) {
					console.log('addPinToMenuAction: menuItem null, returning')
					return
				}
				if (tileGrid.hasAppTile(favoriteId)) {
					menuItem.text = i18n("Unpin from Menu")
					menuItem.icon = "list-remove"
					menuItem.clicked.connect(function() {
						if (root.tileIndex >= 0) {
							tileGrid.removeIndex(root.tileIndex)
						} else {
							tileGrid.removeApp(favoriteId)
						}
					})
				} else {
					menuItem.text = i18n("Pin to Menu")
					menuItem.icon = "bookmark-new"
					menuItem.clicked.connect(function() {
						tileGrid.addApp(favoriteId)
					})
				}
				menu.addMenuItem(menuItem)
			}

			function addActionList(actionList, listModel, index) {
				if (!actionList || !actionList.forEach) {
					return
				}
				actionList.forEach(function(actionItem) {
					var menuItem = menu.newMenuItem()
					if (!menuItem)
						return
					menuItem.text = actionItem.text ? actionItem.text : ""
					menuItem.enabled = actionItem.type != "title" && ("enabled" in actionItem ? actionItem.enabled : true)
					menuItem.separator = actionItem.type == "separator"
					menuItem.section = actionItem.type == "title"
					menuItem.icon = actionItem.icon ? actionItem.icon : null
					menuItem.clicked.connect(function() {
						listModel.triggerIndexAction(index, actionItem.actionId, actionItem.actionArgument)
					})

					if (actionItem.actionId == 'addToDesktop') {
						menu.removeMenuItem(menuItem)
					} else if (actionItem.actionId == 'addToPanel') {
						menu.removeMenuItem(menuItem)
					} else if (actionItem.actionId == 'addToTaskManager') {
						menuItem.text = i18n("Pin to Taskbar")
						menuItem.icon = "bookmark-new"
					}
				})
			}
		}
	}

	Component {
		id: contextMenuItemComponent

		PlasmaExtras.MenuItem {
			property variant actionItem

			text: actionItem.text ? actionItem.text : ""
			enabled: actionItem.type != "title" && ("enabled" in actionItem ? actionItem.enabled : true)
			separator: actionItem.type == "separator"
			section: actionItem.type == "title"
			icon: actionItem.icon ? actionItem.icon : null

			onClicked: {
				actionClicked(actionItem.actionId, actionItem.actionArgument)
			}
		}
	}
}
