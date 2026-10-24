import QtQuick
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Rectangle {
	id: tileItemView
	color: appObj.backgroundColor
	property color gradientBottomColor: Qt.darker(appObj.backgroundColor, 2.0)

	Component {
		id: tileGradient
		Gradient {
			GradientStop { position: 0.0; color: appObj.backgroundColor }
			GradientStop { position: 1.0; color: tileItemView.gradientBottomColor }
		}
	}
	gradient: appObj.backgroundGradient ? tileGradient.createObject(tileItemView) : null

	readonly property int tilePadding: 4 * config.scaleFactor
	readonly property int smallIconSize: config.smallTileIcons ? 24 : 32 * config.scaleFactor
	readonly property int mediumIconSize: config.smallTileIcons ? 48 : 72 * config.scaleFactor
	readonly property int largeIconSize: config.smallTileIcons ? 72 : 96 * config.scaleFactor

	readonly property int labelAlignment: appObj.isGroup ? config.groupLabelAlignment : config.tileLabelAlignment

	property bool hovered: false

	// State conditions read appObj (QML properties) instead of modelData
	// (plain JS object): Qt >= 6.10 (Plasma 6.8) no longer tracks JS-object
	// property changes in bindings, so only QML-property dependencies update
	// after a tile is resized (see AppObject.updateFromTile).
	states: [
		State {
			when: appObj.tileW == 1 && appObj.tileH >= 1
			PropertyChanges { target: icon; size: smallIconSize }
			PropertyChanges { target: label; visible: false }
		},
		State {
			when: appObj.tileW >= 2 && appObj.tileH == 1
			AnchorChanges { target: icon
				anchors.horizontalCenter: undefined
				anchors.left: tileItemView.left
			}
			PropertyChanges { target: icon; anchors.leftMargin: tilePadding }
			PropertyChanges { target: label
				verticalAlignment: Text.AlignVCenter
			}
			AnchorChanges { target: label
				anchors.left: icon.right
			}
		},
		State {
			when: (appObj.tileW >= 2 && appObj.tileH == 2) || (appObj.tileW == 2 && appObj.tileH >= 2)
			PropertyChanges { target: icon; size: mediumIconSize }
		},
		State {
			when: appObj.tileW >= 3 && appObj.tileH >= 3
			PropertyChanges { target: icon; size: largeIconSize }
		}
	]

	Image {
		id: backgroundImage
		anchors.fill: parent
		visible: appObj.backgroundImage
		source: appObj.backgroundImage
		fillMode: Image.PreserveAspectCrop
		asynchronous: true
		smooth: true
		mipmap: true
	}

	Kirigami.Icon {
		id: icon
		visible: appObj.showIcon
		source: appObj.iconSource
		anchors.verticalCenter: parent.verticalCenter
		// The view is taller than the title when a group background is extended.
		// Keep the icon in the title row.
		anchors.verticalCenterOffset: (appObj.isGroup && appObj.groupRect) ? -(Math.max(0, appObj.groupRect.h) * cellBoxSize) / 2 : 0
		anchors.horizontalCenter: parent.horizontalCenter
		// property int size: 72 // Just a default, overriden in State change
		property int size: Math.min(parent.width, parent.height) / 2
		width: appObj.showIcon ? size : 0
		height: appObj.showIcon ? size : 0
		anchors.fill: (appObj.iconFill && !appObj.isGroup) ? parent : null
		smooth: appObj.iconFill || config.smallTileIcons
	}

	PlasmaComponents3.Label {
		id: label
		visible: appObj.showLabel
		text: appObj.labelText
		anchors.top: parent.top
		anchors.bottom: parent.bottom
		// Leave the label in the title row when the background continues below it.
		anchors.bottomMargin: (appObj.isGroup && appObj.groupRect) ? Math.max(0, appObj.groupRect.h) * cellBoxSize : 0
		anchors.leftMargin: tilePadding
		anchors.rightMargin: tilePadding
		anchors.left: parent.left
		anchors.right: parent.right
		wrapMode: Text.Wrap
		horizontalAlignment: labelAlignment
		verticalAlignment: Text.AlignBottom
		width: parent.width
		renderType: Text.QtRendering // Fix pixelation when scaling. Plasma.Label uses NativeRendering.
		style: Text.Outline
		styleColor: appObj.backgroundGradient ? tileItemView.gradientBottomColor : appObj.backgroundColor
	}
}
