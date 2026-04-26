extends CanvasLayer
signal map_mode_selected(mode: MapMode.Type)

@export var enabled_modes: Dictionary[String, bool] = {
	"POLITICAL": true,
	"IDEOLOGY": true,
	"PROVINCE": true,
	"TERRITORY": true,
	"TERRAIN": true,
}


@onready var mode_buttons: Dictionary[MapMode.Type, Button] = {
	MapMode.Type.POLITICAL: $PanelContainer/GridContainer/ButtonPolitical,
	MapMode.Type.IDEOLOGY: $PanelContainer/GridContainer/ButtonIdeology,
	MapMode.Type.PROVINCE: $PanelContainer/GridContainer/ButtonProvince,
	MapMode.Type.TERRITORY: $PanelContainer/GridContainer/ButtonTerritory,
	MapMode.Type.TERRAIN: $PanelContainer/GridContainer/ButtonTerrain,
}


func _ready() -> void:
	for mode: MapMode.Type in mode_buttons.keys():
		var button: Button = mode_buttons[mode]
		var mode_name: String = MapMode.Type.keys()[mode]
		
		if not enabled_modes.get(mode_name, true):
			button.hide()
		button.pressed.connect(func(m = mode): _on_mode_pressed(m))

func _on_mode_pressed(mode: MapMode.Type) -> void:
	map_mode_selected.emit(mode)
