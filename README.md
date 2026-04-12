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

대시보드 묶음은 `Executive Overview -> Investigation Hub -> Entity Detail` 흐름으로 구성되어 있습니다.

| 레이어 | 대시보드 | UID | 설명 |
|--------|----------|-----|------|
| Executive Overview | Executive Overview | `cc-overview` | 비용, 세션, 지연, 도구 성공률을 먼저 보고 다음 조사 대상을 고르는 진입점 |
| Investigation Hub | API Requests | `cc-api-requests` | request volume, 비용, p95 latency, `api_error` 기반 오류 분해, 느린 요청/오류 상세 |
| Investigation Hub | Tool Analytics | `cc-tool-analytics` | tool decision/execution/success funnel, canary stat, 느린 실행, raw tool detail |
| Investigation Hub | Events Explorer | `cc-events-explorer` | event filter 기반 타임라인, `api_error` 포함 event investigation queue, raw event stream |
| Investigation Hub | Prompt Analytics | `cc-prompt-analytics` | prompt investigation queue, canary column, 최근 user prompt 목록 |
| Entity Detail | Prompt Detail | `cc-prompt-detail` | 개별 prompt의 summary-first 상세, prompt canary stat, session trace coverage, API/tool/event raw detail |
| Entity Detail | Session Explorer | `cc-session-explorer` | 세션 단위 여정, prompt journey, API/tool summary, related traces |
| Entity Detail | Trace Explorer | `cc-trace-explorer` | session-aware trace search, trace timeline, duration distribution |

모든 대시보드는 상단 네비게이션 링크로 상호 연결되며, 시간 범위와 공통 변수는 이동 시 유지됩니다.

## 공통 조사 필터

주요 대시보드는 **User -> Session -> Prompt -> Tool / Model / Event** 흐름의 공통 필터를 공유합니다.

- **User**: Prometheus의 `user_email` 레이블에서 동적으로 조회됩니다.
- **Session / Prompt / Tool / Model**: Loki 로그에서 현재 범위에 존재하는 값으로 동적으로 좁혀집니다.
- **Event**: `api_request`, `api_error`, `tool_result`, `tool_decision`, `user_prompt` 필터를 공통 event 축으로 사용합니다.
- 대시보드 첫 진입 시에는 첫 번째 사용자 값이 기본 선택되고, 나머지 필터는 기본적으로 `All` 상태로 시작합니다.
- 표의 `Prompt ID`, `Session ID`, `Tool`, `Model`, `Event` 컬럼은 drilldown link를 포함하므로 수동 ID 입력 없이 상세 화면으로 이동할 수 있습니다.
- Trace Explorer는 `session.id` span attribute를 이용해 세션 단위 trace correlation을 지원합니다.

## Grafana Alerting

기본 canary alert rule도 함께 provision 됩니다.

- 규칙 파일: [grafana/provisioning/alerting/claude-code-canary-rules.yml](/Users/shinukyi/Gallary/projects/proto/agent-observability/grafana/provisioning/alerting/claude-code-canary-rules.yml)
- 기본 룰 그룹: `claude-code-canary`
- 포함된 경보:
  - `Claude Code API Error Rate Elevated`
  - `Claude Code Abort Reject Rate Elevated`
  - `Claude Code Write Share Elevated`

현재 저장소에는 contact point / notification policy provisioning은 포함하지 않았습니다.
따라서 alert rule은 자동 생성되지만, 실제 알림 전송은 Grafana UI의 `Alerting` 메뉴에서 contact point와 routing policy를 별도로 연결해야 합니다.

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
