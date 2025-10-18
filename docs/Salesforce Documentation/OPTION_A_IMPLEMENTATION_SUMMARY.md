# Option A Implementation: OAuth 2.0 JWT Direct Server-to-Server Integration
**Date:** October 18, 2025  
**Status:** ✅ Documentation Updated

---

## What Changed?

This document summarizes the shift from **Experience Cloud public webhook + HMAC** to **OAuth 2.0 JWT Bearer direct REST endpoint**.

### Option Comparison

| Aspect | Option B (Deprecated) | Option A (Chosen) |
|--------|---------------------|-------------------|
| **Inbound Pattern** | Public Experience Cloud site + Guest User + HMAC webhook | Direct server-to-server OAuth 2.0 JWT via Apex REST |
| **Authentication** | Signature-based (HMAC-SHA256 validation in code) | Token-based (Salesforce OAuth platform, JWT minting) |
| **Exposure** | `https://domain/services/apexrest/dograh-webhook/*` | `https://domain/services/apexrest/dograh/events` |
| **User Context** | Anonymous Guest User | Authenticated Integration User |
| **Licensing** | Experience Cloud license required | Standard Salesforce license |
| **Audit Trail** | Guest activity logged | Integration User activity logged |
| **Permission Model** | Guest profile with minimal perms | Custom Permission Set (CRUD on Dograh* only) |
| **Security Boundary** | Open public endpoint (signature-protected) | Closed OAuth-authenticated endpoint |
| **Dograh-Side Complexity** | HMAC signing service | JWT minting + OAuth token caching |
| **Cert Management** | Shared signing secret in metadata | RSA key pair, public cert in Connected App |

---

## Files Updated

### 1. SALESFORCE_BACKEND_QUICK_START.md (32.5 KB)

**Removed:**
- ❌ Step 1.1: Webhook signing secret generation
- ❌ Step 1.4: Webhook signer module verification
- ❌ Step 4: Configure Named Credentials (for outbound calls—still needed for LWC context fetches)
- ❌ Step 5: Create Experience Cloud Site
- ❌ Step 6.1: HMAC validation unit test
- ❌ Step 6.2: HMAC-based webhook test
- ❌ Step 6.4: Correlation ID tracing (retained, updated for new flow)

**Added:**
- ✅ Step 1.1: Generate RSA key pair for JWT signing (`openssl genrsa + x509`)
- ✅ Step 1.3: JWT token minter module (`api/services/salesforce/jwt_client.py`) with full Python code
- ✅ Step 1.4: JWT client verification
- ✅ Step 3: Create Connected App & JWT Bearer Flow (new section, 45 mins)
  - Create Connected App with certificate-based signing
  - Retrieve Consumer Key
  - Create Integration User (least privilege)
  - Create and assign Permission Set (`Dograh_Integration_User`)
  - Configure JWT in Dograh (env vars + K8s secrets)
- ✅ Step 4: Deploy Apex REST Receiver (was Step 3, updated for new endpoint)
  - `DograhEventsReceiver.cls` (new code, no HMAC validation)
  - `DograhEventLogger.cls` (updated for new flow)
- ✅ Step 5: Deploy Platform Event Processor (was Steps 4-5 combined)
  - `DograhEventProcessor.cls` (Queueable, idempotent upsert)
  - `DograhCallEventTrigger.trigger` (unchanged in logic)
- ✅ Step 6: Test Integration (updated for OAuth flow)
  - 6.1: Apex REST OAuth validation test
  - 6.2: JWT bearer token mint test
  - 6.3: POST event to Apex REST (with bearer token)
  - 6.4: Platform Event consumption
  - 6.5: Idempotency test (same payload twice)
  - 6.6: Correlation ID tracing end-to-end

**Troubleshooting Updates:**
- ❌ Removed HMAC mismatch, Experience Cloud site, guest user issues
- ✅ Added JWT expiry, Connected App cert mismatch, Integration User permission errors
- ✅ Updated health check endpoints to verify Connected App, JWT client, Integration User status

---

### 2. SALESFORCE_BACKEND_INTEGRATION_GUIDE.md (49 KB)

**Architecture Changes:**

- **Section 1.1 Diagram**: Updated to show:
  - ❌ Removed: "Experience Cloud Guest User webhook (signed payloads)"
  - ✅ Added: "Dograh → OAuth 2.0 JWT → Apex REST (/dograh/events) → Platform Event"

- **Section 1.2 Latency Budget**: Updated line item
  - Changed: "Webhook acknowledgement ≤ 100 ms (HMAC validation + Platform Event publication)"
  - To: "Apex REST ≤ 100 ms (OAuth token validation + Platform Event publication)"

**Section 3 (Complete Rewrite)**: "Secure Inbound Integration"
- ❌ Removed: Section 3.1-3.3 (HMAC-based webhook, guest user profile, payload hardening)
- ✅ Added: Section 3.1-3.5 (OAuth 2.0 JWT Bearer flow)
  - 3.1: Why OAuth instead of public webhooks (security boundary, audit trail, permission isolation)
  - 3.2: Certificate-based JWT setup (key generation, Connected App, JWT Bearer flow diagram, Python code)
  - 3.3: Apex REST endpoint code (DograhEventsReceiver with no HMAC, returns 202)
  - 3.4: Integration User & Permission Set creation
  - 3.5: Certificate rotation policy (1-year production, 6-month sandbox)

**Section 4 (Transactional Outbox)**: Updated flow diagram
- Changed from: "Webhook (Guest) → Platform Event → Queueable"
- To: "Apex REST (authenticated) → Platform Event → Queueable"

---

### 3. SALESFORCE_INTEGRATION_TEST_SUITE.md (21 KB) — *To be updated*

**Pending Changes:**
- ❌ Remove HMAC validation unit test patterns
- ✅ Add JWT Bearer token validation tests
- ✅ Add OAuth error handling tests (expired token, invalid cert, etc.)
- ✅ Keep idempotency, Platform Event, E2E tests (logic unchanged)
- ✅ Update CI/CD to validate Connected App certificate isn't expired

---

## New Code Artifacts

### Apex Classes (Salesforce)

#### DograhEventsReceiver.cls (New, ~50 lines)
- Replaces: `DograhWebhookReceiver.cls` + `DograhWebhookSecurity.cls` (HMAC validation removed)
- Authentication: OAuth platform handles token validation; code runs as Integration User
- No HMAC verification needed; JWT validation done by Salesforce platform
- Returns HTTP 202 (async processing)

#### DograhEventLogger.cls (Updated, ~30 lines)
- Removed: HMAC failure logging
- Kept: Success, error, and retry logging (same logging patterns)

#### DograhEventProcessor.cls (Unchanged, ~80 lines)
- Idempotent upsert using External_Run_Id__c external ID
- Insert Task for call activity
- Dead-letter queue on failure

#### Permission Sets (New)
- `Dograh_Integration_User`: CRUD on Dograh* objects, Task, Lead, Contact only

---

### FastAPI / Python (Dograh Backend)

#### api/services/salesforce/jwt_client.py (New, ~100 lines)
- `SalesforceJWTClient` class
- Methods:
  - `_mint_jwt()`: Creates JWT with iss, sub, aud, exp, iat
  - `get_access_token()`: Exchanges JWT for access token; caches for 2 hours
  - `post_event_async()`: POSTs event to Apex REST endpoint with bearer token

#### Integration in API (Small changes)
- Add `SalesforceJWTClient` instance during app initialization
- Inject into campaign event processor
- Call `post_event_async()` instead of webhook signing service

---

### Infrastructure (K8s)

#### Secrets (New)
```bash
kubectl create secret generic salesforce-jwt \
  --from-literal=client_id="<Consumer Key>" \
  --from-file=private_key=dograh_jwt_private.pem \
  --from-literal=org_id="<Org ID>"
```

#### Deployment Changes (Small)
- Mount `/var/run/secrets/salesforce-jwt/` volume
- Add env vars: `SALESFORCE_CLIENT_ID`, `SALESFORCE_JWT_PRIVATE_KEY`, `SALESFORCE_ORG_ID`, `SALESFORCE_DOMAIN`

---

## Implementation Path

### Phase 1: Preparation (1-2 days)
1. Generate RSA key pair (`openssl` commands in Step 1.1)
2. Create Connected App in Salesforce sandbox
3. Retrieve Consumer Key and certificate from app
4. Share public cert with Dograh team
5. Communicate schedule to stakeholders

### Phase 2: Dograh Backend (1-2 days)
1. Implement `api/services/salesforce/jwt_client.py`
2. Add JWT client initialization to `api/app.py`
3. Replace webhook signing service with JWT minting
4. Test JWT minting locally: `python -c "from api.services.salesforce.jwt_client import ..."`
5. Deploy to staging K8s cluster; verify token exchange

### Phase 3: Salesforce Deployment (1-2 days)
1. Create Integration User
2. Create Permission Set and assign to user
3. Deploy Apex REST receiver + logger + processor classes
4. Run Apex unit tests
5. Validate in sandbox

### Phase 4: End-to-End Testing (1 day)
1. Execute Step 6 tests in Quick-Start guide (JWT mint → REST POST → PE consumption)
2. Validate idempotency (POST same payload twice → 1 record)
3. Verify correlation ID tracing
4. Check debug logs and async job queue

### Phase 5: Cutover (0.5 days)
1. Disable old webhook endpoint (if still active)
2. Promote to production (update Connected App for prod domain)
3. Rotate prod certificates into K8s secret
4. Monitor Dograh event queue and Salesforce async job queue

---

## Security Checklist

### Before Sandbox Deployment
- [ ] RSA private key generated with 2048-bit strength
- [ ] Public certificate valid for ≥ 1 year
- [ ] Private key stored securely (not in code repo)
- [ ] Connected App scopes limited to `api` + `refresh_token`
- [ ] Integration User has least-privilege permission set
- [ ] JWT token client code reviewed for clock skew, expiry handling
- [ ] No hardcoded secrets in Apex or Python code

### Before Production Deployment
- [ ] Certificate rotation policy documented
- [ ] Key rotation procedure tested (generate new key, upload cert, update Dograh env)
- [ ] Dograh JWT minter logs token expiry events
- [ ] Salesforce Real-Time Event Monitoring subscribed to Dograh Integration User auth events
- [ ] Dead-letter queue monitoring alerts configured
- [ ] Fallback procedure documented (what if JWT minting fails?)

---

## Backward Compatibility

### If You Need Both Old & New (Transitional Period)

1. **Keep old webhook endpoint running** during transition:
   - Deploy both `DograhEventsReceiver` (new OAuth) and deprecated `DograhWebhookReceiver` (old HMAC)
   - Configure Dograh to POST to both endpoints for N days

2. **Monitor both flows**:
   - Old webhook: Query debug logs for HMAC validation attempts
   - New REST: Query Apex job queue for JWT-authenticated events

3. **Cutover window**:
   - Day 1-3: Both endpoints active (Dograh sends to both)
   - Day 4: Disable old webhook; verify no HMAC events
   - Day 5+: Remove deprecated code from Salesforce repo

---

## Testing Strategy

### Unit Tests
- **Apex:** JWT validation by platform (tested implicitly via OAuth), REST payload parsing, Queueable idempotency
- **Python:** JWT minting edge cases (expiry, missing private key), token caching logic, API error handling

### Integration Tests
- JWT bearer token exchange (mint JWT → POST to Salesforce OAuth → get token)
- Authenticated REST call (use token → POST to /dograh/events → 202 response)
- Platform Event → Queueable → record upsert (idempotency verified)
- Correlation ID propagation across all layers

### E2E Tests
- Campaign flow: Salesforce Launch → Dograh executes → JWT POST event → Call Activity created
- Error flow: Dograh sends invalid JWT → 401 error → logged to dead-letter queue
- Retry flow: Queueable fails on first attempt → Salesforce retries → succeeds

---

## Metrics & Success Criteria

| Metric | Target | Validation |
|--------|--------|-----------|
| JWT token mint latency | < 50 ms (cached 2 hrs) | Monitor Dograh logs for token exchange timing |
| REST endpoint response time | < 100 ms (202 Accepted) | Load test with 1000 concurrent requests |
| Idempotency success rate | 100% | POST same payload 100x → exactly 1 Salesforce record |
| Correlation ID coverage | 100% of events | Audit logs include correlation ID from Dograh → SFDC → activity record |
| Dead-letter queue errors | 0 (post-validation) | Monitor Dograh_Integration_Error__c for failures |

---

## Migration Checklist

```markdown
### Phase 1: Setup
- [ ] RSA key pair generated
- [ ] Connected App created in SFDC sandbox
- [ ] Consumer Key documented
- [ ] Certificate uploaded to app
- [ ] Key rotation policy written

### Phase 2: Dograh Implementation
- [ ] JWT client module implemented
- [ ] Token minting tested locally
- [ ] Dograh event processor updated to call new endpoint
- [ ] Environment variables configured (staging cluster)
- [ ] Staging deployment successful

### Phase 3: Salesforce Build
- [ ] Integration User created
- [ ] Permission Set created and assigned
- [ ] DograhEventsReceiver.cls deployed
- [ ] DograhEventProcessor.cls deployed
- [ ] Trigger active
- [ ] Apex unit tests passing

### Phase 4: Testing
- [ ] JWT bearer flow test (Step 6.2) passing
- [ ] REST POST test (Step 6.3) successful
- [ ] Event consumption test (Step 6.4) verified
- [ ] Idempotency test (Step 6.5) 100% success
- [ ] Correlation ID tracing (Step 6.6) end-to-end

### Phase 5: Production Cutover
- [ ] Prod Connected App created + cert uploaded
- [ ] Prod K8s secret created with new private key
- [ ] Prod deployment validated
- [ ] Dograh switched to prod Salesforce org
- [ ] Monitor Salesforce and Dograh logs for errors
- [ ] Success criteria met (metrics above)
```

---

## Support & Questions

**Q: What if JWT token minting fails?**  
A: Dograh logs error; retries with exponential backoff. Monitor `SALESFORCE_JWT_PRIVATE_KEY` env var and cert expiry date.

**Q: How often do I rotate certificates?**  
A: Every 12 months in production (noted in Salesforce Connected App). Generate new key 30 days before expiry; upload new cert; maintain old cert for 7 days (grace period for cached tokens).

**Q: Can I use the same Connected App for multiple Dograh environments?**  
A: **No.** Create separate Connected Apps per environment (dev, staging, prod) with different Consumer Keys. This ensures audit trail isolation and allows revocation per environment.

**Q: Do I still need a public webhook endpoint?**  
A: **No.** This architecture eliminates the public Experience Cloud site entirely. Apex REST endpoint is private (OAuth-authenticated).

**Q: What about outbound Dograh API calls from Salesforce (e.g., fetch workflow status)?**  
A: Still use Named Credentials + External Credentials (Section 2 of Backend Integration Guide). This option only changes the *inbound* integration pattern.

---

## References

- **Salesforce OAuth 2.0 JWT Bearer Flow:** https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/oauth_jwt_bearer_flow.html
- **Connected App Setup:** https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_auth_connected_app.html
- **Apex REST Essentials:** https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_classes_restful_http.htm
- **Platform Events:** https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/platform_events_intro.htm
- **Queueable Apex:** https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_class_system_queueable.htm

---

**Document Version:** 1.0  
**Last Updated:** October 18, 2025  
**Next Review:** When certificate expires or architecture evolves

---

## Quick Links to Updated Docs

- [SALESFORCE_BACKEND_QUICK_START.md](./SALESFORCE_BACKEND_QUICK_START.md) — Implementation steps (updated)
- [SALESFORCE_BACKEND_INTEGRATION_GUIDE.md](./SALESFORCE_BACKEND_INTEGRATION_GUIDE.md) — Architecture details (Sections 3-4 rewritten)
- [SALESFORCE_INTEGRATION_TEST_SUITE.md](./SALESFORCE_INTEGRATION_TEST_SUITE.md) — Test patterns (to be updated)
- [SALESFORCE_README.md](./SALESFORCE_README.md) — Navigation hub

