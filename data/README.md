# Data Layout

이 디렉터리는 게임의 정적 데이터와 밸런스 테이블을 보관합니다.

현재 사용 중인 파일:
- `ship_stats.json`
- `upgrades.json`
- `level_progression.json`
- `reward_rules.json`
- `enemy_spawn_rules.json`
- `authoring_palette.json`
- `soldier_rules.json`

추가 후보:
- `boss_rules.json`

## Recommended 1st Phase

우선순위가 높은 데이터 파일은 아래 3개입니다.

1. `level_progression.json`
- 시간/레벨에 따른 난이도 진행
- 레벨별 적 생성 간격, 동시 적 수
- XP/지휘 성장 곡선

2. `reward_rules.json`
- 병사 처치 보상
- 수장 보상
- 백병전 추가 보상
- 나포 보상

3. `enemy_spawn_rules.json`
- 일반 적 스폰 거리/간격
- `spawn_recipes` 기반 차단진/편대 조립 규칙
- `encounter_profiles` 기반 시간대별 편대 풀 선택
- `scenario_triggers` 기반 조건/액션형 전개 전환
- 함종 비율 변화
- 엘리트/중간보스 호위 구성

4. `authoring_palette.json`
- 조립 가능한 함선/무기/전투/스폰/전개 부품 목록
- `assembly_blocks` 기반 실행/카드/참조 블록 스키마
- 맵에디터식 팔레트 UI나 디버그 메뉴에서 참조할 stable id 묶음
- 원본 데이터와의 참조 무결성 검증

## Recommended 2nd Phase

5. `soldier_rules.json`
- 병사 기본 체력, 공격력, 이동속도
- 탐지/무기 전환 거리
- cross-ship 교전 기준 거리
- 플레이어 장군(captain) 기본 보정

## Example Files

이 디렉터리에는 아직 런타임에서 사용하지 않는 예시 템플릿이 들어 있습니다.
이 파일들은 실제 마이그레이션 전에 구조를 합의하거나 값을 채워 넣기 위한 초안입니다.

- `level_progression.example.json`
- `reward_rules.example.json`
- `enemy_spawn_rules.example.json`

## Notes

- 씬 경로, 머티리얼 값, 카메라 세팅, UI 테마 색은 `/data`보다 현재 씬/스크립트 기반 관리가 더 적합합니다.
- 실제 연결을 시작할 때는 예시 파일을 복사해 `.json` 실파일로 만들고, 로더를 붙이는 식이 가장 안전합니다.
