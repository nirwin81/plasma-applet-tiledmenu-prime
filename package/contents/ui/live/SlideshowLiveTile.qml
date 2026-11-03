import QtQuick
import QtQuick.Window
import Qt.labs.folderlistmodel

// Live tile: crossfading slideshow of the images in a folder.
// Tile fields: liveFolder (path or file:// URL, default ~/Pictures),
// liveInterval (seconds, default 10), liveShuffle (bool),
// liveRecursive (bool: also use images in subfolders).
Item {
	id: slideshowLiveTile

	readonly property var imageFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp", "*.gif", "*.avif", "*.jxl"]

	// Recursive scan limits, so pointing the tile at ~ or a symlink loop
	// can't hang the menu or grow without bound.
	readonly property int maxDepth: 12
	readonly property int maxFolders: 2000
	readonly property int maxImages: 10000

	// URLs of every image the slideshow can show.
	property var imageUrls: []

	//--- Top-level folder only: live-updating model.
	FolderListModel {
		id: folderModel
		folder: appObj.liveRecursive ? "" : appObj.liveFolderUrl
		showDirs: false
		showHidden: false
		caseSensitive: false
		sortField: FolderListModel.Name
		nameFilters: slideshowLiveTile.imageFilters
		onCountChanged: if (!appObj.liveRecursive) slideshowLiveTile.collectTopLevel()
		onStatusChanged: if (status === FolderListModel.Ready && !appObj.liveRecursive) slideshowLiveTile.collectTopLevel()
	}

	readonly property bool recursive: appObj.liveRecursive
	onRecursiveChanged: {
		if (!recursive) {
			scanGeneration++ // cancel any scan in progress
			collectTopLevel()
		}
	}

	function collectTopLevel() {
		var urls = []
		for (var i = 0; i < folderModel.count; i++) {
			urls.push(folderModel.get(i, "fileUrl").toString())
		}
		setImages(urls)
	}

	//--- Recursive: walk the tree one folder at a time (no shell involved).
	Component {
		id: dirModelComponent
		FolderListModel {
			showDirs: true
			showDotAndDotDot: false
			showHidden: false
			caseSensitive: false
			sortField: FolderListModel.Name
			nameFilters: slideshowLiveTile.imageFilters // folders aren't filtered
		}
	}

	property int scanGeneration: 0
	property var scanQueue: []
	property var scanFound: []
	property int scanFolderCount: 0
	property var scanSignatures: ({})

	function startScan() {
		scanGeneration++
		scanQueue = [{ url: appObj.liveFolderUrl, depth: 0 }]
		scanFound = []
		scanFolderCount = 0
		scanSignatures = {}
		scanNext(scanGeneration)
	}

	function scanNext(generation) {
		if (generation !== scanGeneration) {
			return // settings changed; a newer scan has taken over
		}
		if (scanQueue.length === 0 || scanFolderCount >= maxFolders || scanFound.length >= maxImages) {
			scanFound.sort()
			setImages(scanFound)
			return
		}
		var entry = scanQueue.shift()
		scanFolderCount++
		var model = dirModelComponent.createObject(slideshowLiveTile, { folder: entry.url })
		var done = false
		function finish() {
			if (done || model.status !== FolderListModel.Ready) {
				return
			}
			done = true
			if (generation !== scanGeneration) {
				// A newer scan has started; don't touch its shared state.
				model.destroy()
				return
			}
			// Symlinks can make the same folder appear under many paths (or
			// loop forever). FolderListModel can't tell us about symlinks, so
			// fingerprint each listing and skip folders we've already seen.
			var signature = []
			for (var j = 0; j < model.count; j++) {
				signature.push(model.get(j, "fileName") + "|" + model.get(j, "fileSize") + "|" + model.get(j, "fileModified"))
			}
			signature = signature.join("\n")
			var isRepeat = signature !== "" && scanSignatures.hasOwnProperty(signature)
			scanSignatures[signature] = true
			if (!isRepeat) {
				for (var i = 0; i < model.count; i++) {
					var url = model.get(i, "fileUrl").toString()
					if (model.get(i, "fileIsDir")) {
						if (entry.depth < maxDepth) {
							scanQueue.push({ url: url, depth: entry.depth + 1 })
						}
					} else if (scanFound.length < maxImages) {
						scanFound.push(url)
					}
				}
			}
			model.destroy()
			// Wrap in a fresh closure: Qt.callLater merges pending calls to the
			// same function, and scanNext is the same function for every tile,
			// so tiles scanning at once would cancel each other's next step.
			Qt.callLater(function() { scanNext(generation) })
		}
		model.statusChanged.connect(finish)
		finish() // in case it was already Ready
	}

	readonly property string scanKey: appObj.liveRecursive ? appObj.liveFolderUrl : ""
	// Creation and the first scanKey evaluation both request a scan; the
	// zero-length timer merges them (per tile) into a single scan.
	onScanKeyChanged: if (appObj.liveRecursive) scanStartTimer.restart()
	Component.onCompleted: if (appObj.liveRecursive) scanStartTimer.restart()
	Timer {
		id: scanStartTimer
		interval: 0
		onTriggered: slideshowLiveTile.startScan()
	}

	//--- Playback
	property int currentIndex: -1
	property bool frontIsA: true

	function setImages(urls) {
		imageUrls = urls
		currentIndex = -1
		advance()
	}

	function nextIndex() {
		var n = imageUrls.length
		if (n <= 1) {
			return 0
		}
		if (appObj.liveShuffle) {
			if (currentIndex < 0) {
				return Math.floor(Math.random() * n)
			}
			var i = Math.floor(Math.random() * (n - 1))
			return i >= currentIndex ? i + 1 : i // never repeat the current image
		}
		return (currentIndex + 1) % n
	}

	function advance() {
		if (imageUrls.length === 0) {
			imageA.source = ""
			imageB.source = ""
			return
		}
		currentIndex = nextIndex()
		// Load into the hidden image; it fades in once loaded (onStatusChanged).
		var back = frontIsA ? imageB : imageA
		back.source = imageUrls[currentIndex]
	}

	Timer {
		interval: appObj.liveInterval * 1000
		running: tileItemView.liveActive && slideshowLiveTile.imageUrls.length > 1
		repeat: true
		onTriggered: slideshowLiveTile.advance()
	}

	component SlideImage: Image {
		required property bool isFront
		anchors.fill: parent
		fillMode: Image.PreserveAspectCrop
		// Decode at tile size (cover + crop) instead of full photo resolution.
		sourceSize.width: slideshowLiveTile.width * Screen.devicePixelRatio
		sourceSize.height: slideshowLiveTile.height * Screen.devicePixelRatio
		asynchronous: true
		cache: false
		smooth: true
		mipmap: true
		opacity: isFront ? 1 : 0
		Behavior on opacity { NumberAnimation { duration: 600 } }
	}

	SlideImage {
		id: imageA
		isFront: slideshowLiveTile.frontIsA
		onStatusChanged: if (status === Image.Ready && !isFront) slideshowLiveTile.frontIsA = true
	}
	SlideImage {
		id: imageB
		isFront: !slideshowLiveTile.frontIsA
		onStatusChanged: if (status === Image.Ready && !isFront) slideshowLiveTile.frontIsA = false
	}
}
