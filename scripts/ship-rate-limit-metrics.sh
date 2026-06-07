#!/bin/bash
# Claude Code statusline rate_limits → OTLP gauge shipper
#
# stdin: Claude Code statusline 입력 JSON 전체.
# ~/.claude/statusline-command.sh 에서 백그라운드로 호출된다 (출력/실패 모두 무시됨).
#
# 흐름: rate_limits.{five_hour,seven_day,seven_day_opus}.{used_percentage,resets_at}
#       → otel-collector OTLP HTTP(:4318) → prometheus exporter(:8889) → Prometheus
# 메트릭: claude_code_rate_limit_used_percent{window=...}        (게이지, 0–100)
#         claude_code_rate_limit_resets_at_seconds{window=...}   (게이지, epoch 초)
# resource service.name=claude-usage-statusline → exported_job 라벨로 출처 구분.
#
# 사용법: ship-rate-limit-metrics.sh [--dry-run]
#   --dry-run : 페이로드만 stdout으로 출력하고 전송/쓰로틀 갱신은 생략 (디버깅용)
set -u

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

# statusline은 최소 환경에서 실행되므로 절대경로 우선 (statusline-command.sh와 동일 관례)
JQ=/opt/homebrew/bin/jq
[ -x "$JQ" ] || JQ=$(command -v jq 2>/dev/null) || exit 0
CURL=/usr/bin/curl

OTLP_URL="${CC_RATELIMIT_OTLP_URL:-http://localhost:4318/v1/metrics}"
THROTTLE_FILE=/tmp/cc-ratelimit-otlp.last
THROTTLE_SEC=60

# ─── 쓰로틀: statusline은 수백 ms 간격으로 재실행되므로 60s에 1회만 전송 ───
now=$(date +%s)
if ! $DRY_RUN && [ -f "$THROTTLE_FILE" ]; then
  last=$(stat -f %m "$THROTTLE_FILE" 2>/dev/null || echo 0)
  [ $((now - last)) -lt "$THROTTLE_SEC" ] && exit 0
fi

input=$(cat)
[ -n "$input" ] || exit 0

# rate_limits가 없거나 used_percentage가 전부 비면 jq가 empty를 내고 전송을 생략한다.
payload=$("$JQ" -c --arg now "${now}000000000" '
  def num: if type == "number" then . elif type == "string" then (tonumber? // null) else null end;
  (.rate_limits // {}) as $rl
  | [ {w: "five_hour",      d: ($rl.five_hour // {})},
      {w: "seven_day",      d: ($rl.seven_day // {})},
      {w: "seven_day_opus", d: ($rl.seven_day_opus // {})} ]
  | map(.pct = (.d.used_percentage | num) | .rst = (.d.resets_at | num))
  | map(select(.pct != null)) as $wins
  | if ($wins | length) == 0 then empty else
    { resourceMetrics: [{
        resource: {attributes: [{key: "service.name", value: {stringValue: "claude-usage-statusline"}}]},
        scopeMetrics: [{
          scope: {name: "ship-rate-limit-metrics"},
          metrics: (
            [{ name: "claude_code.rate_limit.used_percent",
               gauge: {dataPoints: ($wins | map({
                 asDouble: .pct, timeUnixNano: $now,
                 attributes: [{key: "window", value: {stringValue: .w}}]}))} }]
            + (($wins | map(select(.rst != null))) as $r
               | if ($r | length) == 0 then [] else
                 [{ name: "claude_code.rate_limit.resets_at_seconds",
                    gauge: {dataPoints: ($r | map({
                      asDouble: .rst, timeUnixNano: $now,
                      attributes: [{key: "window", value: {stringValue: .w}}]}))} }]
                 end)
          )
        }]
      }]
    }
    end
' <<< "$input" 2>/dev/null)

[ -n "$payload" ] || exit 0

if $DRY_RUN; then
  printf '%s\n' "$payload"
  exit 0
fi

# 전송 성공 시에만 쓰로틀 갱신 → 컬렉터 일시 다운이면 다음 statusline 렌더에서 재시도
if "$CURL" -m 2 -s -o /dev/null -f -X POST -H 'Content-Type: application/json' \
     -d "$payload" "$OTLP_URL"; then
  touch "$THROTTLE_FILE"
fi
exit 0
