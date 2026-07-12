extends Resource
class_name Database

# Data Containers
var tag_to_country: Dictionary[String, Country] = {}
var color_to_province: Dictionary[Color, Province] = {}
var id_to_province: Dictionary[String, Province] = {}
var id_to_territory: Dictionary[String, Territory] = {}
var id_to_flag: Dictionary[String, Flag] = {}

# Flag Components
var flag_backgrounds: Dictionary[String, CompressedTexture2D] = {}
var flag_icons: Dictionary[String, CompressedTexture2D] = {}
var flag_icons_colored: Dictionary[String, CompressedTexture2D] = {}

# Helpers
var province_color_to_lookup: Dictionary[Color, Color] = {}
