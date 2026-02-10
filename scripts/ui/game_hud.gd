extends CanvasLayer

## 게임 HUD (Game HUD)
## 레벨, 점수, 선원 상태 등을 시각화함

@onready var level_label: Label = $TopPanel/HBox/LevelLabel
@onready var score_label: Label = $TopPanel/HBox/ScoreLabel
@onready var enemy_count_label: Label = $SidePanel/VBox/EnemyCountLabel
@onready var crew_label: Label = $SidePanel/VBox/CrewLabel

func _ready() -> void:
	# 초기화
	update_level(1)
	update_score(0)
	update_enemy_count(0)
	update_crew_status(4) # 기본 선원 4명

func update_level(val: int) -> void:
	if not is_inside_tree() or level_label == null: return
	level_label.text = "LEVEL: " + str(val)

func update_score(val: int) -> void:
	if not is_inside_tree() or score_label == null: return
	score_label.text = "SCORE: " + str(val)

func update_enemy_count(val: int) -> void:
	if not is_inside_tree() or enemy_count_label == null: return
	enemy_count_label.text = "ENEMIES: " + str(val)

func update_crew_status(count: int) -> void:
	if not is_inside_tree() or crew_label == null: return
	crew_label.text = "CREW: " + str(count) + " / 4"
