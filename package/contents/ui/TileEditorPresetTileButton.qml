import QtQuick
import QtQuick.Layouts
import QtCore

Item {
	id: presetTileButton
	Layout.fillWidth: parent.width
	Layout.preferredHeight: image.paintedHeight

	visible: source
	property alias source: image.source
	property string filename: 'temp.jpg'
	property int w: 0
	property int h: 0

	Image {
		id: image
		anchors.centerIn: parent
		width: Math.min(parent.width, sourceSize.width)

		fillMode: Image.PreserveAspectFit
	}

	HoverOutlineEffect {
		id: hoverOutlineEffect
		anchors.fill: image
		hoverRadius: Math.min(width, height)
		property alias control: mouseArea
	}

	MouseArea {
		id: mouseArea
		anchors.fill: image
		hoverEnabled: true
		acceptedButtons: Qt.LeftButton
		cursorShape: Qt.ArrowCursor

		onClicked: presetTileButton.select()
	}

	function getDownloadDir() {
		// Save directly into ~/.local/share/ which is guaranteed to exist.
		// Filenames should include a tiledmenu_ prefix to avoid collisions.
		var dataDir = StandardPaths.writableLocation(StandardPaths.GenericDataLocation)
		return dataDir.toString().replace(/^file:\/\//, '') + '/'
	}

	function resizeTile() {
		var sizeChanged = false
		if (presetTileButton.w > 0) {
			appObj.tile.w = presetTileButton.w
			sizeChanged = true
		}
		if (presetTileButton.h > 0) {
			appObj.tile.h = presetTileButton.h
			sizeChanged = true
		}
		if (sizeChanged) {
			appObj.tileChanged()
			tileGrid.tileModelChanged()
		}
	}

	function setTileBackgroundImage(filepath) {
		backgroundImageField.text = filepath
		labelField.checked = false
		iconField.checked = false
	}

	function select() {
		logger.debug('select', source)

		var sourceFilepath = '' + source // cast to string
		var isLocalFilepath = sourceFilepath.indexOf('file://') == 0 || sourceFilepath.indexOf('/') == 0
		if (isLocalFilepath) {
			presetTileButton.setTileBackgroundImage(source)
			presetTileButton.resizeTile()
		} else {
			var tiledMenuDir = getDownloadDir()
			var localFilepath = tiledMenuDir + filename
			logger.debug('localFilepath', localFilepath)

			logger.debug('grabToImage.start')
			image.grabToImage(function(result){
				logger.debug('grabToImage.done', result, result.url)
				result.saveToFile(localFilepath)
				presetTileButton.setTileBackgroundImage(localFilepath)
				presetTileButton.resizeTile()
			}, image.sourceSize)
		}
	}

}
