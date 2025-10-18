# Salesforce-Dograh Integration Test Suite
## Automated Validation Framework

**Version:** 1.0  
**Date:** October 18, 2025  
**Purpose:** Comprehensive test coverage for back-end integration across Apex, Python, and end-to-end flows

---

## Table of Contents
1. [Apex Unit Tests](#apex-unit-tests)
2. [FastAPI Integration Tests](#fastapi-integration-tests)
3. [End-to-End Scenarios](#end-to-end-scenarios)
4. [CI/CD Integration](#cicd-integration)

---

## Apex Unit Tests

### DograhWebhookSecurityTest.cls
```apex
@IsTest
private class DograhWebhookSecurityTest {
    private static final String TEST_SECRET = 'test-webhook-secret-12345';
    private static final String TEST_PAYLOAD = '{"event_type":"call_completed"}';

    @IsTest
    static void testHmacValidationSuccess() {
        // Arrange
        Blob secret = Blob.valueOf(TEST_SECRET);
        Blob payload = Blob.valueOf(TEST_PAYLOAD);
        Blob hmac = Crypto.generateMac('HmacSHA256', payload, secret);
        String signature = EncodingUtil.convertToHex(hmac);

        // Mock Custom Metadata
        Dograh_Settings__mdt mockSettings = new Dograh_Settings__mdt(
            DeveloperName = 'default',
            Webhook_Secret__c = TEST_SECRET
        );

        // Act & Assert
        Test.startTest();
        DograhWebhookSecurity.validateHmacSignature(mockSettings, signature, payload);
        Test.stopTest();
        // No exception = success
    }

    @IsTest
    static void testHmacValidationFailure() {
        // Arrange
        String invalidSignature = '0000000000000000000000000000000000000000000000000000000000000000';
        Blob payload = Blob.valueOf(TEST_PAYLOAD);

        Dograh_Settings__mdt mockSettings = new Dograh_Settings__mdt(
            DeveloperName = 'default',
            Webhook_Secret__c = TEST_SECRET
        );

        // Act & Assert
        Test.startTest();
        try {
            DograhWebhookSecurity.validateHmacSignature(mockSettings, invalidSignature, payload);
            System.assert(false, 'Expected DograhSecurityException');
        } catch (DograhSecurityException e) {
            System.assertEquals('HMAC signature verification failed', e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testTimestampValidation() {
        // Arrange
        Long currentTime = System.currentTimeMillis() / 1000;
        Long freshTimestamp = currentTime - 100; // 100 seconds ago
        Long staleTimestamp = currentTime - 400; // 400 seconds ago

        // Act & Assert
        Test.startTest();
        System.assert(DograhWebhookSecurity.isTimestampFresh(String.valueOf(freshTimestamp)));
        System.assert(!DograhWebhookSecurity.isTimestampFresh(String.valueOf(staleTimestamp)));
        Test.stopTest();
    }
}
```

### DograhCallPersistenceJobTest.cls
```apex
@IsTest
private class DograhCallPersistenceJobTest {
    @IsTest
    static void testIdempotentUpsert() {
        // Arrange
        String externalId = 'dograh-run-12345';
        Map<String, Object> payload = new Map<String, Object>{
            'workflow_run_id' => 12345,
            'duration_seconds' => 245,
            'disposition' => 'Qualified'
        };

        DograhCallEvent__e event = new DograhCallEvent__e(
            Correlation_ID__c = 'test-correlation-' + System.currentTimeMillis(),
            Payload__c = JSON.serialize(payload),
            Event_Type__c = 'call_completed',
            Retries__c = 0
        );

        // Act
        Test.startTest();
        System.enqueueJob(new DograhCallPersistenceJob(new List<DograhCallEvent__e>{ event }));
        Test.stopTest();

        // Assert
        List<Dograh_Call_Activity__c> inserted = [
            SELECT External_Run_Id__c, Duration_Seconds__c
            FROM Dograh_Call_Activity__c
            WHERE Correlation_ID__c = :event.Correlation_ID__c
        ];
        System.assertEquals(1, inserted.size());

        // Re-process same event (idempotency check)
        Test.startTest();
        System.enqueueJob(new DograhCallPersistenceJob(new List<DograhCallEvent__e>{ event }));
        Test.stopTest();

        List<Dograh_Call_Activity__c> afterReprocess = [
            SELECT Id
            FROM Dograh_Call_Activity__c
            WHERE Correlation_ID__c = :event.Correlation_ID__c
        ];
        System.assertEquals(1, afterReprocess.size(), 'Duplicate record should not be created');
    }

    @IsTest
    static void testErrorHandling() {
        // Arrange
        DograhCallEvent__e event = new DograhCallEvent__e(
            Correlation_ID__c = 'test-error-' + System.currentTimeMillis(),
            Payload__c = 'invalid json {',
            Event_Type__c = 'call_completed',
            Retries__c = 0
        );

        // Act
        Test.startTest();
        System.enqueueJob(new DograhCallPersistenceJob(new List<DograhCallEvent__e>{ event }));
        Test.stopTest();

        // Assert: Error logged to dead-letter queue
        List<Dograh_Integration_Error__c> errors = [
            SELECT Error_Message__c, Status__c
            FROM Dograh_Integration_Error__c
            WHERE Correlation_ID__c = :event.Correlation_ID__c
        ];
        System.assertEquals(1, errors.size());
        System.assertEquals('PENDING_RETRY', errors[0].Status__c);
    }
}
```

### DograhCircuitBreakerTest.cls
```apex
@IsTest
private class DograhCircuitBreakerTest {
    private static final String TEST_ENDPOINT = 'callout:Dograh_API/workflow/fetch';

    @IsTest
    static void testCircuitBreakerStateMachine() {
        // Arrange & Act
        Test.startTest();

        // Initially closed
        System.assert(!DograhCircuitBreaker.isOpen(TEST_ENDPOINT), 'Circuit should start closed');

        // Record 5 failures (threshold)
        for (Integer i = 0; i < 5; i++) {
            DograhCircuitBreaker.recordFailure(TEST_ENDPOINT);
        }

        // Should be open
        System.assert(DograhCircuitBreaker.isOpen(TEST_ENDPOINT), 'Circuit should be open after threshold');

        // Record success
        DograhCircuitBreaker.recordSuccess(TEST_ENDPOINT);

        // Should be closed
        System.assert(!DograhCircuitBreaker.isOpen(TEST_ENDPOINT), 'Circuit should be closed after success');

        Test.stopTest();
    }
}
```

---

## FastAPI Integration Tests

### test_webhook_receiver.py
```python
import pytest
import json
import hmac
import hashlib
from datetime import datetime
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from api.app import app

client = TestClient(app)

WEBHOOK_SECRET = "test-secret-key-12345"
TEST_CORRELATION_ID = "test-correlation-123"

def generate_hmac_signature(payload: bytes, secret: str) -> str:
    """Generate HMAC-SHA256 signature matching Salesforce validation."""
    h = hmac.new(secret.encode(), payload, hashlib.sha256)
    return h.hexdigest()

class TestWebhookReceiver:
    
    def test_webhook_success_with_valid_hmac(self):
        """Test successful webhook reception with valid HMAC."""
        payload = {
            "event_type": "call_completed",
            "workflow_run_id": 12345,
            "duration_seconds": 245,
            "disposition": "Qualified"
        }
        payload_json = json.dumps(payload)
        payload_bytes = payload_json.encode()
        
        signature = generate_hmac_signature(payload_bytes, WEBHOOK_SECRET)
        timestamp = str(int(datetime.now().timestamp()))
        
        response = client.post(
            "/api/v1/webhook/call-event",
            content=payload_json,
            headers={
                "X-Dograh-Signature": signature,
                "X-Correlation-ID": TEST_CORRELATION_ID,
                "X-Dograh-Timestamp": timestamp,
                "Content-Type": "application/json"
            }
        )
        
        assert response.status_code == 200
        assert response.json()["status"] == "accepted"

    def test_webhook_rejection_invalid_signature(self):
        """Test webhook rejection with invalid HMAC."""
        payload = {"event_type": "call_completed"}
        payload_json = json.dumps(payload)
        
        response = client.post(
            "/api/v1/webhook/call-event",
            content=payload_json,
            headers={
                "X-Dograh-Signature": "0000000000000000000000000000000000000000000000000000000000000000",
                "X-Correlation-ID": TEST_CORRELATION_ID,
                "X-Dograh-Timestamp": str(int(datetime.now().timestamp())),
                "Content-Type": "application/json"
            }
        )
        
        assert response.status_code == 401
        assert "Security validation failed" in response.json()["error"]

    def test_webhook_rejection_stale_timestamp(self):
        """Test webhook rejection with stale timestamp."""
        payload = {"event_type": "call_completed"}
        payload_json = json.dumps(payload)
        
        # Timestamp from 10 minutes ago
        stale_timestamp = str(int(datetime.now().timestamp()) - 600)
        signature = generate_hmac_signature(payload_json.encode(), WEBHOOK_SECRET)
        
        response = client.post(
            "/api/v1/webhook/call-event",
            content=payload_json,
            headers={
                "X-Dograh-Signature": signature,
                "X-Correlation-ID": TEST_CORRELATION_ID,
                "X-Dograh-Timestamp": stale_timestamp,
                "Content-Type": "application/json"
            }
        )
        
        assert response.status_code == 401

    def test_correlation_id_propagation(self):
        """Test correlation ID is logged and returned in response."""
        payload = {"event_type": "call_completed"}
        payload_json = json.dumps(payload)
        signature = generate_hmac_signature(payload_json.encode(), WEBHOOK_SECRET)
        timestamp = str(int(datetime.now().timestamp()))
        
        response = client.post(
            "/api/v1/webhook/call-event",
            content=payload_json,
            headers={
                "X-Dograh-Signature": signature,
                "X-Correlation-ID": TEST_CORRELATION_ID,
                "X-Dograh-Timestamp": timestamp,
                "Content-Type": "application/json"
            }
        )
        
        assert response.status_code == 200
        assert response.headers.get("X-Correlation-ID") == TEST_CORRELATION_ID


class TestCampaignProgressEndpoint:
    
    def test_campaign_progress_with_caching(self):
        """Test campaign progress endpoint returns cached data."""
        campaign_id = 1
        
        with patch('api.db_client.get_campaign') as mock_get:
            mock_campaign = MagicMock()
            mock_campaign.id = campaign_id
            mock_campaign.state = 'running'
            mock_campaign.total_rows = 100
            mock_campaign.processed_rows = 50
            mock_campaign.failed_rows = 5
            mock_get.return_value = mock_campaign
            
            # First call
            response1 = client.get(f"/api/v1/campaign/{campaign_id}/progress")
            assert response1.status_code == 200
            assert response1.json()["progress_percentage"] == 50.0
            
            # Second call (should be cached)
            response2 = client.get(f"/api/v1/campaign/{campaign_id}/progress")
            assert response2.status_code == 200
            
            # Verify backend was called only once (due to caching)
            assert mock_get.call_count == 1


class TestHealthEndpoint:
    
    def test_health_check_returns_ok(self):
        """Test health endpoint responds correctly."""
        response = client.get("/api/v1/health")
        assert response.status_code == 200
        assert response.json()["message"] == "OK"
```

---

## End-to-End Scenarios

### e2e_test_workflow.py
```python
import pytest
import asyncio
import httpx
from datetime import datetime

# These tests assume:
# - Salesforce sandbox running with Dograh integration deployed
# - Dograh API running on localhost:8000
# - Environment variables set: SF_INSTANCE_URL, SF_CLIENT_ID, SF_CLIENT_SECRET, SF_USERNAME, SF_PASSWORD

@pytest.fixture
async def salesforce_client():
    """Authenticate with Salesforce via OAuth."""
    async with httpx.AsyncClient() as client:
        # Get access token
        token_response = await client.post(
            f"{os.getenv('SF_INSTANCE_URL')}/services/oauth2/token",
            data={
                "grant_type": "password",
                "client_id": os.getenv("SF_CLIENT_ID"),
                "client_secret": os.getenv("SF_CLIENT_SECRET"),
                "username": os.getenv("SF_USERNAME"),
                "password": os.getenv("SF_PASSWORD")
            }
        )
        token = token_response.json()["access_token"]
        client.headers["Authorization"] = f"Bearer {token}"
        yield client

@pytest.mark.asyncio
async def test_end_to_end_call_capture_flow(salesforce_client):
    """
    End-to-end scenario:
    1. Create campaign in Salesforce
    2. Dograh API processes campaign
    3. Call completed webhook sent to Salesforce
    4. Dograh_Call_Activity__c record created
    5. Verify correlation ID traced across all systems
    """
    
    correlation_id = f"e2e-test-{datetime.now().timestamp()}"
    
    # Step 1: Create campaign in Salesforce
    campaign_response = await salesforce_client.post(
        f"{os.getenv('SF_INSTANCE_URL')}/services/data/v62.0/sobjects/Dograh_Campaign__c",
        json={
            "Campaign_Name__c": "E2E Test Campaign",
            "Workflow_Id__c": 1,
            "External_Campaign_Id__c": f"external-{correlation_id}",
            "State__c": "Draft",
            "Total_Records__c": 10
        }
    )
    campaign_id = campaign_response.json()["id"]
    print(f"Created campaign: {campaign_id}")
    
    # Step 2: Trigger campaign start (calls Dograh API)
    # Simulated via FastAPI:
    async with httpx.AsyncClient(base_url="http://localhost:8000") as dograh_client:
        start_response = await dograh_client.post(
            f"/api/v1/campaign/{campaign_id}/start",
            json={"correlation_id": correlation_id}
        )
        assert start_response.status_code == 200
    
    # Step 3: Simulate call completion webhook
    # (This would normally be sent by Dograh after ASR/LLM completes)
    import json
    import hmac
    import hashlib
    
    webhook_payload = {
        "event_type": "call_completed",
        "workflow_run_id": 12345,
        "correlation_id": correlation_id,
        "duration_seconds": 245,
        "disposition": "Qualified",
        "transcript": "Test conversation transcript"
    }
    
    payload_json = json.dumps(webhook_payload)
    signature = hmac.new(
        os.getenv("WEBHOOK_SECRET").encode(),
        payload_json.encode(),
        hashlib.sha256
    ).hexdigest()
    
    webhook_response = await salesforce_client.post(
        f"{os.getenv('SF_INSTANCE_URL')}/services/apexrest/dograh-webhook/",
        content=payload_json,
        headers={
            "X-Dograh-Signature": signature,
            "X-Correlation-ID": correlation_id,
            "X-Dograh-Timestamp": str(int(datetime.now().timestamp())),
            "Content-Type": "application/json"
        }
    )
    assert webhook_response.status_code == 200
    
    # Step 4: Wait for async processing and verify record creation
    await asyncio.sleep(5)  # Allow Queueable to execute
    
    # Query Dograh_Call_Activity__c
    query_response = await salesforce_client.get(
        f"{os.getenv('SF_INSTANCE_URL')}/services/data/v62.0/query",
        params={
            "q": f"SELECT Id, Correlation_ID__c, Disposition__c FROM Dograh_Call_Activity__c WHERE Correlation_ID__c = '{correlation_id}'"
        }
    )
    records = query_response.json()["records"]
    
    assert len(records) > 0, "Call Activity record not created"
    call_activity = records[0]
    assert call_activity["Disposition__c"] == "Qualified"
    assert call_activity["Correlation_ID__c"] == correlation_id
    
    print(f"✓ End-to-end flow successful: {call_activity['Id']}")
    print(f"✓ Correlation ID traced: {correlation_id}")
```

---

## CI/CD Integration

### GitHub Actions Workflow
Create `.github/workflows/salesforce-integration-tests.yml`:
```yaml
name: Salesforce Integration Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  apex-tests:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Salesforce CLI
      run: npm install -g @salesforce/cli
    
    - name: Authenticate Salesforce
      run: sf org login web --url ${{ secrets.SF_SANDBOX_URL }} --set-default-dev-hub
      env:
        SFDX_AUTOUPDATE_DISABLE: true
        SFDX_USE_GENERIC_UNIX_KEYCHAIN: true
        SF_CLI_EXEC_TIMEOUT: 300
        FORCE_COLOR: 1
    
    - name: Deploy Metadata
      run: sf project deploy start --target-org ${{ secrets.SF_SANDBOX_ORG }}
    
    - name: Run Apex Tests
      run: |
        sf apex run test \
          --test-class "DograhWebhookSecurityTest,DograhCallPersistenceJobTest,DograhCircuitBreakerTest" \
          --target-org ${{ secrets.SF_SANDBOX_ORG }} \
          --code-coverage \
          --wait 60
    
    - name: Generate Coverage Report
      run: sf apex list log --target-org ${{ secrets.SF_SANDBOX_ORG }} | tee coverage.txt
    
    - name: Upload Coverage
      uses: codecov/codecov-action@v3
      with:
        files: ./coverage.txt

  fastapi-tests:
    runs-on: ubuntu-latest
    services:
      redis:
        image: redis:7-alpine
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'
    
    - name: Install dependencies
      run: pip install -r api/requirements.dev.txt
    
    - name: Run FastAPI tests
      env:
        REDIS_URL: redis://localhost:6379
        DOGRAH_SF_SIGNING_SECRET: ${{ secrets.WEBHOOK_SECRET }}
      run: pytest api/tests/test_webhook_receiver.py -v --cov=api --cov-report=xml
    
    - name: Upload Coverage
      uses: codecov/codecov-action@v3
      with:
        files: ./coverage.xml

  e2e-tests:
    runs-on: ubuntu-latest
    needs: [apex-tests, fastapi-tests]
    if: github.ref == 'refs/heads/main'
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'
    
    - name: Install dependencies
      run: pip install -r api/requirements.dev.txt
    
    - name: Run E2E Tests
      env:
        SF_INSTANCE_URL: ${{ secrets.SF_SANDBOX_URL }}
        SF_CLIENT_ID: ${{ secrets.SF_CLIENT_ID }}
        SF_CLIENT_SECRET: ${{ secrets.SF_CLIENT_SECRET }}
        SF_USERNAME: ${{ secrets.SF_USERNAME }}
        SF_PASSWORD: ${{ secrets.SF_PASSWORD }}
        WEBHOOK_SECRET: ${{ secrets.WEBHOOK_SECRET }}
      run: pytest api/tests/e2e_test_workflow.py -v
    
    - name: Post Results to Slack
      if: always()
      uses: slackapi/slack-github-action@v1.24.0
      with:
        payload: |
          {
            "text": "Salesforce Integration E2E Tests: ${{ job.status }}",
            "blocks": [
              {
                "type": "section",
                "text": {
                  "type": "mrkdwn",
                  "text": "*Salesforce Integration E2E Tests*\nStatus: ${{ job.status }}\nCommit: ${{ github.sha }}\nBranch: ${{ github.ref }}"
                }
              }
            ]
          }
      env:
        SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
        SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

---

## Test Execution Quick Reference

### Run All Tests
```bash
# Apex tests
sfdx force:apex:test:run --testclassname=DograhWebhookSecurityTest,DograhCallPersistenceJobTest --targetusername=<sandbox-alias>

# FastAPI tests
pytest api/tests/test_webhook_receiver.py -v --cov=api

# E2E tests (requires live Salesforce org)
pytest api/tests/e2e_test_workflow.py -v --tb=short
```

### Check Coverage
```bash
# Apex
sfdx force:apex:test:run --resultformat=json --targetusername=<sandbox-alias> | jq '.summary.totalCoverage'

# Python
pytest --cov=api --cov-report=html
open htmlcov/index.html
```

---

**Document Version:** 1.0  
**Last Updated:** October 18, 2025
