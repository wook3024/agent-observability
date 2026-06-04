# Observability Stack

이 폴더는 Docker Compose로 실행하는 로컬 observability 스택입니다.
구성 요소는 OpenTelemetry Collector, Loki, Prometheus, Tempo, Grafana입니다.

## 포함 범위

- 포함됨: Docker Compose 설정, Grafana provisioning, Grafana dashboards, Grafana alert rule provisioning
- 포함되지 않음: 실행 후 쌓이는 metrics/logs/Grafana 내부 상태 데이터

현재 데이터는 Docker named volume에 저장되므로, 다른 PC로 이 폴더만 복사하면 설정은 그대로 재현되지만 기존 수집 데이터까지 같이 이동하지는 않습니다.

## 고정된 이미지 버전

- `otel/opentelemetry-collector-contrib:0.149.0`
- `grafana/loki:3.0.0`
- `prom/prometheus:v3.11.1`
- `grafana/tempo:2.7.2`
- `grafana/grafana:12.4.2`

위 버전 조합으로 실제 `docker compose up -d` 기동 검증을 완료했습니다.

## 현재 수집 경로

- Logs: `Codex / Claude Code -> OTEL Collector -> Loki`
- Metrics: `Codex / Claude Code -> OTEL Collector(prometheus exporter) -> Prometheus scrape`
- Traces: `Codex / Claude Code -> OTEL Collector -> Tempo`

`Prometheus remote write` 대신 Collector의 `prometheus exporter`를 `Prometheus`가 scrape하는 구조로 운영합니다. `Codex CLI` 메트릭은 현재 이 경로에서 안정적으로 확인되었습니다.

## 사전 조건

- Docker Desktop 또는 Docker Engine 설치
- `docker compose` 사용 가능
- 아래 포트가 비어 있어야 함
  - `3000` Grafana
  - `3100` Loki
  - `4317` OTLP gRPC
  - `4318` OTLP HTTP
  - `3200` Tempo
  - `9090` Prometheus
  - `13133` OTEL Collector health check

## 실행 방법

프로젝트 루트에서 아래 명령을 실행합니다.

```bash
docker compose up -d
```

상태 확인:

```bash
docker compose ps
```

중지:

```bash
docker compose down
```

볼륨까지 포함해 완전히 초기화:

```bash
docker compose down -v
```

## 자동 실행

모든 서비스에 `restart: unless-stopped` 정책이 설정되어 있습니다. OrbStack(또는 Docker Desktop)이 시작되면 컨테이너가 자동으로 함께 올라옵니다.

최초 1회만 `docker compose up -d`로 실행하면, 이후에는 OrbStack 재시작 시 별도 명령 없이 자동 복구됩니다.

수동으로 `docker compose down`을 실행한 경우에는 다시 `docker compose up -d`가 필요합니다.

## Grafana 대시보드

대시보드는 `Overview -> Investigation -> Detail` 흐름의 **6종**으로 구성되어 있습니다. 모든 패널은 14일치 라이브 데이터에서 실제로 채워지는 필드만 사용합니다.

| 레이어 | 대시보드 | UID | 설명 |
|--------|----------|-----|------|
| Overview | Executive Overview | `cc-overview` | 진짜 canary(툴 실패율·cache 효율·subagent 비용 비중) + 비용/지연 추세 + 세션 조사 큐. 여기서 다음 조사 대상을 고른다 |
| Investigation | Activity & Cost | `cc-activity` | 요청/비용/토큰 요약, **effort·query_source(서브에이전트)·model×version** 분해, cache 효율 추세, prompt 조사 큐 |
| Investigation | Tools & Edits | `cc-tool-analytics` | decision→execution→success 퍼널, **툴 실패(실제 `error` 텍스트)**, Read:Edit·반복 파일 편집, code-edit 결정(Prometheus) |
| Investigation | Events Explorer | `cc-events-explorer` | **15종 이벤트** 필터·타임라인·조사 큐. 행에서 `trace_id`로 Trace Explorer 연결 |
| Detail | Entity Detail (Session/Prompt) | `cc-session-explorer` | 세션(선택적으로 프롬프트) 요약·canary·API/tool 요약·세션 트레이스·원시 타임라인 |
| Detail | Trace Explorer | `cc-trace-explorer` | 세션 단위 trace 검색·타임라인·duration 분포 |

모든 대시보드는 상단 네비게이션 링크로 상호 연결되며, 시간 범위와 공통 변수는 이동 시 유지됩니다.

> **라이브 데이터 기준 주의 (2026-06-04 검증)**
> - **`api_error` 이벤트는 이 Claude Code 빌드에서 발생하지 않습니다.** API 신뢰성은 `api_error`가 아니라 **도구 실패율(`tool_result | success="false"`, 실제 `error` 텍스트)** 로 추적합니다.
> - **로그의 `user_email`/`user_id`는 항상 `unknown`** 입니다(실제 식별자는 Prometheus 라벨·로그의 `user_account_id`에만). 따라서 대시보드에 **User 필터가 없습니다**(사실상 단일 사용자). 다사용자로 확장하려면 OTEL 측에서 사용자 메타데이터를 채우거나 `user_account_id` 기준으로 전환하세요.
> - **트레이스는 실재합니다**(`claude_code.interaction` 루트, span별 `session.id`). 로그에도 `trace_id`가 있어 로그↔트레이스 상호 연결이 가능합니다.
> - Loki에서 `service_name`만 인덱스 라벨이고 나머지(`event_name`, `tool_name`, `model`, `session_id` 등)는 structured metadata이므로 `{service_name=~"$service"} | event_name = "..."` 형태로 조회합니다.

## Codex CLI 대시보드

`Codex CLI`용 초안 대시보드도 함께 포함되어 있습니다.

| 대시보드 | UID | 설명 |
|--------|-----|------|
| Codex CLI - Executive Overview (Draft) | `codex-overview` | 메트릭 기반 turn/latency/token 요약 + Loki 조사 패널 |
| Codex CLI - Tool & API Analytics (Draft) | `codex-tool-api-analytics` | tool/api investigation 중심 패널 + metric throughput |

실제 검증 결과 기준:

- Loki 로그 식별 키: `service_name="codex_cli_rs"`
- Prometheus 메트릭 식별 키: `exported_job="codex_cli_rs"`
- `event_name`, `tool_name`, `user_email`, `originator`, `session_source`, `model`은 Loki selector 라벨이 아니라 structured metadata 필드로 다루는 편이 안전합니다.
- 따라서 LogQL은 `{service_name="codex_cli_rs"} | event_name = "codex.tool_result"` 같은 형태를 사용해야 합니다.

## 공통 조사 필터

주요 대시보드는 **Service -> Session -> Prompt -> Tool / Model / Event** 흐름의 공통 필터를 공유합니다.

- **Service**: `claude-code` / `claude-code-desktop` / 둘 다(`claude-code.*`) 중 선택. 기본 `claude-code`.
- **Session / Prompt / Tool / Model**: Loki 로그에서 현재 범위에 존재하는 값으로 동적으로 좁혀집니다(structured metadata).
- **Event**: 15종 이벤트(`api_request`, `tool_result`, `tool_decision`, `user_prompt`, `compaction`, `subagent_completed`, `skill_activated`, `hook_*`, `mcp_server_connection`, `permission_mode_changed`, `plugin_loaded`, `at_mention`, `feedback_survey`)를 공통 event 축으로 사용합니다.
- **User 필터는 없습니다.** 로그의 `user_email`이 항상 `unknown`이라 무의미하기 때문입니다. 멀티유저 환경에서는 `user_account_id` 기반으로 전환하세요.
- 표의 `Session ID`, `Prompt ID`, `Tool`, `Model`, `Trace` 컬럼은 drilldown link를 포함하므로 수동 ID 입력 없이 상세 화면으로 이동할 수 있습니다.
- Events Explorer / Entity Detail의 `Trace` 컬럼과 Trace Explorer는 `trace_id` / `session.id`로 로그↔트레이스를 연결합니다.

## Grafana Alerting

canary alert rule이 provision 됩니다. 모든 규칙은 라이브에서 실제로 비0인 신호만 사용합니다. **알림 전송(contact point / notification policy)은 기본적으로 비활성화** 되어 있습니다 — 규칙은 평가/표시되지만 실제 알림은 전송되지 않습니다.

- 규칙 파일: [grafana/provisioning/alerting/claude-code-canary-rules.yml](grafana/provisioning/alerting/claude-code-canary-rules.yml)
- 알림 경로 파일: [grafana/provisioning/alerting/notifications.yml](grafana/provisioning/alerting/notifications.yml)
- 룰 그룹: `claude-code-canary`
- 포함된 경보:
  - `Claude Code Tool Failure Rate Elevated` — `tool_result success=false` 비율 > 15% (baseline ≈ 2.6%)
  - `Claude Code Write Share Elevated` — `Write / (Edit|Write)` > 60%
  - `Claude Code Subagent Cost Share Elevated` — Prometheus `query_source=subagent` 비용 비중 > 50% (baseline ≈ 26%)

> 구버전의 `API Error Rate` / `Abort Reject Rate` 규칙은 제거했습니다. `api_error`와 `user_abort/user_reject`가 발생하지 않아 **항상 0인 죽은 규칙**이었습니다.

알림을 활성화하려면 [grafana/provisioning/alerting/notifications.yml](grafana/provisioning/alerting/notifications.yml)의 주석 처리된 `contactPoints`/`policies` 블록을 해제하고 `settings.url`을 본인 Slack/Discord/사내 webhook 주소로 교체한 뒤 Grafana를 재기동하세요.

## Claude Code OTEL 환경변수

Claude Code 텔레메트리를 이 스택으로 전송하기 위한 환경변수입니다. `~/.claude/settings.json` 파일의 `env` 블록에 추가합니다.

```json
{
  "env": {
    // 텔레메트리 활성화
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    // 트레이싱 활성화 (베타, traces 전송에 필수)
    "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",

    // Exporter 활성화 (logs/metrics/traces)
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_TRACES_EXPORTER": "otlp",

    // 엔드포인트 및 프로토콜
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",

    // 전송 주기 (ms)
    "OTEL_METRIC_EXPORT_INTERVAL": "10000",
    "OTEL_LOGS_EXPORT_INTERVAL": "5000",

    // Prometheus 호환 (cumulative temporality)
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "cumulative",

    // 로그 상세 수준 (프롬프트 내용 및 도구 실행 상세)
    "OTEL_LOG_USER_PROMPTS": "1",
    "OTEL_LOG_TOOL_DETAILS": "1",

    // 메트릭에 계정/세션/버전 정보 포함
    "OTEL_METRICS_INCLUDE_SESSION_ID": "true",
    "OTEL_METRICS_INCLUDE_VERSION": "true",
    "OTEL_METRICS_INCLUDE_ACCOUNT_UUID": "true",

    // 리소스 속성 (조직 구분용, 선택)
    "OTEL_RESOURCE_ATTRIBUTES": "department=personal,team.id=solo"
  }
}
```

> - `CLAUDE_CODE_ENABLE_TELEMETRY`를 `"1"`로 설정해야 텔레메트리가 활성화됩니다. 이 값이 없으면 나머지 OTEL 환경변수를 설정해도 데이터가 전송되지 않습니다.
> - `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA`를 `"1"`로 설정해야 **트레이스(spans)**가 전송됩니다. 이 값이 없으면 메트릭과 로그만 전송되고 Trace Explorer 대시보드에 데이터가 표시되지 않습니다.

## Codex CLI OTel 설정

`Codex CLI`는 `~/.codex/config.toml`의 `[otel]` 블록으로 연결합니다.

```toml
[otel]
environment = "dev"
log_user_prompt = true
exporter = { otlp-http = { endpoint = "http://localhost:4318/v1/logs", protocol = "binary" } }
trace_exporter = { otlp-http = { endpoint = "http://localhost:4318/v1/traces", protocol = "binary" } }
metrics_exporter = { otlp-http = { endpoint = "http://localhost:4318/v1/metrics", protocol = "binary" } }
```

운영 메모:

- 공식 문서 예시처럼 `exporter`, `trace_exporter`, `metrics_exporter`는 `[otel]` 아래의 inline table 형태가 안정적으로 동작했습니다.
- 로그는 Loki에서 `service_name="codex_cli_rs"`로 보입니다.
- 메트릭은 Prometheus에서 `codex_*` 이름으로 보이며 `exported_job="codex_cli_rs"` 라벨로 필터링하는 편이 안정적입니다.

## 접속 주소

- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`
- Tempo: `http://localhost:3200`
- Loki API: `http://localhost:3100`
- OTLP gRPC: `localhost:4317`
- OTLP HTTP: `http://localhost:4318`

Grafana 기본 계정:

- ID: `admin`
- Password: `admin`

익명 조회도 활성화되어 있습니다.

## 빠른 시작 (새 환경)

```bash
# 1. 이 저장소를 클론하거나 폴더를 복사
# 2. Docker가 설치된 상태에서 실행
docker compose up -d
```

설정과 대시보드가 동일하게 올라옵니다. 기존 수집 데이터는 Docker volume에 저장되므로 별도 백업/복원이 필요합니다.
