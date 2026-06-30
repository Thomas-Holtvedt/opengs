extends Resource

class_name Country

enum Ideology { DEMOCRACY, COMMUNISM }

var tag: String
var base_name: String
var map_color: Color
var ideology: Ideology
var owned_provinces: Array[Province]
var flag: Flag  #Data to be used with FlagDisplay
var text_flag: Texture2D # Small whole-flag texture for inline use in text (RichTextLabel, etc.)


func _init(country_tag: String) -> void:
	self.tag = country_tag
	self.flag = Flag.new()
	self.flag.id = country_tag
