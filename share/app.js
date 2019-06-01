(function () {
	var defaultLineStyle = new ol.style.Style({
		fill: new ol.style.Fill({
			color: [234,231,221,1]
		}),
		stroke: new ol.style.Stroke({
			color: [182,177,162,1],
			width: 1
		})
	});
	var defaultPointStyle = new ol.style.Style({
		image: new ol.style.Circle({
			fill: new ol.style.Fill({
				color: 'rgba(255, 255, 255, 0.4)'
			}),
			stroke: new ol.style.Stroke({
				color: 'rgba(182, 177, 162, 1)',
				width: 1.25
			}),
			radius: 5
		})
	});
	var treeStyle = new ol.style.Style({
		image: new ol.style.Circle({
			fill: new ol.style.Fill({
				color: 'rgba(0, 255, 0, 0.3)'
			}),
			radius: 5
		})
	});
	var labelStyle = function (text) {
		return new ol.style.Style({
			text: new ol.style.Text({
				text: text,
				placement: 'point'
			})
		});
	};

	// the styleFunction will define how features on the map get styled
	function styleFunction(feature, resolution){
		const layer = feature.get('layer');
		switch (layer) {
			case 'roads-casing':
				return [defaultLineStyle];
			case 'buildings':
				return [defaultLineStyle];
			case 'amenity-points':
				switch (feature.get('feature')) {
					case 'natural_tree':
						return treeStyle;
					default:
						break;
				}
				return [defaultPointStyle];
			case 'addresses':
				// console.log(feature);
				return [labelStyle(feature.get('addr_housenumber'), resolution)];
			default:
				// console.log(layer)
				break;
		}
		return null;
	}

	var map = new ol.Map({
		layers: [
			new ol.layer.VectorTile({
				source: new ol.source.VectorTile({
					attributions: '© <a href="http://www.openstreetmap.org/copyright">' +
						'OpenStreetMap contributors</a>',
					format: new ol.format.MVT(),
					tileGrid: ol.tilegrid.createXYZ({maxZoom: 22}),
					tilePixelRatio: 16,
					url: 'http://localhost:8080/maps/osm/{z}/{x}/{y}.vector.pbf'
				}),
				style: styleFunction
			})
		],
		target: 'map',
		view: new ol.View({
			center: ol.proj.transform([9.52226, 47.13866], 'EPSG:4326', 'EPSG:3857'),
			zoom: 19
		})
	});
})();
