extends SubViewport
class_name TextFlagGenerator

# Renders small whole-flag textures for inline use in text (RichTextLabel, etc.).
# This is NOT the on-flag iconography (see Flag.icon_*) — it's the entire flag,
# rendered tiny.

@onready var flag: FlagDisplay = $FlagDisplay

func create_all_text_flags(db: Database) -> void:
	flag.database = db
	for country in db.tag_to_country.values():
		country.text_flag = await create_text_flag(country.flag)

func create_text_flag(input_flag: Flag) -> ImageTexture:
	# A SubViewport only renders inside the tree, so @onready must have run by now.
	if flag == null:
		flag = get_node_or_null("FlagDisplay")
	if flag == null:
		push_error("TextFlagGenerator: add the generator to the scene tree before calling create_text_flag().")
		return null
	flag.apply_flag(input_flag)
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var flag_image: Image = get_texture().get_image()
	flag_image.resize(23, 15)
	return ImageTexture.create_from_image(flag_image)
