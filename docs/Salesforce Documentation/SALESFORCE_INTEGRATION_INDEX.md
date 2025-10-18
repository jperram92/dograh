# Dograh Voice AI Platform × Salesforce Integration Documentation Index
## Complete Reference for Front-End & Back-End Implementation

**Date:** October 18, 2025  
**Audience:** Product Managers, Solution Architects, Integration Engineers, DevOps Teams  
**Status:** Production Ready

---

## 📚 Documentation Overview

This documentation suite provides a complete blueprint for integrating the Dograh Voice AI Platform with Salesforce Lightning Experience. It covers both the user-facing Lightning Web Components (LWCs) and the hardened backend integration architecture required to deliver sub-500ms latency voice conversations at enterprise scale.

### Quick Navigation
| Document | Purpose | Audience | Read Time |
|-----------|---------|----------|-----------|
| **SALESFORCE_FRONTEND_SETUP_GUIDE.md** | LWC placement, configuration, and user workflows | Salesforce Admins, LWC Developers | 45 min |
| **SALESFORCE_FRONTEND_VISUAL_GUIDE.md** | Mockups and visual layouts for all components | Product Managers, UX Designers | 20 min |
| **SALESFORCE_LWC_DESIGN.md** | Technical API contracts and component architecture | Solution Architects | 60 min |
| **SALESFORCE_BACKEND_INTEGRATION_GUIDE.md** | Security, data flows, and operational architecture | Integration Architects, Security Teams | 90 min |
| **SALESFORCE_BACKEND_QUICK_START.md** | Step-by-step sandbox implementation (4-6 hours) | Integration Engineers | 180 min |
| **SALESFORCE_INTEGRATION_TEST_SUITE.md** | Unit, integration, and E2E test patterns | QA Engineers, DevOps | 60 min |
| **(This Document)** | Index and reading roadmap | Everyone | 10 min |

---

## 🎯 Reading Paths by Role

### For Product Managers / Business Stakeholders
1. **Start:** SALESFORCE_FRONTEND_VISUAL_GUIDE.md (understand user experience)
2. **Then:** SALESFORCE_FRONTEND_SETUP_GUIDE.md (learn feature capabilities)
3. **Reference:** Section 1 of Backend Guide (high-level architecture)

### For Salesforce Administrators
1. **Start:** SALESFORCE_FRONTEND_SETUP_GUIDE.md
2. **Then:** SALESFORCE_BACKEND_QUICK_START.md (Sections 1-5: metadata setup)
3. **Reference:** SALESFORCE_FRONTEND_VISUAL_GUIDE.md (for layout decisions)

### For Solution Architects
1. **Start:** SALESFORCE_LWC_DESIGN.md (component contracts)
2. **Then:** SALESFORCE_BACKEND_INTEGRATION_GUIDE.md (full architecture)
3. **Reference:** All documents for requirements mapping

### For Integration Engineers
1. **Start:** SALESFORCE_BACKEND_QUICK_START.md (immediate implementation)
2. **Then:** SALESFORCE_BACKEND_INTEGRATION_GUIDE.md (reference sections 9-10 as needed)
3. **Reference:** SALESFORCE_INTEGRATION_TEST_SUITE.md (validation)

### For DevOps / Infrastructure
1. **Start:** SALESFORCE_BACKEND_INTEGRATION_GUIDE.md, Section 5 (Kubernetes migration)
2. **Then:** SALESFORCE_BACKEND_QUICK_START.md, Section 11.2 (secret rotation)
3. **Reference:** SALESFORCE_INTEGRATION_TEST_SUITE.md, CI/CD Integration section

### For Security / Compliance Teams
1. **Start:** SALESFORCE_BACKEND_INTEGRATION_GUIDE.md, Sections 2-4 (security controls)
2. **Then:** SALESFORCE_BACKEND_INTEGRATION_GUIDE.md, Section 6.3 (monitoring/audit)
3. **Reference:** SALESFORCE_BACKEND_QUICK_START.md (artifact inspection)

---

## 🏗️ Integration Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────────┐
│                   SALESFORCE LIGHTNING EXPERIENCE                   │
│  ┌────────────────────────────────────────┐                        │
│  │  LWCs (Front-End Setup Guide)          │                        │
│  │  • dograhCampaignManager               │                        │
│  │  • dograhCallMonitor                   │                        │
│  │  • dograhAnalyticsDashboard            │                        │
│  └────────────────────────────────────────┘                        │
│                        │                                             │
│  ┌────────────────────▼───────────────────────────────────────┐   │
│  │  Apex Services (Backend Guide, Sections 9)                │   │
│  │  • Named Credentials (callouts)                           │   │
│  │  • Circuit Breaker (Platform Cache)                       │   │
│  │  • Webhook Receiver (HMAC verified)                       │   │
│  │  • Platform Events (async processing)                     │   │
│  │  • Queueable Jobs (DML elevation)                         │   │
│  └────────────────────┬───────────────────────────────────────┘   │
│                       │                                             │
└───────────────────────┼─────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
    Request/      Webhook          WebRTC
    Reply         (signed)          (async)
    (sync)                          (browser)
        │               │               │
        ▼               ▼               ▼
┌─────────────────────────────────────────────────────────────────────┐
│              DOGRAH VOICE AI PLATFORM (FastAPI)                     │
│  ┌────────────────────────────────────────┐                        │
│  │  REST API (Backend Guide, Section 10)  │                        │
│  │  • GET /workflow/fetch                 │                        │
│  │  • POST /campaign/progress             │                        │
│  │  • Correlation ID middleware           │                        │
│  └────────────────────────────────────────┘                        │
│                        │                                             │
│  ┌────────────────────▼──────────────────────────────────────┐    │
│  │  Webhook Signature Gen (Backend Guide, Section 10.1)     │    │
│  │  • HMAC-SHA256 generation                               │    │
│  │  • Timestamp + Correlation ID headers                   │    │
│  └──────────────────────────────────────────────────────────┘    │
│                        │                                             │
│  ┌────────────────────▼──────────────────────────────────────┐    │
│  │  pipecat/ (Real-time Audio)                             │    │
│  │  • WebRTC SDP offer/answer                              │    │
│  │  • ASR/LLM/TTS inference (GPU)                          │    │
│  └──────────────────────────────────────────────────────────┘    │
│                        │                                             │
│  ┌────────────────────▼──────────────────────────────────────┐    │
│  │  Redis + ARQ (async jobs, Backend Guide, Section 10)    │    │
│  │  • Campaign orchestration                               │    │
│  │  • Call run tracking                                    │    │
│  └──────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Kubernetes Cluster (Backend Guide, Section 5)          │
│  • Multi-region deployment                                         │
│  • GPU scheduling (NVIDIA device plugin)                           │
│  • Autoscaling (HPA based on latency)                             │
│  • Blue/green deployment strategy                                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 📋 Phase-by-Phase Implementation Timeline

### Phase 0: Discovery & Planning (Week 1)
- [ ] **Document:** Read all architecture & front-end guides
- [ ] **Discovery:** Map existing Salesforce data model to Dograh workflows
- [ ] **Security:** Conduct threat modeling for webhook endpoint
- [ ] **Deliverable:** Integration requirements document

### Phase 1: Sandbox POC (Week 2-3)
- [ ] **Metadata:** Create custom objects, metadata types, platform events (SALESFORCE_BACKEND_QUICK_START.md, Sections 2)
- [ ] **Apex:** Deploy webhook receiver, circuit breaker, queueable (Sections 3)
- [ ] **Config:** Create named credentials, external credentials (Section 4)
- [ ] **Testing:** Run unit tests (SALESFORCE_INTEGRATION_TEST_SUITE.md)
- [ ] **Deliverable:** Working sandbox with end-to-end flow validated

### Phase 2: LWC Development (Week 3-4, parallel)
- [ ] **Components:** Implement LWCs per SALESFORCE_FRONTEND_SETUP_GUIDE.md
- [ ] **Integration:** Wire LWCs to Apex services (named credential callouts)
- [ ] **Testing:** Integration tests with mock Dograh API
- [ ] **Deliverable:** LWC components deployed to sandbox

### Phase 3: Hardening & Security Review (Week 4-5)
- [ ] **Code Review:** Apex callout patterns, error handling
- [ ] **Security Pen-Test:** HMAC validation, guest user restrictions (Backend Guide, Section 3)
- [ ] **Performance:** Load test with 1k concurrent webhooks (Section 8)
- [ ] **Deliverable:** Security approval, performance baseline

### Phase 4: Kubernetes Deployment (Week 5-6)
- [ ] **Container:** Build Dograh API image with readiness probes (Backend Guide, Section 11.1)
- [ ] **Manifests:** Deploy to managed K8s (EKS/AKS/GKE)
- [ ] **Monitoring:** Set up Prometheus + Alerting (Section 6.3)
- [ ] **Deliverable:** Production K8s cluster with monitoring

### Phase 5: CI/CD Pipeline (Week 6-7)
- [ ] **GitHub Actions:** Apex tests, FastAPI tests, E2E tests (Test Suite)
- [ ] **Secrets:** Implement secret rotation (Backend Quick-Start, Section 11.2)
- [ ] **Observability:** Correlation ID tracing across systems (Backend Guide, Section 6.2)
- [ ] **Deliverable:** Automated test + deploy pipeline

### Phase 6: Production Release (Week 8)
- [ ] **Validation:** Full regression test suite (Test Suite)
- [ ] **Go-Live Runbook:** Create incident response procedures
- [ ] **Training:** Educate support team on monitoring/troubleshooting
- [ ] **Deliverable:** Production deployment

---

## 🔑 Key Architectural Decisions

| Decision | Rationale | Reference |
|----------|-----------|-----------|
| **Hybrid Integration Pattern** | Dual-mode for low-latency queries (sync) + asynchronous data capture (webhook) | Backend Guide, Section 1.1 |
| **HMAC-SHA256 Webhook Verification** | Cryptographic proof of sender authenticity + integrity; prevents spoofing | Backend Guide, Section 3.2 |
| **Transactional Outbox (Platform Events)** | Decouples guest user (limited perms) from elevated DML via async trigger | Backend Guide, Section 4.1 |
| **External ID + Upsert** | Ensures idempotency despite webhook retries; prevents duplicates | Backend Guide, Section 4.2 |
| **Dynamic Field Mapping (CMT)** | Flexible schema evolution without code redeploys; business-admin maintained | Backend Guide, Section 4.3 |
| **Circuit Breaker + Platform Cache** | Protects Salesforce resources during Dograh outages; minimizes API governor impact | Backend Guide, Section 6.1 |
| **Correlation ID Propagation** | End-to-end tracing for rapid RCA; logs joined across Salesforce/Dograh/K8s | Backend Guide, Section 6.2 |
| **Kubernetes for Production** | Enables GPU scheduling, multi-region HA, and sub-500ms latency targets | Backend Guide, Section 5.1 |

---

## 🛡️ Security Checklist

### Before Sandbox Deployment
- [ ] Webhook signing secret generated and securely stored
- [ ] Custom Metadata Type marked "Protected"
- [ ] Guest User profile restricted to GET-only on Site
- [ ] Named Credential tested with valid API token
- [ ] HMAC verification logic audited (constant-time comparison)

### Before Production Deployment
- [ ] Security pen-test completed (webhook endpoint, profile restrictions)
- [ ] HMAC secret rotation procedure documented
- [ ] Real-Time Event Monitoring configured for Guest User anomalies
- [ ] Circuit breaker configured with health check thresholds
- [ ] Correlation ID audit trail enabled

### Ongoing
- [ ] Quarterly HMAC secret rotation
- [ ] Monthly review of rejected webhook attempts (`Dograh_Security_Event__c`)
- [ ] Quarterly update of field mappings per API schema changes
- [ ] Annual pen-test

---

## 📊 Success Metrics

| Metric | Target | Measurement | Reference |
|--------|--------|-------------|-----------|
| **Call Latency (TTFT)** | < 500 ms | P95 latency from LWC initiation | Backend Guide, Section 1.2 |
| **Webhook Success Rate** | > 99.9% | Accepted webhooks / total attempted | Backend Guide, Section 6.3 |
| **Correlation ID Coverage** | 100% | All events traced with ID | Backend Guide, Section 6.2 |
| **Test Code Coverage (Apex)** | ≥ 85% | Unit + integration tests | Test Suite |
| **Platform Event Throughput** | ≥ 5,000/min | Event publishing rate | Backend Guide, Section 8 |
| **Circuit Breaker Activation** | < 1 per month | Unplanned outages detected | Backend Guide, Section 6.1 |

---

## 🚀 Getting Started (Next Steps)

### For First-Time Readers
1. **Spend 20 minutes** reviewing SALESFORCE_FRONTEND_VISUAL_GUIDE.md to understand user experience
2. **Spend 45 minutes** reading SALESFORCE_FRONTEND_SETUP_GUIDE.md to learn LWC capabilities
3. **Choose your path** from the "Reading Paths by Role" section above
4. **Bookmark** all documents for reference during implementation

### For Implementation Teams
1. **Clone or fork** the Dograh repository
2. **Create a tracking issue** in your project management tool referencing the Phase-by-Phase timeline above
3. **Assign roles:** Assign Section 2-5 of Quick-Start to Salesforce Admin; Sections 6-11 to Integration Engineer
4. **Schedule kickoff:** 4-hour session to walk through Architecture Guide Sections 1-4
5. **Establish cadence:** Weekly sync on progress; bi-weekly security reviews

### For Security / Compliance Teams
1. **Review** Backend Guide Section 2 (outbound integration security)
2. **Review** Backend Guide Section 3 (inbound webhook security)
3. **Create risk register** for the integration (store in your risk management system)
4. **Approve** HMAC algorithm, certificate pinning strategy (if needed), and audit logging approach
5. **Schedule** annual pen-test and quarterly secret rotation sync

---

## 🤝 Support & Feedback

- **Questions about LWCs?** → SALESFORCE_FRONTEND_SETUP_GUIDE.md or SALESFORCE_LWC_DESIGN.md
- **Questions about Apex patterns?** → SALESFORCE_BACKEND_INTEGRATION_GUIDE.md, Section 9
- **Getting stuck on setup?** → SALESFORCE_BACKEND_QUICK_START.md with Troubleshooting section
- **Need test examples?** → SALESFORCE_INTEGRATION_TEST_SUITE.md
- **Architecture deep-dive?** → SALESFORCE_BACKEND_INTEGRATION_GUIDE.md, Sections 1-6

---

## 📄 Document Versions & Maintenance

| Document | Version | Last Updated | Status |
|----------|---------|--------------|--------|
| Frontend Setup Guide | 1.0 | Oct 18, 2025 | Production |
| Frontend Visual Guide | 1.0 | Oct 18, 2025 | Production |
| LWC Design | 2.0 | Oct 18, 2025 | Production |
| Backend Integration Guide | 1.0 | Oct 18, 2025 | Production |
| Backend Quick-Start | 1.0 | Oct 18, 2025 | Production |
| Integration Test Suite | 1.0 | Oct 18, 2025 | Production |
| **This Index** | 1.0 | Oct 18, 2025 | Production |

**Change Log:**
- **Oct 18, 2025 (v1.0):** Initial publication; comprehensive coverage of front-end + back-end integration patterns

**Update Schedule:** Review quarterly; update when API schema changes or new LWC components added.

---

## Appendix: Key Terminology

| Term | Definition | Reference |
|------|-----------|-----------|
| **Correlation ID** | Unique request identifier propagated across LWC → Apex → Dograh → Webhook for tracing | Backend Guide, Section 6.2 |
| **Named Credential** | Secure Salesforce abstraction for API endpoint + authentication (OAuth, bearer, basic) | Backend Guide, Section 2.1 |
| **External Credential** | Secure secret storage in Salesforce; stores API key, OAuth token, certificates | Backend Guide, Section 2.1 |
| **Platform Event** | Async messaging primitive; decouples webhook receiver from DML execution | Backend Guide, Section 4.1 |
| **Queueable Apex** | Asynchronous apex job; allows passing non-primitive data and job chaining | Backend Guide, Section 4.1 |
| **External ID** | Unique field on SObject used to deduplicate records during upsert; enables idempotency | Backend Guide, Section 4.2 |
| **Transactional Outbox** | Architectural pattern for safe async publishing; webhook immediately publishes event then returns 200 | Backend Guide, Section 4.1 |
| **Circuit Breaker** | Resilience pattern; stops requests to failing service to allow recovery | Backend Guide, Section 6.1 |
| **HMAC-SHA256** | Cryptographic signature algorithm; verifies webhook authenticity + integrity | Backend Guide, Section 3.2 |
| **Guest User** | Salesforce user profile for unauthenticated external access; restricted DML permissions | Backend Guide, Section 4.1 |
| **TTFT (Time to First Token)** | AI latency metric; time from user input to first response from model | Backend Guide, Section 1.2 |

---

**Document Owner:** Dograh Product & Engineering Team  
**Last Reviewed:** October 18, 2025  
**Next Review Date:** January 18, 2026
