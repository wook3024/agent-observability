# Claude Code 품질 회귀 감지 능력 분석

> GitHub Issue: [anthropics/claude-code#42796](https://github.com/anthropics/claude-code/issues/42796)
> 분석일: 2026-04-12
> 목적: 이슈에서 제기된 품질 회귀 문제를 현재 관측 스택으로 감지할 수 있는지, 프롬프트 개선 판단이 가능한지 평가

---

## 1. 이슈 요약

### 핵심 주장

Claude Code의 **extended thinking 깊이 감소**(`redact-thinking-2026-02-12` 롤아웃)가 복잡한 엔지니어링 작업의 품질 저하로 직결된다. 17,871개의 thinking block과 234,760건의 tool call을 분석하여 증명.

### 핵심 증거 지표

| 지표 | Good 기간 (1/30-2/12) | Degraded 기간 (3/8-3/23) | 변화 |
|------|----------------------|-------------------------|------|
| Read:Edit 비율 | 6.6 | 2.0 | **-70%** |
| 읽지 않고 편집한 비율 | 6.2% | 33.7% | **+5.4배** |
| 유저 인터럽트율 (/1K tool call) | 0.9 | 5.9 | **+6.6배** |
| Reasoning 루프 (/1K tool call) | 8.2 | 21.0 | **+2.6배** |
| Stop hook 위반 (총) | 0 | 173 | 0 → 10/일 |
| 추정 일일 비용 | $12 | $1,504 | **+122배** |
| 프롬프트 감정 비율 (긍정:부정) | 4.4:1 | 3.0:1 | **-32%** |
| Write(전체 재작성) 비율 | 4.9% | 10.0% | **+2배** |
| "simplest" 빈도 (/1K words) | 0.01 | 0.09 | **+642%** |

### 이슈 작성자의 요청사항

1. Thinking 할당량 투명성
2. "Max thinking" 유료 티어
3. API 응답에 `thinking_tokens` 메트릭 추가
4. Stop hook 위반율 같은 canary 지표 모니터링

---

## 2. 현재 관측 스택 구성

> 이 섹션의 환경변수 값은 저장소 안의 설정 파일과 `README.md`에 근거한 **권장/가정 상태**다. 실제 사용자 런타임에서 현재 활성화되었는지는 이 저장소만으로는 직접 검증되지 않았다.

### 환경변수 (권장/가정 상태)

| 환경변수 | 값 | 상태 |
|---------|---|------|
| `CLAUDE_CODE_ENABLE_TELEMETRY` | `1` | ✅ |
| `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA` | `1` | ✅ |
| `OTEL_METRICS_EXPORTER` | `otlp` | ✅ |
| `OTEL_LOGS_EXPORTER` | `otlp` | ✅ |
| `OTEL_TRACES_EXPORTER` | `otlp` | ✅ |
| `OTEL_LOG_USER_PROMPTS` | `1` | ✅ |
| `OTEL_LOG_TOOL_DETAILS` | `1` | ✅ |
| `OTEL_METRICS_INCLUDE_SESSION_ID` | `true` | ✅ |
| `OTEL_METRICS_INCLUDE_VERSION` | `true` | ✅ |
| `OTEL_METRICS_INCLUDE_ACCOUNT_UUID` | `true` | ✅ |
| **`OTEL_LOG_TOOL_CONTENT`** | **미설정** | ❌ |

### 인프라 구성

- **OTEL Collector** v0.149.0: OTLP gRPC/HTTP 수신 → Prometheus/Loki/Tempo 분배
- **Prometheus** v3.11.1: 메트릭 시계열 저장 (15일 보존)
- **Loki** v3.0.0: 로그/이벤트 저장 (31일 보존, TSDB v13)
- **Tempo** v2.7.2: 분산 트레이스 저장
- **Grafana** v12.4.2: 8개 대시보드

### Loki 인덱스 레이블 (현재)

`user_id`, `user_email`, `event_name`

### 수집 중인 메트릭 (8종)

| 메트릭 | 추가 속성 |
|--------|----------|
| `claude_code.session.count` | — |
| `claude_code.token.usage` | `type`, `model` |
| `claude_code.cost.usage` | `model` |
| `claude_code.active_time.total` | `type` |
| `claude_code.lines_of_code.count` | `type` |
| `claude_code.commit.count` | — |
| `claude_code.pull_request.count` | — |
| `claude_code.code_edit_tool.decision` | `language`, `tool_name`, `decision`, `source` |

### 공식 스키마 기준 수집 가능 이벤트 (5종)

| 이벤트 | 주요 속성 |
|--------|----------|
| `user_prompt` | prompt, prompt_length, event.sequence |
| `api_request` | model, cost_usd, duration_ms, input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens, speed |
| `api_error` | model, error, status_code, duration_ms, attempt, speed |
| `tool_result` | tool_name, success, duration_ms, error, tool_parameters, tool_input, decision_type, decision_source, tool_result_size_bytes |
| `tool_decision` | tool_name, decision, source |

현재 대시보드는 이 중 `api_error`를 사실상 활용하지 않고, `user_prompt` / `api_request` / `tool_result` / `tool_decision` 중심으로 구성되어 있다.

### 대시보드 (8종)

1. **Executive Overview** (cc-overview) — 세션, 비용, P95 레이턴시, 프롬프트 조사 큐
2. **API Requests** (cc-api-requests) — 요청수, 비용, 레이턴시, 에러 신호
3. **Tool Analytics** (cc-tool-analytics) — tool 성공률, 실행 패턴
4. **Events Explorer** (cc-events-explorer) — 이벤트 타임라인, 원시 스트림
5. **Prompt Analytics** (cc-prompt-analytics) — 프롬프트별 비용/토큰 집계
6. **Session Explorer** (cc-session-explorer) — 세션 여정, 트레이스 연결
7. **Prompt Detail** (cc-prompt-detail) — 개별 프롬프트 상세 분석
8. **Trace Explorer** (cc-trace-explorer) — 트레이스 목록, 타임라인, 분포

---

## 3. 이슈 지표별 감지 능력 매핑

### 3.1 현재 대시보드로 바로 확인 가능

| 이슈 지표 | 감지 방법 | 대시보드 |
|----------|----------|---------|
| **Read:Edit 비율** | `tool_name`별 count 비교 (Read vs Edit/Write) | Tool Analytics |
| **프롬프트당 비용** | `sum by (prompt_id) (unwrap cost_usd)` | Prompt Analytics / Detail |
| **프롬프트당 토큰** | input_tokens, output_tokens 집계 | Prompt Detail |
| **프롬프트당 API 요청 수** | Prompt Investigation Queue의 `API Calls` 컬럼 | Prompt Analytics / Overview |
| **API 레이턴시 (P95)** | `quantile_over_time(0.95, unwrap duration_ms)` | API Requests |
| **Tool 성공/실패율** | `success=true/false` 비율 | Tool Analytics |
| **모델별 비용 추이** | model 레이블 기준 시계열 | Executive Overview |
| **프롬프트 원문** | `event_name="user_prompt"` 로그 | Prompt Analytics |
| **Write vs Edit 비율** (정밀도) | tool_name별 count에서 Write/Edit 비율 | Tool Analytics |

### 3.2 쿼리 추가로 파생 가능

| 이슈 지표 | 구현 방법 | 필요 작업 |
|----------|----------|----------|
| **Edit 전 Read 없는 비율** | `event_sequence` 기반 시퀀스 분석: 같은 prompt_id 내에서 Read 없이 Edit 발생 패턴 | 커스텀 LogQL 쿼리 + 대시보드 패널 |
| **같은 파일 반복 편집** | `tool_input`에서 파일 경로 추출, 동일 파일 3회+ Edit 감지 | `OTEL_LOG_TOOL_DETAILS=1` (이미 활성) + 파싱 쿼리 |
| **thrashing score** | 기존 `API Calls` + 비용 + tool 성공률을 조합해 이상치 점수화 | 파생 쿼리 또는 summary 패널 추가 |
| **비용 효율성** | 토큰 총량 / 성공적 tool 실행 수 | 복합 쿼리 |
| **프롬프트 길이 vs 결과 상관관계** | `prompt_length`와 비용/토큰/tool 패턴 조합 | `prompt_length` 활용 쿼리 |
| **유저 거부율** (인터럽트 프록시) | `decision_source="user_abort"` 또는 `"user_reject"` 빈도 | `decision_source` 필드 활용 |
| **API 오류/재시도 소진** | `api_error` 이벤트의 `status_code`, `attempt`, `speed` 집계 | `api_error` 전용 패널/알림 추가 |

### 3.3 감지 불가능 (데이터 미존재)

| 이슈 지표 | 불가능 이유 | 대안 |
|----------|-----------|------|
| **Thinking 깊이** (핵심) | Claude Code OTEL에 thinking_tokens 미노출. API 응답에 해당 필드 없음 | Anthropic API 업데이트 필요 |
| **Thinking 내용/서명 길이** | `redact-thinking` 이후 접근 불가 | 없음 |
| **모델 출력 텍스트 분석** ("simplest", "good stopping point" 등) | 모델 응답 텍스트가 OTEL에 미포함 | `OTEL_LOG_TOOL_CONTENT=1` 활성화 시 span에 tool 출력 포함되나 모델의 자연어 응답은 아님 |
| **Reasoning 루프** ("oh wait", "actually" 패턴) | 모델 출력 텍스트 미수집 | 없음 |
| **Stop hook 위반** | 커스텀 bash hook 메커니즘, OTEL과 별도 파이프라인 | hook에서 커스텀 OTEL 이벤트를 직접 emit하면 canary 지표화 가능 |
| **프롬프트 감정 분석** | 원문은 있지만 실시간 분석 파이프라인 없음 | OTEL Collector processor에서 NLP 처리 또는 별도 파이프라인 |
| **시간대별 thinking 깊이** | thinking_tokens 미존재 | 시간대별 비용/레이턴시/성공률로 프록시 가능 |

---

## 4. 미활용 메트릭/속성 전체 목록

### 4.1 미설정 환경변수

#### `OTEL_LOG_TOOL_CONTENT=1`

| 항목 | 내용 |
|------|------|
| 효과 | 트레이스 span 이벤트에 tool 입출력 전체 내용 포함 (60KB/span 제한) |
| 얻는 것 | Read tool 결과(파일 내용), Bash 출력(빌드/테스트 결과), Edit 변경 내용 |
| 주의 | 민감정보 포함 가능, 스토리지 사용량 대폭 증가 |
| 이슈 연관 | 모델이 어떤 코드를 읽고 어떤 변경을 했는지 전체 추적 → convention drift 감지에 활용 가능 |

### 4.2 공식 스키마에는 있으나 현재 대시보드에 미반영인 이벤트 타입

#### `claude_code.api_error`

공식 Monitoring 문서 기준으로 API 실패는 `api_request`가 아니라 별도 `api_error` 이벤트로 기록된다. 현재 대시보드는 `api_request`에 `error`, `status`, `timeout`, `retry_count`가 있다고 가정하고 있어, 실제 스키마와 어긋날 가능성이 있다.

| 속성 | 설명 | 활용 가치 |
|------|------|----------|
| `error` | 에러 메시지 | 에러 유형 분류 |
| `status_code` | HTTP 상태 코드 (`"429"`, `"500"`, `"undefined"`) | 레이트리밋 vs 서버에러 구분 |
| `attempt` | 총 시도 횟수 (1=재시도 없음) | 재시도 소진 감지 (attempt > 10) |
| `speed` | `"fast"` / `"normal"` | fast 모드에서 에러율 비교 |
| `duration_ms` | 실패까지 소요 시간 | 타임아웃 패턴 분석 |
| `model` | 모델 식별자 | 모델별 에러율 |

### 4.3 수집되지만 요약 패널/경보 관점에서는 미활용인 속성

#### api_request 이벤트

| 속성 | 설명 | 활용 가치 |
|------|------|----------|
| `speed` | `"fast"` / `"normal"` | 세부 테이블에는 이미 표시되지만, fast 모드 vs normal 모드 비교용 summary 패널은 없음 |

#### tool_result 이벤트

| 속성 | 설명 | 활용 가치 |
|------|------|----------|
| `tool_result_size_bytes` | tool 결과 바이트 크기 | raw detail에는 있으나, Read 결과 크기 분포/임계치 기반 경보는 없음 |
| `mcp_server_scope` | MCP 서버 식별자 | MCP tool 사용 분석 |
| `decision_type` | `"accept"` / `"reject"` | raw detail에는 있으나, 수락/거부 추이 패널은 미구성 |
| `decision_source` | `"config"`, `"hook"`, `"user_permanent"`, `"user_temporary"`, `"user_abort"`, `"user_reject"` | raw detail에는 있으나, **유저 인터럽트 프록시** 지표로는 미승격 |
| `tool_parameters` | Bash 명령어, git_commit_id, MCP/skill 이름 (JSON) | raw detail에는 있으나, 명령 패턴/commit 연결용 분석 패널은 없음 |
| `tool_input` | tool 인자 전체 (JSON, 4KB 제한) | raw detail에는 있으나, **파일 경로 추출 → Read:Edit 파일 수준 분석** 패널은 없음 |

#### user_prompt 이벤트

| 속성 | 설명 | 활용 가치 |
|------|------|----------|
| `prompt_length` | 프롬프트 문자 수 (항상 수집) | 수집은 되지만, 비용/호출 수와 묶은 상관관계 분석 패널은 없음 |

### 4.4 메트릭 속성 중 미활용

| 메트릭 | 속성 | 설명 | 활용 가치 |
|--------|------|------|----------|
| `active_time.total` | `type` | `"user"` (타이핑) vs `"cli"` (처리) | 사용자 대기 시간 vs 실제 처리 시간 비율 |
| `code_edit_tool.decision` | `source` | 6종 결정 소스 | hook/config에 의한 자동 결정 vs 사용자 수동 결정 비율 |
| `code_edit_tool.decision` | `decision` | `"accept"` / `"reject"` | 코드 편집 거부율 추적 |

### 4.5 공통 표준 속성 중 미활용

| 속성 | 설명 | 활용 가치 |
|------|------|----------|
| `terminal.type` | `"iTerm.app"`, `"vscode"`, `"cursor"`, `"tmux"` | 터미널별 사용 패턴 비교 |
| `workspace.host_paths` | 작업 디렉토리 경로 (이벤트 전용) | 프로젝트별 비용/품질 분석 |
| `organization.id` | 조직 UUID | 조직 단위 집계 (팀 환경) |

### 4.6 Resource 속성 중 미활용

| 속성 | 설명 | 활용 가치 |
|------|------|----------|
| `service.version` | Claude Code 버전 | 버전별 품질 회귀 감지 |
| `os.type` / `os.version` | OS 정보 | 플랫폼별 이슈 분석 |
| `host.arch` | CPU 아키텍처 | 아키텍처별 성능 비교 |

### 4.7 Loki 인덱스 추가 후보

현재 `user_id`, `user_email`, `event_name`만 인덱스됨. 추가 시 쿼리 성능 향상:

| 후보 | 이유 |
|------|------|
| `tool_name` | 모든 tool 쿼리에서 사용되나 인덱스 아님 |
| `model` | 모델별 필터링 빈번 |
| `success` | tool 성공/실패 필터링 |
| `speed` | fast/normal 모드 필터링 |

### 4.8 트레이스 미활용 기능

| 기능 | 설명 | 활용 가치 |
|------|------|----------|
| **TRACEPARENT 전파** | Claude가 실행하는 Bash/PowerShell 서브프로세스가 W3C trace context 상속 | 빌드/테스트 등 서브프로세스를 같은 트레이스에 연결 |
| **Span 내 tool content** | `OTEL_LOG_TOOL_CONTENT=1` 시 입출력 포함 | 모델이 읽은 코드와 변경 내용 전체 추적 |

---

## 5. 프롬프트 품질 진단 가능 여부

### 5.1 가능한 진단 시나리오

#### 시나리오 A: "이 프롬프트가 왜 비효율적인가?"

```
높은 cost_usd + 높은 API 요청 수 + 낮은 tool 성공률
= thrashing 신호

단, 이 값만으로 프롬프트가 나쁜지 모델이 회귀했는지까지 단정할 수는 없다.
```

**활용 쿼리:**
```logql
# 프롬프트당 API 요청 수 (thrashing 지표)
sum by (prompt_id) (count_over_time(
  {service_name="claude-code"} | user_email=~"$user_email"
  | event_name = `api_request` | prompt_id =~ ".+"
  [$__range]))
```

#### 시나리오 B: "모델이 충분히 조사하고 있는가?"

```
특정 prompt_id에서 Edit 비율 > Read 비율
= 연구 없이 편집하는 위험 신호
```

**활용 쿼리:**
```logql
# Read:Edit 비율
sum by (prompt_id) (count_over_time(
  {service_name="claude-code"} | user_email=~"$user_email"
  | tool_name="Read" | event_name = `tool_result`
  [$__range]))
/
sum by (prompt_id) (count_over_time(
  {service_name="claude-code"} | user_email=~"$user_email"
  | tool_name=~"Edit|Write" | event_name = `tool_result`
  [$__range]))
```

#### 시나리오 C: "사용자가 모델을 자주 중단시키는가?"

```
높은 decision_source="user_abort" 빈도
= 모델 행동에 대한 사용자 불만 신호의 프록시
```

**활용 쿼리:**
```logql
# 유저 거부/중단 비율
sum(count_over_time(
  {service_name="claude-code"} | user_email=~"$user_email"
  | event_name = `tool_result` | decision_source =~ "user_abort|user_reject"
  [$__range]))
/
sum(count_over_time(
  {service_name="claude-code"} | user_email=~"$user_email"
  | event_name = `tool_result`
  [$__range]))
* 100
```

#### 시나리오 D: "프롬프트 길이와 효율의 상관관계"

```
짧은 prompt_length + 높은 cost_usd = 모호한 지시 또는 모델 회귀 가능성
긴 prompt_length + 낮은 cost_usd = 상대적으로 효율적인 실행 신호
```

### 5.2 판단 한계

| 판단 가능 | 판단 불가능 |
|----------|-----------|
| 프롬프트 결과가 비효율적이었는지 (비용, 토큰, 시간) | 왜 비효율적이었는지 (모델 측 vs 프롬프트 측 원인 구분) |
| 모델이 연구 패턴을 따랐는지 (Read:Edit 비율) | 모델이 내부적으로 얼마나 깊이 생각했는지 (thinking depth) |
| 사용자가 불만을 표시했는지 (abort/reject 빈도) | 모델 출력의 구체적 품질 (convention 준수, 코드 정확성) |
| 비용 이상치 프롬프트 식별 | 프롬프트를 어떻게 개선해야 하는지 구체적 제안 |

### 5.3 근본적 갭

**이슈 #42796의 핵심 결론은 프롬프트 품질이 아닌 모델의 thinking 깊이 문제다.** 이슈 작성자의 프롬프트는 동일한데 모델 행동이 변한 것이므로:

- 동일 프롬프트의 시간대별 결과 변화를 추적하면 **모델 측 회귀**를 간접 감지 가능
- 하지만 `thinking_tokens`가 API 응답에 포함되지 않는 한 **근본 원인 특정은 불가능**
- 이슈 작성자가 요청한 `thinking_tokens` 메트릭은 Anthropic API 업데이트가 선행되어야 수집 가능

---

## 6. 적합도 결론 및 우선순위

### 6.1 결론

이 저장소에서 **새 메트릭을 추가할 적합도는 중간**이다.

- 가장 시급한 과제는 새 메트릭 생성보다 **공식 스키마와 현재 대시보드의 불일치 해소**다.
- 그다음은 이미 수집 중인 속성을 **canary 지표와 요약 패널**로 승격하는 일이다.
- `thinking_tokens` 계열은 로컬 스택에서 해결할 문제가 아니라 **upstream API 노출이 선행**되어야 한다.

### 6.2 바로 진행할 일

1. **`api_error` 패널/알림 추가**
   - 공식 스키마 기준으로 API 실패는 `api_error` 이벤트가 소스 오브 트루스다.
   - `status_code`, `attempt`, `speed`, `model` 기준으로 실패율/재시도 소진/레이트리밋을 분리해 보여주는 것이 우선이다.

2. **회귀 canary 패널 추가**
   - Read:Edit 비율
   - `decision_source=user_abort|user_reject` 비율
   - prompt별 `API Calls / Cost / Tool Success Rate` 조합 점수
   - `service.version`, `model`, `speed` 분해

3. **파일 수준 조사 패널 추가**
   - `tool_input`에서 파일 경로를 추출해 "Read 없이 Edit", "같은 파일 반복 편집"을 잡는 보조 패널을 만든다.

### 6.3 조건부로 진행할 일

1. **Stop hook OTEL 이벤트화**
   - 이미 현업에서 stop hook을 운영 중이라면, hook 위반을 커스텀 OTEL 로그/이벤트로 보내는 것이 강력한 선행지표가 된다.

2. **`OTEL_LOG_TOOL_CONTENT=1` 제한적 사용**
   - 기본 활성화보다는 짧은 기간의 조사 세션이나 특정 사용자/프로젝트에만 한정하는 것이 현실적이다.
   - 민감정보와 저장 비용 리스크가 크다.

### 6.4 지금은 하지 말 일

1. **`thinking_tokens` 대체 메트릭을 로컬에서 억지로 만들기**
   - 현재 공식 스키마에 없다.
   - Read:Edit, abort rate, API thrashing 같은 프록시 canary는 가능하지만, 근본 원인 메트릭의 대체재는 아니다.

2. **감정 분석/NLP 파이프라인을 1차 우선순위로 두기**
   - 운영 복잡도 대비 즉시 가치가 낮다.
   - 먼저 구조적 행동 지표를 안정화하는 편이 낫다.

### 6.5 수정 후 최종 판단

- **매우 적합**: `api_error`, Read:Edit, abort/reject, version/model/speed 기반 canary
- **적합**: 파일 반복 편집, Read 없는 Edit, 비용 효율성 같은 파생 지표
- **조건부 적합**: stop hook OTEL 연동, `OTEL_LOG_TOOL_CONTENT=1`
- **불가**: `thinking_tokens`, reasoning loop, 모델 응답 텍스트 기반 분석

---

## 7. 반영 계획

### 7.1 심층 검토에서 추가로 확인된 사항

1. **`api_error`는 대시보드 설계의 정합성 이슈다**
   - 현재 `API Requests` 대시보드는 `api_request` 이벤트 안에서 오류/재시도 신호를 찾도록 짜여 있다.
   - 그러나 공식 스키마 기준으로 실패는 별도 `api_error` 이벤트가 소스 오브 트루스다.
   - 따라서 이 작업은 "메트릭 추가"라기보다 **기존 데이터 모델에 맞춘 쿼리/패널 재설계**로 보는 편이 정확하다.

2. **`event_sequence`는 이미 일부 대시보드에서 쓰고 있다**
   - `Prompt Detail`, `Prompt Analytics`, `Overview`는 `event_sequence` 필드를 실제로 사용한다.
   - 다만 "Read 없이 Edit" 같은 교차 이벤트 시퀀스 판정에 필요한 수준으로 모든 관련 이벤트에 안정적으로 들어오는지는 raw stream으로 한 번 더 검증해야 한다.

3. **Loki 인덱스 추가는 P0가 아니다**
   - `tool_name`, `model`, `success`, `speed`는 분명 쿼리에 자주 쓰이지만, 인덱스 증설은 저장 비용과 cardinality 리스크를 동반한다.
   - 먼저 패널/쿼리 구조를 정리하고, 실제 탐색 지연이 확인될 때 2차 최적화로 다루는 편이 안전하다.

4. **알림은 별도 산출물로 다뤄야 한다**
   - 현재 저장소에는 Grafana alert rule provisioning 파일이 추가되었지만, contact point / notification policy provisioning은 아직 없다.
   - 따라서 "패널 추가"와 "알림 전송 경로 운영화"는 계속 분리해서 다루는 것이 맞다.

### 7.2 목표 산출물

1. **정합성 보정**
   - `API Requests` 대시보드가 공식 이벤트 스키마와 맞도록 수정

2. **회귀 canary 묶음**
   - Read:Edit 비율
   - abort/reject 비율
   - prompt별 thrashing score
   - version/model/speed 분해

3. **보조 조사 패널**
   - Read 없이 Edit
   - 같은 파일 반복 편집
   - Read 결과 크기 분포

4. **운영 문서**
   - 어떤 패널이 canary인지
   - 어떤 값이 이상치인지
   - 어떤 드릴다운 경로로 들어가야 하는지

### 7.3 단계별 실행안

#### Phase 0. 데이터 정합성 검증

대상 파일:
- [grafana/dashboards/api-requests.json](grafana/dashboards/api-requests.json:342)
- [grafana/dashboards/events-explorer.json](grafana/dashboards/events-explorer.json:686)
- [grafana/dashboards/prompt-detail.json](grafana/dashboards/prompt-detail.json:1070)

작업:
- `api_error` 이벤트가 실제로 유입되는지 raw stream 기준으로 확인
- `event_sequence`가 `tool_result` / `api_error`에도 일관되게 존재하는지 확인
- `decision_source`, `tool_input`, `tool_result_size_bytes`, `service_version`, `speed` 필드의 실제 표기 형태를 검증

완료 기준:
- 이후 대시보드 작업이 "가정"이 아니라 "실제 필드명" 기준으로 진행 가능

#### Phase 1. `API Requests` 정합성 수정

대상 파일:
- [grafana/dashboards/api-requests.json](grafana/dashboards/api-requests.json:205)
- [grafana/dashboards/events-explorer.json](grafana/dashboards/events-explorer.json:446)

작업:
- `Observed Error/Retry Signals`를 `api_request` 기반 추정치에서 `api_error` 기반 패널로 교체
- `API Request Detail`과 별개로 `API Error Detail` 테이블 추가
- `status_code`, `attempt`, `model`, `speed` 기준 breakdown 패널 추가
- `Events Explorer`에서 `api_error`도 탐색 가능한 1급 이벤트로 승격

완료 기준:
- API 실패 원인 분석이 공식 이벤트 모델과 일치
- 레이트리밋/서버 오류/재시도 소진을 구분 가능

#### Phase 2. 회귀 canary 패널 추가

대상 파일:
- [grafana/dashboards/overview.json](grafana/dashboards/overview.json:228)
- [grafana/dashboards/tool-analytics.json](grafana/dashboards/tool-analytics.json:205)
- [grafana/dashboards/prompt-analytics.json](grafana/dashboards/prompt-analytics.json:534)
- [grafana/dashboards/prompt-detail.json](grafana/dashboards/prompt-detail.json:256)

작업:
- `Overview` 상단에 canary stat 3~4개 추가
- `Prompt Investigation Queue`에 thrashing score 또는 이상치 플래그 컬럼 추가
- `Tool Analytics`에 abort/reject 비율, Read:Edit 비율, Write 비율 패널 추가
- `Prompt Detail`에 현재 프롬프트의 canary summary 추가

권장 canary 정의:
- `Read:Edit ratio`
- `Abort/Reject rate`
- `API errors per 100 requests`
- `Prompt thrashing score = z(cost) + z(api_calls) - z(tool_success_rate)` 같은 조합식

완료 기준:
- Overview에서 이상 징후를 본 뒤 Prompt/Tool/API 상세로 한 번에 내려갈 수 있음

#### Phase 3. 파일 수준 보조 조사 패널

대상 파일:
- [grafana/dashboards/tool-analytics.json](grafana/dashboards/tool-analytics.json:806)
- [grafana/dashboards/prompt-detail.json](grafana/dashboards/prompt-detail.json:1133)

작업:
- `tool_input`에서 파일 경로를 뽑아 "같은 파일 반복 편집" 테이블 추가
- `Read` 없이 `Edit/Write`가 먼저 나온 prompt/file 조합 탐지
- `tool_result_size_bytes` 기반으로 "얕은 읽기" 후보를 보여주는 분포 패널 추가

주의:
- 이 단계는 LogQL 파싱 난이도가 높으므로, 먼저 raw detail에서 JSON 구조를 확인한 뒤 진행
- 쿼리가 과도하게 복잡해지면 Grafana transform 또는 OTEL 측 전처리를 검토

완료 기준:
- 모델이 충분히 읽지 않고 편집에 들어가는 패턴을 prompt/file 단위로 추적 가능

#### Phase 4. 운영화

대상 파일:
- [README.md](README.md:70)
- [grafana/provisioning/alerting/claude-code-canary-rules.yml](grafana/provisioning/alerting/claude-code-canary-rules.yml:1)

작업:
- canary 해석 가이드 문서화
- 알림 임계치 설계
- 기존 rule provisioning을 contact point / notification policy까지 확장

권장 임계치 초안:
- abort/reject 비율 급증
- `api_error` 비율 급증
- Read:Edit ratio 급락
- 특정 `service.version` 또는 `model`에서만 이상치 집중

완료 기준:
- 대시보드가 "조사 도구"에서 "지속 감시 도구"로 확장됨

### 7.4 우선순위

#### P0

- `api_error` 정합성 수정
- Overview canary stat 추가
- Prompt/Tool/API 드릴다운 연결 유지

#### P1

- Prompt별 thrashing score
- abort/reject 및 Read:Edit 패널
- Prompt Detail canary summary

#### P2

- 파일 수준 조사 패널
- stop hook OTEL 연동
- 알림 규칙 추가

#### P3

- Loki 인덱스 추가 검토
- `OTEL_LOG_TOOL_CONTENT=1` 제한적 시범 적용
- 감정 분석/NLP 보조 파이프라인 검토

### 7.5 지금 문서 기준 권장 반영 순서

1. 대시보드 쿼리 정합성부터 바로잡는다.
2. 다음으로 Overview/Prompt/Tool 화면에 회귀 canary를 올린다.
3. 그 후에만 파일 수준 분석과 alerting으로 들어간다.
4. Loki 인덱스와 tool content는 마지막에 검토한다.

이 순서가 좋은 이유는, 가장 낮은 리스크로 가장 큰 관측 품질 개선을 먼저 얻을 수 있기 때문이다.

---

## 8. 참고 자료

- [Claude Code Monitoring 공식 문서](https://code.claude.com/docs/en/monitoring-usage)
- [anthropics/claude-code#42796 — Extended Thinking Quality Regression](https://github.com/anthropics/claude-code/issues/42796)
- [anthropics/claude-code#19117 — Telemetry Configuration Ambiguity](https://github.com/anthropics/claude-code/issues/19117)
- [Claude Code ROI Measurement Guide](https://github.com/anthropics/claude-code-monitoring-guide)
