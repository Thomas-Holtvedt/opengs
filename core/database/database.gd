extends Node
class_name Database

# Data Containers
var tag_to_country: Dictionary[String, Country] = {}
var color_to_province: Dictionary[Color, Province] = {}
var id_to_province: Dictionary[String, Province] = {}
var id_to_territory: Dictionary[String, Territory] = {}

# Helpers
var province_color_to_lookup: Dictionary[Color, Color] = {}
