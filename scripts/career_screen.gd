extends Control

# The career screen (res://scenes/career_screen.tscn): your rank and XP, research points and the research lab
# where you spend them on technology upgrades, your achievements, and your best result on each world.
# Opened from the main menu ("Career") and from the mission report ("Research lab").

signal closed

const Career = preload("res://scripts/career.gd")
const StarsDisplay = preload("res://scripts/stars_display.gd")
const SolarSystemData = preload("res://scripts/solar_system_data.gd")
const TAB_NAMES = ["research", "achievements", "best"]

@onready var panel: PanelContainer = $Center/Panel
@onready var rank_label: Label = $Center/Panel/Column/Header/TitleBlock/Rank
@onready var xp_text: Label = $Center/Panel/Column/Header/XpBlock/XpText
@onready var xp_bar: ProgressBar = $Center/Panel/Column/Header/XpBlock/XpBar
@onready var research_label: Label = $Center/Panel/Column/Header/ResearchBlock/Research
@onready var tabs: TabContainer = $Center/Panel/Column/Tabs
@onready var upgrades_grid: GridContainer = $"Center/Panel/Column/Tabs/Research lab/Scroll/Upgrades"
@onready var achievements_grid: GridContainer = $Center/Panel/Column/Tabs/Achievements/Grid
@onready var best_list: VBoxContainer = $"Center/Panel/Column/Tabs/Best results/List"

func _ready():
	$Center/Panel/Column/Header/CloseButton.pressed.connect(close)
	tabs.tab_changed.connect(func(_index): animate_tab())

func open(tab_name := "research"):
	tabs.current_tab = max(TAB_NAMES.find(tab_name), 0)
	refresh()
	# The screen dims, the panel pops in, and the cards come up one after another
	$Dim.modulate.a = 0.0
	$Dim.create_tween().tween_property($Dim, "modulate:a", 1.0, 0.25)
	UiMotion.pop_in(panel, 0.0, 0.45)
	UiMotion.reveal_text(rank_label, 0.15, 0.7, 0.4)
	animate_tab(0.25)

func close():
	var fade = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.2)
	await fade.finished
	closed.emit()
	queue_free()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func animate_tab(delay := 0.0):
	var shown = [upgrades_grid, achievements_grid, best_list][tabs.current_tab]
	UiMotion.stagger(shown.get_children(), delay, 0.035, Vector2(0, 16), 0.5)

func refresh():
	var data = GameState.career
	var rank = Career.rank_for(data["xp"])
	rank_label.text = rank["title"]
	if rank["next"] > 0:
		xp_text.text = "%d XP   ·   %d to %s" % [data["xp"], rank["next"] - data["xp"], Career.rank_for(rank["next"])["title"]]
		xp_bar.value = 100.0 * (data["xp"] - rank["floor"]) / float(rank["next"] - rank["floor"])
	else:
		xp_text.text = "%d XP   ·   the highest rank" % data["xp"]
		xp_bar.value = 100.0
	research_label.text = str(data["research"])
	fill_upgrades()
	fill_achievements()
	fill_best_results()

# ---------------------------------------------------------------------------
# The research lab
# ---------------------------------------------------------------------------
func fill_upgrades():
	for old in upgrades_grid.get_children():
		upgrades_grid.remove_child(old)
		old.queue_free()
	for upgrade_id in Career.UPGRADES:
		var upgrade = Career.UPGRADES[upgrade_id]
		var owned = GameState.has_upgrade(upgrade_id)
		var card = make_card(Color(0.78, 0.65, 1.0) if owned else Color(0.45, 0.8, 1.0, 0.5))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var words = VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 0)
		row.add_child(words)
		words.add_child(make_label(upgrade["title"], 16, Color.WHITE, "TitleLabel"))
		var text = make_label(upgrade["text"], 12, Color(0.72, 0.77, 0.85))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 260
		words.add_child(text)
		if owned:
			var owned_label = make_label("INSTALLED", 12, Color(0.78, 0.65, 1.0), "DataLabel")
			owned_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(owned_label)
		else:
			var buy = Button.new()
			buy.text = "%d RP" % upgrade["cost"]
			buy.custom_minimum_size = Vector2(86, 34)
			buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			buy.disabled = GameState.career["research"] < upgrade["cost"]
			buy.tooltip_text = "Buy for %d research points" % upgrade["cost"] if not buy.disabled else "You need %d research points. Fly missions and send science home to earn them." % upgrade["cost"]
			buy.pressed.connect(buy_upgrade.bind(upgrade_id))
			row.add_child(buy)
		upgrades_grid.add_child(card)

func buy_upgrade(upgrade_id):
	if not GameState.buy_upgrade(upgrade_id):
		return
	GameState.show_toast(Career.UPGRADES[upgrade_id]["title"], "Installed on every spacecraft you build from now on.", "research")
	refresh()
	# The new upgrade's card flashes
	for card in upgrades_grid.get_children():
		var title_label: Label = card.get_child(0).get_child(0).get_child(0)
		if title_label.text == Career.UPGRADES[upgrade_id]["title"]:
			UiMotion.pop_in(card, 0.0, 0.4)
	UiMotion.count_up(research_label, GameState.career["research"], func(value): return str(int(value)), 0.0, 0.5)

# ---------------------------------------------------------------------------
# Achievements and best results
# ---------------------------------------------------------------------------
func fill_achievements():
	for old in achievements_grid.get_children():
		achievements_grid.remove_child(old)
		old.queue_free()
	for achievement_id in Career.ACHIEVEMENTS:
		var achievement = Career.ACHIEVEMENTS[achievement_id]
		var earned = achievement_id in GameState.career["achievements"]
		var card = make_card(Color(1.0, 0.82, 0.35) if earned else Color(1, 1, 1, 0.12))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var words = VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		card.add_child(words)
		words.add_child(make_label(("★  " if earned else "") + achievement["title"], 15, Color(1.0, 0.88, 0.55) if earned else Color(0.6, 0.64, 0.7), "TitleLabel"))
		var text = make_label(achievement["text"], 11, Color(0.72, 0.77, 0.85) if earned else Color(0.48, 0.52, 0.58))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 240
		words.add_child(text)
		achievements_grid.add_child(card)

func fill_best_results():
	for old in best_list.get_children():
		best_list.remove_child(old)
		old.queue_free()
	var best = GameState.career["best"]
	if best.is_empty():
		best_list.add_child(make_label("No missions yet. Pick a world in the solar system and send a probe!", 14, Color(0.72, 0.77, 0.85)))
		return
	for destination in best:
		var result = best[destination]
		var card = make_card(Color(0.45, 0.8, 1.0, 0.35))
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		card.add_child(row)
		var name_label = make_label(SolarSystemData.BODIES.get(destination, {}).get("label", destination), 18, Color.WHITE, "TitleLabel")
		name_label.custom_minimum_size.x = 200
		row.add_child(name_label)
		row.add_child(make_label("Best grade: %s" % (result["grade"] if result["grade"] != "" else "—"), 14, Color(0.85, 0.9, 1.0)))
		row.add_child(make_label("Score: %s" % (str(result["score"]) if result["score"] >= 0 else "—"), 14, Color(0.85, 0.9, 1.0)))
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var stars = Control.new()
		stars.set_script(StarsDisplay)
		stars.custom_minimum_size = Vector2(80, 22)
		stars.filled = result.get("stars", 0)
		row.add_child(stars)
		best_list.add_child(card)

func make_card(edge_color):
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.15, 0.9)
	style.border_color = edge_color
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	return card

func make_label(text, font_size, color, variation = ""):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if variation != "":
		label.theme_type_variation = variation
	return label
