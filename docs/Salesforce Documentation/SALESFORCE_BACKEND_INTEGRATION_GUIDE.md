# Expert Architectural Report: Dograh Voice AI Platform Back-End Integration with Salesforce

**Version:** 1.0  
**Date:** October 18, 2025  
**Audience:** Salesforce Solution Architects, Integration Engineers, DevOps Leads

---

## How This Guide Complements the Front-End Playbooks
- `docs/SALESFORCE_FRONTEND_SETUP_GUIDE.md` and `docs/SALESFORCE_FRONTEND_VISUAL_GUIDE.md` describe the Lightning Web Component (LWC) placement, user journeys, and visual layout.
- This document maps those user experiences to a hardened integration backend, detailing how the Dograh API services, Salesforce Apex code, and infrastructure cooperate to deliver the promised features.
- `docs/SALESFORCE_LWC_DESIGN.md` defines the component surface area and API expectations; the guide below provides the reference implementation patterns, security controls, and operational procedures required to realize those contracts.

> **Reading Order Recommendation**  
> 1. Visual layout (Visual Guide) → 2. LWC capabilities (Front-End Setup Guide) → 3. Component APIs (LWC Design) → 4. **This backend guide** → 5. Implementation checklist (Section 7) → 6. Release checklist (Section 8).

---

## 1. Architectural Foundation and Bidirectional Flow Model

### 1.1 Conversation Orchestration Topology
```
┌───────────────────────────────────────────────────────────────────────────────┐
│                         Salesforce Lightning Experience                        │
│                                                                               │
│  ┌──────────────────────┐       HTTPS / Platform Events       ┌──────────────┐ │
│  │  LWC Layer           │ ───────────────────────────────────▶ │ Apex (REST   │ │
│  │  - dograhCampaign…   │                                     │  Services)   │ │
│  │  - dograhWorkflow…   │ ◀───────────────────────────────────│  Named Cred. │ │
│  │  - dograhCallMonitor │   (Context Fetch + Mutation Hooks)  │  Platform    │ │
│  └──────────────────────┘                                     │  Events)     │ │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
            ▲                      ▲                   ▲                     │
            │                      │                   │                     │
            │ WebRTC /             │ REST              │ Webhook             │
            │ WebSocket            │ (callouts)        │ (signed payloads)   │
            │                      │                   │                     ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                          Dograh Voice AI Platform (FastAPI)                   │
│  - `api/routes/workflow.py` (workflow CRUD, validation, runs)                 │
│  - `api/routes/campaign.py` (campaign orchestration)                          │
│  - `api/routes/rtc_offer.py` + `pipecat/` (real-time audio, WebRTC)           │
│  - Redis + ARQ workers (streaming jobs, asynchronous processing)              │
│                                                                               │
│  Bidirectional Control Loops:                                                 │
│  1. **AI Query (Request & Reply)** – LWC → Apex → Dograh REST (Named Cred.)   │
│  2. **AI Data Capture (Webhook)** – Dograh REST Hook → Apex REST → Platform   │
│     Event → Queueable Apex → Salesforce Data                                 │
└───────────────────────────────────────────────────────────────────────────────┘
```

- **Low-latency mandate:** Keeps conversational Time to First Token (TTFT) < 500 ms by minimizing synchronous hops, caching metadata with Platform Cache, and locating AI compute near users.
- **Hybrid pattern alignment:** Mirrors Salesforce Integration Patterns (`Remote Process Invocation – Request & Reply` + `Fire-and-Forget with Callback`).

### 1.2 Latency Budget
| Subsystem | Target | Notes |
|-----------|--------|-------|
| LWC → Apex invocation | ≤ 50 ms | Use `@AuraEnabled(cacheable=true)` where possible. |
| Apex outbound call (Named Credential) | ≤ 150 ms | Keep payload lean; avoid synchronous SOQL chatter. |
| AI inference (ASR + LLM + TTS) | ≤ 200 ms | Requires GPU-backed deployment (Section 5). |
| Webhook acknowledgement | ≤ 100 ms | Return 200 immediately after HMAC validation + Platform Event publication. |
| **Total** | **≤ 500 ms** | Assumes regional co-location (Section 5.3). |

---

## 2. Secure Outbound Integration (Salesforce Requesting Data)

### 2.1 Named Credentials + External Credentials
1. **Create External Credential** (`Dograh_External_Credential`)
   - Principals: `Dograh_Service_Account` (per org) or `Dograh_Runtime_User` (per user).
   - Authentication Protocol: Custom Bearer token.
   - Secret storage: Use Credential Type = "Custom Headers" with tokens injected as protected values via deployment pipeline.
2. **Create Named Credential** (`Dograh_API`)
   - URL: `https://<dograh-domain>/api/v1`
   - Identity Type: Named Principal (service account) or Per User (delegated auth).
   - Authentication: External Credential reference.
3. **Apex usage pattern**
```apex
HttpRequest req = new HttpRequest();
req.setMethod('GET');
req.setEndpoint('callout:Dograh_API/workflow/fetch');
req.setHeader('X-Correlation-ID', correlationId);
HttpResponse res = new Http().send(req);
```
- **DevOps note:** use Salesforce CLI or Metadata API to deploy credential definitions; secrets must be injected post-deploy via secure release steps.

### 2.2 Callout Approaches
- **External Services**: Register Dograh OpenAPI spec → auto-generated invocable actions for Flow/Einstien Bots. Recommended for CRUD + simple POSTs.
- **Custom Apex Callouts**: Required for streaming, bespoke headers (e.g., correlation IDs), or circuit-breaker logic. Leverage `api/services/mps_service_key_client.py` as reference for Dograh-side authentication flows.

### 2.3 Efficient Data Retrieval
- **SOQL**: Use selective filters; leverage skinny tables for high-traffic LWC context queries.
- **Analytics API**: For aggregated metrics, call `/services/data/vXX.X/analytics/reports/{reportId}` via Named Credential. Cache responses in Platform Cache for 60 seconds to respect report concurrency limits.
- **Caching**: Mirror Dograh workflow definitions (`WorkflowModel.workflow_definition`) in Platform Cache, invalidated via custom Platform Event when Dograh publishes a definition change.

---

## 3. Secure Inbound Integration (Server-to-Server OAuth 2.0 JWT)

### 3.1 Connected App & JWT Bearer Flow

**Why OAuth instead of public webhooks?**
- **Security boundary:** Dograh authenticated as a Named Principal (integration user), not anonymous Guest.
- **Audit trail:** All Dograh API calls logged under Integration User; queryable in Salesforce audit logs and security event stream.
- **Permission isolation:** Integration User granted only CRUD on Dograh* objects, Task, Lead/Contact—can't read/modify sensitive data.
- **No Experience Cloud overhead:** Avoids site licensing, guest profile complexity, and URL exposure.

### 3.2 Certificate-Based JWT Bearer Setup

1. **Generate RSA Key Pair** (at Dograh deployment time):
   ```bash
   openssl genrsa -out dograh_jwt_private.pem 2048
   openssl req -new -x509 -key dograh_jwt_private.pem -out dograh_jwt_cert.pem -days 365
   ```

2. **Create Salesforce Connected App**:
   - Setup → Apps → App Manager → New Connected App
   - Enable OAuth Settings → Use Digital Signatures
   - Upload public cert (`dograh_jwt_cert.pem`)
   - Selected Scopes: `api`, `refresh_token`
   - Result: Consumer Key (client_id) and private key retained by Dograh

3. **JWT Bearer Flow** (Client Credentials):
   ```
   Dograh → [Mint JWT using private key]
       ↓
   POST /services/oauth2/token
       ├─ grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer
       ├─ assertion=<JWT>
       ↓
   Salesforce → [Validate JWT signature with uploaded cert]
       ↓
   Return access_token (valid 2 hours)
   ```

4. **Dograh-Side JWT Minter** (`api/services/salesforce/jwt_client.py`):
   ```python
   import jwt
   import time
   
   class SalesforceJWTClient:
       def __init__(self, private_key: str, client_id: str, org_id: str):
           self.private_key = private_key
           self.client_id = client_id
           self.org_id = org_id
           self.access_token = None
           self.token_expiry = None
       
       def _mint_jwt(self) -> str:
           now = int(time.time())
           payload = {
               "iss": self.client_id,
               "sub": self.org_id,
               "aud": "https://test.salesforce.com",  # or production
               "exp": now + 300,  # 5 min validity
               "iat": now,
           }
           return jwt.encode(payload, self.private_key, algorithm="RS256")
       
       def get_access_token(self) -> str:
           if self.access_token and self.token_expiry > datetime.utcnow():
               return self.access_token
           
           jwt_token = self._mint_jwt()
           response = requests.post(
               "https://test.salesforce.com/services/oauth2/token",
               data={
                   "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                   "assertion": jwt_token,
               }
           )
           data = response.json()
           self.access_token = data["access_token"]
           self.token_expiry = datetime.utcnow() + timedelta(minutes=120)  # Cache 2 hours
           return self.access_token
   ```

### 3.3 Apex REST Endpoint (Private)

```apex
@RestResource(urlMapping='/dograh/events')
global with sharing class DograhEventsReceiver {
    
    @HttpPost
    global static void handleEvent() {
        String correlationId = RestContext.request.headers.get('X-Correlation-ID') ?? 'unknown';
        
        try {
            RestRequest req = RestContext.request;
            String body = req.requestBody.toString();
            
            // 1) Validate payload schema
            EventPayload payload = (EventPayload) JSON.deserialize(body, EventPayload.class);
            if (String.isBlank(payload.correlationId) || String.isBlank(payload.recordId)) {
                throw new AuraHandledException('Missing required fields');
            }
            
            correlationId = payload.correlationId;
            
            // 2) Publish Platform Event (async, decoupled DML)
            Dograh_Call_Event__e evt = new Dograh_Call_Event__e(
                Correlation_ID__c = payload.correlationId,
                Payload__c = body,
                Event_Type__c = payload.eventType ?? 'call_update',
                Retries__c = 0
            );
            EventBus.publish(evt);
            
            DograhEventLogger.logSuccess(correlationId, 'Event queued for processing');
            
            // 3) Return 202 Accepted (processing continues async)
            RestContext.response.statusCode = 202;
            RestContext.response.responseBody = Blob.valueOf(
                JSON.serialize(new Map<String, Object>{
                    'status' => 'accepted',
                    'correlationId' => correlationId
                })
            );
        } catch (Exception e) {
            DograhEventLogger.logError(correlationId, e.getMessage());
            RestContext.response.statusCode = 400;
            RestContext.response.responseBody = Blob.valueOf(
                JSON.serialize(new Map<String, Object>{'error' => e.getMessage()})
            );
        }
    }
    
    global class EventPayload {
        public String correlationId;
        public String recordId;
        public String eventType;
        public String status;
        public String message;
    }
}
```

- **Key point:** No HMAC validation needed (OAuth token itself is proof of sender identity).
- **Exposure:** Automatically available at `/services/apexrest/dograh/events` (standard Apex REST URL).
- **Authentication:** Platform handles token validation; Apex code runs as Integration User (authenticated caller).

### 3.4 Integration User & Permission Set

- **Create Integration User** in Setup → Users:
  - Username: `dograh-integration@company.invalid`
  - Profile: Salesforce (standard, not guest).
  - License: As assigned.

- **Create Permission Set** (`Dograh_Integration_User`):
  - Grant API Enabled.
  - Grant CRUD on `Dograh_Call_Activity__c`, `Dograh_Campaign__c`, `Dograh_Integration_Error__c`.
  - Grant CREATE, READ, UPDATE on `Task`, `Lead`, `Contact`.
  - **Restrict:** No access to sensitive objects (Opportunity, Quote, PII fields).

- **Assign** Permission Set to Integration User.

### 3.5 Certificate Rotation Policy

- **Validity:** 1-year cert in production; 6 months in sandbox.
- **Rotation**: 
  1. Generate new key pair 30 days before expiry.
  2. Upload new cert to Connected App (New Signing Key).
  3. Keep old cert active for 7 days (grace period for cached JWTs).
  4. Update Dograh environment with new private key.
  5. Document in runbook; alert team 60 days prior.

---

## 4. Data Capture, Transactional Integrity, Dynamic Mapping

### 4.1 Transactional Outbox Pattern
```
Dograh (Authenticated Call) → Apex REST (/dograh/events)
                                    ↓
                            (Return 202 immediately)
                                    ↓
                            Platform Event (DograhCallEvent__e)
                                    ↓
                Automated Trigger (DograhCallEventTrigger.trigger)
                                    ↓
                            Enqueue Queueable (DograhEventProcessor)
                                    ↓
                            Elevated DML (Integration User context)
                                    ↓
                            Upsert Call Activity + Create Task
```

- **Advantage:** Decouples HTTP response from DML; Dograh doesn't wait for database writes.
- **Reliability:** If Queueable fails, event remains in Platform Event log for replay (Salesforce manages retry).
- **Audit:** Every step logged with correlation ID.

### 4.2 Idempotent Persistence
- Each Dograh call has immutable `workflow_run_id` (in Dograh API, call model).
- Salesforce external ID: `Dograh_Call_Activity__c.External_Run_Id__c = workflow_run_id`.
- Upsert logic in Queueable:
  ```apex
  Dograh_Call_Activity__c callRecord = new Dograh_Call_Activity__c(
      External_Run_Id__c = payload.workflowRunId,  // External ID
      Correlation_ID__c = payload.correlationId,
      Status__c = payload.status,
      Transcript__c = payload.transcript
  );
  upsert callRecord Dograh_Call_Activity__c.External_Run_Id__c;
  ```
- **Result:** Duplicate webhook → Second event processed → Upsert finds existing record by External ID → Update, no insert.

### 4.3 Dynamic Field Mapping via CMT
- Define `Dograh_Field_Map__mdt` records:
  ```
  Json_Key__c = "sentiment"
  Salesforce_Field__c = "Sentiment_Score__c"
  Data_Type__c = "Decimal"
  Transform_Class__c = null  (use as-is)
  Event_Type__c = "call_completed"
  ```
- Apex service loads metadata:
  ```apex
  Map<String, String> fieldMap = new Map<String, String>();
  for (Dograh_Field_Map__mdt mapping : [SELECT Json_Key__c, Salesforce_Field__c FROM Dograh_Field_Map__mdt WHERE Event_Type__c = :eventType]) {
      fieldMap.put(mapping.Json_Key__c, mapping.Salesforce_Field__c);
  }
  ```
- Apply during upsert; no code changes needed when Dograh schema evolves.

---

## 5. Enterprise AI Agent Infrastructure Strategy

### 5.1 From Docker Compose to Kubernetes
| Current | Target | Migration Notes |
|---------|--------|-----------------|
| `docker-compose.yaml` | K8s `Deployment` per service | Use `kompose` as baseline but hand-author manifests with readiness/liveness probes. |
| `api/Dockerfile` | Container image (GHCR/ECR) | Enable multi-arch build; harden with `USER appuser`. |
| Redis / ARQ workers | Managed services (e.g., AWS ElastiCache) or K8s StatefulSet | Provision highly available cluster with replicas. |

### 5.2 Hosting Options
- **Managed Voice AI PaaS (LiveKit Cloud, Vapi)**: Minimal ops, SLA-backed latency, but limited custom NLP pipelines.
- **Managed Kubernetes (AKS/EKS/GKE)**: Full control. Recommended when using custom LLM/TTS models in `pipecat/` or `native/rnnoise/` noise suppression.

### 5.3 Low-Latency Deployment Controls
- **Regional Sharding:** Deploy clusters in target geographies; leverage Geo DNS to route WebRTC initiation to nearest region.
- **GPU Scheduling:** Annotate deployments with `resources.requests/limits: { nvidia.com/gpu: 1 }`. Utilize NVIDIA device plugin; adopt MIG partitioning for concurrency.
- **Autoscaling:** Configure Horizontal Pod Autoscalers (HPA) based on P95 inference latency and Redis queue depth; optionally add KEDA for event-driven scaling off ARQ metrics.

---

## 6. Operational Resilience, Availability, Observability

### 6.1 Circuit Breaker + Platform Cache
- Implement `DograhCircuitBreaker` Apex service:
  - Cache key: `dograh:breaker:<endpoint>` stored in Org Cache (1-hour TTL).
  - State machine: Closed → Open (after N consecutive failures) → Half-Open.
  - Use `PlatformCache` API (`Cache.Org.put`, `Cache.Org.get`) for O(1) access.
- Tie breaker to Dograh `api/services/telephony/worker_event_subscriber.py` health events; if FastAPI signals degradation, open circuit preemptively.

### 6.2 Correlation ID Propagation
1. **Generate** in LWC (UUID via `crypto.randomUUID()`).
2. **Include** header `X-Correlation-ID` on all Apex calls (`fetch()` or `@wire`).
3. **Apex Outbound**: `req.setHeader('X-Correlation-ID', correlationId);`
4. **Dograh**: Log header using `loguru` in `api/routes/*.py`.
5. **Webhook**: Dograh echoes header back → stored on Platform Event → persisted on SObject field `Correlation_ID__c`.
- Use correlation ID to join Salesforce debug logs, Dograh API logs, and infrastructure traces.

### 6.3 Monitoring & Alerting
- **Salesforce**: Query `PlatformEventUsageMetric`, subscribe to Real-Time Event Monitoring (ApiEventStream) where available.
- **Dograh**: Instrument FastAPI with Prometheus exporter; track P95 latency, error rates, ARQ backlog (`api/tasks/arq.py`).
- **Security**: Log rejected HMAC attempts in `Dograh_Security_Event__c`; review via Salesforce Security Center.

---

## 7. Implementation Blueprint

### 7.1 Salesforce Build Checklist
1. **Metadata Setup**
   - Create External Credential + Named Credential (`Dograh_API`).
   - Deploy Apex classes: `DograhWebhook`, `DograhWebhookSecurity`, `DograhFieldMapService`, `DograhCircuitBreaker`, Queueable jobs.
   - Define Custom Metadata Types: `Dograh_Settings__mdt`, `Dograh_Field_Map__mdt`.
   - Create Platform Event `Dograh_Call_Event__e`.
   - Configure Custom Objects: `Dograh_Call_Activity__c`, `Dograh_Campaign__c`, `Dograh_Workflow__c` with External IDs.
2. **Experience Cloud Site**
   - Create site for webhook endpoint; restrict Guest profile to minimum permissions.
3. **Flows & Automation**
   - Optional Flow to mirror Dograh campaign status to Salesforce Campaign hierarchy.
4. **Testing**
   - Unit tests covering HMAC validation (mock Crypto), queueable logic, Platform Event processing (use Test.startTest/Test.stopTest).

### 7.2 Dograh Platform Configuration
1. Expose REST endpoints with correlation ID support (`loguru` structured logging).
2. Implement webhook signature generator aligning with Salesforce HMAC formula.
3. Publish Platform Event handshake when workflows/campaigns change to refresh Salesforce caches.
4. Prepare OpenAPI spec for key endpoints (`api/routes/workflow.py`, `api/routes/campaign.py`, `api/routes/reports.py`).
5. Containerize with readiness probes (FastAPI `GET /health`).

### 7.3 DevOps Considerations
- **CI/CD**: Use GitHub Actions pipelines to build Dograh images, run FastAPI tests, deploy to K8s with blue/green strategy.
- **Salesforce Deployments**: Use SFDX scratch orgs; apply Unlock Package or metadata deploys; secrets injected post-deploy.
- **Observability Bridge**: Forward Dograh logs to central stack (e.g., Datadog) with correlation IDs; integrate Salesforce Event Monitoring logs for unified dashboards.

---

## 8. Validation & Release Checklist

| Phase | Key Activities | Exit Criteria |
|-------|----------------|----------------|
| Unit Testing | Apex tests ≥ 85% coverage for new classes; FastAPI route tests for webhook & campaign APIs | CI green build |
| Integration Testing | End-to-end call simulation: LWC → Dograh → Webhook → Salesforce upsert | Correlation ID traced across logs |
| Security Review | Pen-test webhook endpoint, verify HMAC rotation, guest profile restrictions | Security sign-off |
| Performance Testing | Load test Dograh API (1k concurrent) + Salesforce Platform Event throughput (5k/min) | Latency < 500 ms, no event drops |
| Go-Live | Run release playbook, verify monitoring dashboards, enable circuit breaker alerts | Post-deploy smoke tests pass |

---

## Appendices

### A. Sequence Diagram: Call Monitor Update
```
LWC (dograhCallMonitor)        Apex Named Cred          Dograh API              Salesforce Webhook
         |                           |                        |                             |
1. start session                    |                        |                             |
2. fetch live calls ───────────────▶|                        |                             |
         |         3. GET /campaign/progress (X-Corr) ──────▶|                             |
         |                           |        4. response ◀──┘                             |
5. render update                    |                        |                             |
         |                           |                        | 6. call disposition event   |
         |                           |                        |──────────────▶              |
         |                           |                        |            7. webhook POST  |
         |                           |       8. verify HMAC ◀───────────────────────────────┐
         |                           |                        |                             |
         |                           | 9. publish Platform Event (Correlation_ID__c)         |
         |                           |──────────────────────────────────────────────────────▶|
         |                           |                        | 10. Queueable upsert        |
         |                           |                        |                             |
11. refresh UI via LDS              |                        |                             |
```

### B. Reference Components in Repo
- **API Layer**: `api/routes/workflow.py`, `api/routes/campaign.py`, `api/routes/reports.py`
- **Asynchronous Processing**: `api/tasks/arq.py`, `api/services/telephony/worker_event_subscriber.py`
- **Data Models**: `api/db/models.py`
- **Utilities**: `api/utils/` (extend for correlation ID helpers)

### C. Key External References
- Salesforce Integration Patterns (architect.salesforce.com)
- Salesforce Secure Coding Guide (developer.salesforce.com)
- Kubernetes GPU Scheduling (kubernetes.io)
- Voice AI Latency Optimization (comparevoiceai.com, cerebrium.ai)

---

## 9. Apex Implementation Reference Patterns

### 9.1 Named Credential Callout with Circuit Breaker
```apex
public class DograhWorkflowService {
    private static final String DOGRAH_API = 'callout:Dograh_API';
    private static final Integer TIMEOUT_MS = 5000;
    private static final String CACHE_PARTITION = 'local';

    public static WorkflowDTO fetchWorkflow(Integer workflowId, String correlationId) {
        // Check circuit breaker
        if (DograhCircuitBreaker.isOpen(DOGRAH_API)) {
            throw new DograhIntegrationException(
                'Circuit breaker OPEN for Dograh API. Service temporarily unavailable.'
            );
        }

        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint(DOGRAH_API + '/workflow/fetch/' + workflowId);
            req.setHeader('X-Correlation-ID', correlationId);
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(TIMEOUT_MS);

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() == 200) {
                DograhCircuitBreaker.recordSuccess(DOGRAH_API);
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                return new WorkflowDTO(parsed);
            } else {
                DograhCircuitBreaker.recordFailure(DOGRAH_API);
                throw new DograhIntegrationException(
                    'Dograh API returned ' + res.getStatusCode() + ': ' + res.getBody()
                );
            }
        } catch (HttpCalloutException e) {
            DograhCircuitBreaker.recordFailure(DOGRAH_API);
            throw new DograhIntegrationException('HTTP callout failed: ' + e.getMessage(), e);
        }
    }
}

public class DograhCircuitBreaker {
    private static final String CACHE_PARTITION = 'local';
    private static final Integer FAILURE_THRESHOLD = 5;
    private static final Integer RETRY_TIMEOUT_SECS = 60;

    public static Boolean isOpen(String endpoint) {
        try {
            String state = (String) Cache.Org.get(CACHE_PARTITION, getCacheKey(endpoint, 'state'));
            return state == 'OPEN';
        } catch (Exception e) {
            return false; // Default to allowing requests if cache unavailable
        }
    }

    public static void recordSuccess(String endpoint) {
        try {
            Cache.Org.put(CACHE_PARTITION, getCacheKey(endpoint, 'state'), 'CLOSED', 3600);
            Cache.Org.put(CACHE_PARTITION, getCacheKey(endpoint, 'failures'), 0, 3600);
        } catch (Exception e) {
            // Log but don't fail if cache unavailable
        }
    }

    public static void recordFailure(String endpoint) {
        try {
            Integer failures = (Integer) Cache.Org.get(CACHE_PARTITION, getCacheKey(endpoint, 'failures')) ?? 0;
            failures++;
            if (failures >= FAILURE_THRESHOLD) {
                Cache.Org.put(CACHE_PARTITION, getCacheKey(endpoint, 'state'), 'OPEN', RETRY_TIMEOUT_SECS);
            }
            Cache.Org.put(CACHE_PARTITION, getCacheKey(endpoint, 'failures'), failures, 3600);
        } catch (Exception e) {
            // Log but don't fail if cache unavailable
        }
    }

    private static String getCacheKey(String endpoint, String metric) {
        return 'dograh:breaker:' + endpoint + ':' + metric;
    }
}
```

### 9.2 Webhook Receiver with HMAC Validation
```apex
@RestResource(urlMapping='/dograh-webhook/*')
global without sharing class DograhWebhookReceiver {
    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String correlationId = req.headers.get('X-Correlation-ID');

        try {
            // Validation gate 1: HMAC signature
            DograhWebhookSecurity.validateHmacSignature(req);

            // Validation gate 2: Content-Type
            String contentType = req.headers.get('Content-Type');
            if (!contentType?.contains('application/json')) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('Invalid Content-Type. Expected application/json');
                return;
            }

            // Validation gate 3: Payload size
            if (req.requestBody.length() > 1000000) { // 1 MB
                res.statusCode = 413;
                res.responseBody = Blob.valueOf('Payload too large');
                return;
            }

            // Validation gate 4: Timestamp freshness
            String timestamp = req.headers.get('X-Dograh-Timestamp');
            if (!DograhWebhookSecurity.isTimestampFresh(timestamp)) {
                res.statusCode = 401;
                res.responseBody = Blob.valueOf('Request timestamp stale');
                DograhSecurityAudit.logRejection(req, 'STALE_TIMESTAMP', correlationId);
                return;
            }

            // Parse and publish event
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
                req.requestBody.toString()
            );

            // Publish Platform Event for async processing
            DograhCallEvent__e event = new DograhCallEvent__e(
                Correlation_ID__c = correlationId,
                Payload__c = JSON.serialize(payload),
                Event_Type__c = (String) payload.get('event_type'),
                Retries__c = 0
            );

            EventBus.publish(event);

            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"status": "accepted"}');
            DograhWebhookLogger.logSuccess(correlationId, payload);

        } catch (DograhSecurityException e) {
            res.statusCode = 401;
            res.responseBody = Blob.valueOf('{"error": "Security validation failed"}');
            DograhSecurityAudit.logRejection(req, e.getMessage(), correlationId);
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('{"error": "Internal server error"}');
            DograhWebhookLogger.logError(correlationId, e);
        }
    }
}

public class DograhWebhookSecurity {
    private static final Integer MAX_TIMESTAMP_AGE_SECONDS = 300; // 5 minutes

    public static void validateHmacSignature(RestRequest req) {
        String providedSignature = req.headers.get('X-Dograh-Signature');
        if (String.isBlank(providedSignature)) {
            throw new DograhSecurityException('Missing X-Dograh-Signature header');
        }

        // Retrieve secret from Protected Custom Metadata Type
        Dograh_Settings__mdt settings = Dograh_Settings__mdt.getInstance('default');
        if (settings == null || String.isBlank(settings.Webhook_Secret__c)) {
            throw new DograhSecurityException('Webhook secret not configured');
        }

        Blob secret = Blob.valueOf(settings.Webhook_Secret__c);
        Blob payload = req.requestBody;

        // Compute expected HMAC
        Blob hmac = Crypto.generateMac(
            'HmacSHA256',
            payload,
            secret
        );

        String computedSignature = EncodingUtil.convertToHex(hmac);

        // Constant-time comparison to prevent timing attacks
        if (!Crypto.constantTimeEq(
            EncodingUtil.convertToHex(Crypto.generateMac('HmacSHA256', payload, secret)),
            providedSignature
        )) {
            throw new DograhSecurityException('HMAC signature verification failed');
        }
    }

    public static Boolean isTimestampFresh(String timestamp) {
        if (String.isBlank(timestamp)) {
            return false;
        }

        try {
            Long requestTime = Long.valueOf(timestamp);
            Long currentTime = System.currentTimeMillis() / 1000;
            Long diff = currentTime - requestTime;
            return diff >= 0 && diff <= MAX_TIMESTAMP_AGE_SECONDS;
        } catch (Exception e) {
            return false;
        }
    }
}
```

### 9.3 Platform Event Trigger with Queueable
```apex
trigger DograhCallEventTrigger on DograhCallEvent__e (after insert) {
    List<DograhCallEvent__e> events = Trigger.new;

    // Enqueue async processing
    System.enqueueJob(new DograhCallPersistenceJob(events));
}

public class DograhCallPersistenceJob implements Queueable {
    private List<DograhCallEvent__e> events;

    public DograhCallPersistenceJob(List<DograhCallEvent__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext context) {
        List<Dograh_Call_Activity__c> callsToUpsert = new List<Dograh_Call_Activity__c>();

        for (DograhCallEvent__e event : events) {
            try {
                Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
                    event.Payload__c
                );

                // Apply field mappings
                for (Dograh_Field_Map__mdt mapping : getFieldMappings(event.Event_Type__c)) {
                    Object value = payload.get(mapping.Json_Key__c);

                    if (value != null && String.isNotBlank(mapping.Salesforce_Field__c)) {
                        Dograh_Call_Activity__c call = new Dograh_Call_Activity__c();
                        call.put(mapping.Salesforce_Field__c, value);
                        call.Correlation_ID__c = event.Correlation_ID__c;
                        callsToUpsert.add(call);
                    }
                }
            } catch (Exception e) {
                DograhWebhookLogger.logError(event.Correlation_ID__c, e);
                // Log to dead-letter queue
                insertErrorRecord(event, e.getMessage());
            }
        }

        if (!callsToUpsert.isEmpty()) {
            try {
                // Upsert using External ID to ensure idempotency
                upsert callsToUpsert Dograh_Call_Activity__c.External_Run_Id__c;
                DograhWebhookLogger.logBatchSuccess(callsToUpsert.size());
            } catch (DmlException e) {
                DograhWebhookLogger.logError('DML_ERROR', e);
                for (Dograh_Call_Activity__c call : callsToUpsert) {
                    insertErrorRecord(call, e.getMessage());
                }
            }
        }
    }

    private List<Dograh_Field_Map__mdt> getFieldMappings(String eventType) {
        return [
            SELECT Json_Key__c, Salesforce_Field__c, Data_Type__c, Transform_Class__c
            FROM Dograh_Field_Map__mdt
            WHERE Event_Type__c = :eventType
        ];
    }

    private void insertErrorRecord(DograhCallEvent__e event, String error) {
        Dograh_Integration_Error__c errorRec = new Dograh_Integration_Error__c(
            Correlation_ID__c = event.Correlation_ID__c,
            Event_Type__c = event.Event_Type__c,
            Payload__c = event.Payload__c,
            Error_Message__c = error.abbreviate(255),
            Status__c = 'PENDING_RETRY'
        );
        insert errorRec;
    }
}
```

---

## 10. Dograh FastAPI Enhancements

### 10.1 Webhook Signature Generation (Python)
Add to `api/services/webhook/signer.py`:
```python
import hmac
import hashlib
import time
from typing import Tuple
from loguru import logger

class DograhWebhookSigner:
    def __init__(self, secret: str):
        self.secret = secret.encode()

    def generate_signature(self, payload: bytes) -> str:
        """Generate HMAC-SHA256 signature matching Salesforce validation logic."""
        h = hmac.new(self.secret, payload, hashlib.sha256)
        return h.hexdigest()

    def build_signed_payload(self, json_payload: str) -> Tuple[str, str, str]:
        """
        Build webhook payload with signature and timestamp headers.
        
        Returns:
            Tuple of (signature_header, timestamp_header, correlation_id)
        """
        from uuid import uuid4
        
        correlation_id = str(uuid4())
        timestamp = str(int(time.time()))
        payload_bytes = json_payload.encode('utf-8')
        
        signature = self.generate_signature(payload_bytes)
        
        logger.info(
            f"Generated webhook signature | correlation_id={correlation_id} "
            f"| signature_preview={signature[:16]}... | timestamp={timestamp}"
        )
        
        return signature, timestamp, correlation_id
```

### 10.2 Correlation ID Middleware (FastAPI)
Add to `api/app.py` in middleware stack:
```python
import uuid
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

class CorrelationIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Extract correlation ID from incoming request or generate new one
        correlation_id = request.headers.get('X-Correlation-ID') or str(uuid.uuid4())
        
        # Attach to request state for use in route handlers
        request.state.correlation_id = correlation_id
        
        # Add to logger context (if using structlog)
        logger.info(
            "Request received",
            correlation_id=correlation_id,
            method=request.method,
            path=request.url.path
        )
        
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = correlation_id
        
        logger.info(
            "Request completed",
            correlation_id=correlation_id,
            status_code=response.status_code
        )
        
        return response

# In app.py lifespan, add:
app.add_middleware(CorrelationIDMiddleware)
```

### 10.3 Campaign Progress Endpoint with Caching
Enhance `api/routes/campaign.py`:
```python
from functools import lru_cache
from datetime import datetime, timedelta

@router.get("/{campaign_id}/progress")
async def get_campaign_progress(
    campaign_id: int,
    user: UserModel = Depends(get_user),
) -> CampaignProgressResponse:
    """
    Real-time campaign progress with correlation ID tracking.
    Cached for 10 seconds to reduce database load.
    """
    correlation_id = request.state.correlation_id
    
    logger.info(
        f"Fetching campaign progress",
        campaign_id=campaign_id,
        correlation_id=correlation_id,
        user_id=user.id
    )
    
    try:
        campaign = await db_client.get_campaign(campaign_id, user.id)
        if not campaign:
            raise HTTPException(status_code=404, detail="Campaign not found")
        
        # Calculate metrics
        total_rows = campaign.total_rows or 0
        processed = campaign.processed_rows
        failed = campaign.failed_rows
        progress_pct = (processed / total_rows * 100) if total_rows > 0 else 0
        
        response = CampaignProgressResponse(
            campaign_id=campaign_id,
            state=campaign.state,
            total_rows=total_rows,
            processed_rows=processed,
            failed_calls=failed,
            progress_percentage=progress_pct,
            source_sync=campaign.source_sync or {},
            rate_limit=campaign.rate_limit or 50,
            started_at=campaign.started_at,
            completed_at=campaign.completed_at
        )
        
        logger.info(
            f"Campaign progress retrieved",
            campaign_id=campaign_id,
            progress_pct=progress_pct,
            correlation_id=correlation_id
        )
        
        return response
        
    except Exception as e:
        logger.error(
            f"Error fetching campaign progress: {e}",
            campaign_id=campaign_id,
            correlation_id=correlation_id,
            exc_info=True
        )
        raise HTTPException(status_code=500, detail=str(e))
```

---

## 11. DevOps & Deployment Guidance

### 11.1 Kubernetes Deployment Manifest
Create `k8s/dograh-api-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dograh-api
  namespace: dograh
  labels:
    app: dograh-api
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: dograh-api
  template:
    metadata:
      labels:
        app: dograh-api
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: dograh-api
      containers:
      - name: api
        image: ghcr.io/dograh/api:v1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 8000
          protocol: TCP
        env:
        - name: DEPLOYMENT_MODE
          value: "production"
        - name: REDIS_URL
          valueFrom:
            configMapKeyRef:
              name: dograh-config
              key: redis-url
        - name: DOGRAH_SF_SIGNING_SECRET
          valueFrom:
            secretKeyRef:
              name: dograh-secrets
              key: sf-signing-secret
        - name: CORRELATION_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.uid
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
---
apiVersion: v1
kind: Service
metadata:
  name: dograh-api-svc
  namespace: dograh
spec:
  type: ClusterIP
  selector:
    app: dograh-api
  ports:
  - port: 80
    targetPort: http
    protocol: TCP
---
apiVersion: autoscaling.k8s.io/v2
kind: HorizontalPodAutoscaler
metadata:
  name: dograh-api-hpa
  namespace: dograh
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: dograh-api
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### 11.2 Secrets Rotation Strategy
Create `scripts/rotate-sf-secrets.sh`:
```bash
#!/bin/bash
set -e

NAMESPACE="dograh"
SECRET_NAME="dograh-secrets"
NEW_SECRET=$(openssl rand -base64 32)
TIMESTAMP=$(date +%s)

echo "[$(date)] Rotating Salesforce signing secret..."

# Update K8s secret
kubectl patch secret $SECRET_NAME -n $NAMESPACE \
  --type='json' \
  -p="[{'op': 'replace', 'path': '/data/sf-signing-secret', 'value':'$(echo -n $NEW_SECRET | base64)'}]"

# Trigger pod restart to pick up new secret
kubectl rollout restart deployment/dograh-api -n $NAMESPACE
kubectl rollout status deployment/dograh-api -n $NAMESPACE

# Notify Salesforce integration team
echo "[$(date)] Secret rotated. Update Dograh_Settings__mdt in Salesforce org immediately."
echo "New secret prefix: ${NEW_SECRET:0:8}..."

# Log rotation event
kubectl logs -n $NAMESPACE -l app=dograh-api --tail=50 | grep "secret"
```

### 11.3 Monitoring & Alerting Setup
Create `prometheus/dograh-alerts.yaml`:
```yaml
groups:
- name: dograh-api
  interval: 30s
  rules:
  - alert: DograhWebhookFailureRate
    expr: |
      (rate(dograh_webhook_errors_total[5m]) / rate(dograh_webhook_requests_total[5m])) > 0.05
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Dograh webhook error rate > 5%"
      description: "{{ $value | humanizePercentage }} of webhooks failing"

  - alert: DograhHighLatency
    expr: |
      histogram_quantile(0.95, dograh_api_latency_seconds) > 0.5
    for: 10m
    labels:
      severity: critical
    annotations:
      summary: "Dograh API P95 latency exceeds 500ms target"
      description: "P95 latency: {{ $value | humanizeDuration }}"

  - alert: DograhCircuitBreakerOpen
    expr: |
      dograh_circuit_breaker_state == 1
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "Circuit breaker OPEN for endpoint {{ $labels.endpoint }}"
      description: "Service will reject requests until recovery"
```

---

## 12. Sandbox POC Checklist (First 48 Hours)

### Phase 1: Salesforce Metadata (Day 1, 4 hours)
- [ ] Create Custom Metadata Type `Dograh_Settings__mdt` with fields: `Webhook_Secret__c`, `API_URL__c`, `Org_ID__c`
- [ ] Create Custom Metadata Type `Dograh_Field_Map__mdt` with columns: `Json_Key__c`, `Salesforce_Field__c`, `Data_Type__c`, `Event_Type__c`
- [ ] Create Platform Event `DograhCallEvent__e` with fields: `Correlation_ID__c`, `Payload__c`, `Event_Type__c`, `Retries__c`
- [ ] Create Custom Object `Dograh_Call_Activity__c` with fields:
  - `External_Run_Id__c` (Text, External ID, Unique)
  - `Correlation_ID__c` (Text)
  - `Workflow_Id__c` (Number)
  - `Duration__c` (Number)
  - `Disposition__c` (Picklist)
  - `Transcript__c` (Long Text Area)

### Phase 2: Apex Code Deployment (Day 1, 4 hours)
- [ ] Deploy `DograhWebhookReceiver.cls` and test endpoint accessibility via Site
- [ ] Deploy `DograhWebhookSecurity.cls` and validate HMAC with sample payload
- [ ] Deploy `DograhCallEventTrigger.trigger` and `DograhCallPersistenceJob.cls`
- [ ] Deploy `DograhWorkflowService.cls` and test callout to Dograh API with mock response
- [ ] Deploy `DograhCircuitBreaker.cls` and verify Platform Cache integration

### Phase 3: Dograh API Enhancements (Day 1, 4 hours)
- [ ] Add `CorrelationIDMiddleware` to `api/app.py`
- [ ] Implement `DograhWebhookSigner` in `api/services/webhook/signer.py`
- [ ] Update `api/routes/campaign.py` to include correlation ID in logs
- [ ] Update `api/routes/workflow.py` health endpoint to signal circuit breaker via custom header
- [ ] Containerize and push image to registry with `api/Dockerfile` updates

### Phase 4: End-to-End Test (Day 2, 8 hours)
- [ ] LWC → Apex callout to Dograh `/campaign/progress` with `X-Correlation-ID` header
- [ ] Dograh webhook POST to Salesforce Experience Cloud endpoint with signed payload
- [ ] Validate HMAC signature in `DograhWebhookSecurity`
- [ ] Platform Event published and Queueable executed
- [ ] Dograh Call Activity record upserted with external ID matching
- [ ] Query logs: trace correlation ID through Salesforce, Dograh, and K8s pod logs
- [ ] Load test: 100 concurrent webhook calls; verify no duplicates via upsert

### Phase 5: Documentation & Handoff (Day 2, 4 hours)
- [ ] Document sandbox org `CustomMetadata` seed data and deployment steps
- [ ] Record demo video of end-to-end flow
- [ ] Create runbook for secret rotation and incident response
- [ ] Capture lessons learned and update Section 12 of this guide

---

**Next Steps**  
1. Align front-end LWC development timelines with backend credential provisioning.  
2. Build sandbox proof-of-concept using Phase 1–5 above; capture lessons learned.  
3. Formalize runbook for incident response leveraging correlation IDs and circuit breakers.
