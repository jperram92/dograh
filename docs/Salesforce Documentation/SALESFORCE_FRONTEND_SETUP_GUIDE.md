# Salesforce Front-End Setup Guide
## Dograh Voice AI Platform - User Experience & Analytics

**Version:** 1.0  
**Date:** October 18, 2025  
**Audience:** Salesforce Administrators, Business Users, Report Developers

---

## Table of Contents

1. [Lightning Web Component (LWC) Placement](#lwc-placement)
2. [Page Layouts & Lightning Pages](#page-layouts)
3. [Reports & Dashboards](#reports-dashboards)
4. [Analytics & Metrics](#analytics-metrics)
5. [User Workflows](#user-workflows)
6. [Mobile Experience](#mobile-experience)

---

## 1. Lightning Web Component (LWC) Placement

### Overview

The Dograh integration provides **6 Lightning Web Components** that can be added to various pages in Salesforce. These components enable users to manage voice AI campaigns, monitor real-time call activity, and analyze conversation effectiveness.

---

### 1.1 Campaign Manager Component (`dograhCampaignManager`)

**Purpose:** Create, launch, and monitor voice AI campaigns directly from Lead, Contact, or Campaign records.

#### Where to Place:

**Option A: Lightning Record Page (Recommended)**
- **Location:** Lead Record Page, Contact Record Page, Campaign Record Page
- **Region:** Main content area or sidebar
- **Visibility:** Show to users with "Dograh Campaign Manager" permission set

**Setup Steps:**

1. Navigate to **Setup → Lightning App Builder**
2. Select **Lead Record Page** (or Contact/Campaign)
3. Click **Edit**
4. Drag **Dograh Campaign Manager** component from Custom Components panel
5. Place in **Right Sidebar** or **Top of Page**
6. Configure component properties:
   - **Title:** "Voice AI Campaigns"
   - **Show Active Campaigns Only:** True
   - **Max Campaigns to Display:** 5
7. Set component visibility:
   - Click **Add Filter**
   - **Filter Type:** Permission
   - **Permission Set:** `Dograh_Campaign_Manager`
8. Click **Save** → **Activate**

**Component Features:**
- ✅ View active campaigns targeting this Lead/Contact
- ✅ Launch new campaign with 1-click (uses saved workflows)
- ✅ Real-time call status updates (via Platform Events)
- ✅ Quick actions: Pause, Resume, Stop campaign
- ✅ Mini analytics: Calls completed, success rate, avg duration

**Screenshot Mockup:**

```
┌─────────────────────────────────────────────────────┐
│  Voice AI Campaigns                          [New ▼]│
├─────────────────────────────────────────────────────┤
│  ● Lead Qualifier Campaign                          │
│    Status: Running  |  Progress: 47/100            │
│    Success Rate: 68% | Avg Duration: 3m 24s        │
│    [Pause] [View Details]                          │
├─────────────────────────────────────────────────────┤
│  ● Follow-Up Outreach                               │
│    Status: Scheduled  |  Start: Oct 18 2:00 PM     │
│    Target: 250 leads | Workflow: Follow-Up V2      │
│    [Edit] [Cancel]                                 │
└─────────────────────────────────────────────────────┘
```

---

### 1.2 Workflow Builder Component (`dograhWorkflowBuilder`)

**Purpose:** Create and configure AI voice conversation workflows (scripts, prompts, call flows).

#### Where to Place:

**Option A: Custom Tab (Recommended)**
- **Location:** Dograh app navigation bar
- **Tab Label:** "AI Workflows"
- **Visibility:** "Dograh Workflow Admin" permission set

**Option B: Lightning Page (Full Width)**
- **Location:** Custom Lightning Page (`Dograh_Workflow_Builder_Page`)
- **URL:** `/lightning/n/Dograh_Workflows`

**Setup Steps:**

1. Navigate to **Setup → Tabs**
2. Click **New** (Lightning Component Tab)
3. **Lightning Component:** `c:dograhWorkflowBuilder`
4. **Tab Label:** "AI Workflows"
5. **Tab Icon:** Select "Flow" icon
6. Click **Next** → Apply to **Dograh** app
7. Set profile visibility:
   - **Available for:** Dograh Workflow Admin permission set
8. Click **Save**

**Component Features:**
- ✅ Visual workflow designer (drag-and-drop nodes)
- ✅ AI prompt configuration (greeting, questions, objection handling)
- ✅ Call flow logic (conditional branching, transfers, hangups)
- ✅ Test mode (preview conversation flow before deploying)
- ✅ Version control (save drafts, publish versions, rollback)
- ✅ Template library (pre-built workflows: Lead Qualifier, Appointment Setter, Survey)

**Screenshot Mockup:**

```
┌───────────────────────────────────────────────────────────────┐
│  AI Workflow Builder                      [Save Draft] [Publish]│
├───────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────┐    ┌────────────────────────┐   │
│  │ Workflow Properties     │    │ Visual Flow Designer   │   │
│  │                         │    │                        │   │
│  │ Name: Lead Qualifier    │    │   [START]              │   │
│  │ Category: Sales         │    │      ↓                 │   │
│  │ Voice: Professional F   │    │   [Greeting]           │   │
│  │ Retry: 2 attempts       │    │      ↓                 │   │
│  │ Call Window: 9am-6pm    │    │   [Ask: Available?]    │   │
│  │                         │    │    ↙     ↘            │   │
│  │ [Test Workflow]         │    │  [Yes]   [No]          │   │
│  └─────────────────────────┘    │    ↓       ↓          │   │
│                                  │ [Schedule] [Qualify]   │   │
│                                  │            ↓          │   │
│                                  │         [END]          │   │
│                                  └────────────────────────┘   │
├───────────────────────────────────────────────────────────────┤
│  AI Prompt Configuration                                      │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Greeting:                                              │  │
│  │ "Hi {{First_Name}}, this is Alex calling from         │  │
│  │  {{Company_Name}}. I'm reaching out because you       │  │
│  │  recently downloaded our whitepaper. Do you have      │  │
│  │  2 minutes to chat about your automation needs?"      │  │
│  │                                                        │  │
│  │ [Insert Merge Field ▼]  [Preview Voice]              │  │
│  └────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

---

### 1.3 Call Monitor Component (`dograhCallMonitor`)

**Purpose:** Real-time monitoring dashboard for live AI voice calls with transcription.

#### Where to Place:

**Option A: Lightning Home Page (Recommended)**
- **Location:** Home page for Sales/Service teams
- **Region:** Full width top section
- **Visibility:** "Dograh Call Monitor" permission set

**Option B: Utility Bar (Pop-up)**
- **Location:** Utility bar (accessible from any page)
- **Icon:** Phone icon
- **Auto-open:** When active campaigns running

**Setup Steps:**

1. Navigate to **Setup → Lightning App Builder**
2. Select **Home Page** (or create new)
3. Click **Edit**
4. Drag **Dograh Call Monitor** component to top section
5. Set to **Full Width** (12 columns)
6. Configure properties:
   - **Refresh Interval:** 5 seconds (Platform Event driven)
   - **Max Calls to Display:** 10
   - **Show Transcription:** True
   - **Play Call Recordings:** True (if enabled)
7. Set visibility filter:
   - **Permission Set:** `Dograh_Call_Monitor`
8. Click **Save** → **Activate**

**Component Features:**
- ✅ Live call list (ongoing, queued, completed in last 5 mins)
- ✅ Real-time transcription (updates every 5 seconds via Platform Events)
- ✅ Call status indicators (connecting, in-progress, completed, failed)
- ✅ Call duration timer (live)
- ✅ Lead/Contact quick view (click to open record)
- ✅ Call disposition (auto-captured: Qualified, Not Interested, Callback, No Answer)
- ✅ Sentiment analysis (positive, neutral, negative based on AI)
- ✅ Quick actions: Pause campaign, transfer to human agent, flag for review

**Screenshot Mockup:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Live Call Monitor                    🔴 3 Active | ⏸ 2 Paused | ✓ 47 Today│
├─────────────────────────────────────────────────────────────────────────┤
│  Call ID       Contact          Campaign         Status      Duration   │
├─────────────────────────────────────────────────────────────────────────┤
│  🔴 #12847    John Smith        Lead Qualifier   In Progress  2m 14s    │
│               Acme Corp                           😊 Positive            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Transcript (Real-time):                                         │   │
│  │ AI: "Hi John, thanks for your time. I understand you're         │   │
│  │      exploring automation solutions for your sales team..."     │   │
│  │ John: "Yes, we're looking to reduce manual outreach by 50%."    │   │
│  │ AI: "Great! Can you tell me about your current process?"        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│  [View Full Record] [Transfer to Agent] [Flag for Review]             │
├─────────────────────────────────────────────────────────────────────────┤
│  🟡 #12846    Sarah Johnson     Follow-Up        Connecting    0m 08s   │
│               Tech Solutions                                             │
├─────────────────────────────────────────────────────────────────────────┤
│  ✓ #12845     Mike Davis        Lead Qualifier   Completed     4m 32s   │
│               Global Industries                   ✓ Qualified            │
│  Disposition: Qualified - Meeting Scheduled for Oct 20 2pm              │
│  [View Recording] [Create Follow-Up Task]                              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### 1.4 Analytics Dashboard Component (`dograhAnalyticsDashboard`)

**Purpose:** Comprehensive analytics showing AI effectiveness, conversion rates, and ROI metrics.

#### Where to Place:

**Option A: Custom Tab (Recommended)**
- **Location:** Dograh app navigation
- **Tab Label:** "AI Performance"
- **Full width Lightning page**

**Option B: Reports & Dashboards Page**
- Embed as component in custom Dashboard

**Setup Steps:**

1. Navigate to **Setup → Lightning App Builder**
2. Click **New** → **App Page**
3. **Label:** "Dograh AI Performance"
4. **Template:** Full Width
5. Add **Dograh Analytics Dashboard** component
6. Configure date filters:
   - **Default Range:** Last 30 Days
   - **Comparison:** Previous 30 Days
7. Configure metrics:
   - **Show ROI Calculation:** True (requires cost data)
   - **Show Conversion Funnel:** True
   - **Show Sentiment Analysis:** True
8. Set visibility:
   - **Permission Set:** `Dograh_Analytics_Viewer`
9. Click **Save** → **Activate**
10. Add to **Dograh** app navigation

**Component Features:**
- ✅ Key metrics cards (Total Calls, Success Rate, Avg Duration, Cost per Lead)
- ✅ Conversion funnel (Calls → Answered → Qualified → Opportunity → Won)
- ✅ Time-series charts (calls over time, success rate trends)
- ✅ Campaign comparison table (side-by-side performance)
- ✅ Sentiment analysis distribution (positive/neutral/negative %)
- ✅ Top performing workflows (ranked by conversion rate)
- ✅ Geographic heatmap (if phone numbers have location data)
- ✅ Call outcome breakdown (qualified, not interested, callback, no answer, error)
- ✅ Export to Excel/PDF functionality

**Screenshot Mockup:**

```
┌───────────────────────────────────────────────────────────────────────────┐
│  AI Performance Dashboard            [Last 30 Days ▼] [Export ▼]          │
├───────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │ Total Calls  │ │ Success Rate │ │ Avg Duration │ │ Cost/Lead    │   │
│  │    2,847     │ │    68.4%     │ │   3m 24s     │ │   $2.14      │   │
│  │  ↑ 12% MoM   │ │  ↑ 5.2% MoM  │ │  ↓ 8% MoM    │ │  ↓ 18% MoM   │   │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘   │
├───────────────────────────────────────────────────────────────────────────┤
│  Conversion Funnel                                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  2,847 Calls → 1,947 Answered (68%) → 834 Qualified (43%) →        ││
│  │  312 Opps (37%) → 89 Won (29%)  [Overall Conversion: 3.1%]         ││
│  └─────────────────────────────────────────────────────────────────────┘│
├───────────────────────────────────────────────────────────────────────────┤
│  Calls Over Time (Last 30 Days)                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │   📊 [Line chart showing daily call volume and success rate]        ││
│  └─────────────────────────────────────────────────────────────────────┘│
├───────────────────────────────────────────────────────────────────────────┤
│  Top Performing Workflows                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  Workflow               Calls   Success   Qualified   Cost/Lead     ││
│  │  Lead Qualifier V3      1,247   72%       47%         $1.98         ││
│  │  Follow-Up Outreach     834     65%       38%         $2.31         ││
│  │  Appointment Setter     766     61%       52%         $2.45         ││
│  └─────────────────────────────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────────────┘
```

---

### 1.5 Consent Manager Component (`dograhConsentManager`)

**Purpose:** Manage Do Not Call (DNC) lists, consent preferences, and compliance tracking.

#### Where to Place:

**Option A: Contact/Lead Record Page**
- **Location:** Related tab or sidebar
- **Visibility:** All users (read), Admins (edit)

**Setup Steps:**

1. Navigate to **Setup → Lightning App Builder**
2. Select **Contact Record Page**
3. Click **Edit**
4. Add new tab: **"Communication Preferences"**
5. Drag **Dograh Consent Manager** component to tab
6. Configure properties:
   - **Show DNC History:** True
   - **Allow Manual Override:** False (admin only)
   - **Show Compliance Audit:** True
7. Click **Save** → **Activate**

**Component Features:**
- ✅ Current consent status (Opted In, Opted Out, DNC, Unsubscribed)
- ✅ Consent history timeline (date, method, source)
- ✅ DNC list management (add/remove with reason)
- ✅ Compliance audit trail (TCPA, GDPR, CASL)
- ✅ Quick actions: Send opt-in SMS, Request consent

---

### 1.6 Correlation ID Tracer Component (`dograhCorrelationIdTracer`)

**Purpose:** 360° end-to-end tracing for debugging integration issues (admin/support tool).

#### Where to Place:

**Option A: Utility Bar (Admin Only)**
- **Location:** Utility bar
- **Visibility:** System Administrators, Support Engineers
- **Icon:** Search icon

**Setup Steps:**

1. Navigate to **Setup → App Manager**
2. Edit **Dograh** app
3. Click **Utility Items (Desktop)**
4. Click **Add Utility Item**
5. Select **Dograh Correlation ID Tracer**
6. **Label:** "Trace Integration"
7. **Icon:** `search`
8. **Width:** 400px
9. **Height:** 600px
10. Click **Save**

**Component Features:**
- ✅ Correlation ID search (find all logs, events, errors for a given ID)
- ✅ Timeline view (chronological flow across systems)
- ✅ Error highlighting (red for failures, yellow for retries)
- ✅ Export trace logs (for support tickets)

---

## 2. Page Layouts & Lightning Pages

### 2.1 Lead Record Page

**Recommended Layout:**

```
┌─────────────────────────────────────────────────────────────┐
│  Lead Details                                               │
│  [Standard Lead fields: Name, Company, Email, Phone, etc.] │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  ┌────────────────────────────┐   │
│  │ Voice AI Campaigns  │  │ Communication Preferences  │   │
│  │ (dograhCampaignMgr) │  │ (dograhConsentManager)     │   │
│  └─────────────────────┘  └────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  Related Lists:                                             │
│  - Call Activities (Dograh_Call_Activity__c)                │
│  - Tasks                                                    │
│  - Notes                                                    │
└─────────────────────────────────────────────────────────────┘
```

**Setup Steps:**

1. Navigate to **Setup → Object Manager → Lead**
2. Click **Lightning Record Pages**
3. Select **Lead Record Page** (or create new)
4. Add components as shown above
5. Add **Related List - Single** for `Dograh_Call_Activity__c`
   - **Sort Order:** Recent Activity Date (DESC)
   - **Rows:** 5
6. Click **Save** → **Activate**

---

### 2.2 Campaign Record Page

**Recommended Layout:**

```
┌─────────────────────────────────────────────────────────────┐
│  Campaign Details                                           │
│  [Standard Campaign fields: Name, Type, Status, etc.]      │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Dograh Campaign Manager (Full Width)                    ││
│  │ - Link Dograh Campaign                                  ││
│  │ - View Real-time Progress                               ││
│  │ - Campaign Analytics                                    ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  Related Lists:                                             │
│  - Dograh Campaigns (Dograh_Campaign__c lookup)             │
│  - Campaign Members                                         │
│  - Call Activities                                          │
└─────────────────────────────────────────────────────────────┘
```

---

### 2.3 Custom Lightning App: "Dograh Voice AI"

**App Navigation Bar:**

```
┌───────────────────────────────────────────────────────────────┐
│  [Dograh Logo]  Home | Campaigns | AI Workflows | Live Calls │
│                       | Performance | Leads | Contacts        │
└───────────────────────────────────────────────────────────────┘
```

**Setup Steps:**

1. Navigate to **Setup → App Manager**
2. Click **New Lightning App**
3. **App Name:** "Dograh Voice AI"
4. **Developer Name:** `Dograh_Voice_AI`
5. Click **Next**
6. **App Options:**
   - ✅ Show in Lightning Experience
   - ✅ Show in Mobile
7. Click **Next**
8. **Utility Items:**
   - Add: Dograh Correlation ID Tracer (admin only)
9. Click **Next**
10. **Navigation Items:**
    - Home
    - Campaigns (standard)
    - AI Workflows (custom tab)
    - Live Calls (custom Lightning page with dograhCallMonitor)
    - Performance (custom Lightning page with dograhAnalyticsDashboard)
    - Leads (standard)
    - Contacts (standard)
    - Reports (standard)
    - Dashboards (standard)
11. Click **Next**
12. **User Profiles:**
    - Assign to: System Administrator, Dograh Users (custom profile)
13. Click **Save & Finish**

---

## 3. Reports & Dashboards

### 3.1 Standard Reports (Pre-built)

The Dograh package includes **15 pre-built reports** that can be used out-of-the-box or customized.

#### Report 1: **Campaign Performance Summary**

**Report Type:** Dograh Campaigns with Call Activities

**Columns:**
- Campaign Name
- Status
- Start Date
- Total Calls
- Calls Answered
- Success Rate (%)
- Avg Call Duration
- Total Cost
- Cost per Lead

**Filters:**
- Date Range: Last 30 Days
- Status: Active, Completed

**Grouping:** Campaign Name

**Chart:** Horizontal Bar Chart (Success Rate by Campaign)

**Where to Use:**
- Embed in **Performance Dashboard**
- Schedule email to Sales Manager (weekly)

---

#### Report 2: **Daily Call Activity Report**

**Report Type:** Call Activities (Dograh_Call_Activity__c)

**Columns:**
- Call Date/Time
- Contact Name
- Phone Number
- Campaign Name
- Call Outcome
- Duration
- Sentiment
- Created By (AI Agent Name)

**Filters:**
- Call Date: Today
- Outcome: All

**Grouping:** Call Outcome

**Summary:** Count of calls by outcome

**Where to Use:**
- Morning standup meetings
- Embed in Home page component
- Export to Excel for daily review

---

#### Report 3: **Qualified Leads Report**

**Report Type:** Leads with Call Activities

**Columns:**
- Lead Name
- Company
- Phone
- Last Call Date
- Call Outcome
- Lead Status
- Owner
- Next Follow-Up Date

**Filters:**
- Call Outcome: Qualified
- Lead Status: New, Working
- Last Call Date: Last 7 Days

**Sorting:** Last Call Date (DESC)

**Where to Use:**
- Assign to sales reps for follow-up
- Embed in Lead queue Lightning page
- Auto-send to Sales team (daily digest)

---

#### Report 4: **AI Effectiveness Scorecard**

**Report Type:** Dograh Campaigns with Call Activities

**Columns:**
- Workflow Name
- Total Calls
- Answer Rate (%)
- Qualification Rate (%)
- Avg Call Duration
- Sentiment Score (Avg)
- Cost per Qualified Lead
- ROI (%)

**Filters:**
- Date Range: Last Quarter
- Min Calls: 50 (statistical significance)

**Grouping:** Workflow Name

**Sorting:** Qualification Rate (DESC)

**Chart:** Scatter Plot (Answer Rate vs Qualification Rate)

**Where to Use:**
- Quarterly business reviews
- Workflow optimization planning
- Executive reporting

---

#### Report 5: **Failed Call Analysis**

**Report Type:** Call Activities (Dograh_Call_Activity__c)

**Columns:**
- Call Date/Time
- Contact Name
- Campaign Name
- Error Type
- Error Message
- Retry Count
- Correlation ID (for debugging)

**Filters:**
- Outcome: Error, Failed
- Date Range: Last 7 Days

**Grouping:** Error Type

**Summary:** Count of errors by type

**Where to Use:**
- Support team triage
- Integration health monitoring
- Root cause analysis

---

### 3.2 Custom Dashboards

#### Dashboard 1: **Sales Manager Dashboard**

**Components:**

```
┌─────────────────────────────────────────────────────────────┐
│  Dograh Voice AI - Sales Performance                        │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  │
│  │ Calls Today   │  │ Success Rate  │  │ Qualified     │  │
│  │     127       │  │     68%       │  │      34       │  │
│  │  ↑ 23% vs avg │  │  ↑ 5% vs avg  │  │  ↑ 12% vs avg │  │
│  └───────────────┘  └───────────────┘  └───────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Calls by Outcome (Today)          [Donut Chart]         ││
│  │ - Qualified: 34 (27%)                                   ││
│  │ - Not Interested: 45 (35%)                              ││
│  │ - Callback: 28 (22%)                                    ││
│  │ - No Answer: 20 (16%)                                   ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────┐  ┌─────────────────────────┐ │
│  │ Top Performing Campaigns │  │ Qualified Leads         │ │
│  │ (Last 7 Days)            │  │ (Awaiting Follow-Up)    │ │
│  │ [Table Report]           │  │ [Table Report]          │ │
│  └──────────────────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Setup Steps:**

1. Navigate to **Reports Tab** → **New Dashboard**
2. **Name:** "Dograh Sales Manager Dashboard"
3. **Folder:** Dograh Reports
4. Add components:
   - Metric 1: Calls Today (Report: Daily Call Activity)
   - Metric 2: Success Rate (Report: Campaign Performance)
   - Metric 3: Qualified Leads (Report: Qualified Leads)
   - Chart 1: Calls by Outcome (Report: Daily Call Activity, Donut Chart)
   - Table 1: Top Campaigns (Report: Campaign Performance Summary)
   - Table 2: Qualified Leads (Report: Qualified Leads Report)
5. Set **Refresh Schedule:** Every hour during business hours
6. Click **Save**
7. **Share Dashboard** with Sales Manager profile

---

#### Dashboard 2: **Executive Performance Dashboard**

**Components:**

```
┌─────────────────────────────────────────────────────────────┐
│  Voice AI ROI Dashboard (Executive View)                    │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌────────┐│
│  │ Total Calls │ │ Pipeline    │ │ Revenue     │ │ ROI    ││
│  │   12,847    │ │  $487K      │ │  $142K      │ │  287%  ││
│  │  (MTD)      │ │  (Sourced)  │ │  (Closed)   │ │  (MTD) ││
│  └─────────────┘ └─────────────┘ └─────────────┘ └────────┘│
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Conversion Funnel (Last Quarter)     [Funnel Chart]     ││
│  │ Calls (12,847) → Answered (8,745) → Qualified (3,214) →││
│  │ Opportunity (1,124) → Closed Won (287)                  ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────┐  ┌─────────────────────────┐ │
│  │ Cost Savings Analysis    │  │ AI vs Human Performance │ │
│  │ [Bar Chart]              │  │ [Comparison Table]      │ │
│  │ AI: $2.14/lead           │  │ Metric    AI   Human    │ │
│  │ Human: $8.50/lead        │  │ Cost/Lead $2   $9       │ │
│  │ Savings: $81,542/mo      │  │ Success%  68%  45%      │ │
│  └──────────────────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

### 3.3 Report Types (Custom)

To create the above reports, you'll need these **custom report types**:

#### Report Type 1: **Dograh Campaigns with Call Activities**

**Primary Object:** Dograh_Campaign__c  
**Secondary Object:** Dograh_Call_Activity__c (related via Campaign lookup)

**Fields Available:**
- Campaign: Name, Status, Start Date, End Date, Total Budget, Workflow Name
- Call Activity: Call Date, Outcome, Duration, Sentiment, Cost, Error Type

**Setup Steps:**

1. Navigate to **Setup → Report Types**
2. Click **New Custom Report Type**
3. **Primary Object:** Dograh Campaign (`Dograh_Campaign__c`)
4. **Report Type Label:** "Dograh Campaigns with Call Activities"
5. **Description:** "Analyze campaign performance with call activity metrics"
6. **Store in Category:** Dograh Reports
7. Click **Next**
8. **Relate Another Object:**
   - Object: Dograh Call Activity (`Dograh_Call_Activity__c`)
   - Relationship: "Campaigns may or may not have Call Activities"
9. Click **Save**
10. Add fields from both objects
11. Click **Save**

---

## 4. Analytics & Metrics

### 4.1 Key Performance Indicators (KPIs)

The following metrics should be tracked to measure AI effectiveness:

#### Operational KPIs

| Metric | Definition | Target | Data Source |
|--------|------------|--------|-------------|
| **Total Calls** | Number of calls initiated by AI | 1,000+/month | `Dograh_Call_Activity__c` |
| **Answer Rate** | % of calls answered by recipient | >60% | `COUNT(Outcome='Answered')/COUNT(Total)` |
| **Avg Call Duration** | Average length of answered calls | 3-5 minutes | `AVG(Duration_Seconds__c)` |
| **Success Rate** | % of calls achieving desired outcome | >65% | `COUNT(Outcome='Qualified')/COUNT(Answered)` |
| **Error Rate** | % of calls with technical failures | <2% | `COUNT(Outcome='Error')/COUNT(Total)` |

#### Business KPIs

| Metric | Definition | Target | Data Source |
|--------|------------|--------|-------------|
| **Qualified Leads** | Leads qualified by AI | 500+/month | `COUNT(Call_Activity WHERE Outcome='Qualified')` |
| **Conversion Rate** | % of qualified leads → opportunities | >30% | `COUNT(Opps)/COUNT(Qualified Leads)` |
| **Cost per Lead** | Total campaign cost / leads generated | <$3 | `SUM(Cost)/COUNT(Leads)` |
| **ROI** | Revenue generated / total cost | >250% | `(Revenue - Cost)/Cost * 100` |
| **Pipeline Generated** | Total opp value sourced by AI | $100K+/month | `SUM(Opportunity.Amount WHERE Source='Dograh')` |

#### Quality KPIs

| Metric | Definition | Target | Data Source |
|--------|------------|--------|-------------|
| **Sentiment Score** | Average sentiment (1-5 scale) | >3.5 | `AVG(Sentiment_Score__c)` |
| **Callback Rate** | % of prospects requesting callback | 15-25% | `COUNT(Outcome='Callback')/COUNT(Answered)` |
| **DNC Rate** | % of prospects opting out | <5% | `COUNT(Outcome='Do Not Call')/COUNT(Total)` |
| **Human Transfer Rate** | % of calls escalated to human | <10% | `COUNT(Transferred_to_Human__c=TRUE)/COUNT(Answered)` |

---

### 4.2 Einstein Analytics Integration (Optional)

For advanced analytics, create **Einstein Analytics** dashboards:

#### Dashboard: **Voice AI Predictive Analytics**

**Features:**
- ✅ Predictive lead scoring (which leads most likely to convert after AI call)
- ✅ Best time to call analysis (optimal call windows by timezone, industry)
- ✅ Workflow effectiveness trends (which workflows declining in performance)
- ✅ Anomaly detection (identify unusual call failure spikes)

**Setup Steps:**

1. Enable **Einstein Analytics** in your org
2. Install **Dograh Einstein Analytics Template** (from AppExchange or custom)
3. Schedule data sync from Dograh objects to Einstein Analytics
4. Customize dashboards with your branding
5. Share with executive team

---

## 5. User Workflows

### 5.1 Sales Rep Daily Workflow

**Morning (9:00 AM):**

1. **Open Salesforce** → Navigate to **Dograh Voice AI** app
2. **Home Page** → Review "Qualified Leads Awaiting Follow-Up" component
3. **Filter leads** assigned to me from yesterday's AI calls
4. **Sort by** Sentiment Score (prioritize positive sentiment first)
5. **Click lead** → View call transcript in "Call Activities" related list
6. **Review conversation** → Understand prospect's pain points, objections
7. **Create Task**: "Follow up on AI call - {summarize key points}"
8. **Send personalized email** referencing AI conversation
9. **Schedule call** if prospect requested callback

**Throughout Day:**

10. **Monitor Live Calls** (optional) → Open utility bar "Live Call Monitor"
11. **Review real-time transcripts** if campaign targeting your territory
12. **Flag calls for immediate follow-up** using Quick Action button
13. **Transfer to yourself** if AI escalates high-value prospect

**End of Day (5:00 PM):**

14. **Review Daily Report** → "Qualified Leads Report" (auto-emailed at 4 PM)
15. **Update lead statuses** → Move qualified leads to "Contacted" status
16. **Log call outcomes** → Update "Next Steps" field on lead record
17. **Provide feedback** → Use "Flag for Review" button if AI misqualified lead

---

### 5.2 Campaign Manager Workflow

**Campaign Launch (Weekly):**

1. **Navigate to** "AI Workflows" tab
2. **Select workflow** from template library (e.g., "Lead Qualifier V3")
3. **Click** "New Campaign from Workflow"
4. **Configure campaign:**
   - Name: "Q4 Lead Qualification - Week 42"
   - Target List: Upload CSV or select Salesforce list
   - Schedule: Oct 18, 9:00 AM - 6:00 PM EST
   - Max Calls/Hour: 100
   - Retry Logic: 2 attempts, 24 hours apart
5. **Review consent compliance** → System auto-excludes DNC contacts
6. **Launch campaign** → Click "Start Campaign"

**Campaign Monitoring (Daily):**

7. **Open Campaign Record** → View "Dograh Campaign Manager" component
8. **Review metrics:**
   - Calls completed vs. target
   - Success rate trend (compared to previous campaigns)
   - Cost per lead (real-time)
9. **Adjust campaign** if needed:
   - Pause if success rate drops below 50% (investigate issue)
   - Increase max calls/hour if performance strong
   - Update workflow script if AI struggling with specific objection

**Campaign Wrap-Up (End of Week):**

10. **Stop campaign** → Click "Stop Campaign" button
11. **Export report** → "Campaign Performance Summary" report
12. **Analyze results:**
    - Which workflow variant performed best?
    - What time of day had highest answer rates?
    - Which industries/segments converted best?
13. **Document learnings** → Update campaign notes
14. **Clone best-performing campaign** → Use as template for next week

---

### 5.3 Admin Workflow (Monthly)

**Performance Review (1st of Month):**

1. **Run Report:** "AI Effectiveness Scorecard" (last month)
2. **Identify underperforming workflows** (success rate <55%)
3. **Review call recordings** for failed calls (sample 10-20 calls)
4. **Update workflows:**
   - Refine AI prompts for common objections
   - Adjust call timing windows
   - Update qualification criteria
5. **Test updated workflows** in sandbox before deploying

**Compliance Audit (Monthly):**

6. **Run Report:** "DNC Compliance Report" (all calls last month)
7. **Verify zero calls** to DNC-listed contacts (should be system-enforced)
8. **Review consent audit trail** for any manual overrides
9. **Export audit report** for legal/compliance team

**Integration Health Check:**

10. **Open Utility Bar** → "Correlation ID Tracer"
11. **Search for failed calls** (last 7 days)
12. **Analyze error patterns:**
    - API timeouts? (increase timeout in Named Credential)
    - Authentication failures? (rotate External Credential token)
    - Circuit breaker open? (check Dograh API health)
13. **Create support ticket** if unresolved errors persist

---

## 6. Mobile Experience

### 6.1 Salesforce Mobile App

All Dograh LWC components are **mobile-responsive** and available in the Salesforce Mobile App.

#### Mobile Home Page Layout

```
┌───────────────────────────────┐
│  Dograh Voice AI (Mobile)     │
├───────────────────────────────┤
│  📊 Today's Performance       │
│     127 Calls | 68% Success   │
│     [View Details]            │
├───────────────────────────────┤
│  🔴 Live Calls (3 Active)     │
│     • John Smith - 2m 14s     │
│     • Sarah Johnson - 0m 45s  │
│     [View All]                │
├───────────────────────────────┤
│  ✅ Qualified Leads (12)      │
│     • Mike Davis - Tech Co    │
│       "Interested in demo"    │
│     • Lisa Chen - Acme Corp   │
│       "Budget approved"       │
│     [Follow Up All]           │
└───────────────────────────────┘
```

**Setup Steps:**

1. Navigate to **Setup → Salesforce App → App Builder**
2. Select **Dograh Mobile Home Page**
3. Add components:
   - Dograh Campaign Manager (compact view)
   - Dograh Call Monitor (compact view, max 5 calls)
   - Qualified Leads (list view, max 10 leads)
4. Configure mobile-specific properties:
   - **Compact Mode:** True
   - **Max Items:** 5 (for performance)
   - **Auto-Refresh:** 30 seconds (longer than desktop)
5. Click **Save**

---

### 6.2 Mobile Notifications

Enable **push notifications** for critical events:

**Notification Types:**

1. **High-Value Lead Qualified**
   - Trigger: AI qualifies lead with budget >$50K
   - Notification: "🎯 Hot Lead: John Smith ($75K budget) - Tap to view"
   - Action: Opens Lead record

2. **Campaign Milestone**
   - Trigger: Campaign reaches 50%, 75%, 100% completion
   - Notification: "✅ Q4 Lead Campaign: 75% complete (234/312 calls)"

3. **Call Requires Escalation**
   - Trigger: AI unable to handle objection, requests human transfer
   - Notification: "📞 Transfer Request: Sarah Johnson needs sales rep"
   - Action: Opens live call view, enables 1-click transfer

**Setup Steps:**

1. Navigate to **Setup → Notification Builder**
2. Click **New Notification**
3. **Notification Type:** Custom Notification
4. **Trigger:** Platform Event (`Dograh_Call_Activity_Event__e`)
5. **Filter:** `Event_Type__c = 'qualified' AND Budget__c > 50000`
6. **Notification Text:** "🎯 Hot Lead: {Contact_Name__c} ({Budget__c} budget)"
7. **Actions:**
   - Action 1: "View Lead" → Open `{Lead_Id__c}` record
   - Action 2: "Call Now" → Launch phone dialer with `{Phone__c}`
8. **Recipients:** Assigned user (dynamically determined)
9. Click **Save** → **Activate**

---

## 7. Example User Scenarios

### Scenario 1: Sales Manager Launches Campaign

**Persona:** Jane (Sales Manager)  
**Goal:** Launch 500-lead qualification campaign for Q4 pipeline

**Steps:**

1. **Monday 9:00 AM:** Jane opens Salesforce → Dograh app
2. Navigates to **"AI Workflows"** tab
3. Clicks **"New Campaign"** button
4. Selects workflow: **"Lead Qualifier V3"** (68% success rate historically)
5. Configures campaign:
   - **Name:** "Q4 Enterprise Lead Qualification - Week 42"
   - **Target List:** Uploads CSV of 500 MQLs from marketing
   - **Call Window:** 9 AM - 6 PM EST (respects timezones)
   - **Max Concurrent Calls:** 50
   - **Retry:** 2 attempts, 24 hours apart
6. Reviews consent compliance: System shows "12 contacts excluded (DNC list)"
7. Clicks **"Launch Campaign"** → Confirmation modal appears
8. Campaign starts immediately

**Throughout Week:**

9. Jane monitors dashboard on mobile app (checks 2-3x daily)
10. **Tuesday 3 PM:** Receives notification "🎯 Hot Lead: Acme Corp ($250K budget)"
11. Clicks notification → Opens lead record → Assigns to top sales rep Sarah
12. **Wednesday:** Reviews "Campaign Performance" component → 68% success rate maintained
13. **Friday 5 PM:** Campaign completes → 342/500 calls answered, 124 qualified

**Outcome:**

- 124 qualified leads generated in 5 days
- Cost: $2.14/lead ($265 total)
- 34 opportunities created (27% conversion)
- Projected pipeline: $487K

---

### Scenario 2: Sales Rep Follows Up on AI-Qualified Lead

**Persona:** Tom (Account Executive)  
**Goal:** Close deal with lead qualified by AI yesterday

**Steps:**

1. **Tuesday 9:15 AM:** Tom receives email digest: "5 Qualified Leads Awaiting Your Follow-Up"
2. Opens Salesforce → Dograh app → **"Qualified Leads"** report
3. Sorts by **Sentiment Score** (prioritizes positive conversations)
4. Top lead: **Mike Davis, CTO at Tech Solutions** (Sentiment: 😊 4.8/5)
5. Clicks lead name → Lead record opens
6. Scrolls to **"Call Activities"** related list
7. Sees AI call from yesterday: **"Qualified - Interested in Demo"**
8. Clicks **"View Transcript"** button → Modal opens with full conversation

**Transcript Insights:**

```
AI: "Hi Mike, this is Alex from Dograh. You recently downloaded our 
     automation whitepaper. Do you have 2 minutes?"
Mike: "Sure, we're actually evaluating automation tools right now."
AI: "Perfect timing! What's your biggest challenge with your current process?"
Mike: "We're spending 20 hours a week on manual lead outreach. It's killing 
       our team's productivity."
AI: "I understand. On average, our customers reduce outreach time by 65%. 
     Would you be interested in a quick demo to see how it works?"
Mike: "Yes, let's schedule something. I'm available Thursday or Friday afternoon."
AI: "Great! I'll have our sales team reach out to find a time that works. 
     By the way, what's your timeline for making a decision?"
Mike: "We need something in place by end of Q4. Budget is already approved."
```

9. Tom notes key points:
   - Pain point: 20 hrs/week manual outreach
   - Timeline: End of Q4 (urgent)
   - Budget: Approved (high intent)
   - Availability: Thursday/Friday afternoon

10. Tom sends personalized email:

```
Subject: Demo - Reduce Manual Outreach by 65% (Thursday?)

Hi Mike,

I'm following up on your conversation with our AI assistant yesterday. 
I understand you're spending 20 hours a week on manual lead outreach and 
need a solution by end of Q4 - I can definitely help with that.

Since your budget is approved and timeline is tight, let's get a demo 
scheduled this week. Are you free Thursday at 2 PM EST for a 30-minute 
screen share? I'll show you exactly how we can cut your outreach time 
by 65% (based on your current volume).

Looking forward to it!
Tom

[Calendar Link]
```

11. Mike responds: "Thursday 2 PM works! See you then."
12. Tom creates Opportunity: "$75K ARR - Tech Solutions" (Stage: Demo Scheduled)

**Outcome:**

- Demo scheduled within 24 hours of AI qualification
- Opportunity created with high close probability (budget approved, urgent timeline)
- Tom spent 10 minutes on personalized outreach (vs. 30+ mins cold calling)

---

## 8. Best Practices

### 8.1 Component Placement Guidelines

1. **Campaign Manager:** Always place on Lead/Contact record pages (sidebar or tab)
2. **Call Monitor:** Home page for active managers, utility bar for reps
3. **Analytics Dashboard:** Custom tab (full-width Lightning page)
4. **Consent Manager:** Related tab on Contact/Lead (compliance)
5. **Workflow Builder:** Custom tab (admin/power users only)

### 8.2 Report Scheduling

- **Daily Reports:** Send at 8 AM (before team starts working)
- **Weekly Reports:** Send Monday 9 AM (plan week ahead)
- **Monthly Reports:** Send 1st of month (executive review)

### 8.3 Dashboard Refresh Rates

- **Live Call Monitor:** 5 seconds (Platform Event driven)
- **Campaign Metrics:** 1 minute (during active campaigns)
- **Daily Summary:** 15 minutes (off-peak hours)
- **Historical Analytics:** 1 hour (no real-time needed)

### 8.4 Mobile Optimization

- Limit components to 3-5 per mobile page (performance)
- Use compact view for all mobile components
- Enable notifications for critical events only (avoid fatigue)
- Test on iOS and Android devices before rollout

---

## 9. Training Resources

### 9.1 User Training Paths

**Sales Rep Training (1 hour):**
1. How to review AI-qualified leads (15 min)
2. Reading call transcripts effectively (15 min)
3. Using Live Call Monitor (10 min)
4. Managing consent/DNC (10 min)
5. Hands-on practice (10 min)

**Campaign Manager Training (2 hours):**
1. Creating AI workflows (30 min)
2. Launching campaigns (20 min)
3. Monitoring campaign performance (20 min)
4. Analyzing reports (30 min)
5. Troubleshooting issues (20 min)

**Admin Training (4 hours):**
1. Platform architecture overview (30 min)
2. Component configuration (1 hour)
3. Report/dashboard setup (1 hour)
4. Integration health monitoring (1 hour)
5. Security & compliance (30 min)

---

## 10. Success Metrics (90-Day Plan)

**Month 1 (Pilot):**
- ✅ 5 users trained
- ✅ 1 campaign launched (100 leads)
- ✅ 3 reports/dashboards deployed
- ✅ >60% answer rate achieved

**Month 2 (Scale):**
- ✅ 20 users trained
- ✅ 5 concurrent campaigns (1,000 leads)
- ✅ 10 reports/dashboards deployed
- ✅ >65% success rate achieved

**Month 3 (Optimize):**
- ✅ 50+ users trained (full sales team)
- ✅ 10+ concurrent campaigns (5,000+ leads)
- ✅ Einstein Analytics deployed
- ✅ >70% success rate achieved
- ✅ ROI >250% (revenue vs. cost)

---

## Conclusion

This front-end setup guide provides a comprehensive roadmap for deploying Dograh Voice AI components in Salesforce. By following these recommendations, your users will have:

✅ **Intuitive UI** - Components placed where users naturally work  
✅ **Real-time Visibility** - Live call monitoring and instant notifications  
✅ **Actionable Insights** - Reports/dashboards that drive decision-making  
✅ **Mobile Access** - Full functionality on Salesforce Mobile App  
✅ **Compliance Confidence** - Built-in DNC and consent management  

**Next Steps:**
1. Review this guide with your Salesforce Admin team
2. Customize component placement for your org's needs
3. Build 3-5 priority reports to start
4. Train pilot user group (5-10 users)
5. Gather feedback and iterate

For technical implementation details, refer to the main design document: `SALESFORCE_LWC_DESIGN.md`

---

**Questions? Contact:**  
Salesforce Admin Team: admin@yourcompany.com  
Dograh Support: support@dograh.io
