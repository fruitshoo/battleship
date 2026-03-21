# Project Structure Map

이 문서는 현재 프로젝트의 디렉터리 구조를 빠르게 파악하기 위한 안내서입니다.
목표는 "파일이 어디 있는가"보다 "무엇을 고치려면 어디를 보면 되는가"를 빨리 찾는 것입니다.

## 한 줄 요약

이 프로젝트는 크게 아래 5개 층으로 보면 이해가 쉽습니다.

1. `scenes/`
- 실제로 Godot가 여는 장면 파일

2. `scripts/`
- 장면에 붙는 로직

3. `resources/`
- 재사용되는 머티리얼, 환경, 아이템, UI 리소스

4. `assets/`
- 원본 아트/오디오/셰이더 파일

5. `data/`
- JSON 기반 밸런스/정적 규칙 데이터

---

## 최상위 폴더

```text
battleship/
├── assets/       원본 에셋 (오디오, 모델, 폰트, UI, 셰이더, VFX)
├── data/         JSON 데이터 (선박 스탯, 업그레이드, 진행/보상/스폰 규칙)
├── docs/         정리 문서, 라이선스/구조 메모
├── resources/    Godot Resource (.tres, .gdshader 등)
├── scenes/       실제 게임 장면 (.tscn)
├── scripts/      게임 로직 (.gd)
├── build/        빌드 산출물
└── docs/         배포/정리용 문서
```

주의:
- `.godot/`, `.tmp_userdata/`, `.git/`는 보통 작업 대상이 아닙니다.

---

## 가장 많이 보게 되는 규칙

### 1. `scenes/`와 `scripts/`는 보통 짝입니다

예:
- [player_ship.tscn](/Users/shk/Godot/battleship/scenes/ships/player_ship.tscn)
- [player_ship.gd](/Users/shk/Godot/battleship/scripts/entities/ships/player_ship.gd)

즉,
- 장면 배치/노드 구조를 보려면 `scenes/`
- 실제 동작 로직을 보려면 `scripts/`

### 2. `resources/`는 "공용 설정"

예:
- [world_environment_clear_day.tres](/Users/shk/Godot/battleship/resources/environment/world_environment_clear_day.tres)
- [sail_material.tres](/Users/shk/Godot/battleship/resources/materials/sail_material.tres)

즉,
- 특정 장면이 아니라 여러 곳에서 재사용되는 설정은 보통 여기 있습니다.

### 3. `assets/`는 원본 재료

예:
- [assets/audio/sfx](/Users/shk/Godot/battleship/assets/audio/sfx)
- [assets/models](/Users/shk/Godot/battleship/assets/models)
- [assets/vfx](/Users/shk/Godot/battleship/assets/vfx)

즉,
- 실제 그림/소리/텍스처 파일은 여기
- 게임에서 쓰는 묶음/설정은 `resources/` 또는 `scenes/`

### 4. `data/`는 밸런스 값

현재 핵심 파일:
- [ship_stats.json](/Users/shk/Godot/battleship/data/ship_stats.json)
- [upgrades.json](/Users/shk/Godot/battleship/data/upgrades.json)
- [level_progression.json](/Users/shk/Godot/battleship/data/level_progression.json)
- [reward_rules.json](/Users/shk/Godot/battleship/data/reward_rules.json)
- [enemy_spawn_rules.json](/Users/shk/Godot/battleship/data/enemy_spawn_rules.json)

즉,
- "숫자 밸런스"를 건드리고 싶으면 이제 먼저 `data/`를 보는 게 맞습니다.

---

## `scenes/` 빠른 가이드

```text
scenes/
├── main.tscn                실제 게임 메인 씬
├── main_menu.tscn           메인 메뉴
├── ships/
│   ├── player_ship.tscn     플레이어 함선
│   ├── enemy_ship.tscn      일반 적 함선
│   └── boss_ship.tscn       보스 전용 함선
├── entities/
│   ├── soldiers/
│   │   └── soldier.tscn     병사
│   ├── launchers/           대포, 발리스타, 장군전, 신기전 발사기
│   └── weapons/             병사 개인 무기
├── effects/                 연기, 물보라, 부유물, 바다 등
├── projectiles/             화살, 포탄, 로켓, 화통
├── props/                   돛대, 깃발, 러더
├── ships/hulls/             선체 외형 프리팹
└── ui/                      HUD, 업그레이드 창, 옵션 창
```

### 어디를 보면 되는가
- 배 외형이 이상하다
  - `scenes/ships/hulls/`
- 대포/발사기 노드 구성이 궁금하다
  - `scenes/entities/launchers/`
- 병사/개인 무기 구성이 궁금하다
  - `scenes/entities/soldiers/`
  - `scenes/entities/weapons/`
- HUD/메뉴 레이아웃이 궁금하다
  - `scenes/ui/`

---

## `scripts/` 빠른 가이드

```text
scripts/
├── main.gd
├── camera/       카메라 제어
├── effects/      이펙트 동작
├── entities/     배/병사/발사기 및 무기 로직
├── helpers/      공용 유틸
├── managers/     게임 전역 시스템
├── projectiles/  투사체 로직
├── props/        돛대/깃발/러더 로직
├── resource_types/ 커스텀 Resource 클래스
└── ui/           HUD/메뉴 로직
```

### 핵심 폴더 해석

#### `scripts/managers/`
전역 규칙/진행을 잡는 곳

대표 파일:
- [level_manager.gd](/Users/shk/Godot/battleship/scripts/managers/level_manager.gd)
- [enemy_spawner.gd](/Users/shk/Godot/battleship/scripts/managers/enemy_spawner.gd)
- [upgrade_manager.gd](/Users/shk/Godot/battleship/scripts/managers/upgrade_manager.gd)
- [audio_manager.gd](/Users/shk/Godot/battleship/scripts/managers/audio_manager.gd)
- [wind_manager.gd](/Users/shk/Godot/battleship/scripts/managers/wind_manager.gd)

질문으로 바꾸면:
- 레벨업/보상/공적은 어디?
  - `level_manager`
- 적이 언제 나오나?
  - `enemy_spawner`
- 업그레이드 데이터는 어디?
  - `upgrade_manager` + `data/upgrades.json`

#### `scripts/entities/`
실제 게임 유닛 로직

현재는 아래처럼 나뉩니다.

- `scripts/entities/ships/`
- `scripts/entities/soldiers/`
- `scripts/entities/launchers/`
- `scripts/entities/weapons/`

대표 파일:
- [base_ship.gd](/Users/shk/Godot/battleship/scripts/entities/ships/base_ship.gd)
- [player_ship.gd](/Users/shk/Godot/battleship/scripts/entities/ships/player_ship.gd)
- [chaser_ship.gd](/Users/shk/Godot/battleship/scripts/entities/ships/chaser_ship.gd)
- [boss_ship.gd](/Users/shk/Godot/battleship/scripts/entities/ships/boss_ship.gd)
- [soldier.gd](/Users/shk/Godot/battleship/scripts/entities/soldiers/soldier.gd)

여기서 중요한 점:
- 메인 파일 하나 + helper 여러 개로 나뉜 경우가 많습니다

예:
- `base_ship.gd`
  - boarding helper
  - collision helper
  - status helper
  - visual helper
- `player_ship.gd`
  - movement helper
  - crew helper
  - runtime helper
  - support helper

장착 무기 쪽은 따로:
- `scripts/entities/launchers/` = 대포, 발리스타, 장군전, 신기전 발사기
- `scripts/entities/weapons/` = 병사 개인 무기

즉, 한 파일만 보면 안 보이고 helper까지 같이 봐야 전체가 보입니다.

#### `scripts/props/`
배 위 부품 로직

대표 파일:
- [mast.gd](/Users/shk/Godot/battleship/scripts/props/mast.gd)
- [flag.gd](/Users/shk/Godot/battleship/scripts/props/flag.gd)

여기는 최근 정리되어서:
- 상태
- geometry
- wind
- material
- smoke
helper가 나뉘어 있습니다.

#### `scripts/ui/`
HUD/메뉴 동작

대표 파일:
- [game_hud.gd](/Users/shk/Godot/battleship/scripts/ui/game_hud.gd)
- [main_menu.gd](/Users/shk/Godot/battleship/scripts/ui/main_menu.gd)
- [upgrade_ui.gd](/Users/shk/Godot/battleship/scripts/ui/upgrade_ui.gd)
- [ship_control_ui.gd](/Users/shk/Godot/battleship/scripts/ui/ship_control_ui.gd)
- [naval_ui_theme.gd](/Users/shk/Godot/battleship/scripts/ui/naval_ui_theme.gd)

---

## `resources/` 빠른 가이드

```text
resources/
├── environment/  월드 환경, 포스트 프로세싱, 카메라 환경
├── materials/    돛/물/목재 같은 공용 머티리얼
├── items/       아이템 데이터 리소스
└── ui/           UI 관련 리소스
```

어떤 경우 여기부터 보나?
- 포스트 프로세싱이 이상하다
  - `resources/environment/`
- 물/돛 머티리얼이 이상하다
  - `resources/materials/`

---

## 자주 쓰는 탐색 기준

### “밸런스 숫자”를 고치고 싶다
먼저:
- [data](/Users/shk/Godot/battleship/data)

그다음:
- `scripts/managers/`
- `scripts/entities/`

### “화면에 보이는 모양”을 고치고 싶다
먼저:
- `scenes/`
- `resources/materials/`
- `assets/`

### “동작 로직”을 고치고 싶다
먼저:
- `scripts/`

---

## 왜 복잡하게 느껴지는가

현재 헷갈리는 이유는 크게 3개입니다.

1. `scenes/`, `scripts/`, `resources/`, `assets/`가 모두 비슷한 이름으로 병렬 존재
2. `entities/` 안에서 메인 파일 + helper 파일이 많이 분화
3. `scenes/ships/hulls/`와 `scripts/entities/`가 둘 다 "배"처럼 보여 역할 구분이 직관적이지 않음

즉 구조가 무작위는 아닌데, 처음 보면 "같은 것 같은데 다른 폴더"가 많아서 복잡하게 느껴집니다.

---

## 추천 멘탈 모델

프로젝트를 이렇게 생각하면 조금 편합니다.

- `assets` = 원재료
- `resources` = 공용 설정
- `scenes` = 조립된 프리팹
- `scripts` = 행동
- `data` = 숫자 규칙

이 5개만 기억해도 훨씬 덜 복잡해집니다.

---

## 다음 정리 후보

나중에 더 정리한다면 체감이 큰 건 아래입니다.

1. `scenes/entities/`와 `scenes/ships/` 역할을 더 명확히 메모하기
2. `scripts/entities/` helper 분류 규칙을 문서화하기
3. 자주 찾는 핵심 파일만 따로 `ENTRY_POINTS.md` 같은 문서로 만들기
