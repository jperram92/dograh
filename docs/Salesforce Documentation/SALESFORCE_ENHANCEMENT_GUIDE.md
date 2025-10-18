# Salesforce-Dograh Integration: Enhancement Guide
## Addressing Executive Feedback & Security Hardening

**Document Version:** 1.0  
**Last Updated:** October 18, 2025  
**Status:** Production Enhancement Roadmap  
**Audience:** Backend Engineers, DevOps, Security Architects

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Quick Wins (1-2 Days)](#quick-wins-1-2-days)
   - [1. Token Lifecycle & Concurrency Mutex](#1-token-lifecycle--concurrency-mutex)
   - [2. Error Propagation & DLQ Alerting](#2-error-propagation--dlq-alerting)
   - [4. Idempotency Scope Expansion](#4-idempotency-scope-expansion)
3. [Medium Effort (3-5 Days)](#medium-effort-3-5-days)
   - [3. Observability Gaps - Event Monitoring](#3-observability-gaps---event-monitoring-integration)
   - [5. API Latency Budget & Fallback Queue](#5-api-latency-budget--fallback-queue)
   - [7. Platform Event Volume & Limits Analysis](#7-platform-event-volume--limits-analysis)
   - [8. Data Residency & Latency Alignment](#8-data-residency--latency-alignment)
4. [Strategic (1-2 Weeks)](#strategic-1-2-weeks)
   - [6. JWT Rotation Operations & Automation](#6-jwt-rotation-operations--automation)
   - [9. LWC Data Fetch & Caching Inefficiencies](#9-lwc-data-fetch--caching-inefficiencies)
   - [10. Mobile UX & Streaming Updates](#10-mobile-ux--streaming-updates)
5. [Implementation Checklists](#implementation-checklists)
6. [Testing & Validation](#testing--validation)
7. [Deployment Strategy](#deployment-strategy)

---

## Executive Summary

This guide addresses 10 critical feedback items from executive stakeholder review. These enhancements improve:

- **Security**: Thread-safe token handling, multi-layer idempotency
- **Reliability**: Error alerting automation, fallback queue patterns
- **Scalability**: Platform Event limits analysis, data residency optimization
- **Observability**: Real-time monitoring, event logging integration
- **UX**: Mobile optimization, streaming instead of polling

**Total Implementation Effort**: 2-3 weeks across all items  
**Risk Level**: Low (all changes are additive; no breaking changes)  
**Production Ready**: Can be deployed incrementally

---

# QUICK WINS (1-2 Days)

---

## 1. Token Lifecycle & Concurrency Mutex

### Problem
Current JWT token caching (4-minute TTL on 5-minute tokens) creates race conditions when multiple parallel requests attempt simultaneous token mint:
- **Scenario**: 5 concurrent webhook calls arrive
- **Current Behavior**: Each triggers token mint → 5 redundant API calls to Salesforce
- **Risk**: Token quota exhaustion, unnecessary latency

### Solution: Thread-Safe Token Caching with asyncio.Lock

#### Updated Python SalesforceJWTClient

Replace the existing token caching in `api/db/base_client.py`:

```python
import asyncio
import time
import hashlib
import json
from datetime import datetime, timedelta
from typing import Optional
import jwt
import aiohttp
from constants import DOGRAH_CONFIG

class SalesforceJWTClient:
    """Thread-safe OAuth JWT client with mutex-protected token caching."""
    
    def __init__(self, org_id: str, client_id: str, private_key: str):
        self.org_id = org_id
        self.client_id = client_id
        self.private_key = private_key
        self.login_url = "https://login.salesforce.com"
        
        # Token cache with concurrency protection
        self._access_token: Optional[str] = None
        self._token_expiry: Optional[datetime] = None
        self._token_lock = asyncio.Lock()
        
        # Metrics for monitoring
        self._mint_attempts = 0
        self._cache_hits = 0
        self._race_conditions_prevented = 0
    
    def _calculate_payload_hash(self, payload: dict) -> str:
        """Calculate deterministic hash of payload for idempotency."""
        payload_str = json.dumps(payload, sort_keys=True)
        return hashlib.md5(payload_str.encode()).hexdigest()
    
    def _mint_jwt(self) -> str:
        """Generate JWT assertion signed with private key."""
        now = datetime.utcnow()
        
        # JWT expires in 2 minutes (well before token expiry)
        exp_time = now + timedelta(minutes=2)
        
        payload = {
            "iss": self.client_id,
            "sub": f"integration_user@{self.org_id}",
            "aud": self.login_url,
            "exp": int(exp_time.timestamp()),
            "iat": int(now.timestamp()),
        }
        
        token = jwt.encode(
            payload,
            self.private_key,
            algorithm="RS256"
        )
        
        return token
    
    async def _fetch_token_from_salesforce(self) -> tuple[str, datetime]:
        """Exchange JWT for access token via OAuth 2.0."""
        jwt_token = self._mint_jwt()
        
        async with aiohttp.ClientSession() as session:
            data = {
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": jwt_token,
                "client_id": self.client_id,
            }
            
            async with session.post(
                f"{self.login_url}/services/oauth2/token",
                data=data,
                timeout=aiohttp.ClientTimeout(total=10)
            ) as resp:
                if resp.status != 200:
                    error_text = await resp.text()
                    raise Exception(
                        f"OAuth token exchange failed: {resp.status} - {error_text}"
                    )
                
                result = await resp.json()
                access_token = result["access_token"]
                
                # Parse token to extract expiry
                decoded = jwt.decode(
                    access_token,
                    options={"verify_signature": False}
                )
                exp_timestamp = decoded["exp"]
                token_expiry = datetime.utcfromtimestamp(exp_timestamp)
                
                return access_token, token_expiry
    
    async def get_access_token(self) -> str:
        """
        Get valid access token with thread-safe caching.
        
        Implements mutex to prevent race conditions:
        - If token is valid and not expiring soon → return cached token (fast path)
        - If token is missing or expiring → acquire lock, recheck, mint new token
        - If another coroutine already minting → wait for lock (don't duplicate mint)
        
        Safety Buffer: Refresh token when 1 minute remains (2 min before actual expiry)
        """
        
        # Fast path: check if we have a valid cached token
        if self._access_token and self._token_expiry:
            time_until_expiry = self._token_expiry - datetime.utcnow()
            
            # 1-minute safety buffer: refresh if < 2 minutes remain
            if time_until_expiry > timedelta(minutes=2):
                self._cache_hits += 1
                return self._access_token
        
        # Slow path: acquire lock to mint new token
        async with self._token_lock:
            # Double-check: another coroutine might have minted while we waited
            if self._access_token and self._token_expiry:
                time_until_expiry = self._token_expiry - datetime.utcnow()
                if time_until_expiry > timedelta(minutes=2):
                    self._race_conditions_prevented += 1
                    return self._access_token
            
            # Mint new token
            try:
                self._mint_attempts += 1
                access_token, token_expiry = await self._fetch_token_from_salesforce()
                self._access_token = access_token
                self._token_expiry = token_expiry
                
                return access_token
            except Exception as e:
                raise Exception(f"Failed to obtain access token: {str(e)}")
    
    async def post_event_async(
        self,
        event_type: str,
        payload: dict,
        timeout: float = 5.0
    ) -> dict:
        """
        Post webhook event to Dograh backend with OAuth authentication.
        
        Args:
            event_type: Event type (e.g., 'call_started', 'campaign_progress')
            payload: Event data (will be hashed for idempotency)
            timeout: Request timeout in seconds
            
        Returns:
            Response JSON with event ID and processing status
        """
        # Get thread-safe access token
        access_token = await self.get_access_token()
        
        # Calculate payload hash for idempotency verification
        payload_hash = self._calculate_payload_hash(payload)
        
        # Add correlation ID if present
        correlation_id = payload.get("correlation_id", "unknown")
        
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "X-Dograh-Idempotency-Key": payload_hash,
            "X-Correlation-ID": correlation_id,
        }
        
        url = f"{DOGRAH_CONFIG['api_url']}/webhooks/{event_type}"
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    url,
                    json=payload,
                    headers=headers,
                    timeout=aiohttp.ClientTimeout(total=timeout)
                ) as resp:
                    result = await resp.json()
                    
                    if resp.status >= 400:
                        raise Exception(
                            f"Webhook failed: {resp.status} - {result}"
                        )
                    
                    return result
        except asyncio.TimeoutError:
            raise Exception(f"Webhook timeout after {timeout}s for {event_type}")
    
    def get_metrics(self) -> dict:
        """Return metrics for monitoring token cache effectiveness."""
        return {
            "mint_attempts": self._mint_attempts,
            "cache_hits": self._cache_hits,
            "race_conditions_prevented": self._race_conditions_prevented,
            "cache_efficiency": (
                self._cache_hits / (self._cache_hits + self._mint_attempts)
                if (self._cache_hits + self._mint_attempts) > 0
                else 0
            ),
        }
```

#### Concurrency Test Case

Add to `api/tests/test_token_concurrency.py`:

```python
import asyncio
import pytest
from datetime import datetime, timedelta
from unittest.mock import AsyncMock, patch, MagicMock
from db.base_client import SalesforceJWTClient

@pytest.mark.asyncio
async def test_concurrent_token_requests_no_race_condition():
    """
    Verify that 10 concurrent requests only trigger 1 token mint.
    
    This test ensures the asyncio.Lock prevents race conditions.
    """
    client = SalesforceJWTClient(
        org_id="test_org",
        client_id="test_client",
        private_key="test_key"
    )
    
    # Mock the Salesforce OAuth endpoint
    mock_token = "mock_access_token_12345"
    mock_response = {
        "access_token": mock_token,
        "expires_in": 3600,
        "token_type": "Bearer"
    }
    
    call_count = 0
    
    async def mock_fetch(*args, **kwargs):
        nonlocal call_count
        call_count += 1
        
        # Simulate network delay
        await asyncio.sleep(0.1)
        
        return mock_token, datetime.utcnow() + timedelta(hours=1)
    
    # Replace the fetch method
    client._fetch_token_from_salesforce = mock_fetch
    
    # Fire 10 concurrent requests
    tasks = [client.get_access_token() for _ in range(10)]
    tokens = await asyncio.gather(*tasks)
    
    # All should get the same token
    assert all(t == mock_token for t in tokens)
    
    # But only 1 fetch should have occurred
    assert call_count == 1, f"Expected 1 mint, got {call_count}"
    
    # Verify metrics
    metrics = client.get_metrics()
    assert metrics["race_conditions_prevented"] == 9
    assert metrics["cache_efficiency"] > 0.8

@pytest.mark.asyncio
async def test_token_refresh_with_safety_buffer():
    """
    Verify token is refreshed when 1 minute remains (2-min safety buffer).
    """
    client = SalesforceJWTClient(
        org_id="test_org",
        client_id="test_client",
        private_key="test_key"
    )
    
    call_count = 0
    
    async def mock_fetch(*args, **kwargs):
        nonlocal call_count
        call_count += 1
        
        # Token expires in 3 minutes from now
        return f"token_{call_count}", datetime.utcnow() + timedelta(minutes=3)
    
    client._fetch_token_from_salesforce = mock_fetch
    
    # First call: get token
    token1 = await client.get_access_token()
    assert token1 == "token_1"
    assert call_count == 1
    
    # Second call within 1 minute: should use cached token (>2 min remaining)
    token2 = await client.get_access_token()
    assert token2 == "token_1"
    assert call_count == 1  # No new mint
    
    # Simulate time passing: manually set expiry to 1 minute from now
    client._token_expiry = datetime.utcnow() + timedelta(minutes=1)
    
    # Third call: should refresh (only 1 min remaining, below 2-min buffer)
    token3 = await client.get_access_token()
    assert token3 == "token_2"
    assert call_count == 2  # New mint occurred
```

#### Integration with FastAPI

Update `api/routes/main.py` to use the new thread-safe client:

```python
from fastapi import FastAPI, BackgroundTasks
from db.base_client import SalesforceJWTClient
import asyncio

app = FastAPI()

# Initialize thread-safe client at app startup
jwt_client: Optional[SalesforceJWTClient] = None

@app.on_event("startup")
async def startup():
    global jwt_client
    jwt_client = SalesforceJWTClient(
        org_id=DOGRAH_CONFIG["salesforce_org_id"],
        client_id=DOGRAH_CONFIG["salesforce_client_id"],
        private_key=DOGRAH_CONFIG["salesforce_private_key"]
    )

@app.post("/webhooks/campaign_progress")
async def handle_campaign_progress(payload: dict) -> dict:
    """
    Example endpoint that safely posts events to Salesforce.
    The asyncio.Lock ensures concurrent requests don't cause race conditions.
    """
    try:
        # This will be thread-safe even with 100 concurrent requests
        result = await jwt_client.post_event_async(
            event_type="campaign_progress",
            payload=payload,
            timeout=5.0
        )
        return {"status": "accepted", "event_id": result.get("id")}
    except Exception as e:
        logger.error(f"Failed to post campaign progress: {str(e)}")
        return {"status": "error", "error": str(e)}, 500

@app.get("/metrics/token_cache")
async def get_token_metrics() -> dict:
    """Expose token cache metrics for monitoring."""
    if jwt_client:
        return jwt_client.get_metrics()
    return {}
```

#### Monitoring & Alerting

Add Prometheus metrics to track concurrency effectiveness:

```python
# In api/logging_config.py or monitoring module

from prometheus_client import Counter, Gauge, Histogram

# Token cache metrics
token_mint_attempts = Counter(
    "dograh_token_mint_attempts_total",
    "Total JWT token mint operations"
)

token_cache_hits = Counter(
    "dograh_token_cache_hits_total",
    "Total token cache hits (avoided mint)"
)

race_conditions_prevented = Counter(
    "dograh_race_conditions_prevented_total",
    "Concurrency lock prevented race conditions"
)

token_cache_efficiency = Gauge(
    "dograh_token_cache_efficiency_ratio",
    "Cache hit ratio (0-1): hits / (hits + mints)"
)

# Alert rule (add to Prometheus)
# ALERT TokenCacheEfficiencyLow
# IF dograh_token_cache_efficiency_ratio < 0.7
# FOR 5m
# ANNOTATIONS {
#   summary = "Token cache efficiency below 70%"
#   description = "Too many JWT mints happening. Check for clock skew or token expiry issues."
# }
```

#### Deployment Steps

1. **Update Python client** in `api/db/base_client.py` (copy code above)
2. **Add test file** `api/tests/test_token_concurrency.py`
3. **Update FastAPI integration** in `api/routes/main.py`
4. **Add Prometheus rules** to monitoring config
5. **Test locally**: `pytest api/tests/test_token_concurrency.py -v`
6. **Deploy to staging** and run load test with 100 concurrent requests
7. **Verify metrics**: Token cache efficiency should be >80%

**Estimated Time**: 2-3 hours implementation + 1 hour testing

---

## 2. Error Propagation & DLQ Alerting

### Problem
Dead-letter queue captures failed webhooks, but no automated alerting to operations team:
- **Current State**: DLQ entries logged, but require manual dashboard monitoring
- **Risk**: Critical errors unnoticed for hours; SLA violations

### Solution: Automated Slack/Email Alerts for Repeated DLQ Events

#### Step 1: Create DLQ Alert Platform Event

Add to `api/schemas/platform_events.py`:

```python
"""
Platform Event: Dograh_DLQ_Alert__e
Purpose: Triggered when >3 webhook failures occur in 24 hours
Subscribe: Admin notification flow, Slack integration
"""

class DograhDLQAlert:
    """
    Schema for DLQ Alert Platform Event
    Publishes when error threshold exceeded.
    """
    
    DLQ_ALERT_TRIGGER_COUNT = 3  # Errors per 24h window
    DLQ_ALERT_WINDOW_HOURS = 24
    
    # Event fields:
    # - error_type (Picklist: OAuth, Network, Validation, Rate_Limit, Other)
    # - failure_count (Number: current count in window)
    # - last_error_message (Text)
    # - correlation_ids (LongText: JSON array of related correlation IDs)
    # - severity (Picklist: Info, Warning, Critical)
    # - recommended_action (Text)
```

#### Step 2: Apex Queueable to Count DLQ Events

Add to `force-app/main/default/classes/DograhDLQMonitor.cls`:

```apex
/**
 * DLQMonitor - Monitors Integration_Error__c (DLQ) records
 * Purpose: Count failures in 24h window, publish alert if threshold exceeded
 * 
 * Usage: Called from Integration_Error__c trigger after insert
 */

public class DograhDLQMonitor implements Queueable {
    public static final Integer DLQ_THRESHOLD = 3;
    public static final Integer HOURS_WINDOW = 24;
    public static final String ALERT_EVENT = 'Dograh_DLQ_Alert__e';
    
    public void execute(QueueableContext context) {
        try {
            checkDLQThreshold();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'DLQ Monitor Error: ' + e.getMessage());
        }
    }
    
    public static void checkDLQThreshold() {
        // Count errors in last 24 hours
        DateTime windowStart = DateTime.now().addHours(-HOURS_WINDOW);
        
        List<Dograh_Integration_Error__c> recentErrors = [
            SELECT Id, Error_Type__c, Error_Message__c, Correlation_ID__c
            FROM Dograh_Integration_Error__c
            WHERE CreatedDate >= :windowStart
            AND Retry_Count__c >= 1  // Only count persistent failures
            WITH SECURITY_ENFORCED
        ];
        
        if (recentErrors.size() >= DLQ_THRESHOLD) {
            publishDLQAlert(recentErrors);
        }
    }
    
    private static void publishDLQAlert(List<Dograh_Integration_Error__c> errors) {
        // Group errors by type
        Map<String, Integer> errorCounts = new Map<String, Integer>();
        List<String> correlationIds = new List<String>();
        
        for (Dograh_Integration_Error__c err : errors) {
            String errType = err.Error_Type__c ?? 'Unknown';
            errorCounts.put(errType, (errorCounts.get(errType) ?? 0) + 1);
            if (err.Correlation_ID__c != null) {
                correlationIds.add(err.Correlation_ID__c);
            }
        }
        
        // Determine severity
        String severity = errors.size() >= 10 ? 'Critical' : 'Warning';
        String errorTypeDisplay = String.join(errorCounts.keySet(), ', ');
        
        // Publish alert event
        Dograh_DLQ_Alert__e alertEvent = new Dograh_DLQ_Alert__e(
            Error_Type__c = errorTypeDisplay,
            Failure_Count__c = errors.size(),
            Last_Error_Message__c = errors[0].Error_Message__c,
            Correlation_IDs__c = JSON.serialize(correlationIds),
            Severity__c = severity,
            Recommended_Action__c = getDLQAction(errorTypeDisplay, errors.size())
        );
        
        // Set context for flow/process
        EventBus.publish(alertEvent);
    }
    
    private static String getDLQAction(String errorType, Integer count) {
        if (errorType.contains('OAuth')) {
            return 'Check JWT certificate expiration and OAuth token exchange';
        } else if (errorType.contains('Rate_Limit')) {
            return 'Verify Dograh API rate limits; consider fallback queue';
        } else if (errorType.contains('Network')) {
            return 'Check network connectivity and Dograh endpoint availability';
        } else {
            return 'Review error logs; contact Dograh support if persistent';
        }
    }
}
```

#### Step 3: Trigger to Monitor DLQ

Add to `force-app/main/default/triggers/Dograh_Integration_Error_Trigger.trigger`:

```apex
/**
 * Trigger: Dograh_Integration_Error_Trigger
 * Object: Dograh_Integration_Error__c (Dead-Letter Queue)
 * 
 * Enqueues DLQ monitor to check if alert threshold exceeded
 */

trigger Dograh_Integration_Error_Trigger on Dograh_Integration_Error__c (
    after insert
) {
    if (Trigger.isAfter && Trigger.isInsert) {
        // Enqueue async monitor (non-blocking)
        System.enqueueJob(new DograhDLQMonitor());
    }
}
```

#### Step 4: Flow for Slack Notification

Create in Salesforce: **Dograh DLQ Alert to Slack Flow**

```
Trigger: Platform Event "Dograh_DLQ_Alert__e"

Actions:
1. Get Record - Fetch latest Integration Errors (for details)
2. HTTP Callout - POST to Slack Webhook:
   URL: {SLACK_WEBHOOK_URL}
   Payload:
   {
       "channel": "#dograh-alerts",
       "username": "Dograh Integration Monitor",
       "icon_emoji": ":warning:",
       "attachments": [
           {
               "color": "{Severity_Color}",  // red=critical, yellow=warning
               "title": "DLQ Alert: {error_type}",
               "fields": [
                   {
                       "title": "Failure Count (24h)",
                       "value": "{Failure_Count}",
                       "short": true
                   },
                   {
                       "title": "Last Error",
                       "value": "{Last_Error_Message}",
                       "short": false
                   },
                   {
                       "title": "Recommended Action",
                       "value": "{Recommended_Action}",
                       "short": false
                   },
                   {
                       "title": "Correlation IDs",
                       "value": "{Correlation_IDs}",
                       "short": false
                   }
               ],
               "actions": [
                   {
                       "type": "button",
                       "text": "View DLQ",
                       "url": "{Salesforce_URL}/lightning/o/Dograh_Integration_Error__c/list"
                   }
               ]
           }
       ]
   }
3. Notification - Send Email to [dograh-oncall@company.com]
   Subject: "🚨 Dograh Integration Alert: {error_type} x{Failure_Count}"
   Body: Include error details, recommended actions, dashboard link
```

#### Step 5: Email Notification Template

Create in Salesforce: **Dograh DLQ Alert Email**

```
Subject: Dograh Integration Alert - {!Severity} - {!Error_Type}

Hello,

{!Failure_Count} Dograh integration errors detected in the last 24 hours.

== Alert Details ==
Error Type: {!Error_Type}
Count: {!Failure_Count}
Severity: {!Severity}

Last Error Message:
{!Last_Error_Message}

Related Correlation IDs:
{!Correlation_IDs}

== Recommended Action ==
{!Recommended_Action}

== Next Steps ==
1. View DLQ records: [Link to DLQ List View]
2. Check correlation ID details: [Link to Integration Log]
3. Verify Dograh backend status: [Dograh status page]

For urgent issues, contact: dograh-support@company.com

---
Sent by Dograh Integration Monitor
```

#### Monitoring Dashboard Component

Create LWC component: `dograhDLQAlerts.js`

```javascript
import { LightningElement, wire, track } from 'lwc';
import getDLQStats from '@salesforce/apex/DograhDLQController.getDLQStats';

export default class DograhDLQAlerts extends LightningElement {
    @track dqlStats = null;
    @track errorChart = null;
    @track alertsLoading = true;

    @wire(getDLQStats, { hours: 24 })
    wiredStats(result) {
        if (result.data) {
            this.dqlStats = result.data;
            this.buildChart();
        } else if (result.error) {
            console.error('Error loading DLQ stats:', result.error);
        }
        this.alertsLoading = false;
    }

    buildChart() {
        // Render error distribution by type
        const chartData = {
            labels: Object.keys(this.dqlStats.byType),
            datasets: [{
                label: 'Errors by Type',
                data: Object.values(this.dqlStats.byType),
                backgroundColor: ['#e85d75', '#ff9500', '#ffc107']
            }]
        };
        this.errorChart = chartData;
    }

    get hasCriticalAlerts() {
        return this.dqlStats?.criticalCount > 0;
    }

    openDLQList() {
        window.open('/lightning/o/Dograh_Integration_Error__c/list', '_blank');
    }
}
```

#### Deployment Checklist

- [ ] Create `Dograh_DLQ_Alert__e` Platform Event
- [ ] Deploy `DograhDLQMonitor` Apex class
- [ ] Deploy `Dograh_Integration_Error_Trigger` trigger
- [ ] Create Flow: "Dograh DLQ Alert to Slack"
- [ ] Create Email Template: "Dograh DLQ Alert Email"
- [ ] Configure Slack Webhook (Settings > Integrations > Incoming Webhooks)
- [ ] Create DLQ Alert LWC component
- [ ] Add component to Admin dashboard
- [ ] Test with manual DLQ record insertion
- [ ] Verify Slack message received within 30 seconds
- [ ] Add monitoring to on-call runbook

**Estimated Time**: 4-5 hours implementation + 1 hour testing

---

## 4. Idempotency Scope Expansion

### Problem
Current idempotency only uses Correlation ID; multi-tenant scenarios need additional layers:
- **Risk**: Payload mutations not detected; duplicate processing if event replayed

### Solution: 3-Field Idempotency Key (Correlation ID + Event Type + Payload Hash)

#### Step 1: Update Platform Event Trigger

Update `force-app/main/default/triggers/Dograh_Call_Event_Trigger.trigger`:

```apex
trigger Dograh_Call_Event_Trigger on Dograh_Call_Event__e (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        DograhCallPersistenceJob.processCallEvents(Trigger.new);
    }
}
```

#### Step 2: Enhanced Queueable with Payload Hash

Update `force-app/main/default/classes/DograhCallPersistenceJob.cls`:

```apex
/**
 * DograhCallPersistenceJob - Persist call events to Dograh_Call_Activity__c
 * 
 * Enhanced Idempotency:
 * - Correlation_ID__c: Request-level deduplication
 * - Event_Type__c: Event category
 * - Payload_Hash__c (MD5): Detects mutation attacks / replays
 * 
 * Usage: Queueable job enqueued from Platform Event trigger
 */

public class DograhCallPersistenceJob implements Queueable {
    private List<Dograh_Call_Event__e> callEvents;
    
    public DograhCallPersistenceJob(List<Dograh_Call_Event__e> events) {
        this.callEvents = events;
    }
    
    public void execute(QueueableContext context) {
        processCallEvents(this.callEvents);
    }
    
    public static void processCallEvents(List<Dograh_Call_Event__e> events) {
        List<Dograh_Call_Activity__c> activitiesToUpsert = new List<Dograh_Call_Activity__c>();
        List<Dograh_Integration_Error__c> dlqRecords = new List<Dograh_Integration_Error__c>();
        
        for (Dograh_Call_Event__e event : events) {
            try {
                Dograh_Call_Activity__c activity = processCallEvent(event);
                if (activity != null) {
                    activitiesToUpsert.add(activity);
                }
            } catch (Exception e) {
                // Queue to DLQ for retry
                dlqRecords.add(createDLQRecord(event, e));
            }
        }
        
        // Upsert activities with 3-field idempotency key
        if (!activitiesToUpsert.isEmpty()) {
            performIdempotentUpsert(activitiesToUpsert);
        }
        
        // Write DLQ records
        if (!dlqRecords.isEmpty()) {
            insert as system dlqRecords;
        }
    }
    
    private static Dograh_Call_Activity__c processCallEvent(Dograh_Call_Event__e event) {
        // Lookup contact/lead by phone
        String callerPhone = event.Phone__c;
        String sanitizedPhone = sanitizePhone(callerPhone);
        
        // Find existing contact with this phone
        List<Contact> contacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Phone = :sanitizedPhone
            LIMIT 1
        ];
        
        String contactId = contacts.isEmpty() ? null : contacts[0].Id;
        
        // Create activity record
        Dograh_Call_Activity__c activity = new Dograh_Call_Activity__c(
            // External ID for idempotency (TEXT field, not Number!)
            Workflow_Run_ID__c = event.Workflow_Run_ID__c,  // e.g., "wf_run_123456"
            
            // Additional idempotency fields
            Event_Type__c = event.Event_Type__c,  // e.g., "call_ended"
            Payload_Hash__c = event.Payload_Hash__c,  // MD5 of event payload
            
            // Standard fields
            Contact__c = contactId,
            Campaign__c = event.Campaign_ID__c,
            Call_Direction__c = event.Call_Direction__c,
            Duration_Seconds__c = event.Duration_Seconds__c,
            Call_Status__c = event.Call_Status__c,
            Disposition_Code__c = event.Disposition_Code__c,
            Transcript__c = event.Transcript__c,
            Summary__c = event.Summary__c,
            Recording_URL__c = event.Recording_URL__c,
            Cost__c = event.Cost__c,
            Correlation_ID__c = event.Correlation_ID__c,  // For tracing
            Caller_Phone__c = sanitizedPhone,  // Shield Encrypted
        );
        
        return activity;
    }
    
    private static void performIdempotentUpsert(List<Dograh_Call_Activity__c> activities) {
        /**
         * 3-Field Idempotency Key:
         * 
         * The combination of:
         * 1. Workflow_Run_ID__c (External ID - unique run identifier)
         * 2. Event_Type__c (ensures different event types not deduplicated together)
         * 3. Payload_Hash__c (MD5 of event - detects mutations)
         * 
         * Upsert semantics:
         * - If all 3 match existing record → update (retry scenario)
         * - If any differ → insert new record (legitimate duplicate from different event)
         * - If Workflow_Run_ID + Event_Type match but Hash differs → reject (mutation/tampering)
         */
        
        Map<String, Dograh_Call_Activity__c> idempotencyMap = new Map<String, Dograh_Call_Activity__c>();
        
        for (Dograh_Call_Activity__c activity : activities) {
            // Build 3-part idempotency key
            String idempotencyKey = buildIdempotencyKey(
                activity.Workflow_Run_ID__c,
                activity.Event_Type__c,
                activity.Payload_Hash__c
            );
            
            if (idempotencyMap.containsKey(idempotencyKey)) {
                // Duplicate in same batch - keep first occurrence
                System.debug(LoggingLevel.WARN, 
                    'Duplicate in batch: ' + idempotencyKey);
                continue;
            }
            
            // Check for hash mismatch with existing record
            List<Dograh_Call_Activity__c> existing = [
                SELECT Id, Payload_Hash__c, Correlation_ID__c
                FROM Dograh_Call_Activity__c
                WHERE Workflow_Run_ID__c = :activity.Workflow_Run_ID__c
                AND Event_Type__c = :activity.Event_Type__c
                LIMIT 1
            ];
            
            if (!existing.isEmpty() && existing[0].Payload_Hash__c != activity.Payload_Hash__c) {
                // SECURITY: Payload hash mismatch indicates tampering or multi-tenant confusion
                System.debug(LoggingLevel.ERROR, 
                    'SECURITY ALERT: Payload hash mismatch for ' + 
                    activity.Workflow_Run_ID__c + 
                    '. Existing: ' + existing[0].Payload_Hash__c + 
                    ' New: ' + activity.Payload_Hash__c);
                
                // Log to integration error / DLQ
                throw new DograhIntegrationException(
                    'Payload hash verification failed - possible tampering'
                );
            }
            
            idempotencyMap.put(idempotencyKey, activity);
        }
        
        // Perform upsert with external ID
        List<Database.UpsertResult> results = Database.upsert(
            idempotencyMap.values(),
            Dograh_Call_Activity__c.Workflow_Run_ID__c,  // Use External ID field
            false  // allOrNone=false to allow partial success
        );
        
        // Log results for audit
        logUpsertResults(results);
    }
    
    private static String buildIdempotencyKey(
        String workflowRunId, 
        String eventType, 
        String payloadHash
    ) {
        // Concatenate 3 fields: correlation_id|event_type|hash
        return workflowRunId + '|' + eventType + '|' + payloadHash;
    }
    
    private static void logUpsertResults(List<Database.UpsertResult> results) {
        Integer inserted = 0, updated = 0;
        
        for (Database.UpsertResult result : results) {
            if (result.isCreated()) {
                inserted++;
            } else if (result.isSuccess()) {
                updated++;
            }
        }
        
        System.debug(LoggingLevel.INFO, 
            'Upsert completed: ' + inserted + ' inserted, ' + updated + ' updated');
    }
    
    private static Dograh_Integration_Error__c createDLQRecord(
        Dograh_Call_Event__e event, 
        Exception e
    ) {
        String payloadJson = JSON.serialize(new Map<String, Object>{
            'workflow_run_id' => event.Workflow_Run_ID__c,
            'event_type' => event.Event_Type__c,
            'phone' => event.Phone__c,
            'duration' => event.Duration_Seconds__c
        });
        
        return new Dograh_Integration_Error__c(
            Correlation_ID__c = event.Correlation_ID__c,
            Event_Type__c = 'CALL_PERSISTENCE_FAILURE',
            Error_Type__c = 'Processing',
            Error_Message__c = e.getMessage(),
            Payload__c = payloadJson,
            Retry_Count__c = 0,
            Status__c = 'Pending_Retry'
        );
    }
    
    private static String sanitizePhone(String phone) {
        // Remove non-digit characters
        return phone.replaceAll('[^0-9]', '');
    }
}

public class DograhIntegrationException extends Exception {}
```

#### Step 3: Update Custom Object Schema

Modify `force-app/main/default/objects/Dograh_Call_Activity__c/fields/`:

**Workflow_Run_ID__c** (External ID)
```
Field Type: Text
Length: 64
Unique: Yes
Case Sensitive: No
Description: External identifier for idempotency (e.g., wf_run_abc123def456)
External ID: Yes ← CRITICAL
```

**Event_Type__c** (Restricted Picklist)
```
Field Type: Picklist
Values:
  - call_started
  - call_ended
  - transfer_initiated
  - disposition_set
  - timeout
Description: Type of event that created this record (used for idempotency)
```

**Payload_Hash__c** (Text)
```
Field Type: Text
Length: 32  (MD5 hash length)
Description: MD5 hash of event payload - used to detect tampering/mutations
Indexed: Yes
Help Text: If this differs on retry, payload may have been tampered with
```

#### Step 4: Backend Python Integration

Update webhook handler in `api/routes/rtc_offer.py` or relevant endpoint:

```python
import hashlib
import json
from typing import Optional

class WebhookPayloadHasher:
    """Calculate deterministic MD5 hash of webhook payload for idempotency."""
    
    @staticmethod
    def calculate_hash(payload: dict) -> str:
        """
        Calculate MD5 hash of normalized JSON payload.
        
        Normalization ensures same logical payload always produces same hash:
        - Sort dictionary keys
        - Exclude mutable fields (timestamps, correlation_id)
        - Lowercase string values
        
        Args:
            payload: Raw webhook payload dict
            
        Returns:
            32-character hex string (MD5 hash)
        """
        # Remove fields that change on retry
        normalized_payload = {
            k: v for k, v in payload.items()
            if k not in ['correlation_id', 'timestamp', 'retry_count']
        }
        
        # Sort for deterministic ordering
        payload_json = json.dumps(normalized_payload, sort_keys=True)
        
        # Compute MD5
        hash_obj = hashlib.md5(payload_json.encode())
        return hash_obj.hexdigest()
    
    @staticmethod
    def validate_hash(payload: dict, provided_hash: Optional[str]) -> bool:
        """
        Validate provided hash matches computed hash.
        
        Returns False if hash mismatch (indicates tampering).
        """
        if provided_hash is None:
            return True  # No hash provided, assume valid
        
        computed = WebhookPayloadHasher.calculate_hash(payload)
        return computed == provided_hash

@app.post("/webhooks/call_completed")
async def handle_call_completed(payload: dict, request: Request) -> dict:
    """
    Handle completed call webhook from Dograh backend.
    
    Includes idempotency hash for mutation detection.
    """
    correlation_id = payload.get("correlation_id", "unknown")
    payload_hash = WebhookPayloadHasher.calculate_hash(payload)
    event_type = payload.get("event_type", "call_completed")
    
    # Add hash to payload before posting to Salesforce
    payload_with_hash = {
        **payload,
        "payload_hash": payload_hash,
        "event_type": event_type
    }
    
    try:
        # Post to Salesforce with all 3 idempotency fields
        result = await jwt_client.post_event_async(
            event_type="call_completed",
            payload=payload_with_hash,
            timeout=5.0
        )
        
        logger.info(
            f"Call event processed: correlation_id={correlation_id}, "
            f"hash={payload_hash}, event_type={event_type}"
        )
        
        return {"status": "accepted", "event_id": result.get("id")}
    
    except Exception as e:
        logger.error(
            f"Failed to process call event: {str(e)}, "
            f"correlation_id={correlation_id}, payload_hash={payload_hash}"
        )
        return {"status": "error", "error": str(e)}, 500
```

#### Step 5: Test Cases

Add to `force-app/main/default/classes/DograhCallPersistenceJobTest.cls`:

```apex
@IsTest
private class DograhCallPersistenceJobTest {
    
    @IsTest
    static void testIdempotencyWith3FieldKey() {
        /**
         * Scenario: Same event replayed 3 times
         * Expected: Only 1 Call Activity record created
         */
        
        String workflowRunId = 'wf_run_test_123';
        String eventType = 'call_ended';
        String payloadHash = 'abc123def456';
        String correlationId = 'corr_xyz_789';
        
        // First publish: creates record
        Dograh_Call_Event__e event1 = new Dograh_Call_Event__e(
            Workflow_Run_ID__c = workflowRunId,
            Event_Type__c = eventType,
            Payload_Hash__c = payloadHash,
            Correlation_ID__c = correlationId,
            Duration_Seconds__c = 125,
            Phone__c = '+14155551234',
            Disposition_Code__c = 'COMPLETED'
        );
        
        EventBus.publish(event1);
        Test.getEventBus().deliver();
        
        List<Dograh_Call_Activity__c> records1 = [
            SELECT Id, Workflow_Run_ID__c 
            FROM Dograh_Call_Activity__c 
            WHERE Workflow_Run_ID__c = :workflowRunId
        ];
        Assert.areEqual(1, records1.size(), 'Expected 1 record after first publish');
        
        // Second publish (retry): upserts existing, doesn't create new
        EventBus.publish(event1);
        Test.getEventBus().deliver();
        
        List<Dograh_Call_Activity__c> records2 = [
            SELECT Id 
            FROM Dograh_Call_Activity__c 
            WHERE Workflow_Run_ID__c = :workflowRunId
        ];
        Assert.areEqual(1, records2.size(), 'Expected 1 record after retry (upserted)');
        Assert.areEqual(records1[0].Id, records2[0].Id, 'Same record should be updated');
    }
    
    @IsTest
    static void testPayloadHashMismatchDetection() {
        /**
         * Scenario: Replay with modified hash (tampering detection)
         * Expected: Integration error logged, record not updated
         */
        
        String workflowRunId = 'wf_run_tamper_123';
        String eventType = 'call_ended';
        String originalHash = 'original_hash_abc123';
        
        // Create original record
        Dograh_Call_Activity__c original = new Dograh_Call_Activity__c(
            Workflow_Run_ID__c = workflowRunId,
            Event_Type__c = eventType,
            Payload_Hash__c = originalHash,
            Duration_Seconds__c = 125
        );
        insert original;
        
        // Attempt replay with different hash
        String tamperedHash = 'tampered_hash_def456';
        
        Dograh_Call_Event__e tamperedEvent = new Dograh_Call_Event__e(
            Workflow_Run_ID__c = workflowRunId,
            Event_Type__c = eventType,
            Payload_Hash__c = tamperedHash,  // Different hash!
            Correlation_ID__c = 'corr_tamper_test'
        );
        
        Test.startTest();
        try {
            EventBus.publish(tamperedEvent);
            Test.getEventBus().deliver();
        } catch (Exception e) {
            // Expected: hash mismatch error
            System.assert(e.getMessage().contains('hash'), 
                'Expected hash mismatch error');
        }
        Test.stopTest();
        
        // Verify DLQ record was created
        List<Dograh_Integration_Error__c> dlq = [
            SELECT Error_Message__c 
            FROM Dograh_Integration_Error__c 
            WHERE Correlation_ID__c = 'corr_tamper_test'
        ];
        Assert.areEqual(1, dlq.size(), 'DLQ should contain tampering detection');
    }
    
    @IsTest
    static void testBatchDuplicateDetection() {
        /**
         * Scenario: 10 identical events in single batch
         * Expected: Only 1 record inserted
         */
        
        List<Dograh_Call_Event__e> duplicateEvents = new List<Dograh_Call_Event__e>();
        
        for (Integer i = 0; i < 10; i++) {
            duplicateEvents.add(new Dograh_Call_Event__e(
                Workflow_Run_ID__c = 'wf_dup_batch_123',
                Event_Type__c = 'call_ended',
                Payload_Hash__c = 'batch_hash_xyz',
                Duration_Seconds__c = 200
            ));
        }
        
        Test.startTest();
        EventBus.publish(duplicateEvents);
        Test.getEventBus().deliver();
        Test.stopTest();
        
        List<Dograh_Call_Activity__c> records = [
            SELECT Id 
            FROM Dograh_Call_Activity__c 
            WHERE Workflow_Run_ID__c = 'wf_dup_batch_123'
        ];
        
        Assert.areEqual(1, records.size(), 
            'Batch duplicates should result in 1 record');
    }
}
```

#### Deployment Checklist

- [ ] Add `Payload_Hash__c`, `Event_Type__c` fields to `Dograh_Call_Activity__c`
- [ ] Ensure `Workflow_Run_ID__c` marked as External ID (TEXT, not Number)
- [ ] Deploy enhanced `DograhCallPersistenceJob` class
- [ ] Add hash calculation to Python backend (`WebhookPayloadHasher`)
- [ ] Add test cases to `DograhCallPersistenceJobTest`
- [ ] Test locally: `pytest api/tests/test_idempotency.py -v`
- [ ] Run Apex tests: `sfdx force:apex:test:run -l RunLocalTests`
- [ ] Deploy to staging
- [ ] Verify 3-field idempotency with test payload
- [ ] Verify hash mismatch detection (security validation)

**Estimated Time**: 3-4 hours implementation + 2 hours testing

---

# MEDIUM EFFORT (3-5 Days)

---

## 3. Observability Gaps - Event Monitoring Integration

### Problem
Correlation IDs exist but Event Monitoring API is not leveraged to detect OAuth failures in real time:
- **Gap**: 401/403 responses from Salesforce Connected App are not surfaced to operations teams
- **Impact**: Failed JWT exchanges can go unnoticed for hours, causing webhook backlogs

### Solution: Transaction Security Policies + Event Monitoring Dashboards

#### Step 1: Enable Event Monitoring & Real-Time Events

1. Purchase/enable Event Monitoring for the Salesforce org
2. Navigate to **Setup → Event Monitoring Settings**
3. Enable the following Log Types:
   - `API` (captures REST/SOAP calls and status codes)
   - `Login` (captures OAuth JWT bearer failures)
   - `PlatformEvents` (monitors publish errors)
4. Enable **Real-Time Event Monitoring** for `API` logins

#### Step 2: Transaction Security Policy (Detect OAuth 401s)

Create a Transaction Security Policy to detect API calls from the Dograh Connected App that return 401:

```
Setup → Transaction Security → New Policy → Event Type = API Event

Conditions:
  - Client Name Equals "DograhConnectedApp"
  - Status Equals 401

Action:
  - Block: No (monitor only)
  - Notify: Yes → Send email to dograh-oncall@company.com
  - Execute Apex: DograhTransactionSecurityHandler
```

#### Step 3: Apex Handler for Policy

Create `force-app/main/default/classes/DograhTransactionSecurityHandler.cls`:

```apex
public without sharing class DograhTransactionSecurityHandler implements TxnProvider {
    /**
     * Transaction Security handler invoked when API 401 is detected.
     * Publishes Dograh_Event_Monitor__e event for real-time dashboards.
     */
    public void execute(TxnContext ctx, TxnState state) {
        EventMonitoring.EventLogFile eventData = ctx.getEventLog();

        Dograh_Event_Monitor__e monitoringEvent = new Dograh_Event_Monitor__e(
            Event_Type__c = 'OAUTH_FAILURE',
            Connected_App__c = String.valueOf(eventData.CLIENT_ID),
            User_Name__c = String.valueOf(eventData.USER_NAME),
            Source_IP__c = String.valueOf(eventData.CLIENT_IP),
            Status_Code__c = String.valueOf(eventData.STATUS),
            Request_URI__c = String.valueOf(eventData.URI),
            Occurred_At__c = DateTime.valueOf(eventData.EVENT_TIME),
            Correlation_ID__c = eventData.getFieldValue('REQUEST_ID')
        );

        EventBus.publish(monitoringEvent);

        // Optional: invoke Slack alert if repeated failures occur
        DograhEventMonitor.enqueueAlert(monitoringEvent);
    }
}
```

Create helper class `DograhEventMonitor.cls`:

```apex
public without sharing class DograhEventMonitor {
    public static final Integer OAUTH_ALERT_THRESHOLD = 5; // per hour

    public static void enqueueAlert(Dograh_Event_Monitor__e evt) {
        System.enqueueJob(new DograhEventMonitorJob(evt));
    }
}

public without sharing class DograhEventMonitorJob implements Queueable {
    private Dograh_Event_Monitor__e monitoringEvent;

    public DograhEventMonitorJob(Dograh_Event_Monitor__e evt) {
        monitoringEvent = evt;
    }

    public void execute(QueueableContext context) {
        DateTime windowStart = DateTime.now().addMinutes(-60);

        Integer failureCount = [
            SELECT COUNT()
            FROM Dograh_Event_Monitor__e
            WHERE Event_Type__c = 'OAUTH_FAILURE'
            AND Occurred_At__c >= :windowStart
        ];

        if (failureCount >= DograhEventMonitor.OAUTH_ALERT_THRESHOLD) {
            Dograh_DLQ_Alert__e alert = new Dograh_DLQ_Alert__e(
                Error_Type__c = 'OAuth',
                Failure_Count__c = failureCount,
                Severity__c = 'Warning',
                Recommended_Action__c = 'Verify JWT private key, Connected App certificate, and Salesforce status.'
            );
            EventBus.publish(alert);
        }
    }
}
```

#### Step 4: Real-Time Event Monitoring Dashboard

Use Salesforce analytics to build a **Lightning App** dashboard:

| Component | Description | Filter |
|-----------|-------------|--------|
| API Failure Timeline | Line chart of OAUTH failures per hour | Event_Type = `OAUTH_FAILURE` |
| Top Users Failing OAuth | Bar chart | Group by `User_Name__c` |
| Source IP Heatmap | Heatmap of `Source_IP__c` | Highlight suspicious IPs |
| 24h Summary | KPI cards (Total Failures, Unique Users, Last Failure) | N/A |

#### Step 5: Async Analysis via Event Log File API

Add nightly job to fetch Event Log Files for audit:

```bash
# scripts/event_monitoring_fetch.sh
DAY=$(date -u +"%Y-%m-%d")
sfdx force:data:soql:query \
  --query "SELECT Id, EventType, LogFile FROM EventLogFile WHERE EventType IN ('API', 'Login') AND CreatedDate = ${DAY}T00:00:00Z" \
  --resultformat csv \
  --outputdir logs/event_monitoring/${DAY}

# Post-process with Python to store in S3 & generate reports
python scripts/process_event_logs.py logs/event_monitoring/${DAY}
```

`scripts/process_event_logs.py`:

```python
import csv
import json
import boto3
from pathlib import Path

s3 = boto3.client("s3")

def process(path: Path, bucket: str):
    for log_file in path.glob("*.csv"):
        with log_file.open() as fh:
            reader = csv.DictReader(fh)
            oauth_failures = [row for row in reader if row["STATUS"] == "401"]

        report_path = log_file.with_suffix(".json")
        report_path.write_text(json.dumps(oauth_failures, indent=2))

        s3.upload_file(str(report_path), bucket, f"event-monitoring/{report_path.name}")

if __name__ == "__main__":
    process(Path("logs/event_monitoring"), "dograh-monitoring")
```

#### Deployment Checklist

- [ ] Enable Event Monitoring & Real-Time Event Monitoring
- [ ] Create Transaction Security Policy with API event conditions
- [ ] Deploy `DograhTransactionSecurityHandler` & helper classes
- [ ] Create `Dograh_Event_Monitor__e` Platform Event
- [ ] Build Lightning dashboard for OAuth failures
- [ ] Schedule nightly script to export Event Log Files
- [ ] Update operations runbook with alert response procedure

**Estimated Time**: 3 days (config + Apex + dashboard + automation)

---

## 5. API Latency Budget & Fallback Queue

### Problem
Dograh REST calls target ≤500 ms latency, but spikes above 700 ms can cause Lightning components to time out and LLM prompts to fail. No asynchronous fallback exists.

### Solution: Hybrid Sync + Async Queue with SLA Monitoring

#### Step 1: Prometheus Latency Budget Alerts

Add histogram metrics in FastAPI middleware (`api/logging_config.py`):

```python
from prometheus_client import Histogram

sf_latency_seconds = Histogram(
    "dograh_salesforce_api_latency_seconds",
    "Salesforce API response time",
    buckets=(0.1, 0.3, 0.5, 0.7, 1.0, 2.0, 5.0)
)

@app.middleware("http")
async def record_latency(request: Request, call_next):
    if request.url.path.startswith("/salesforce/"):
        with sf_latency_seconds.time():
            return await call_next(request)
    return await call_next(request)
```

Prometheus rule:

```
ALERT SalesforceLatencyBudgetBreached
IF histogram_quantile(0.95, rate(dograh_salesforce_api_latency_seconds_bucket[5m])) > 0.7
FOR 10m
ANNOTATIONS {
  summary = "Salesforce API p95 latency >700ms",
  description = "Switching to asynchronous queue to avoid timeouts."
}
```

#### Step 2: FastAPI Fallback Pattern

Add fallback service `api/services/fallback_queue.py`:

```python
from datetime import datetime
from typing import Any, Dict
import asyncio
import uuid

from services.redis_queue import enqueue_async_task
from utils.logger import logger

FALLBACK_THRESHOLD_MS = 700


async def call_salesforce_with_fallback(operation: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    start = datetime.utcnow()

    try:
        response = await jwt_client.post_event_async(operation, payload)
        duration_ms = (datetime.utcnow() - start).total_seconds() * 1000

        if duration_ms > FALLBACK_THRESHOLD_MS:
            logger.warning("Latency high: %.2fms; enqueueing fallback", duration_ms)
            await enqueue_fallback(operation, payload)
        return {"status": "synchronous", "result": response}

    except Exception as exc:
        logger.error("Salesforce call failed (%s); using fallback", exc)
        await enqueue_fallback(operation, payload)
        return {"status": "async", "result": "queued"}


async def enqueue_fallback(operation: str, payload: Dict[str, Any]) -> None:
    task_id = str(uuid.uuid4())
    job = {
        "task_id": task_id,
        "operation": operation,
        "payload": payload,
        "enqueued_at": datetime.utcnow().isoformat(),
    }
    await enqueue_async_task("salesforce_fallback", job)
```

#### Step 3: Redis Worker (ARQ)

`api/services/redis_queue.py`:

```python
import json
import aioredis

REDIS_URL = DOGRAH_CONFIG["redis_url"]


async def enqueue_async_task(queue: str, payload: dict) -> None:
    redis = await aioredis.from_url(REDIS_URL)
    await redis.rpush(queue, json.dumps(payload))


async def dequeue_async_task(queue: str) -> dict | None:
    redis = await aioredis.from_url(REDIS_URL)
    data = await redis.lpop(queue)
    return json.loads(data) if data else None
```

Worker `api/tasks/salesforce_fallback_worker.py`:

```python
import asyncio
from services.redis_queue import dequeue_async_task
from db.base_client import SalesforceJWTClient
from utils.logger import logger

async def worker(jwt_client: SalesforceJWTClient):
    while True:
        job = await dequeue_async_task("salesforce_fallback")
        if not job:
            await asyncio.sleep(1)
            continue

        try:
            await jwt_client.post_event_async(job["operation"], job["payload"], timeout=10.0)
            logger.info("Fallback job %s succeeded", job["task_id"])
        except Exception as exc:
            logger.error("Fallback job %s failed: %s", job["task_id"], exc)
            # Retry logic / DLQ integration can follow existing patterns


if __name__ == "__main__":
    asyncio.run(worker(jwt_client))
```

Invoke from FastAPI route:

```python
@app.post("/salesforce/campaigns")
async def create_campaign(payload: dict) -> dict:
    result = await call_salesforce_with_fallback("create_campaign", payload)
    if result["status"] == "async":
        return {"status": "accepted", "async": True}, 202
    return result
```

#### Step 4: Queueable Apex Consumer (Fallback Processing)

Create `force-app/main/default/classes/DograhFallbackProcessor.cls`:

```apex
public without sharing class DograhFallbackProcessor implements Queueable {
    @AuraEnabled
    public static void enqueue(String fallbackId) {
        System.enqueueJob(new DograhFallbackProcessor(fallbackId));
    }

    private String fallbackId;

    public DograhFallbackProcessor(String id) {
        fallbackId = id;
    }

    public void execute(QueueableContext context) {
        // Pull payload from custom object (Dograh_Fallback__c) populated via REST
        Dograh_Fallback__c pending = [
            SELECT Id, Operation__c, Payload__c
            FROM Dograh_Fallback__c
            WHERE External_Id__c = :fallbackId
            LIMIT 1
        ];

        // Process operation (e.g., create campaign records)
        DograhAPIHandler.handleAsyncOperation(pending.Operation__c, pending.Payload__c);

        pending.Status__c = 'Processed';
        update pending;
    }
}
```

#### Deployment Checklist

- [ ] Add Prometheus histogram & alert rule
- [ ] Implement `call_salesforce_with_fallback` logic
- [ ] Deploy Redis worker service in Kubernetes (consumer pods)
- [ ] Create `Dograh_Fallback__c` custom object for tracking async jobs
- [ ] Deploy `DograhFallbackProcessor` Apex class
- [ ] Update runbook with SLA thresholds & failover steps

**Estimated Time**: 4 days (metrics, async queue, Apex integration, testing)

---

## 7. Platform Event Volume & Limits Analysis

### Problem
High-volume campaigns can publish millions of events/hour. Documentation lacks throughput planning, replay retention guidance, and fallback strategies.

### Solution: Capacity Planning + Monitoring

#### Platform Event Limits Cheat Sheet

| Org Type | Publish Limit (Events/Hour) | Default Replay | High-Volume Replay | Daily Storage |
|----------|-----------------------------|----------------|--------------------|---------------|
| Standard Platform Events | 1,000 | 24h | N/A | 72h logs |
| High-Volume Platform Events (HVPE) | 50,000 (per subscription) | 24h | 72h (premium) | 7 days |
| Event Bus Capacity Add-on | 150,000 | 72h | 7 days | 10 days |

#### Campaign Throughput Calculator

`scripts/pe_capacity_calculator.py`:

```python
def required_pe_rate(campaigns_per_hour: int, leads_per_campaign: int, events_per_lead: int) -> int:
    return campaigns_per_hour * leads_per_campaign * events_per_lead


def recommend_plan(rate: int) -> str:
    if rate <= 1_000:
        return "Standard Platform Events sufficient"
    if rate <= 50_000:
        return "Enable High-Volume Platform Events"
    return "Purchase Event Bus Capacity add-on"


if __name__ == "__main__":
    rate = required_pe_rate(campaigns_per_hour=5_000, leads_per_campaign=100, events_per_lead=1)
    print("Required events/hour:", rate)
    print("Recommendation:", recommend_plan(rate))
```

#### HVPE Conversion Checklist

- [ ] Convert `Dograh_Campaign_Event__e` and `Dograh_Call_Event__e` to High-Volume Platform Events
- [ ] Enable **High-Volume Platform Events** from Setup
- [ ] Update subscribers (Apex triggers) to use `after insert` only (HVPE restriction)
- [ ] Update replay ID handling in integration clients (only numeric replay IDs)

#### Queue Depth Monitoring

Add field `Queue_Depth__c` to `Dograh_Integration_Log__c`. Update Apex to track publish failures:

```apex
public without sharing class DograhEventPublisher {
    public static void publishCampaignEvent(Dograh_Campaign_Event__e evt) {
        SaveResult result = EventBus.publish(evt);
        if (!result.isSuccess()) {
            logFailure('CampaignEvent', result.getErrors());
            throw new DograhIntegrationException('Failed to publish campaign event');
        }
    }

    private static void logFailure(String eventName, List<Database.Error> errors) {
        Dograh_Integration_Log__c log = new Dograh_Integration_Log__c(
            Event_Name__c = eventName,
            Status__c = 'PublishFailed',
            Error_Message__c = errors[0].getMessage(),
            Queue_Depth__c = getBusQueueDepth()
        );
        log.insert();
    }

    @TestVisible
    private static Integer getBusQueueDepth() {
        // For illustration: use Event Monitoring or future API when exposed
        return 0;
    }
}
```

Prometheus exporter (Node.js example) to poll Salesforce `/services/data/vXX.X/sobjects/EventBusSubscriber` and expose queue depth for Grafana alerts.

#### Alerting Rule

```
ALERT PlatformEventQueueHigh
IF dograh_salesforce_pe_queue_depth > 0.8 * dograh_salesforce_pe_limit
FOR 5m
ANNOTATIONS {
  summary = "Platform Event queue depth exceeds 80%",
  description = "Reduce publish rate or provision High-Volume Platform Events."
}
```

**Estimated Time**: 3 days (analysis tooling, HVPE conversion, monitoring)

---

## 8. Data Residency & Latency Alignment

### Problem
Documentation lacks guidance for region alignment when handling PII/PHI. Dograh services may be deployed in regions far from Salesforce org, introducing latency and compliance risk.

### Solution: Regional Deployment Matrix + Compliance Checklist

#### Data Residency Matrix

| Region | Salesforce Instance | Dograh API Region | Storage | Latency Target | Compliance |
|--------|---------------------|-------------------|---------|----------------|------------|
| US-East | *.my.salesforce.com | AWS `us-east-1` | S3 `us-east-1` (AES-256) | ≤70 ms | SOC2, HIPAA (BAA), CCPA |
| US-West | *.na*.salesforce.com | GCP `us-west2` | GCS `us-west2` | ≤80 ms | SOC2, HIPAA |
| EU-Central | *.eu*.salesforce.com | AWS `eu-west-1` | S3 `eu-west-1` | ≤90 ms | GDPR, Schrems II |
| APAC | *.ap*.salesforce.com | AWS `ap-southeast-2` | S3 `ap-southeast-2` | ≤110 ms | IRAP, APRA |

#### Deployment Guidelines

1. **Region Pairing**: Select Kubernetes cluster within 1 region hop of Salesforce instance
2. **Transcript Storage**: Use region-aligned object storage (S3/GCS) with server-side encryption
3. **Encryption Keys**: KMS keys remain in-region (no cross-region replication for PHI)
4. **Traffic Routing**: Configure CloudFront/CloudFlare regional edge caches pointing to nearest cluster

#### Compliance Checklist

- [ ] Business Associate Agreement (BAA) signed for HIPAA customers
- [ ] Data Processing Addendum (DPA) executed (GDPR)
- [ ] Audit logging enabled (Salesforce Field Audit Trail + Dograh Integration Logs)
- [ ] Shield Platform Encryption for `Dograh_Call_Activity__c` sensitive fields
- [ ] Access logs retained for 1 year (HIPAA) / 6 months (GDPR)

#### Monitoring Latency

Add synthetic probe (`scripts/latency_probe.py`):

```python
import time
import requests

def probe(url: str) -> float:
    start = time.perf_counter()
    r = requests.get(url, timeout=2.0)
    r.raise_for_status()
    return (time.perf_counter() - start) * 1000


if __name__ == "__main__":
    latency = probe("https://dograh-us-east-1.example.com/healthz")
    print(f"Latency: {latency:.2f}ms")
```

Integrate with Grafana world map panel to visualize latency per region.

**Estimated Time**: 2 days (documentation, compliance alignment, monitoring)

---

# STRATEGIC (1-2 Weeks)

---

## 6. JWT Rotation Operations & Automation

### Problem
JWT certificate rotation is manual, risky, and often delayed beyond security best practice. No automation exists for generating new keys, updating Salesforce Connected App, and syncing Kubernetes secrets.

### Solution: GitHub Actions Pipeline + Graceful Key Rollover

#### Rotation Schedule

- Rotate RSA key pair every **90 days**
- Maintain overlapping validity for 24 hours (old + new certificate)
- Store reminders in PagerDuty/Calendar (automated via workflow)

#### Step 1: Key Generation Script

`scripts/generate_jwt_cert.ps1`:

```powershell
param(
        [string]$OutputDir = "certs",
        [int]$KeySize = 2048
)

$date = Get-Date -Format "yyyyMMdd"
$privateKeyPath = Join-Path $OutputDir "dograh_jwt_$date.key"
$publicCertPath = Join-Path $OutputDir "dograh_jwt_$date.crt"

openssl genrsa -out $privateKeyPath $KeySize
openssl req -new -x509 -key $privateKeyPath -out $publicCertPath -days 365 -subj "/CN=DograhJWT$date"

Write-Host "Generated private key: $privateKeyPath"
Write-Host "Generated certificate: $publicCertPath"
```

#### Step 2: GitHub Actions Workflow

`.github/workflows/jwt-rotation.yml`:

```yaml
name: JWT Certificate Rotation

on:
    workflow_dispatch:
        inputs:
            environment:
                description: "Target environment"
                required: true
                default: "production"

jobs:
    rotate:
        runs-on: ubuntu-latest
        permissions:
            contents: read
            id-token: write
        steps:
            - uses: actions/checkout@v4

            - name: Generate RSA key pair
                run: |
                    mkdir certs
                    openssl genrsa -out certs/dograh_jwt_new.key 2048
                    openssl req -new -x509 -key certs/dograh_jwt_new.key \
                        -out certs/dograh_jwt_new.crt -days 365 -subj "/CN=DograhJWT"

            - name: Upload cert to Salesforce
                env:
                    SFDX_AUTH_URL: ${{ secrets.SFDX_AUTH_URL }}
                run: |
                    npm install --global sfdx-cli
                    echo $SFDX_AUTH_URL | sfdx force:auth:sfdxurl:store --setalias dograh
                    sfdx force:connectedapp:jwt:cert:add \
                        --targetusername dograh \
                        --connectedappname DograhConnectedApp \
                        --certificatefile certs/dograh_jwt_new.crt

            - name: Update Kubernetes secret
                env:
                    K8S_CONFIG: ${{ secrets.K8S_CONFIG }}
                run: |
                    echo "$K8S_CONFIG" > kubeconfig
                    kubectl --kubeconfig kubeconfig create secret generic dograh-jwt \
                        --from-file=jwt.key=certs/dograh_jwt_new.key \
                        --dry-run=client -o yaml | kubectl --kubeconfig kubeconfig apply -f -

            - name: Notify Slack
                env:
                    SLACK_WEBHOOK: ${{ secrets.SLACK_ROTATION_WEBHOOK }}
                run: |
                    payload=$(jq -n \
                        --arg text "JWT certificate rotated for ${{ github.event.inputs.environment }}" \
                        '{text: $text}')
                    curl -X POST -H 'Content-type: application/json' --data "$payload" $SLACK_WEBHOOK

            - name: Upload secrets to GitHub Secrets
                uses: crazy-max/ghaction-github-secrets@v1
                with:
                    token: ${{ secrets.GH_TOKEN }}
                    secrets: |
                        DOGRAH_JWT_PRIVATE_KEY=certs/dograh_jwt_new.key
                        DOGRAH_JWT_PUBLIC_CERT=certs/dograh_jwt_new.crt
```

#### Step 3: Grace Period Validation

Add integration test to ensure new and old keys work for 24 hours:

```python
def test_jwt_grace_period(old_key_path, new_key_path):
        client_old = SalesforceJWTClient(org_id, client_id, old_key_path)
        client_new = SalesforceJWTClient(org_id, client_id, new_key_path)

        token_old = asyncio.run(client_old.get_access_token())
        token_new = asyncio.run(client_new.get_access_token())

        assert token_old
        assert token_new
```

#### Step 4: Runbook Updates

- [ ] Run workflow the last business day before expiry
- [ ] Verify Salesforce Connected App shows both certificates
- [ ] Verify Dograh pods reload secret (`kubectl rollout restart deployment dograh-api`)
- [ ] Monitor OAuth failure dashboard for anomalies

**Estimated Time**: 5 days (workflow, secret management, testing, documentation)

---

## 9. LWC Data Fetch & Caching Inefficiencies

### Problem
Lightning components rely on imperative Apex and 5-second polling for updates, leading to unnecessary API usage and slow UI response.

### Solution: Use `@wire(cacheable=true)`, Platform Cache, and Platform Event invalidation

#### Step 1: Apex Controllers with Cacheable Wire

`force-app/main/default/classes/DograhCampaignController.cls`:

```apex
public with sharing class DograhCampaignController {
    @AuraEnabled(cacheable=true)
    public static List<Dograh_Campaign__c> getActiveCampaigns() {
        return [
            SELECT Id, Name, Status__c, Progress_Percentage__c
            FROM Dograh_Campaign__c
            WHERE Status__c IN ('running', 'paused')
            ORDER BY LastModifiedDate DESC
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Dograh_Call_Activity__c> getRecentCalls(Id contactId) {
        return [
            SELECT Id, Summary__c, Call_Status__c, Duration_Seconds__c, Correlation_ID__c
            FROM Dograh_Call_Activity__c
            WHERE Contact__c = :contactId
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
    }
}
```

#### Step 2: LWC using `@wire`

`ui/src/components/dograhCampaignManager/dograhCampaignManager.ts`:

```typescript
import { LightningElement, wire } from 'lwc';
import getActiveCampaigns from '@salesforce/apex/DograhCampaignController.getActiveCampaigns';
import { refreshApex } from '@salesforce/apex';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class DograhCampaignManager extends LightningElement {
    campaigns;
    wiredResult;
    subscription;

    @wire(getActiveCampaigns)
    wiredCampaigns(value) {
        this.wiredResult = value;
        const { data, error } = value;
        if (data) {
            this.campaigns = data;
        } else if (error) {
            console.error('Failed to load campaigns', error);
        }
    }

    connectedCallback() {
        this.subscribeToEvents();
    }

    disconnectedCallback() {
        this.unsubscribeFromEvents();
    }

    subscribeToEvents() {
        const channel = '/event/Dograh_Campaign_Event__e';
        const messageCallback = (response) => {
            if (response?.data?.payload?.Event_Type__c === 'progress_update') {
                refreshApex(this.wiredResult);
            }
        };
        subscribe(channel, -1, messageCallback).then((response) => {
            this.subscription = response;
        });

        onError((error) => {
            console.error('EMP API error', error);
        });
    }

    unsubscribeFromEvents() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {
                this.subscription = null;
            });
        }
    }
}
```

#### Step 3: Platform Cache for Analytics Dashboards

`force-app/main/default/classes/DograhAnalyticsService.cls`:

```apex
public with sharing class DograhAnalyticsService {
    private static final String CACHE_REGION = 'DograhAnalytics';
    private static final Integer CACHE_TTL_SECONDS = 120;

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDashboardMetrics() {
        Cache.Session session = Cache.Session.getPrivateCache(CACHE_REGION);
        Map<String, Object> cached = (Map<String, Object>)session.get('dashboard_metrics');
        if (cached != null) {
            return cached;
        }

        Map<String, Object> metrics = new Map<String, Object>{
            'totalCalls' => [SELECT COUNT() FROM Dograh_Call_Activity__c],
            'activeCampaigns' => [SELECT COUNT() FROM Dograh_Campaign__c WHERE Status__c = 'running'],
            'avgDuration' => [SELECT AVG(Duration_Seconds__c) avg FROM Dograh_Call_Activity__c][0].avg
        };

        session.put('dashboard_metrics', metrics, CACHE_TTL_SECONDS);
        return metrics;
    }

    @AuraEnabled
    public static void invalidateCache() {
        Cache.Session.getPrivateCache(CACHE_REGION).remove('dashboard_metrics');
    }
}
```

Invalidate cache when Platform Event indicates updates:

```apex
trigger DograhAnalyticsEventTrigger on Dograh_Campaign_Event__e (after insert) {
    if (Trigger.new.anyMatch(evt -> evt.Event_Type__c == 'progress_update')) {
        DograhAnalyticsService.invalidateCache();
    }
}
```

**Estimated Time**: 3 days (controller updates, Platform Cache configuration, testing)

---

## 10. Mobile UX & Streaming Updates

### Problem
Current LWC layout is desktop-centric. Mobile users experience horizontal scrolling, slow load times, and data staleness due to polling.

### Solution: Responsive Lightning Cards + empApi streaming + performance budget

#### Step 1: Responsive Layout

`ui/src/components/dograhCallMonitor/dograhCallMonitor.html`:

```html
<template>
    <lightning-card title="Active Calls">
        <div class="cards">
            <template for:each={callItems} for:item="item">
                <section key={item.id} class="call-card">
                    <header class="call-header">
                        <h3>{item.contactName}</h3>
                        <lightning-badge label={item.status}></lightning-badge>
                    </header>
                    <p class="call-summary">{item.summary}</p>
                    <div class="call-meta">
                        <span>Duration: {item.duration}s</span>
                        <span>Workflow: {item.workflow}</span>
                    </div>
                    <footer class="call-actions">
                        <lightning-button-group>
                            <lightning-button variant="brand" label="View" data-id={item.id} onclick={handleView}></lightning-button>
                            <lightning-button variant="neutral" label="Disposition" data-id={item.id} onclick={handleDisposition}></lightning-button>
                        </lightning-button-group>
                    </footer>
                </section>
            </template>
        </div>
    </lightning-card>
</template>
```

`dograhCallMonitor.css`:

```css
.cards {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 1rem;
}

.call-card {
    border: 1px solid var(--lwc-colorBorder);
    border-radius: 0.75rem;
    padding: 1rem;
    background: var(--lwc-colorBackgroundAlt);
}

@media screen and (max-width: 480px) {
    .call-card {
        padding: 0.75rem;
    }

    .call-actions lightning-button {
        width: 100%;
    }

    .call-actions lightning-button + lightning-button {
        margin-top: 0.5rem;
    }
}
```

#### Step 2: Streaming API (No Polling)

`dograhCallMonitor.ts`:

```typescript
import { LightningElement, track } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getActiveCalls from '@salesforce/apex/DograhCallMonitorController.getActiveCalls';

export default class DograhCallMonitor extends LightningElement {
    channelName = '/event/Dograh_Call_Event__e';
    subscription;
    @track callItems = [];

    connectedCallback() {
        this.loadCalls();
        this.subscribeToEvents();
    }

    disconnectedCallback() {
        this.unsubscribeFromEvents();
    }

    loadCalls() {
        getActiveCalls()
            .then((result) => {
                this.callItems = result;
            })
            .catch((error) => {
                console.error('Failed to fetch calls', error);
            });
    }

    subscribeToEvents() {
        const callback = (message) => {
            const payload = message.data.payload;
            if (payload.Event_Type__c === 'call_started' || payload.Event_Type__c === 'call_ended') {
                this.loadCalls();
            }
        };

        subscribe(this.channelName, -1, callback).then((response) => {
            this.subscription = response;
        });

        onError((error) => {
            console.error('EMP API error', JSON.stringify(error));
        });
    }

    unsubscribeFromEvents() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {
                this.subscription = null;
            });
        }
    }

    handleView(event) {
        const id = event.target.dataset.id;
        // Navigate to record
    }

    handleDisposition(event) {
        const id = event.target.dataset.id;
        // Open modal for disposition update
    }
}
```

#### Step 3: Performance Budget

- **Initial load**: <2 seconds (Chrome Lighthouse mobile)
- **Event refresh**: <500 ms (on new Platform Event)
- **Network budget**: <200 KB per view

Use Salesforce **Performance Profiler** to capture baseline metrics. Add automated UI test (Lightning Testing Service) to ensure component renders within budget.

**Estimated Time**: 4 days (responsive redesign, streaming integration, testing)

---

# Implementation Checklists

---

## Checklist 1: Token Concurrency Mutex

- [ ] Create `SalesforceJWTClient` class with `asyncio.Lock()`
- [ ] Implement 1-minute safety buffer (refresh when 2 min remain)
- [ ] Add double-check pattern for lock acquisition
- [ ] Write concurrent test (10 parallel requests = 1 mint)
- [ ] Add Prometheus metrics: `token_mint_attempts`, `cache_hits`, `cache_efficiency`
- [ ] Test under load (100 concurrent requests)
- [ ] Verify cache efficiency >80%
- [ ] Deploy to staging
- [ ] Monitor production for 24 hours

**Success Criteria:**
- Concurrent requests don't trigger redundant token mints
- Cache efficiency ≥80%
- No timeout errors under 100 concurrent requests

---

## Checklist 2: DLQ Alert Automation

- [ ] Create `Dograh_DLQ_Alert__e` Platform Event
- [ ] Deploy `DograhDLQMonitor` Apex class
- [ ] Deploy `Dograh_Integration_Error_Trigger` trigger
- [ ] Create Flow: "Dograh DLQ Alert to Slack"
- [ ] Configure Slack webhook URL in Flow
- [ ] Create email template "Dograh DLQ Alert Email"
- [ ] Create LWC dashboard component for DLQ stats
- [ ] Test: Insert 3+ DLQ records manually, verify Slack alert
- [ ] Verify email received within 2 minutes
- [ ] Update on-call runbook with alert procedures

**Success Criteria:**
- Slack alert within 30 seconds of 3rd error
- Email alert within 2 minutes
- Alert includes error type, count, correlation IDs

---

## Checklist 3: Idempotency Hash

- [ ] Add `Payload_Hash__c` (Text, 32 char) field to `Dograh_Call_Activity__c`
- [ ] Add `Event_Type__c` (Picklist) field
- [ ] Ensure `Workflow_Run_ID__c` is External ID (TEXT, not Number)
- [ ] Update `DograhCallPersistenceJob` with 3-field idempotency logic
- [ ] Add hash calculation to Python backend
- [ ] Write test: Replay same event 3x, expect 1 record
- [ ] Write test: Different hash on retry, expect error
- [ ] Write test: 10-event batch, expect 1 record
- [ ] Deploy to staging
- [ ] Verify with production webhook replay scenario

**Success Criteria:**
- Same event replayed 3x = 1 record (idempotent)
- Hash mismatch detected and logged
- DLQ record created on tampering detection

---

## Checklist 4: Event Monitoring Integration

- [ ] Enable Event Monitoring and Real-Time Event Monitoring
- [ ] Create Transaction Security Policy for OAuth 401 detection
- [ ] Deploy `DograhTransactionSecurityHandler` and support classes
- [ ] Create `Dograh_Event_Monitor__e` Platform Event
- [ ] Build Lightning dashboard (timeline, KPIs, IP heatmap)
- [ ] Schedule nightly Event Log export script & S3 archival
- [ ] Force JWT failure; verify alert + dashboard update

**Success Criteria:**
- OAuth failures publish an event within 60 seconds
- Notification sent to on-call (email/Slack)
- Dashboard reflects accurate 24h totals

---

## Checklist 5: API Fallback Queue

- [ ] Add Prometheus histogram + alert for `dograh_salesforce_api_latency`
- [ ] Implement `call_salesforce_with_fallback` & Redis queue helpers
- [ ] Deploy Redis worker (auto-scaled deployment)
- [ ] Create `Dograh_Fallback__c` object & `DograhFallbackProcessor`
- [ ] Add integration tests for sync + async flows
- [ ] Load test with induced 900 ms latency spike
- [ ] Document operational playbook for queue depth monitoring

**Success Criteria:**
- Requests >700 ms return HTTP 202 with queue ID
- Async jobs process within 2 minutes at p95
- No data loss during fallback activation

---

## Checklist 6: Platform Event Capacity Planning

- [ ] Convert campaign/call events to High-Volume Platform Events
- [ ] Run capacity calculator for expected campaign throughput
- [ ] Configure queue depth exporter & Prometheus alert
- [ ] Update Apex publisher logging with queue depth
- [ ] Validate replay IDs post-conversion
- [ ] Perform sandbox stress test (≥60k events/hour)

**Success Criteria:**
- Publish success rate ≥99.9% at projected load
- Alert triggers when queue depth >80% of limit
- Subscribers replay successfully after failover

---

## Checklist 7: Data Residency Alignment

- [ ] Document region pairing matrix in Backend Guide
- [ ] Update Kubernetes overlays per region (US/EU/APAC)
- [ ] Configure region-aligned storage with encryption & logging
- [ ] Verify KMS keys remain in-region (no replication)
- [ ] Deploy latency probes; integrate with Grafana map
- [ ] Complete compliance checklist (BAA, DPA, audit logs)

**Success Criteria:**
- Latency probes meet regional targets
- Compliance/legal teams sign off on matrix
- Runbook updated with regional deployment steps

---

## Checklist 8: JWT Rotation Automation

- [ ] Store GitHub secrets (SFDX auth, K8s config, Slack webhook)
- [ ] Add `jwt-rotation.yml` workflow to repository
- [ ] Dry-run workflow in staging (cert upload + secret update)
- [ ] Validate 24-hour overlap for old/new certificates
- [ ] Automate reminder (GitHub scheduled workflow or PagerDuty)
- [ ] Update security runbook with rotation procedure

**Success Criteria:**
- Workflow completes without manual edits
- Salesforce Connected App lists new cert
- Dograh pods reload secret (no downtime)

---

## Checklist 9: LWC Caching & Platform Cache

- [ ] Refactor Apex controllers with `@AuraEnabled(cacheable=true)`
- [ ] Update LWCs to use `@wire` + `refreshApex`
- [ ] Enable Platform Cache region `DograhAnalytics`
- [ ] Add cache invalidation trigger on Platform Event
- [ ] Measure API reduction (target ≥40%) via Salesforce limits dashboard
- [ ] Run UI smoke tests ensuring <500 ms refresh post-event

**Success Criteria:**
- API calls reduced ≥40% for dashboard endpoints
- LWC refreshes within 1 second after event
- No stale data after invalidation events

---

## Checklist 10: Mobile UX & Streaming

- [ ] Implement responsive Lightning Card layout & CSS breakpoints
- [ ] Replace polling logic with empApi subscription
- [ ] Add LTS/Lighthouse tests validating <2s load time
- [ ] Pilot with mobile reps; capture usability feedback
- [ ] Update Visual Guide with new mockups + metrics
- [ ] Monitor network logs ensuring zero polling requests

**Success Criteria:**
- Mobile load time <2 seconds; event refresh <500 ms
- Positive user feedback (≥4/5 satisfaction)
- Streaming updates replace polling entirely

---

# Testing & Validation

---

## Load Test: Token Concurrency

```bash
# Using Apache Bench or similar
ab -n 1000 -c 100 http://localhost:8000/webhooks/campaign_progress

# Expected:
# - Token mints: ~10 (vs 1000 requests)
# - Cache hits: ~990
# - Efficiency: ~99%
```

## Smoke Test: DLQ Alerting

```apex
// In Salesforce Developer Console

// Step 1: Create 3 DLQ records
insert new Dograh_Integration_Error__c(
    Error_Type__c = 'OAuth',
    Error_Message__c = 'Token expired',
    Retry_Count__c = 1
);

// Step 2: Wait 30 seconds for alert to publish
System.debug('Check Slack #dograh-alerts channel');
```

## Idempotency Validation

```python
# Python test
import requests
import json

payload = {
    "workflow_run_id": "wf_test_123",
    "event_type": "call_ended",
    "duration": 125,
    "correlation_id": "test_corr_123"
}

# First post
r1 = requests.post("http://localhost:8000/webhooks/call_completed", json=payload)
print(f"First: {r1.status_code}")  # 202

# Replay
r2 = requests.post("http://localhost:8000/webhooks/call_completed", json=payload)
print(f"Replay: {r2.status_code}")  # 202

# Verify: Only 1 record in Salesforce
```

---

# Deployment Strategy

---

## Phase 1: Quick Wins (Week 1)
- Deploy token concurrency mutex (production-safe, backward-compatible)
- Deploy DLQ alerting (operations immediately benefits)
- Deploy idempotency hash (no schema breaking changes)

## Phase 2: Medium Effort (Weeks 2-3)
- Deploy Event Monitoring integration (requires Salesforce config)
- Deploy fallback queue pattern (canary: 10% of traffic)
- Deploy Platform Event scaling analysis

## Phase 3: Strategic (Weeks 4-5)
- Deploy JWT rotation automation
- Deploy LWC caching patterns (A/B test for performance)
- Deploy mobile UX redesign

**Rollback Plan**: Each change is isolated and can be reverted independently

---

## Next Actions

1. **Immediate (Today)**:
   - [ ] Review this document with team
   - [ ] Assign owners for each gap (5-6 tasks)
   - [ ] Create GitHub issues for tracking

2. **This Week**:
   - [ ] Implement Quick Wins (3 tasks)
   - [ ] Deploy to staging
   - [ ] Load test token concurrency

3. **Next Week**:
   - [ ] Implement Medium Effort items (4 tasks)
   - [ ] Full integration testing
   - [ ] Update runbooks & documentation

4. **Following Week**:
   - [ ] Implement Strategic items (3 tasks)
   - [ ] Production deployment planning
   - [ ] Team training on new patterns

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Oct 18, 2025 | Initial version addressing all 10 feedback items |

---

**Questions or Issues?** Contact: dograh-architecture@company.com

