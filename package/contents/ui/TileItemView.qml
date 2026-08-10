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
	readonly property real tileIconSize:
		Math.min(width, height) * config.tileIconSizePercent / 100

	readonly property int labelAlignment: appObj.isGroup ? config.groupLabelAlignment : config.tileLabelAlignment

	property bool hovered: false

	states: [
		State {
			when: modelData.w == 1 && modelData.h >= 1
			PropertyChanges { target: icon; size: tileIconSize }
			PropertyChanges { target: label; visible: false }
		},
		State {
			when: modelData.w >= 2 && modelData.h == 1
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
			when: (modelData.w >= 2 && modelData.h == 2) || (modelData.w == 2 && modelData.h >= 2)
			PropertyChanges { target: icon; size: (0.7 * tileIconSize) }
		},
		State {
			when: modelData.w >= 3 && modelData.h >= 3
			PropertyChanges { target: icon; size: (0.75 * tileIconSize) }
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
		anchors.horizontalCenter: parent.horizontalCenter
		// property int size: 72 // Just a default, overriden in State change
		property real size: Math.min(parent.width, parent.height) / 2
		width: appObj.showIcon ? size : 0
		height: appObj.showIcon ? size : 0
		anchors.fill: appObj.iconFill ? parent : null
		smooth: true
	}

	PlasmaComponents3.Label {
		id: label
		visible: appObj.showLabel
		text: appObj.labelText
		anchors.top: parent.top
		anchors.bottom: parent.bottom
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
