# D8N Architecture Diagrams

## Purpose

These diagrams are for founder, CTO, reviewer, investor, and future engineering discussions.

They use Mermaid so they can render in GitHub, VS Code, and many documentation tools.

## Platform Overview

```mermaid
flowchart TB
  D8N[D8N Platform Core]

  D8N --> Identity[D8N ID / Identity]
  D8N --> Profiles[D8N Profiles]
  D8N --> Match[D8N Match / Matching]
  D8N --> Chat[D8N Chat / Messaging]
  D8N --> Verify[D8N Verify / Verification]
  D8N --> Trust[D8N Trust]
  D8N --> Media[D8N Media]
  D8N --> Pay[D8N Pay / Billing]
  D8N --> Notify[D8N Notify / Notifications]
  D8N --> Insights[D8N Insights / Analytics]
  D8N --> Admin[D8N Admin]

  HookUs[HookUs] --> D8N
  Date9ja[Date9ja] --> D8N
  DateSA[DateSA] --> D8N
  DateAussie[DateAussie] --> D8N
  Future[Future Brands] --> D8N
```

## API-Only Core With Separate Frontends

```mermaid
flowchart LR
  Marketing[D8N Marketing Site<br/>Next.js] --> API[D8N Platform API<br/>Rails API-only]
  HookUsWeb[HookUs Web] --> API
  Date9jaWeb[Date9ja Web] --> API
  Mobile[Mobile Apps] --> API
  AdminUI[D8N Admin<br/>Rails/Hotwire or separate app] --> API
  OperatorPortal[Future Operator Portal] --> API

  API --> PG[(PostgreSQL)]
  API --> Redis[(Redis)]
  API --> R2[(Cloudflare R2)]
  API --> Providers[Email / SMS / Payments / Verification]
```

## Identity Versus Brand Profiles

```mermaid
flowchart TB
  User[D8N User<br/>platform identity]

  User --> Credentials[Credentials<br/>email/password, phone OTP, OAuth, WebAuthn]
  User --> Verification[User Verification<br/>email, phone, selfie, ID]

  User --> HookUsProfile[HookUs Profile]
  User --> Date9jaProfile[Date9ja Profile]
  User --> DateSAProfile[DateSA Profile]

  HookUsProfile --> HookUsActivity[HookUs likes, matches, chats]
  Date9jaProfile --> Date9jaActivity[Date9ja likes, matches, chats]
  DateSAProfile --> DateSAActivity[DateSA likes, matches, chats]
```

## Brand Ownership And Operators

```mermaid
flowchart TB
  D8NOrg[D8N Platform Owner]
  ExternalOwner[External Brand Owner]

  D8NOrg --> HookUsBrand[HookUs Brand]
  D8NOrg --> Date9jaBrand[Date9ja Brand]
  ExternalOwner --> PartnerBrand[Future Partner Brand]

  HookUsBrand --> HookUsAdmins[HookUs Operators]
  Date9jaBrand --> Date9jaAdmins[Date9ja Operators]
  PartnerBrand --> PartnerAdmins[Partner Operators]

  D8NOrg --> NetworkAdmins[Network Admins]

  NetworkAdmins --> NetworkData[D8N Network Data]
  HookUsAdmins --> HookUsData[HookUs Scoped Data]
  Date9jaAdmins --> Date9jaData[Date9ja Scoped Data]
  PartnerAdmins --> PartnerData[Partner Brand Scoped Data]
```

## Auth Strategy Model

```mermaid
flowchart TB
  Request[Auth Request]
  Request --> BrandPolicy[Brand Auth Policy]

  BrandPolicy --> PhoneOTP[Phone OTP Strategy]
  BrandPolicy --> EmailPassword[Email Password Strategy]
  BrandPolicy --> OAuth[OAuth Strategy]
  BrandPolicy --> WebAuthn[WebAuthn Strategy]
  BrandPolicy --> Invite[Invite Strategy]

  PhoneOTP --> Session[D8N Session]
  EmailPassword --> Session
  OAuth --> Session
  WebAuthn --> Session
  Invite --> Session

  Session --> SecurityEvent[Security Event]
  Session --> Device[Device Record]
  Session --> Risk[Risk Signals]
```

## Tenant-Safe Request Flow

```mermaid
sequenceDiagram
  participant Client
  participant API as D8N API
  participant Context as Request Context
  participant Policy as Authorization Policy
  participant Domain as Domain Service
  participant DB as PostgreSQL

  Client->>API: Request with domain/header/token
  API->>Context: Resolve current_brand, current_user, permissions
  Context->>Policy: Authorize action
  Policy-->>API: Allowed / denied
  API->>Domain: Call service with context
  Domain->>DB: Tenant-scoped query
  DB-->>Domain: Brand-scoped records
  Domain-->>API: Result
  API-->>Client: Response
```

## Soft Deletion And Recovery

```mermaid
stateDiagram-v2
  [*] --> Active
  Active --> SoftDeleted: user/admin deletes
  SoftDeleted --> Restored: approved recovery
  Restored --> Active
  SoftDeleted --> Anonymized: privacy/legal workflow
  SoftDeleted --> Purged: storage/provider cleanup
  Anonymized --> [*]
  Purged --> [*]
```

## Scaling Shape

```mermaid
flowchart TB
  Internet[Internet] --> Cloudflare[Cloudflare / CDN / WAF]
  Cloudflare --> LB[Load Balancer]

  LB --> Web1[Rails API Web 1]
  LB --> Web2[Rails API Web 2]
  LB --> WebN[Rails API Web N]

  Web1 --> PGPrimary[(Postgres Primary)]
  Web2 --> PGPrimary
  WebN --> PGPrimary

  Web1 --> Redis[(Redis)]
  Web2 --> Redis
  WebN --> Redis

  Worker1[Worker 1] --> Redis
  Worker2[Worker 2] --> Redis
  WorkerN[Worker N] --> Redis

  Worker1 --> PGPrimary
  Worker2 --> PGPrimary
  WorkerN --> PGPrimary

  Web1 --> R2[(R2 / Object Storage)]
  Worker1 --> R2

  PGPrimary --> Replica[(Read Replica later)]
```
