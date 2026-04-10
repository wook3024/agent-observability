# Observability Stack

이 폴더는 Docker Compose로 실행하는 로컬 observability 스택입니다.
구성 요소는 OpenTelemetry Collector, Loki, Prometheus, Grafana입니다.

## 포함 범위

- 포함됨: Docker Compose 설정, Grafana provisioning, Grafana dashboards
- 포함되지 않음: 실행 후 쌓이는 metrics/logs/Grafana 내부 상태 데이터

현재 데이터는 Docker named volume에 저장되므로, 다른 PC로 이 폴더만 복사하면 설정은 그대로 재현되지만 기존 수집 데이터까지 같이 이동하지는 않습니다.

## 고정된 이미지 버전

- `otel/opentelemetry-collector-contrib:0.149.0`
- `grafana/loki:3.0.0`
- `prom/prometheus:v3.11.1`
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

## 사용자별 대시보드 필터링

모든 Grafana 대시보드에는 **User** 드롭다운이 포함되어 있어, 특정 사용자의 데이터만 필터링하여 조회할 수 있습니다.

이 기능이 동작하려면 OTLP 클라이언트(SDK)에서 텔레메트리 데이터를 전송할 때 `user_id` resource attribute를 포함해야 합니다.

### OTLP 클라이언트 설정 예시

**Python (OpenTelemetry SDK)**:

```python
from opentelemetry.sdk.resources import Resource

resource = Resource.create({
    "service.name": "claude-code",
    "user_id": "alice"  # 사용자 식별자
})
```

**Node.js (OpenTelemetry SDK)**:

```javascript
const { Resource } = require('@opentelemetry/resources');

const resource = new Resource({
  'service.name': 'claude-code',
  'user_id': 'alice',  // 사용자 식별자
});
```

`user_id`가 포함되지 않은 데이터는 OTEL Collector에서 자동으로 `"unknown"`으로 설정됩니다. 대시보드에서 "All" 옵션을 선택하면 모든 사용자의 데이터를 통합하여 조회할 수 있습니다.

## 애플리케이션 OTEL 환경변수

이 스택으로 텔레메트리를 보내려면 애플리케이션에 아래 환경변수를 설정합니다.

```bash
# OTLP 엔드포인트 (gRPC)
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"

# OTLP 엔드포인트 (HTTP, gRPC를 사용할 수 없는 환경)
# export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"

# 서비스 식별
export OTEL_SERVICE_NAME="my-service"

# 리소스 속성 (user_id 등 커스텀 속성 추가)
export OTEL_RESOURCE_ATTRIBUTES="user_id=alice,deployment.environment=local"
```

> `user_id` 속성을 보내지 않으면 Collector가 자동으로 `unknown`을 삽입합니다.

## 접속 주소

- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`
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
