# Ship AI Flow Map

이 문서는 현재 함선 AI 흐름을 고정해두기 위한 메모입니다.
목표는 리팩터링을 바로 하자는 것이 아니라, 어떤 파일이 어떤 책임을 갖는지 먼저 보이게 만드는 것입니다.

작성 기준: 2026-05-12

## 핵심 요약

1. 역할은 나뉘어 있다.
- 플레이어, 일반 적선, 지원함, 나포함, 보스는 진입점과 세부 로직이 다르다.
- 다만 충돌, 도선, 상태, 선원 같은 공통 시스템은 `BaseShip` 계열 helper를 공유한다.

2. LimboAI는 "판단층"에 가깝다.
- `scripts/ai/limbo/ship_limbo_ai_pilot.gd`가 BehaviorTree를 수동 tick 한다.
- 그 결과는 대체로 meta 값으로 저장된다.
- 실제 이동, 충돌, 도선, 발사는 기존 ship/helper/launcher 로직이 수행한다.

3. 무리해서 한 군데로 합치면 위험하다.
- 현재 구조는 파편화되어 보이지만, 전투 역할별 예외가 꽤 많다.
- 안전한 방향은 먼저 흐름 문서화, 프로파일링 라벨, 계약 테스트를 보강한 뒤 작은 단위로 정리하는 것이다.

## 큰 흐름

```text
Scene/Spawner
  -> Ship node
    -> _process: 시각/상태 갱신
    -> _physics_process: 이동/전투/충돌 갱신
      -> LimboAI tick, 선택 사항
      -> 역할별 helper 실행
      -> navigation intent 계산
      -> 도선/발사/조타/속도 계산
      -> 충돌 guard, repulsion, wake, 이펙트
```

## 주요 진입점

| 대상 | 진입점 | 주 책임 |
| --- | --- | --- |
| 플레이어 함선 | `scripts/entities/ships/player_ship.gd` | 입력, 조타, 돛/노, 지원함 소환/관리, 자동 도선 스캔 |
| 일반 적선 | `scripts/entities/ships/ai_ship.gd` | 추적선 기본 상태, LimboAI tick, 적/지원함 분기, 공통 AI 호출 |
| 적선 AI 실행 | `scripts/entities/ships/ai_ship_runtime_helper.gd` | 타겟 확인, 분리력, 항법, 도선 시도, 이동/충돌 guard |
| 지원함/legacy 나포함 | `scripts/entities/ships/ai_ship_support_helper.gd` | 호위진, 합류, 구조, 위협 차단, 재집결 |
| 지원함 역할/대형 | `scripts/entities/ships/support_fleet_formation_helper.gd` | 슬롯, 좌우 배치, 열/익형 대형, 회전 시 따라갈 위치 |
| 지원함 상태 | `scripts/entities/ships/support_fleet_state_helper.gd` | 현재 대형/역할 상태 해석 |
| 보스 | `scripts/entities/ships/boss_ship.gd` | 별도 선회/거리 유지 AI, 보스 전용 LimboAI, 공통 상태/충돌 사용 |
| 병사 | `scripts/entities/soldiers/soldier.gd` | 갑판 전투, 이동, 도선 후 행동, 병사 LimboAI |

## 적선 흐름

일반 적선은 대부분 `AIShip`에서 시작해서 `AIShipRuntimeHelper`로 내려간다.
`ChaserShip` 이름은 기존 씬/테스트 호환을 위한 alias로만 남겨둔다.

```text
AIShip._physics_process(delta)
  -> _update_limbo_ai_pilot(delta)
  -> AIShipRuntimeHelper.process_physics(self, delta)
```

`AIShipRuntimeHelper.process_physics` 안에서는 대략 아래 순서로 움직인다.

```text
process_physics
  -> wave sound
  -> logic timer, separation timer
  -> 폐선이면 표류/오프스크린 처리 후 종료
  -> crew allocation 갱신
  -> throttled logic update
  -> team == player 이면 지원함/나포함 경로로 분기
  -> 도선 중이면 AIShipBoardingHelper.process_boarding
  -> 타겟 없으면 정지
  -> AIShipNavigationHelper.build_navigation
  -> 도선 가능 거리/각도/충돌 확인
  -> 조타, 속도, 돛/바람 보정
  -> collision repulsion, boarding pull, impulse 합산
  -> collision guard 적용
  -> 위치/러더/wake/피해 상태 갱신
```

중요한 점:
- `AIShipRuntimeHelper`는 "적선 전용"처럼 보이지만, `team == player` 분기 때문에 지원함/legacy 나포함도 여기서 갈라진다.
- 그래서 이 파일을 단순히 적 AI로만 생각하면 나중에 지원함 동작을 깨뜨리기 쉽다.

## 지원함과 Legacy 나포함 흐름

지원함과 legacy 나포함도 기본적으로 `AIShip` 계열이다.

```text
AIShipRuntimeHelper.process_physics
  -> team == "player"
    -> AIShip._process_support_ai
      -> AIShipSupportHelper.process_support_ai
```

`AIShipSupportHelper`는 아래 성격의 일을 한꺼번에 맡고 있다.
- 플레이어 또는 기함 찾기
- 호위진 슬롯 계산
- 새로 합류한 지원함의 합류 단계 처리
- 회전 중 열/익형 대형 보정
- 위협 감지, 구조, 차단, 재집결
- legacy 나포함의 guard/regroup 행동

대형 위치 계산 자체는 `SupportFleetFormationHelper` 쪽으로 빠져 있다.
즉 `AIShipSupportHelper`는 "상황 판단과 실행", `SupportFleetFormationHelper`는 "어디에 있어야 하는가"에 가깝다.

## LimboAI의 위치

LimboAI는 함선마다 직접 위치를 옮기는 최종 실행자가 아니다.

```text
ShipLimboAIPilot.tick
  -> BehaviorTree update
  -> target/stance/range/navigation/weapon/boarding/support meta 기록
  -> 기존 helper들이 meta를 읽어서 실행
```

현재 계약은 두 단계로 나뉜다.
- `ShipAIPerceptionHelper`: BT 태스크 안에서 필요한 관측값을 읽는다. 예를 들어 팀, 포격선 역할, 도선 가능 여부, 선체 비율, 교전 거리, 예측 타겟 위치를 여기서 얻는다.
- `ShipAIIntentHelper`: BT가 쓴 meta를 실행층이 읽을 수 있는 intent dictionary로 바꾼다. gameplay/debug 쪽에서는 `ShipAILimboKeys.META_*`를 직접 읽지 않고 이 helper를 통과한다.

대표적으로 읽히는 값:
- `META_TARGET_ID`
- `META_INTENT`
- `META_STANCE`
- `META_NAV_DESIRED_POINT`
- `META_NAV_HEADING_POINT`
- `META_NAV_SPEED_MULT`
- `META_WEAPON_INTENT`
- `META_BOARDING_INTENT`
- `META_SUPPORT_MODE`
- `META_ALLY_MODE` (legacy capture meta)

이 값들은 아래 쪽에서 사용된다.
- `AIShipNavigationHelper`: 이동 목표와 조타 힌트
- `AIShipRuntimeHelper`: 도선 의도와 AI 디버그 표시
- `LauncherCombatHelper`: 발사/사격 의도
- `AIShipLifecycleHelper`: 화공 등 특수 공격 의도
- `AIShipSupportHelper`: 지원함/legacy 나포함 모드
- `BossShip`: 보스 거리 유지, 선회, 압박 단계

따라서 LimboAI를 바꿀 때는 "행동 결정"이 바뀌는지, "기존 실행층이 읽는 meta 계약"이 깨지는지를 같이 봐야 한다.
BT 태스크의 관측 로직은 perception helper에, 실행층의 meta 해석은 intent helper에 두는 것이 현재 기준선이다.

## 전투 역할

| 역할 | 대표 파일 | 특징 |
| --- | --- | --- |
| 근접 적선 | `enemy_melee_ship.gd`, `ai_ship.gd` | 접근, 충돌 확인, 측면/정면/마무리 도선 |
| 원거리 적선 | `enemy_gunner_ship.gd`, `ai_ship.gd` | 거리 유지, 포격, 도선 비활성 |
| 화공 계열 | `enemy_firepot_ship.gd`, `ai_ship_lifecycle_helper.gd` | 특수 공격 의도와 쿨다운 처리 |
| 지원함 | `support_ship.gd`, `ai_ship_support_helper.gd` | 플레이어 호위, 슬롯 유지, 구조/차단 |
| legacy 나포함 | `ai_ship.gd`의 `capture_ship` 이후 | 플레이어 팀으로 전환, 나포함 역할, 추종/호위 |
| 보스 | `boss_ship.gd` | 별도 선회 AI, 보스 전용 BehaviorTree, 보스 HUD |

## 공통 시스템

이 부분은 여러 함선이 같이 쓰므로 특히 조심해야 한다.

| 시스템 | 파일 | 역할 |
| --- | --- | --- |
| 선체 접촉 치수 | `scripts/entities/ships/ship_contact_geometry.gd` | 충돌/도선 거리용 half extents, directional radius |
| 충돌/충격 | `scripts/entities/ships/base_ship_collision_helper.gd` | 충돌 이벤트, 밀림, 충돌 피해, 이펙트/SFX |
| 공통 도선 상태 | `scripts/entities/ships/base_ship_boarding_helper.gd` | 밧줄, boarding link, 공통 도선 tick |
| 적선 도선 실행 | `scripts/entities/ships/ai_ship_boarding_helper.gd` | 접근 유지, latch, collision guard |
| 전투 모드 판정 | `scripts/entities/ships/ship_combat_mode_helper.gd` | gunner/charger, boarding 가능 여부 |
| 선원 배치 | `scripts/entities/ships/base_ship_crew_helper.gd` | 선원 슬롯, 배 위 병사 관리 |
| 병사 AI | `scripts/entities/soldiers/soldier_ai_helper.gd` | 병사 목표/상태 행동 |
| 병사 우선순위 | `scripts/entities/soldiers/soldier_ship_work_priority_helper.gd` | 병사가 배 위에서 무엇을 할지 우선순위 |

## 성능 관점의 tick 정책

현재 의도는 아래처럼 나눠 보는 것이 맞다.

### 매 physics frame에 필요한 것

- 실제 위치/회전/속도 반영
- 충돌 guard와 repulsion
- 도선 중 위치 유지
- wake, 러더, 피해 tick 같은 즉시 보이는 상태

### throttling 가능한 것

- LimboAI 판단 tick
- 타겟 재탐색
- 함선 간 separation 재계산
- 지원함/legacy 나포함의 무거운 대형 계산
- 주변 위협 평가

### 이벤트 중심에 가까운 것

- 나포 성공/실패
- 도선 시작/해제
- 지원함 새로 합류
- 무장 장착/업그레이드 적용
- 병사 생성/사망/복귀

성능 문제가 생겼을 때는 "전체 AI가 느리다"보다 먼저 어느 bucket이 커졌는지 봐야 한다.
최근에는 `ai_ship_process_total`, `support_ai`, `soldier_limbo_ai`, `soldier_state_wander` 같은 profiler label이 특히 중요했다.

## 안전하게 고치는 순서

1. 먼저 프로파일러와 계약 테스트로 현재 동작을 고정한다.
2. 역할 경계를 문서나 작은 주석으로 더 명확히 한다.
3. 같은 값을 여러 곳에서 쓰는 경우만 helper로 빼낸다.
4. 움직임, 충돌, 도선, LimboAI meta 계약을 한 번에 바꾸지 않는다.
5. 체감 테스트는 반드시 같이 한다.

우선 확인할 테스트:
- `scripts/test/run_limboai_ship_ai_pilot_contract.sh`
- `scripts/test/run_ship_ai_perception_helper_contract.sh`
- `scripts/test/run_ship_ai_intent_helper_contract.sh`
- `scripts/test/run_boarding_contracts.sh`
- `scripts/test/run_project_contract_sweep.sh`
- `scripts/test/run_modularity_guard_suite.sh`
- `scripts/test/run_midgame_support_fleet_performance_probe.sh 20 5`

## 나중에 해볼 만한 정리

낮은 위험도부터:

1. `AIShipRuntimeHelper` 상단에 enemy/support/captured 분기 요약 주석 추가
2. `AIShipSupportHelper` 내부를 formation, assist, join, guard 섹션으로 더 명확히 접기
3. LimboAI meta 이름과 읽는 위치를 작은 표로 별도 문서화
4. 공통 tick interval 계산만 작은 helper로 분리
5. 충분히 테스트가 쌓인 뒤에만 파일 이동/이름 변경 검토

지금은 구조를 크게 뒤집기보다, 이 지도를 기준으로 "어디를 건드리면 어떤 역할이 영향받는지"를 먼저 보며 가는 쪽이 안전하다.
