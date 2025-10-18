# Salesforce Backend Integration Quick-Start Guide
## Dograh Voice AI Platform

**Version:** 1.0  
**Date:** October 18, 2025  
**Target Audience:** Integration Engineers, DevOps Engineers  
**Estimated Duration:** 4-6 hours for initial setup

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Step 1: Prepare Dograh Backend (30 mins)](#step-1-prepare-dograh-backend)
3. [Step 2: Create Salesforce Metadata (60 mins)](#step-2-create-salesforce-metadata)
4. [Step 3: Create Connected App & JWT Bearer Flow (45 mins)](#step-3-create-connected-app--jwt-bearer-flow)
5. [Step 4: Deploy Apex REST Receiver (45 mins)](#step-4-deploy-apex-rest-receiver)
6. [Step 5: Deploy Platform Event Processor (60 mins)](#step-5-deploy-platform-event-processor)
7. [Step 6: Test Integration (90 mins)](#step-6-test-integration)
8. [Validation & Troubleshooting](#validation--troubleshooting)

---

## Prerequisites

### Dograh Platform
- [ ] Dograh API running locally (`python -m uvicorn api.app:app --host 0.0.0.0 --port 8000`)
- [ ] Redis available for ARQ workers (`redis-cli ping` returns PONG)
- [ ] FastAPI health endpoint accessible: `curl http://localhost:8000/api/v1/health`

### Salesforce
- [ ] Sandbox org with System Administrator profile
- [ ] SFDX CLI installed and authenticated: `sfdx org list`
- [ ] Ability to create Custom Objects, Apex classes, Connected Apps, and Permission Sets
- [ ] File-based or certificate-based keystore for JWT signing (see Step 3)

### Local Environment
- [ ] OpenSSL or equivalent for secret generation: `openssl rand -base64 32`
- [ ] jq for JSON parsing (optional but recommended)
- [ ] Postman or cURL for API testing

---

## Step 1: Prepare Dograh Backend (30 mins)

### 1.1 Generate JWT Signing Certificates
```bash
# Generate private key (keep secret on Dograh side)
openssl genrsa -out dograh_jwt_private.pem 2048

# Generate public certificate (upload to Salesforce Connected App)
openssl req -new -x509 -key dograh_jwt_private.pem -out dograh_jwt_cert.pem -days 365

# Keep private key secure (add to Kubernetes secret or .env)
export SALESFORCE_JWT_PRIVATE_KEY=$(cat dograh_jwt_private.pem | base64 -w 0)
echo "Store this securely: $SALESFORCE_JWT_PRIVATE_KEY"
```

### 1.2 Ensure Correlation ID Support
Verify that `api/app.py` includes the CorrelationIDMiddleware:

```bash
grep -n "CorrelationIDMiddleware" api/app.py
# If not present, add it to the middleware stack before running
```

### 1.3 Add JWT Token Minter to Dograh Backend
Create file `api/services/salesforce/jwt_client.py`:
```python
import jwt
import json
import time
from datetime import datetime, timedelta
from httpx import AsyncClient, Client
import logging

logger = logging.getLogger(__name__)

class SalesforceJWTClient:
    def __init__(self, private_key: str, client_id: str, org_id: str, salesforce_domain: str = "https://test.salesforce.com"):
        self.private_key = private_key
        self.client_id = client_id
        self.org_id = org_id
        self.salesforce_domain = salesforce_domain
        self.access_token = None
        self.token_expiry = None
        self.sync_client = Client()
    
    def _mint_jwt(self) -> str:
        """Mint a JWT for Salesforce OAuth2 JWT Bearer flow."""
        now = int(time.time())
        payload = {
            "iss": self.client_id,
            "sub": self.org_id,
            "aud": self.salesforce_domain,
            "exp": now + 300,  # 5 min validity
            "iat": now,
        }
        token = jwt.encode(payload, self.private_key, algorithm="RS256")
        logger.debug(f"Minted JWT token, exp={datetime.fromtimestamp(payload['exp'])}")
        return token
    
    def get_access_token(self) -> str:
        """Get or refresh Salesforce access token."""
        if self.access_token and self.token_expiry and datetime.utcnow() < self.token_expiry:
            return self.access_token
        
        jwt_token = self._mint_jwt()
        token_url = f"{self.salesforce_domain}/services/oauth2/token"
        
        response = self.sync_client.post(
            token_url,
            data={
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": jwt_token,
            },
        )
        
        if response.status_code != 200:
            logger.error(f"Token mint failed: {response.text}")
            raise Exception(f"Failed to mint Salesforce token: {response.text}")
        
        data = response.json()
        self.access_token = data["access_token"]
        # Cache for 4 minutes (5-minute JWT - 1 min buffer)
        self.token_expiry = datetime.utcnow() + timedelta(minutes=4)
        logger.info("Refreshed Salesforce access token")
        return self.access_token
    
    async def post_event_async(self, instance_url: str, org_id: str, payload: dict, correlation_id: str) -> int:
        """POST event to Salesforce Apex REST endpoint (async)."""
        token = self.get_access_token()
        endpoint = f"{instance_url}/services/apexrest/dograh/events"
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "X-Correlation-ID": correlation_id,
        }
        
        async with AsyncClient() as client:
            response = await client.post(endpoint, json=payload, headers=headers)
        
        if response.status_code not in (200, 202):
            logger.error(f"Event POST failed: {response.status_code} {response.text}")
            raise Exception(f"Salesforce event POST failed: {response.text}")
        
        logger.info(f"Event posted to Salesforce, status={response.status_code}, correlation_id={correlation_id}")
        return response.status_code
```

### 1.4 Test API Health & JWT Client
```bash
# Health check
curl -s http://localhost:8000/api/v1/health | jq .

# Test JWT minter (if exposed as endpoint, otherwise skip)
python -c "
from api.services.salesforce.jwt_client import SalesforceJWTClient
import os

key = os.getenv('SALESFORCE_JWT_PRIVATE_KEY')
client = SalesforceJWTClient(key, 'test-client-id', 'org-id')
token = client._mint_jwt()
print(f'JWT minted: {token[:50]}...')
"
```

---

## Step 2: Create Salesforce Metadata (60 mins)

### 2.1 Login to Sandbox
```bash
# Open browser to sandbox org
sfdx org open --targetusername=<sandbox-alias>
```

### 2.2 Create Custom Metadata Type: Dograh_Settings__mdt
1. Setup → Custom Metadata Types
2. Click **New Custom Metadata Type**
   - Label: `Dograh Settings`
   - Plural Label: `Dograh Settings`
   - Object Name: `Dograh_Settings` (auto-filled)
3. Click **Save**
4. Under Fields:
   - Click **New**
     - Field Label: `Webhook Secret`
     - Field Name: `Webhook_Secret`
     - Data Type: `Text Area (Long)`
     - **CHECK** "Protected"
   - Click **New**
     - Field Label: `API URL`
     - Field Name: `API_URL`
     - Data Type: `Text`
   - Click **New**
     - Field Label: `Org ID`
     - Field Name: `Org_ID`
     - Data Type: `Text`
5. Click **Save**

### 2.3 Create Custom Metadata Type: Dograh_Field_Map__mdt
1. Setup → Custom Metadata Types → **New Custom Metadata Type**
2. Label: `Dograh Field Map`
3. Plural Label: `Dograh Field Maps`
4. Object Name: `Dograh_Field_Map`
5. Fields:
   - `Json_Key__c` (Text) — incoming JSON field name
   - `Salesforce_Field__c` (Text) — target SObject field API name
   - `Data_Type__c` (Picklist) — Integer, String, Boolean, Datetime
   - `Event_Type__c` (Text) — e.g., "call_completed", "campaign_update"
   - `Transform_Class__c` (Text, Optional) — Apex class for custom transforms
6. Click **Save**

### 2.4 Create Platform Event: DograhCallEvent__e
1. Setup → Platform Events
2. Click **New Platform Event**
   - Label: `Dograh Call Event`
   - Plural Label: `Dograh Call Events`
   - API Name: `Dograh_Call_Event__e` (auto-filled)
3. Click **Save**
4. Add Custom Fields:
   - Click **New**
     - Field Label: `Correlation ID`
     - API Name: `Correlation_ID__c`
     - Data Type: `Text`
   - Click **New**
     - Field Label: `Payload`
     - API Name: `Payload__c`
     - Data Type: `Text Area (Long)`
   - Click **New**
     - Field Label: `Event Type`
     - API Name: `Event_Type__c`
     - Data Type: `Text`
   - Click **New**
     - Field Label: `Retries`
     - API Name: `Retries__c`
     - Data Type: `Number` (precision 3, scale 0)
5. Click **Save**

### 2.5 Create Custom Objects
#### 2.5.1 Dograh_Call_Activity__c
1. Setup → Object Manager → **Create**
2. Custom Object
   - Label: `Dograh Call Activity`
   - Plural Label: `Dograh Call Activities`
   - Object Name: `Dograh_Call_Activity`
3. Click **Save**
4. Add Fields:
   - **External_Run_Id__c** (Text)
     - **CHECK** "External ID"
     - **CHECK** "Unique"
     - Length: 255
   - **Correlation_ID__c** (Text) — 36 char UUID
   - **Workflow_Id__c** (Number) — references Dograh workflow
   - **Duration_Seconds__c** (Number) — call duration
   - **Disposition__c** (Picklist) — "Qualified", "Not Interested", "Callback", "No Answer", "Error"
   - **Transcript__c** (Text Area (Rich))
   - **Sentiment_Score__c** (Number) — -1.0 to 1.0
   - **Created_At__c** (DateTime)

#### 2.5.2 Dograh_Campaign__c
1. Setup → Object Manager → **Create**
2. Custom Object
   - Label: `Dograh Campaign`
   - Plural Label: `Dograh Campaigns`
   - Object Name: `Dograh_Campaign`
3. Fields:
   - **External_Campaign_Id__c** (Text, External ID, Unique)
   - **Campaign_Name__c** (Text)
   - **Workflow_Id__c** (Number)
   - **State__c** (Picklist) — "Draft", "Running", "Paused", "Completed"
   - **Total_Records__c** (Number)
   - **Processed_Records__c** (Number)
   - **Failed_Records__c** (Number)

#### 2.5.3 Dograh_Integration_Error__c (Dead-Letter Queue)
1. Custom Object:
   - Label: `Dograh Integration Error`
   - Plural Label: `Dograh Integration Errors`
   - Object Name: `Dograh_Integration_Error`
2. Fields:
   - **Correlation_ID__c** (Text)
   - **Event_Type__c** (Text)
   - **Payload__c** (Text Area (Long))
   - **Error_Message__c** (Text) — 255 char
   - **Status__c** (Picklist) — "Pending Retry", "Manual Review", "Resolved"
   - **Retry_Count__c** (Number)

### 2.6 Seed Custom Metadata Records
1. Setup → Custom Metadata Types → **Dograh Settings** → Manage Records
2. Click **New**
   - Label: `default`
   - API URL: `http://localhost:8000/api/v1` (or production URL)
   - Org ID: *Your Dograh org ID*
3. Click **Save**

---

## Step 3: Create Connected App & JWT Bearer Flow (45 mins)

### 3.1 Create Connected App for OAuth
1. Setup → Apps → App Manager
2. Click **New Connected App**
   - Connected App Name: `Dograh Voice AI`
   - API Name: `Dograh_Voice_AI` (auto)
   - Contact Email: *Your email*
   - **CHECK** "Enable OAuth Settings"
3. Under OAuth Settings:
   - Callback URL: `https://dograh-domain/oauth/callback` (placeholder for now)
   - **CHECK** "Use Digital Signatures"
   - Click **Choose File** → Upload `dograh_jwt_cert.pem` (generated in Step 1.1)
   - Selected OAuth Scopes: Move to right:
     - `api` (Access and manage your data)
     - `refresh_token` (Obtain refresh tokens)
   - Click **Save**

### 3.2 Retrieve Connected App Credentials
1. In App Manager, find **Dograh Voice AI**
2. Click **View**
3. Under **API (Enable OAuth Settings)** section:
   - Copy **Consumer Key** (this is `client_id`)
   - Note: Consumer Secret will be disabled (using cert-based auth instead)

### 3.3 Create Integration User (Least Privilege)
1. Setup → Users
2. Click **New User**
   - First Name: `Dograh`
   - Last Name: `Integration`
   - Email: `dograh-integration@company.invalid`
   - Username: `dograh-integration@company.invalid`
   - Profile: *Select or create least-privilege profile*
   - License Type: `Salesforce`
3. Click **Save**

### 3.4 Create Permission Set for Integration User
1. Setup → Permission Sets
2. Click **New**
   - Label: `Dograh_Integration_User`
   - API Name: `Dograh_Integration_User` (auto)
3. Click **Save**
4. Under **System Permissions**, grant:
   - ✅ API Enabled
   - ✅ Create Records (Dograh_Call_Activity__c, Dograh_Campaign__c, Task)
   - ✅ Edit Records (same)
   - ✅ Read Events (Platform Events)
5. Under **Custom Object Permissions**, grant CRUD on:
   - `Dograh_Call_Activity__c`
   - `Dograh_Campaign__c`
   - `Dograh_Integration_Error__c`
   - `Lead` (if updating Lead records), `Contact`, `Task`
6. Click **Save**

### 3.5 Assign Permission Set to Integration User
1. Setup → Permission Sets → **Dograth_Integration_User**
2. Click **Manage Assignments**
3. Click **Add Assignments**
4. Select **Dograh Integration** user
5. Click **Assign** → **Done**

### 3.6 Configure JWT Bearer Authentication in Dograh
Add to Dograh deployment (Kubernetes secret or .env):

```bash
# Export Connected App details to Dograh environment
export SALESFORCE_CLIENT_ID="<Consumer Key from Step 3.2>"
export SALESFORCE_JWT_PRIVATE_KEY="$(cat dograh_jwt_private.pem | base64 -w 0)"
export SALESFORCE_ORG_ID="<Salesforce Org ID>"
export SALESFORCE_DOMAIN="https://test.salesforce.com"  # Or production URL
export SALESFORCE_INSTANCE_URL="https://<instance>.salesforce.com"  # For REST POST

# Verify env vars are set
echo "SALESFORCE_CLIENT_ID=$SALESFORCE_CLIENT_ID"
```

**If using Kubernetes:**
```bash
kubectl create secret generic salesforce-jwt \
  --from-literal=client_id="$SALESFORCE_CLIENT_ID" \
  --from-file=private_key=dograh_jwt_private.pem \
  --from-literal=org_id="$SALESFORCE_ORG_ID" \
  -n dograh

kubectl set env deployment/dograh-api \
  SALESFORCE_CLIENT_ID="$SALESFORCE_CLIENT_ID" \
  SALESFORCE_JWT_PRIVATE_KEY="$(cat dograh_jwt_private.pem)" \
  SALESFORCE_ORG_ID="$SALESFORCE_ORG_ID" \
  -n dograh
```

## Step 4: Deploy Apex REST Receiver (45 mins)

### 4.1 Create Apex REST Endpoint
Create file `force-app/main/default/classes/DograhEventsReceiver.cls`:

```apex
@RestResource(urlMapping='/dograh/events')
global with sharing class DograhEventsReceiver {
    
    @HttpPost
    global static void handleEvent() {
        String correlationId = RestContext.request.headers.get('X-Correlation-ID') ?? 'unknown';
        
        try {
            RestRequest req = RestContext.request;
            String body = req.requestBody.toString();
            
            // 1) Validate payload
            EventPayload payload = (EventPayload) JSON.deserialize(body, EventPayload.class);
            if (String.isBlank(payload.correlationId) || String.isBlank(payload.recordId)) {
                throw new AuraHandledException('Missing correlationId or recordId');
            }
            
            correlationId = payload.correlationId;
            
            // 2) Publish Platform Event
            Dograh_Call_Event__e evt = new Dograh_Call_Event__e(
                Correlation_ID__c = payload.correlationId,
                Payload__c = body,
                Event_Type__c = payload.eventType ?? 'call_update',
                Retries__c = 0
            );
            Database.SaveResult sr = EventBus.publish(evt);
            
            DograhEventLogger.logSuccess(correlationId, 'Platform Event published', sr.getId());
            
            // 3) Return 202 Accepted (async processing)
            RestContext.response.statusCode = 202;
            RestContext.response.responseBody = Blob.valueOf(
                JSON.serialize(new Map<String, Object>{'status' => 'accepted', 'correlationId' => correlationId})
            );
        } catch (Exception e) {
            DograhEventLogger.logError(correlationId, 'Event handler failed', e.getMessage());
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
        public Map<String, Object> metadata;
    }
}
```

### 4.2 Create Event Logger Class
Create file `force-app/main/default/classes/DograhEventLogger.cls`:

```apex
public class DograhEventLogger {
    public static void logSuccess(String correlationId, String action, String details) {
        System.debug('DograhEvent|SUCCESS|' + correlationId + '|' + action + '|' + details);
    }
    
    public static void logError(String correlationId, String action, String errorMsg) {
        System.debug('DograhEvent|ERROR|' + correlationId + '|' + action + '|' + errorMsg);
    }
    
    public static void logRetry(String correlationId, Integer retryCount, String reason) {
        System.debug('DograhEvent|RETRY|' + correlationId + '|Count=' + retryCount + '|' + reason);
    }
}
```

### 4.3 Deploy Apex Classes
```bash
sfdx force:source:push --targetusername=<sandbox-alias>
sfdx force:apex:test:run --testclassname=DograhEventsReceiverTest --targetusername=<sandbox-alias>
```

### 4.4 Verify Apex REST Endpoint
The endpoint is automatically available at:
```
POST https://<sandbox-instance>.salesforce.com/services/apexrest/dograh/events
```

Test with OAuth token (from Step 3):
```bash
# Get access token via JWT Bearer flow
TOKEN=$(curl -s -X POST "https://test.salesforce.com/services/oauth2/token" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
  -d "assertion=<JWT from Dograh>" | jq -r '.access_token')

# Test endpoint
curl -X POST "https://<instance>.salesforce.com/services/apexrest/dograh/events" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-ID: test-$(date +%s)" \
  -d '{"correlationId":"test-123","recordId":"0011700000IZ3eAAG","eventType":"call_completed","status":"success"}'
```

---

## Step 5: Deploy Platform Event Processor (60 mins)

### 5.1 Create Queueable Event Processor
Create file `force-app/main/default/classes/DograhEventProcessor.cls`:

```apex
public class DograhEventProcessor implements Queueable {
    private Dograh_Call_Event__e evt;
    private Integer retryCount;
    
    public DograhEventProcessor(Dograh_Call_Event__e event) {
        this.evt = event;
        this.retryCount = (Integer) event.Retries__c ?? 0;
    }
    
    public void execute(QueueableContext qc) {
        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(evt.Payload__c);
            
            String recordId = (String) payload.get('recordId');
            String correlationId = evt.Correlation_ID__c;
            String status = (String) payload.get('status');
            String message = (String) payload.get('message');
            
            // Idempotent upsert: use correlationId as external ID
            Task activity = new Task(
                Subject = 'Dograh Call - ' + status,
                Description = message,
                WhatId = recordId,
                Status = 'Completed',
                Priority = 'Normal'
            );
            
            // Upsert with External ID (if External_Run_Id__c is external ID field on custom object)
            Dograh_Call_Activity__c callRecord = new Dograh_Call_Activity__c(
                External_Run_Id__c = correlationId,  // Unique + External ID
                Correlation_ID__c = correlationId,
                Status__c = status
            );
            
            upsert callRecord External_Run_Id__c;
            insert activity;
            
            DograhEventLogger.logSuccess(correlationId, 'Event processed and record upserted', callRecord.Id);
            
        } catch (Exception e) {
            DograhEventLogger.logError(evt.Correlation_ID__c, 'Event processing failed', e.getMessage());
            
            // Persist failed event to DLQ for manual review
            Dograh_Integration_Error__c dlq = new Dograh_Integration_Error__c(
                Correlation_ID__c = evt.Correlation_ID__c,
                Event_Type__c = evt.Event_Type__c,
                Payload__c = evt.Payload__c,
                Error_Message__c = e.getMessage(),
                Status__c = 'Manual Review',
                Retry_Count__c = retryCount
            );
            insert dlq;
            
            throw e;  // Re-throw to fail job and allow Salesforce retry
        }
    }
}
```

### 5.2 Create Platform Event Trigger
Create file `force-app/main/default/triggers/DograhCallEventTrigger.trigger`:

```apex
trigger DograhCallEventTrigger on Dograh_Call_Event__e (after insert) {
    List<Dograh_Call_Event__e> events = Trigger.new;
    
    for (Dograh_Call_Event__e evt : events) {
        // Enqueue processor for async handling
        System.enqueueJob(new DograhEventProcessor(evt));
    }
}
```

### 5.3 Deploy Event Processor & Trigger
```bash
sfdx force:source:push --targetusername=<sandbox-alias>

# Verify trigger is active
sfdx force:source:deploy --manifest deploy/package.xml --targetusername=<sandbox-alias>
```

### 5.4 Test Event Processing
```bash
# Generate test event via Apex
sfdx force:apex:execute --targetusername=<sandbox-alias>

# Paste:
# Dograh_Call_Event__e evt = new Dograh_Call_Event__e(
#   Correlation_ID__c = 'test-' + System.now().getTime(),
#   Payload__c = '{"recordId":"0011700000IZ3eAAG","status":"success"}',
#   Event_Type__c = 'call_completed',
#   Retries__c = 0
# );
# EventBus.publish(evt);

# Check Apex job queue
sfdx force:data:record:list --sobject=AsyncApexJob --where="Status='Queued'" --targetusername=<sandbox-alias>

# Verify Call Activity was created
sfdx force:data:record:list --sobject=Dograh_Call_Activity__c --targetusername=<sandbox-alias>
```

---

## Step 6: Test Integration (90 mins)

### 6.1 Unit Test: Apex REST OAuth Validation
```bash
# Create test class DograhEventsReceiverTest
cat > force-app/main/default/classes/DograhEventsReceiverTest.cls << 'EOF'
@IsTest
private class DograhEventsReceiverTest {
    
    @IsTest
    static void testValidEventPosted() {
        Test.startTest();
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/dograh/events';
        req.httpMethod = 'POST';
        req.headers.put('X-Correlation-ID', 'test-123');
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'correlationId' => 'test-123',
            'recordId' => '0011700000IZ3eAAG',
            'eventType' => 'call_completed',
            'status' => 'success',
            'message' => 'Call completed successfully'
        }));
        
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        DograhEventsReceiver.handleEvent();
        
        System.assertEquals(202, RestContext.response.statusCode);
        Test.stopTest();
    }
    
    @IsTest
    static void testMissingCorrelationId() {
        Test.startTest();
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/dograh/events';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'recordId' => '0011700000IZ3eAAG'
        }));
        
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        DograhEventsReceiver.handleEvent();
        
        System.assertEquals(400, RestContext.response.statusCode);
        Test.stopTest();
    }
}
EOF

sfdx force:apex:test:run --testclassname=DograhEventsReceiverTest --targetusername=<sandbox-alias>
```

### 6.2 Integration Test: JWT Bearer Token Mint
```bash
# Generate JWT and get access token
python3 << 'EOF'
import jwt
import requests
import json
import os
import time
from datetime import datetime, timedelta

PRIVATE_KEY = os.getenv('SALESFORCE_JWT_PRIVATE_KEY')
CLIENT_ID = os.getenv('SALESFORCE_CLIENT_ID')
ORG_ID = os.getenv('SALESFORCE_ORG_ID')
SALESFORCE_DOMAIN = "https://test.salesforce.com"

# Mint JWT
now = int(time.time())
payload = {
    "iss": CLIENT_ID,
    "sub": ORG_ID,
    "aud": SALESFORCE_DOMAIN,
    "exp": now + 300,
    "iat": now,
}

jwt_token = jwt.encode(payload, PRIVATE_KEY, algorithm="RS256")
print(f"JWT Token (first 50 chars): {jwt_token[:50]}...")

# Exchange for access token
token_response = requests.post(
    f"{SALESFORCE_DOMAIN}/services/oauth2/token",
    data={
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": jwt_token,
    }
)

if token_response.status_code == 200:
    data = token_response.json()
    access_token = data['access_token']
    print(f"Access Token Mint: SUCCESS")
    print(f"Token (first 50 chars): {access_token[:50]}...")
    print(f"Token Expiry: {data.get('expires_in')} seconds")
    
    # Store for next test
    with open('/tmp/sf_access_token.txt', 'w') as f:
        f.write(access_token)
else:
    print(f"Token Mint Failed: {token_response.status_code}")
    print(token_response.text)
EOF
```

### 6.3 Integration Test: POST Event to Apex REST
```bash
# POST event using access token from 6.2
ACCESS_TOKEN=$(cat /tmp/sf_access_token.txt)
SALESFORCE_INSTANCE="https://<instance>.salesforce.com"

curl -X POST "${SALESFORCE_INSTANCE}/services/apexrest/dograh/events" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-ID: integration-test-$(date +%s)" \
  -d '{
    "correlationId": "integration-test-'"$(date +%s)"'",
    "recordId": "0011700000IZ3eAAG",
    "eventType": "call_completed",
    "status": "success",
    "message": "Integration test event"
  }' \
  -v

# Expected: HTTP 202 Accepted with {"status":"accepted","correlationId":"..."}
```

### 6.4 Integration Test: Platform Event Consumption
```bash
# Wait a few seconds for async processor to run
sleep 3

# Query Platform Event publication history
sfdx force:data:record:list --sobject=EventBusSubscriber --targetusername=<sandbox-alias>

# Query Call Activity created by Queueable
sfdx force:data:record:list --sobject=Dograh_Call_Activity__c \
  --where="Correlation_ID__c like 'integration-test%'" \
  --targetusername=<sandbox-alias>

# Verify record exists and has correct values
sfdx force:data:record:get --sobject=Dograh_Call_Activity__c --recordid=<record-id> --targetusername=<sandbox-alias>
```

### 6.5 Idempotency Test (Same Payload Twice)
```bash
# POST same event twice with identical correlationId
CORR_ID="idempotency-test-$(date +%s)"
ACCESS_TOKEN=$(cat /tmp/sf_access_token.txt)

for i in 1 2; do
  curl -X POST "${SALESFORCE_INSTANCE}/services/apexrest/dograh/events" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "X-Correlation-ID: $CORR_ID" \
    -d "{\"correlationId\": \"$CORR_ID\", \"recordId\": \"0011700000IZ3eAAG\", \"status\": \"success\"}" \
    --silent -w "POST $i: HTTP %{http_code}\n"
done

sleep 3

# Query Call Activity - should have only ONE record (idempotent upsert)
sfdx force:data:record:list --sobject=Dograh_Call_Activity__c \
  --where="Correlation_ID__c='$CORR_ID'" \
  --targetusername=<sandbox-alias>

# Expected: Exactly 1 record (2nd POST upserted, not inserted)
```

### 6.6 Correlation ID Tracing End-to-End
```bash
# 1. POST event with correlation ID
CORR_ID="trace-test-$(date +%s)"
curl -X POST "${SALESFORCE_INSTANCE}/services/apexrest/dograh/events" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-ID: $CORR_ID" \
  -d "{\"correlationId\": \"$CORR_ID\", \"recordId\": \"0011700000IZ3eAAG\"}"

# 2. Query Salesforce debug logs
sfdx force:apex:log:tail --targetusername=<sandbox-alias> | grep "$CORR_ID"
# Expected: "DograhEvent|SUCCESS|$CORR_ID|..."

# 3. Query Call Activity
sfdx force:data:record:get --sobject=Dograh_Call_Activity__c \
  --where="Correlation_ID__c='$CORR_ID'" \
  --targetusername=<sandbox-alias> | jq '.Correlation_ID__c'
# Expected: "$CORR_ID"

# 4. Check Dograh logs if running locally
docker logs dograh-api | grep "$CORR_ID"
# Correlation ID should appear if Dograh is configured to push events

echo "Correlation ID $CORR_ID traced end-to-end ✓"
```

---

## Validation & Troubleshooting

### Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| HTTP 401 on event POST | Invalid/expired JWT token | Regenerate JWT or check token expiry |
| HTTP 403 | Integration User lacks API permission | Verify Permission Set assigned to user |
| HTTP 400 | Missing correlationId in payload | Ensure payload includes all required fields |
| Platform Event not consumed | Trigger not active or subscription issue | Check DograhCallEventTrigger active status via Setup |
| Call Activity record missing | Queueable job failed | Check Apex job queue: Setup → Apex Jobs → Queueable |
| JWT Token Mint fails | SFDC cert mismatch or expired | Regenerate cert; upload new cert to Connected App |
| SOQL query fails in Queueable | Insufficient field permissions | Add fields to Integration User permission set |
| Dead-letter queue fills up | Event processing consistently fails | Review error messages in Dograh_Integration_Error__c; check payload schema |

### Logs to Check
```bash
# Salesforce debug logs with correlation ID
sfdx force:apex:log:tail --targetusername=<sandbox-alias> | grep "DograhEvent"

# Salesforce async job queue
sfdx force:data:record:list --sobject=AsyncApexJob --where="Status='Queued' OR Status='Processing'" --targetusername=<sandbox-alias>

# Dograh API logs (if running locally)
docker logs dograh-api | tail -100

# Dograh Kubernetes pod logs (if deployed)
kubectl logs -n dograh -l app=dograh-api --tail=100

# JWT token validation logs
grep "JWT\|Bearer\|oauth2" dograh-api.log
```

### Health Check Endpoints
```bash
# Salesforce: Connected App status
sfdx force:data:record:list --sobject=ConnectedApplication --where="Name='Dograh Voice AI'" --targetusername=<sandbox-alias>

# Salesforce: Integration User status
sfdx force:data:record:list --sobject=User --where="Username='dograh-integration@company.invalid'" --targetusername=<sandbox-alias>

# Dograh: API health
curl http://localhost:8000/api/v1/health

# Dograh: JWT signer module health
curl -s http://localhost:8000/api/v1/health/jwt

# Salesforce: Queueable job backlog
sfdx force:data:record:list --sobject=AsyncApexJob --where="JobType='Queueable' AND Status='Queued'" --limit=10 --targetusername=<sandbox-alias>
```

### Security Pre-Flight Checklist
- [ ] Connected App has only required OAuth scopes (`api`, `refresh_token`)
- [ ] Integration User has least-privilege permission set (only CRUD on Dograh objects + Task + Lead + Contact)
- [ ] JWT private key stored securely (Kubernetes secret, not in code)
- [ ] Public cert in Connected App matches private key used by Dograh
- [ ] No hardcoded passwords or tokens in Apex code
- [ ] All logs filter sensitive data (no JWT tokens in debug logs)
- [ ] Dead-letter queue monitored regularly for failed events
- [ ] Quarterly cert rotation plan documented

---

## Next Steps

1. **Share findings** with team; capture any deviations from guide in lessons learned doc.
2. **Automate deployment** using SFDX pipelines; codify metadata/code as source of truth.
3. **Scale to production**: Follow security review checklist (Section 8 of Architecture Guide).
4. **Enhance observability**: Set up Datadog/Splunk forwarding for Salesforce/Dograh logs with correlation IDs.

---

**Document Version:** 1.0  
**Last Updated:** October 18, 2025  
**Support:** Refer to main Architecture Guide (SALESFORCE_BACKEND_INTEGRATION_GUIDE.md) for deeper context.
