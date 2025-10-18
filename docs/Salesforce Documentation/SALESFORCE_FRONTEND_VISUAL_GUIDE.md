# Salesforce Front-End Visual Guide
## Quick Reference for Lightning Web Component Placement

**Version:** 1.0  
**Date:** October 18, 2025

---

## 📱 Complete Salesforce App Layout

```
╔══════════════════════════════════════════════════════════════════════════╗
║                         SALESFORCE - DOGRAH VOICE AI APP                  ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  Navigation Bar:                                                          ║
║  [🏠 Home] [📞 Campaigns] [🤖 AI Workflows] [📊 Live Calls]              ║
║  [📈 Performance] [👥 Leads] [👤 Contacts] [📋 Reports]                   ║
║                                                                           ║
╠══════════════════════════════════════════════════════════════════════════╣
║                             HOME PAGE LAYOUT                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │  📊 TODAY'S PERFORMANCE (Metrics Cards)                            │  ║
║  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────┐ │  ║
║  │  │ Total Calls  │ │ Success Rate │ │ Qualified    │ │ Cost/Lead│ │  ║
║  │  │    127       │ │    68%       │ │     34       │ │  $2.14   │ │  ║
║  │  │  ↑ 23%      │ │  ↑ 5.2%     │ │  ↑ 12%      │ │  ↓ 18%  │ │  ║
║  │  └──────────────┘ └──────────────┘ └──────────────┘ └──────────┘ │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │  🔴 LIVE CALL MONITOR (dograhCallMonitor)                          │  ║
║  │  ────────────────────────────────────────────────────────────────  │  ║
║  │  Call ID     Contact           Status         Duration   Sentiment│  ║
║  │  🔴 #12847  John Smith        In Progress     2m 14s    😊 Positive│ ║
║  │             Acme Corp                                               │  ║
║  │  ┌──────────────────────────────────────────────────────────────┐ │  ║
║  │  │ Real-time Transcript:                                        │ │  ║
║  │  │ AI: "Hi John, thanks for your time. I understand you're     │ │  ║
║  │  │      exploring automation solutions..."                      │ │  ║
║  │  │ John: "Yes, we need to reduce manual work by 50%..."        │ │  ║
║  │  └──────────────────────────────────────────────────────────────┘ │  ║
║  │  [View Record] [Transfer to Agent] [Flag for Review]              │  ║
║  │                                                                     │  ║
║  │  🟡 #12846  Sarah Johnson     Connecting      0m 08s               │  ║
║  │  ✓ #12845   Mike Davis        Completed       4m 32s   ✓ Qualified│  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
║  ┌─────────────────────────────┐ ┌──────────────────────────────────┐  ║
║  │  📋 ACTIVE CAMPAIGNS        │ │  ✅ QUALIFIED LEADS (Need F/U)   │  ║
║  │  • Q4 Lead Qualifier        │ │  • Mike Davis - Tech Co          │  ║
║  │    47/100 (68% success)     │ │    Budget: $75K | High Intent    │  ║
║  │  • Follow-Up Outreach       │ │  • Lisa Chen - Acme              │  ║
║  │    234/250 (scheduled)      │ │    Needs Demo | Timeline: Q4     │  ║
║  └─────────────────────────────┘ └──────────────────────────────────┘  ║
║                                                                           ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## 👤 Lead/Contact Record Page Layout

```
╔══════════════════════════════════════════════════════════════════════════╗
║  LEAD: John Smith - Acme Corporation                          [Convert]  ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │  DETAILS TAB                                                       │  ║
║  │  ────────────────────────────────────────────────────────────────  │  ║
║  │  Name: John Smith                  Title: VP of Sales              │  ║
║  │  Company: Acme Corporation         Phone: (555) 123-4567           │  ║
║  │  Email: john.smith@acme.com        Status: Working                 │  ║
║  │  Industry: Technology              Lead Source: Web                │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
║  ┌──────────────────────────────┐  ┌───────────────────────────────┐   ║
║  │  📞 VOICE AI CAMPAIGNS       │  │  🔒 COMMUNICATION PREFERENCES │   ║
║  │  (dograhCampaignManager)     │  │  (dograhConsentManager)       │   ║
║  │  ──────────────────────────  │  │  ───────────────────────────  │   ║
║  │  ● Lead Qualifier Campaign   │  │  Status: ✅ Opted In          │   ║
║  │    Status: Completed         │  │  Last Updated: Oct 15, 2025   │   ║
║  │    Outcome: ✓ Qualified      │  │  Method: Web Form             │   ║
║  │    Call Date: Oct 17, 2:45pm│  │  DNC List: Not Listed         │   ║
║  │    Duration: 4m 32s          │  │                               │   ║
║  │    Sentiment: 😊 4.8/5       │  │  Consent History:             │   ║
║  │                              │  │  • Oct 15: Opted In (Web)     │   ║
║  │  [View Transcript]           │  │  • Sep 1: Opted In (Email)    │   ║
║  │  [Launch New Campaign ▼]     │  │                               │   ║
║  └──────────────────────────────┘  └───────────────────────────────┘   ║
║                                                                           ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │  📞 CALL ACTIVITIES (Related List - Dograh_Call_Activity__c)       │  ║
║  │  ────────────────────────────────────────────────────────────────  │  ║
║  │  Date/Time           Campaign          Outcome      Duration       │  ║
║  │  Oct 17, 2:45 PM    Lead Qualifier     ✓ Qualified  4m 32s        │  ║
║  │  Oct 10, 3:12 PM    Follow-Up          Callback     2m 18s        │  ║
║  │  Oct 3, 10:05 AM    Lead Qualifier     Not Interest 1m 45s        │  ║
║  │                                                                     │  ║
║  │  [View All (12)]                                                   │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## 🤖 AI Workflow Builder Page

```
╔══════════════════════════════════════════════════════════════════════════╗
║  AI WORKFLOW BUILDER                         [Save Draft] [Publish V2.0] ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  ┌─────────────────────────┐    ┌────────────────────────────────────┐  ║
║  │ WORKFLOW PROPERTIES     │    │ VISUAL FLOW DESIGNER               │  ║
║  │                         │    │                                    │  ║
║  │ Name: Lead Qualifier    │    │         [START]                    │  ║
║  │ Version: 2.0 (Draft)    │    │            ↓                       │  ║
║  │ Category: Sales         │    │      [Greeting Node]               │  ║
║  │ Status: Active          │    │            ↓                       │  ║
║  │                         │    │   [Question: Available?]           │  ║
║  │ Voice Settings:         │    │         ↙        ↘                │  ║
║  │ ● Professional Female   │    │    [Yes]       [No]                │  ║
║  │ ○ Casual Male           │    │      ↓           ↓                 │  ║
║  │ ○ Energetic Female      │    │  [Schedule]  [Qualify Budget]      │  ║
║  │                         │    │      ↓           ↓                 │  ║
║  │ Call Settings:          │    │  [Create Task] [Check Timeline]    │  ║
║  │ Max Duration: 8 mins    │    │                ↓                  │  ║
║  │ Retry Attempts: 2       │    │             [END]                  │  ║
║  │ Call Window: 9am-6pm    │    │                                    │  ║
║  │ Timezone: Contact TZ    │    │ [+ Add Node] [Delete] [Edit]       │  ║
║  │                         │    │                                    │  ║
║  │ [Test Workflow]         │    │                                    │  ║
║  │ [Clone]                 │    │                                    │  ║
║  │ [Version History]       │    │                                    │  ║
║  └─────────────────────────┘    └────────────────────────────────────┘  ║
║                                                                           ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │  AI PROMPT CONFIGURATION                                           │  ║
║  │  ────────────────────────────────────────────────────────────────  │  ║
║  │  Node: Greeting                                                    │  ║
║  │  ┌──────────────────────────────────────────────────────────────┐ │  ║
║  │  │ Script:                                                      │ │  ║
║  │  │ "Hi {{First_Name}}, this is Alex calling from              │ │  ║
║  │  │  {{Company_Name}}. I'm reaching out because you recently    │ │  ║
║  │  │  downloaded our automation whitepaper. Do you have 2        │ │  ║
║  │  │  minutes to chat about reducing manual work in your sales   │ │  ║
║  │  │  process?"                                                   │ │  ║
║  │  │                                                              │ │  ║
║  │  │ [Insert Merge Field ▼]  [Preview Voice 🔊]                 │ │  ║
║  │  └──────────────────────────────────────────────────────────────┘ │  ║
║  │                                                                     │  ║
║  │  Objection Handling:                                               │  ║
║  │  ┌──────────────────────────────────────────────────────────────┐ │  ║
║  │  │ If: "Not interested"                                         │ │  ║
║  │  │ Response: "I understand. Before I let you go, can I ask     │ │  ║
║  │  │            what's currently working well for your team?"    │ │  ║
║  │  │                                                              │ │  ║
║  │  │ If: "Too busy"                                               │ │  ║
║  │  │ Response: "No problem. When would be a better time? I can   │ │  ║
║  │  │            call back at your convenience."                  │ │  ║
║  │  └──────────────────────────────────────────────────────────────┘ │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## 📊 Performance Dashboard

```
╔══════════════════════════════════════════════════════════════════════════╗
║  AI PERFORMANCE DASHBOARD                [Last 30 Days ▼] [Export PDF]  ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐  ║
║  │ Total Calls  │ │ Success Rate │ │ Avg Duration │ │ Cost per Lead│  ║
║  │   2,847      │ │    68.4%     │ │   3m 24s     │ │    $2.14     │  ║
║  │  ↑ 12% MoM   │ │  ↑ 5.2% MoM  │ │  ↓ 8% MoM    │ │  ↓ 18% MoM   │  ║
║  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘  ║
║                                                                           ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │  CONVERSION FUNNEL                                                 │  ║
║  │  ────────────────────────────────────────────────────────────────  │  ║
║  │                                                                     │  ║
║  │   2,847 Calls  →  1,947 Answered  →  834 Qualified  →             │  ║
║  │                      (68%)              (43%)                       │  ║
║  │                                                                     │  ║
║  │   312 Opportunities  →  89 Closed Won                              │  ║
║  │        (37%)                (29%)                                   │  ║
║  │                                                                     │  ║
║  │   Overall Conversion Rate: 3.1% (Calls → Closed Won)              │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
║  ┌──────────────────────────────┐  ┌───────────────────────────────┐   ║
║  │  CALLS OVER TIME (30 Days)   │  │  CALLS BY OUTCOME             │   ║
║  │  ──────────────────────────  │  │  ───────────────────────────  │   ║
║  │      📈 Line Chart           │  │      🍩 Donut Chart           │   ║
║  │  150│        ╱╲              │  │                               │   ║
║  │  100│      ╱  ╲  ╱╲          │  │  ✅ Qualified: 834 (29%)      │   ║
║  │   50│    ╱      ╲╱  ╲        │  │  ❌ Not Interest: 645 (23%)   │   ║
║  │    0└──────────────────      │  │  📞 Callback: 468 (16%)       │   ║
║  │      Oct 1    Oct 15  Oct 30 │  │  ❓ No Answer: 900 (32%)      │   ║
║  └──────────────────────────────┘  └───────────────────────────────┘   ║
║                                                                           ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │  TOP PERFORMING WORKFLOWS                                          │  ║
║  │  ────────────────────────────────────────────────────────────────  │  ║
║  │  Workflow Name        Calls   Success%  Qualified%  Cost/Lead     │  ║
║  │  Lead Qualifier V3    1,247      72%       47%       $1.98        │  ║
║  │  Follow-Up Outreach     834      65%       38%       $2.31        │  ║
║  │  Appointment Setter     766      61%       52%       $2.45        │  ║
║  │  Customer Survey        423      78%       N/A       $1.12        │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
║  ┌──────────────────────────────┐  ┌───────────────────────────────┐   ║
║  │  SENTIMENT ANALYSIS          │  │  CALL DURATION DISTRIBUTION   │   ║
║  │  ──────────────────────────  │  │  ───────────────────────────  │   ║
║  │  😊 Positive:  1,247 (44%)   │  │      📊 Histogram             │   ║
║  │  😐 Neutral:   1,024 (36%)   │  │  800│   ▄▄                    │   ║
║  │  😞 Negative:    576 (20%)   │  │  600│ ▄▄██▄▄                  │   ║
║  │                              │  │  400│ ████████▄▄              │   ║
║  │  Avg Sentiment: 3.8/5        │  │  200│ ████████████            │   ║
║  │                              │  │    0└──────────────            │   ║
║  │                              │  │      0-2  2-4  4-6  6-8+ mins  │   ║
║  └──────────────────────────────┘  └───────────────────────────────┘   ║
║                                                                           ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## 📱 Mobile App Layout

```
┌─────────────────────────────────┐
│  DOGRAH VOICE AI (MOBILE)       │
├─────────────────────────────────┤
│                                 │
│  📊 Today's Performance         │
│  ┌─────────────────────────────┐│
│  │ 127 Calls │ 68% Success     ││
│  │ 34 Qualified │ $2.14/Lead   ││
│  └─────────────────────────────┘│
│                                 │
│  🔴 Live Calls (3 Active)       │
│  ┌─────────────────────────────┐│
│  │ • John Smith - Tech Co      ││
│  │   In Progress │ 2m 14s      ││
│  │   😊 Positive               ││
│  │   [View] [Transfer]         ││
│  ├─────────────────────────────┤│
│  │ • Sarah Johnson - Acme      ││
│  │   Connecting │ 0m 45s       ││
│  │   [View]                    ││
│  └─────────────────────────────┘│
│                                 │
│  ✅ Qualified Leads (12)        │
│  ┌─────────────────────────────┐│
│  │ • Mike Davis - Tech Co      ││
│  │   "Interested in demo"      ││
│  │   Budget: $75K              ││
│  │   [Follow Up] [View]        ││
│  ├─────────────────────────────┤│
│  │ • Lisa Chen - Acme Corp     ││
│  │   "Budget approved"         ││
│  │   Timeline: Q4              ││
│  │   [Follow Up] [View]        ││
│  └─────────────────────────────┘│
│                                 │
│  📊 Active Campaigns (2)        │
│  ┌─────────────────────────────┐│
│  │ • Lead Qualifier            ││
│  │   47/100 │ 68% Success      ││
│  │   [Pause] [View]            ││
│  └─────────────────────────────┘│
│                                 │
└─────────────────────────────────┘
```

---

## 🎯 Component Placement Quick Reference

| Component | Primary Location | Secondary Location | Mobile |
|-----------|-----------------|-------------------|--------|
| **Campaign Manager** | Lead/Contact Record (Sidebar) | Campaign Record Page | ✅ Yes (Compact) |
| **Call Monitor** | Home Page (Full Width) | Utility Bar | ✅ Yes (Top 5 calls) |
| **Workflow Builder** | Custom Tab (Full Page) | - | ❌ Desktop Only |
| **Analytics Dashboard** | Custom Tab (Full Page) | Dashboard Embed | ✅ Yes (Scrollable) |
| **Consent Manager** | Lead/Contact Record (Tab) | - | ✅ Yes (Read-only) |
| **Correlation Tracer** | Utility Bar (Admin) | - | ❌ Desktop Only |

---

## 📋 Report Placement Matrix

| Report Name | Schedule | Recipients | Dashboard | Mobile |
|-------------|----------|------------|-----------|--------|
| Campaign Performance Summary | Weekly (Mon 9AM) | Sales Managers | Executive Dashboard | ✅ |
| Daily Call Activity | Daily (8AM) | Sales Reps | Sales Dashboard | ✅ |
| Qualified Leads | Daily (4PM) | Sales Reps | Home Page Component | ✅ |
| AI Effectiveness Scorecard | Monthly (1st) | Executives | Performance Dashboard | ✅ |
| Failed Call Analysis | On-Demand | Support Team | Integration Health Dashboard | ❌ |

---

## 🔔 Notification Setup

| Event | Trigger | Notification | Priority | Mobile |
|-------|---------|--------------|----------|--------|
| High-Value Lead | Qualified + Budget >$50K | "🎯 Hot Lead: {Name} ({Budget})" | High | ✅ |
| Campaign Milestone | 50%, 75%, 100% complete | "✅ Campaign: {%} complete" | Medium | ✅ |
| Call Escalation | AI requests human transfer | "📞 Transfer: {Name} needs rep" | High | ✅ |
| Circuit Breaker Open | 5 consecutive API failures | "⚠️ Integration Issue Detected" | Critical | ✅ |
| DNC Violation | Call attempted to DNC contact | "🚫 Compliance Alert: DNC Call" | Critical | ✅ |

---

## 🎨 Branding Customization

### Color Scheme (Recommended)

```css
/* Primary Colors */
--dograh-primary: #0070D2;      /* Salesforce Blue */
--dograh-success: #04844B;      /* Green for qualified */
--dograh-warning: #FFAB00;      /* Amber for callbacks */
--dograh-error: #EA001E;        /* Red for failures */
--dograh-neutral: #706E6B;      /* Gray for neutrals */

/* Component Backgrounds */
--dograh-bg-light: #F3F3F3;     /* Light gray */
--dograh-bg-dark: #16325C;      /* Dark blue */

/* Sentiment Colors */
--sentiment-positive: #04844B;  /* Green */
--sentiment-neutral: #FFAB00;   /* Amber */
--sentiment-negative: #EA001E;  /* Red */
```

### Icon Usage

- 🔴 Live/Active indicators
- ✅ Qualified/Success states
- 📞 Call-related actions
- 📊 Analytics/Reports
- 🤖 AI Workflows
- 😊😐😞 Sentiment indicators
- 🎯 High-value opportunities
- ⚠️ Warnings/Issues
- 🚫 Compliance/Violations

---

## 📚 Training Checklists

### ✅ Sales Rep Onboarding Checklist

- [ ] Access Dograh Voice AI app
- [ ] Review Home Page components (10 min)
- [ ] Find qualified leads in your territory
- [ ] Read a call transcript
- [ ] Follow up on 1 AI-qualified lead
- [ ] Review mobile app notifications
- [ ] Flag a call for review (practice)
- [ ] Export Daily Call Activity report

### ✅ Campaign Manager Onboarding Checklist

- [ ] Access AI Workflows tab
- [ ] Browse workflow template library
- [ ] Create test campaign (sandbox)
- [ ] Upload target list (CSV)
- [ ] Configure call window settings
- [ ] Review consent compliance checks
- [ ] Monitor live campaign dashboard
- [ ] Export Campaign Performance report
- [ ] Pause/Resume campaign
- [ ] Analyze campaign results

### ✅ Admin Setup Checklist

- [ ] Install Dograh managed package
- [ ] Configure External Credential
- [ ] Create Platform Cache partition
- [ ] Assign Permission Sets
- [ ] Add components to Lightning Pages
- [ ] Create 5 priority reports
- [ ] Build Sales Manager dashboard
- [ ] Configure mobile app layout
- [ ] Setup notification rules
- [ ] Test end-to-end workflow
- [ ] Train pilot user group
- [ ] Review integration health

---

## 🚀 Quick Start (Day 1 Setup)

**Time Required:** 2-3 hours

### Step 1: Install Package (30 min)
1. Install Dograh managed package from AppExchange
2. Create External Credential with API token
3. Create Platform Cache partition (5 MB)
4. Assign Permission Sets to pilot users

### Step 2: Configure Components (45 min)
1. Edit Lead Record Page → Add Campaign Manager (sidebar)
2. Edit Home Page → Add Call Monitor (full width, top)
3. Create "AI Workflows" tab → Add Workflow Builder
4. Create "Performance" tab → Add Analytics Dashboard

### Step 3: Create Reports (45 min)
1. Create "Campaign Performance Summary" report
2. Create "Daily Call Activity" report
3. Create "Qualified Leads" report
4. Create "Sales Manager Dashboard" with 3 components

### Step 4: Test & Train (30 min)
1. Test campaign launch with 10 test leads
2. Monitor live calls on Home Page
3. Review call transcript on Lead record
4. Train 5 pilot users (30 min each, scheduled separately)

---

**Next:** Proceed to full implementation guide in `SALESFORCE_FRONTEND_SETUP_GUIDE.md`
