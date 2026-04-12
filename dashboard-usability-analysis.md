# Dashboard Usability Analysis

작성일: 2026-04-11

## 목적

현재 Grafana 대시보드 묶음이 Claude Code 관측 데이터를 충분히 수집하고 있음에도, 사용자가 필요한 답을 빠르게 찾기 어렵다는 점을 기준으로 정보구조, 탐색 흐름, KPI, 드릴다운, 성능/운영성 관점의 개선 방향을 정리한다.

## 현재 구조 요약

- 현재 대시보드는 `Overview`, `API Requests`, `Tool Analytics`, `Events Explorer`, `Prompt Analytics`, `Prompt Detail`, `Trace Explorer`로 기능별 분리되어 있다.
- 대시보드 간 상단 링크는 잘 연결돼 있지만, 공통 필터는 사실상 `user_email` 하나에 가깝다.
- 가장 강한 드릴다운은 `Prompt Analytics -> Prompt Detail`, `Trace Explorer -> Trace Timeline`에 집중돼 있다.
- 상세 화면은 raw table/log 비중이 높고, 상위 화면은 “다음에 무엇을 봐야 하는지”까지 안내하지 못한다.

## 핵심 진단

### 1. 시작점이 약하다

- `Overview`는 총합 수치와 추세 차트를 보여주지만, 이상 징후를 발견했을 때 어디로 내려가야 하는지 강한 안내가 없다.
- 상단 네비게이션은 모든 대시보드를 같은 중요도로 배치해 초보 사용자의 첫 탐색 비용이 높다.

### 2. 전역 필터가 너무 얕다

- 대부분의 대시보드가 `user_email`만 공통 변수로 사용한다.
- `session_id`, `prompt_id`, `tool_name`, `model`, `event_name`, `duration bucket` 같은 핵심 분석 축이 공통 상태로 이어지지 않는다.
- `Events Explorer`에는 `event_type` 변수가 있지만, 실제 핵심 로그 스트림 탐색에는 거의 반영되지 않는다.

### 3. 드릴다운이 일부 경로에만 몰려 있다

- 현재 구조에서 자연스러운 drilldown은 `Prompt List -> Prompt Detail`, `Trace List -> Trace Detail` 정도다.
- `Overview`, `API Requests`, `Tool Analytics`, `Events Explorer`의 주요 요약 패널은 다음 조사 액션으로 연결되지 않는다.
- 결과적으로 사용자는 수치를 본 뒤 다시 상단 링크로 “대시보드 간 점프”를 해야 한다.

### 4. 요약보다 원본이 앞에 나온다

- `Prompt Detail`, `Tool Analytics`, `Events Explorer`는 raw log/table 비중이 크다.
- 원시 데이터는 풍부하지만 “비싼 prompt”, “느린 tool”, “실패가 많은 session”, “최근 이상 trace” 같은 의사결정형 요약이 충분하지 않다.
- 초보 사용자에게는 정보가 많아 보이지만 실제로는 판단 피로가 커진다.

### 5. 상세 진입이 ID 의존적이다

- `Prompt Detail`은 `prompt_id`, `session_id`, `Trace Explorer`는 `trace_id` 입력을 전제하는 구조가 남아 있다.
- 클릭 기반 탐색보다 “식별자를 알고 있는 사용자” 중심 설계에 가깝다.

### 6. 관측성 커버리지가 품질/원인 분석까지 이어지지 않는다

- 메트릭은 비용, 토큰, 활동량에 강하지만 API/tool 품질 진단 KPI가 약하다.
- `API Requests`에는 error rate, p95/p99 latency, timeout/retry가 없다.
- `Tool Analytics`에는 decision 대비 실행 전환율, 실패 사유, 느린 실패 Top N이 없다.
- `Trace Explorer`는 traces를 보여주지만 다른 대시보드와의 상관 탐색이 약하다.

### 7. 로그 쿼리 성능이 장기적으로 사용성을 깎을 가능성이 있다

- Loki 설정에서 인덱스 라벨은 사실상 `user_id` 중심이다.
- 하지만 로그 대시보드는 `user_email`과 `event_name` 기반 필터를 많이 사용한다.
- 시간 범위가 커질수록 검색 지연이 늘어날 수 있고, 이 지연은 곧 UX 저하로 이어진다.

## 대폭 개선 방향

### 1. 정보구조를 3단계로 재편

- `Executive Overview`
  - 지금 바로 확인해야 하는 이상 징후와 상위 KPI를 보여준다.
- `Investigation Hub`
  - 비용, 성능, 실패, 이벤트 흐름, session 여정 등 질문 중심 탐색 화면으로 재구성한다.
- `Entity Detail`
  - `Prompt Detail`, `Session Explorer`, `Trace Detail`, `Tool Detail`처럼 특정 객체를 깊게 본다.

## 2. 공통 필터 체계를 확장

- `user_email -> session_id -> prompt_id -> tool_name/model/event_name` 순서의 chained variable로 재구성한다.
- 모든 주요 대시보드가 같은 변수 집합을 공유해야 한다.
- 수동 textbox 입력은 예외 경로로만 남기고, 기본 흐름은 클릭 기반으로 바꾼다.

## 3. 모든 요약 패널에 “다음 행동” 부여

- `Overview`의 `Total Cost`는 비용 상위 prompts나 비용 급증 sessions로 연결한다.
- `API Requests`의 latency/cost 패널은 모델별 상세 또는 느린 요청 목록으로 연결한다.
- `Tool Analytics`의 실패/지연 패널은 실패한 tool executions와 관련 prompt/session으로 연결한다.
- `Events Explorer`의 event count는 해당 event type으로 필터된 stream/detail로 연결한다.

## 4. 상세 화면은 “요약 먼저, 원문 나중”

- `Prompt Detail` 상단에 비용/시간/API/Tool 비중, 실패 여부, 관련 trace 유무를 먼저 보여준다.
- raw logs는 하단으로 내리고, payload는 expandable row나 panel link로 분리한다.
- `Session Explorer`를 별도로 만들어 prompt 단위가 아니라 세션 단위 여정을 볼 수 있게 한다.

## 5. 추가해야 할 KPI

- API: request rate, error rate, p95/p99 latency, timeout/retry, 모델별 비용/지연.
- Tool: decision -> execution -> success 퍼널, 실패 사유 분류, 느린 실패 Top N.
- Prompt: 총 소요시간, API 시간 vs Tool 시간 비중, prompt당 비용/토큰, 반복 실패 prompt.
- Session: 세션당 prompt 수, 총 비용, 총 duration, 중단/에러 비율.
- Trace: error trace 비율, duration distribution by prompt/tool/model, span breakdown.

## 6. 상관 탐색 강화

- `prompt_id`, `session_id`, `trace_id`를 공통 correlation key로 쓴다.
- `Prompt Detail`, `API Requests`, `Tool Analytics`에서 바로 `Trace Explorer`로 이동 가능하게 만든다.
- Grafana data links/panel links 외에 correlations를 써서 로그 -> 메트릭 -> 트레이스 탐색을 강화한다.

## 7. 성능 최적화도 UX 작업으로 다룬다

- `Trace Explorer`는 동일한 TraceQL 쿼리를 여러 패널에서 반복하고 있으므로 shared query 구조를 적용한다.
- refresh 간격은 목적별로 나눈다. 조사형 상세 화면은 10초 자동 새로고침이 불필요할 수 있다.
- Loki 쿼리에서 자주 쓰는 필드를 인덱싱하거나, 최소한 탐색용 대시보드는 더 좁은 selector를 쓰도록 설계한다.

## 우선순위 제안

### P0

- `Overview`를 질문형 진입 대시보드로 재구성
- 공통 필터 확장
- 주요 stat/table에 drilldown 추가
- `Prompt Detail`, `Trace Explorer`의 수동 ID 의존 축소

### P1

- `Session Explorer` 신규 추가
- API/tool 품질 KPI 추가
- raw logs를 summary-first 구조로 재배치
- `Events Explorer` 변수와 실제 쿼리 동기화

### P2

- Loki 인덱스/쿼리 전략 조정
- shared query 적용
- 운영용 문서 패널 추가
- alert-driven directed browsing 설계

## 근거 파일

- [README.md](/Users/shinukyi/Gallary/projects/proto/agent-observability/README.md:70)
- [grafana/dashboards/overview.json](/Users/shinukyi/Gallary/projects/proto/agent-observability/grafana/dashboards/overview.json:127)
- [grafana/dashboards/api-requests.json](/Users/shinukyi/Gallary/projects/proto/agent-observability/grafana/dashboards/api-requests.json:77)
- [grafana/dashboards/tool-analytics.json](/Users/shinukyi/Gallary/projects/proto/agent-observability/grafana/dashboards/tool-analytics.json:199)
- [grafana/dashboards/events-explorer.json](/Users/shinukyi/Gallary/projects/proto/agent-observability/grafana/dashboards/events-explorer.json:301)
- [grafana/dashboards/prompt-analytics.json](/Users/shinukyi/Gallary/projects/proto/agent-observability/grafana/dashboards/prompt-analytics.json:229)
- [grafana/dashboards/prompt-detail.json](/Users/shinukyi/Gallary/projects/proto/agent-observability/grafana/dashboards/prompt-detail.json:487)
- [grafana/dashboards/trace-explorer.json](/Users/shinukyi/Gallary/projects/proto/agent-observability/grafana/dashboards/trace-explorer.json:356)
- [loki-config.yml](/Users/shinukyi/Gallary/projects/proto/agent-observability/loki-config.yml:28)
- [otel-collector-config.yml](/Users/shinukyi/Gallary/projects/proto/agent-observability/otel-collector-config.yml:20)

## 외부 참고

- Grafana dashboard best practices: https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/best-practices/
- Grafana dashboard links: https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/manage-dashboard-links/
- Grafana correlations: https://grafana.com/docs/grafana/latest/administration/correlations/
- Grafana share query results: https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/query-transform-data/share-query/
- Grafana one-click data links: https://grafana.com/whats-new/2025-02-13-one-click-data-links-in-visualizations/
- Grafana Observability Survey 2025: https://grafana.com/blog/observability-survey-takeaways/
- Microsoft Power BI dashboard design tips: https://learn.microsoft.com/en-us/power-bi/create-reports/service-dashboards-design-tips
