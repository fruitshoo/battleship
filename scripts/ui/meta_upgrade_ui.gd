extends CanvasLayer

## 영구 업그레이드 상점 UI (Meta Upgrade UI)
## 골드를 사용하여 영구적으로 스탯을 강화하는 화면

signal closed

@onready var gold_label: Label = $Panel/VBox/GoldLabel
@onready var upgrade_list: VBoxContainer = $Panel/VBox/ScrollContainer/VBox
@onready var close_button: Button = $Panel/VBox/CloseButton

func _ready() -> void:
	update_ui()
	close_button.pressed.connect(_on_close_pressed)

func update_ui() -> void:
	# 골드 표시
	gold_label.text = "보유 골드: %d" % SaveManager.gold
	
	# 리스트 초기화
	for child in upgrade_list.get_children():
		child.queue_free()
	
	# 업그레이드 항목 생성
	for id in MetaManager.UPGRADES:
		var data = MetaManager.UPGRADES[id]
		var level = SaveManager.get_upgrade_level(id)
		var cost = MetaManager.get_upgrade_cost(id)
		
		var item = _create_upgrade_item(id, data, level, cost)
		upgrade_list.add_child(item)

func _create_upgrade_item(id: String, data: Dictionary, level: int, cost: int) -> PanelContainer:
	var panel = PanelContainer.new()
	var hbox = HBoxContainer.new()
	panel.add_child(hbox)
	
	var vbox = VBoxContainer.new()
	hbox.add_child(vbox)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var name_lv = Label.new()
	name_lv.text = "%s (Lv.%d/%d)" % [data["name"], level, data["max_level"]]
	name_lv.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_lv)
	
	var desc = Label.new()
	desc.text = data["description"]
	desc.modulate = Color(0.8, 0.8, 0.8)
	desc.add_theme_font_size_override("font_size", 14)
	vbox.add_child(desc)
	
	var buy_btn = Button.new()
	if level >= data["max_level"]:
		buy_btn.text = "MAX"
		buy_btn.disabled = true
	else:
		buy_btn.text = "구매 (%d G)" % cost
		buy_btn.disabled = SaveManager.gold < cost
		buy_btn.pressed.connect(_on_buy_pressed.bind(id))
	
	hbox.add_child(buy_btn)
	buy_btn.custom_minimum_size = Vector2(120, 0)
	
	return panel

func _on_buy_pressed(id: String) -> void:
	if MetaManager.buy_upgrade(id):
		update_ui()

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
