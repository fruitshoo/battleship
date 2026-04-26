# Flag Scenes

`scenes/props/flag.tscn`은 깃대와 천을 함께 가진 공통 베이스입니다. 특정 깃발을 만들거나 고칠 때는 이 파일보다 이 폴더의 `flag_*.tscn` 파일을 열어 수정합니다.

## 무엇을 열어야 하나

- `flag_player_flagship.tscn`: 플레이어 기함 깃발
- `flag_player_support.tscn`: 지원함 깃발
- `flag_enemy_pennant.tscn`: 일반 적 삼각 깃발
- `flag_enemy_sekibune.tscn`: 세키부네 계열 깃발
- `flag_enemy_elite_tabs.tscn`: 정예 깃발
- `flag_boss_swallowtail.tscn`: 보스 제비꼬리 깃발
- `flag_site_marker.tscn`: 지도/장소 표시용 깃발

## 주로 만질 값

씬 루트 노드를 선택하고 Inspector의 `Cloth`, `Wind` 값만 조정합니다.

- `color`: 천 기본색
- `flag_shape`: 천 모양. `RECTANGLE`, `TRIANGLE`, `SWALLOWTAIL`을 주로 씁니다.
- `flag_size`: 천 크기. x는 가로, y는 세로입니다.
- `flag_texture`: 천 전체 텍스처. 넣으면 자동으로 사용됩니다.
- `emblem_texture`: 천 위에 얹을 문장 텍스처. 넣으면 자동으로 사용됩니다.
- `swallowtail_depth`, `swallowtail_gap`: `SWALLOWTAIL`일 때 꼬리 파임
- `wind_mode`: 바람 반응 방식
- `wave_speed`, `wave_strength`, `side_drag`: 펄럭임

## 바람 반응

- `FREE_ROTATE`: 한쪽만 묶인 작은 깃발처럼 바람 방향을 따라 천이 회전합니다.
- `FIXED_FLUTTER`: 여러 고정점에 묶인 큰 깃발처럼 에디터에서 잡은 위치/각도를 유지하고 펄럭임만 적용합니다.

현재 큰 지휘 깃발 성격의 `flag_player_flagship.tscn`, `flag_enemy_elite_tabs.tscn`, `flag_boss_swallowtail.tscn`은 `FIXED_FLUTTER`로 둡니다. 작은 삼각 표식인 `flag_player_support.tscn`, `flag_enemy_pennant.tscn`은 `FREE_ROTATE`로 둡니다.

## 건드리지 않는 편이 좋은 것

- `flag_kind`: 새 깃발 종류를 라이브러리에 등록할 때만 바꿉니다.
- `Pole`, `FlagMesh` 노드 이름: `flag.gd`가 이 이름으로 노드를 찾습니다.
- `flag.tscn`: 모든 깃발이 공유하는 베이스라서 한 종류만 고치려면 수정하지 않습니다.

깃대는 `flag.tscn` 안에 있습니다. 깃대 높이는 천 크기(`flag_size.y`)에 맞춰 자동으로 정해지므로 각 variant에서 따로 만지지 않습니다.

천 위치나 각도를 직접 조정하고 싶으면 child 노드 `FlagMesh`를 이동/회전/스케일합니다. `FIXED_FLUTTER`에서는 그 transform이 런타임에도 유지되고, `FREE_ROTATE`에서는 그 transform을 기준으로 바람 방향 회전이 더해집니다.
