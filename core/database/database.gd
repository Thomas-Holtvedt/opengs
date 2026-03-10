extends Node
class_name Database


var tag_to_country: Dictionary[String, Country] = {}
var lookup_to_color_province: Dictionary[Color, Color] = {} # Stores efficient to full color table
var color_to_province: Dictionary[Color, Province] = {}
var id_to_province: Dictionary[String, Province] = {}
var id_to_territory: Dictionary[String, Territory] = {}
