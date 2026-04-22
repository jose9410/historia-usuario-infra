# AutoAnalyst Platform (Koncilia Microservices)

Welcome to the **AutoAnalyst** platform repository. This project represents a complete architectural migration from a legacy monolithic automation suite into a highly scalable, containerized microservices ecosystem.

## 🚀 Architectural Overview

The platform has been divided into distinct, loosely coupled microservices, orchestrated via Docker Compose. It leverages a modern tech stack designed for high performance, real-time feedback, and secure background processing.

### 1. Frontend (Angular 17+ & Nginx)
* **Premium Dashboard UI**: A fully redesigned "glassmorphism" dark-theme dashboard replacing the old static interfaces.
* **Reactive Polling**: Implements advanced RxJS patterns (`timer(0, 2000)` with `ChangeDetectorRef`) to provide instant, real-time UI updates for long-running background tasks.
* **Nginx Reverse Proxy**: Serves the compiled Angular application and proxies API requests.
  * *Critical Configuration*: Nginx is configured with `proxy_buffering off` and `proxy_cache off` for the `/api/process` routes to ensure instant delivery of Job IDs without connection hanging.

### 2. Compliance Automator (QAAutomation.Api)
* **Tech Stack**: ASP.NET Core 8.0 Minimal API.
* **Headless Playwright**: Executes complex, multi-step browser automation (RPA) invisibly inside a Linux container.
* **Ultra-Detached Worker Pattern**: Resolves legacy `ObjectDisposedException` crashes. When a user starts an automation batch, the API instantly returns a HTTP 200 with a tracking `JobId`. The actual Playwright execution is spun off into an isolated, detached background thread using `IServiceScopeFactory`, ensuring the HTTP pipeline never blocks or drops the connection.

### 3. Story Synthesis (HistoriaUsuario.Api)
* **Tech Stack**: ASP.NET Core 8.0.
* **Functionality**: "Ingestor AI" component that parses `.vtt` transcription files (e.g., from MS Teams) and automatically synthesizes structured User Stories and deliverables (DOCX, PDF, PNG).

---

## 🛠️ Key Technical Implementations

### Security & Source Control
* **Credential Protection**: Strict `.gitignore` implementations across all repositories completely isolate `appsettings.json` and sensitive Windows Authentication NTLM credentials from version control.

### UI/UX Upgrades
* **Sidebar Navigation**: Transitioned from a top-bar layout to a modern, state-managed left sidebar.
* **Smart Error Recovery**: The frontend includes a "Rescue Timer." If a proxy or network layer hangs for more than 6 seconds, the UI automatically recovers its state and searches for the active background job, preventing the user from being stuck on infinite loading screens.

---

## 🐳 Running the Platform

Ensure Docker Desktop is running, then execute the following command from the root directory:

```powershell
docker-compose up -d --build
```

### Services Included:
* `frontend` (Port 80)
* `automation-api` (Port 8080)
* `historia-usuario-api` (Port 8081)

## 📁 Project Structure

```text
KonciliaMicroservices/
│
├── frontend/
│   ├── koncilia-web/          # Angular Application
│   ├── nginx.conf             # Reverse Proxy & Buffer settings
│   └── Dockerfile             # Multi-stage Node/Nginx build
│
├── backend/
│   ├── QAAutomation.Api/      # Compliance Automator (Playwright)
│   └── HistoriaUsuario.Api/   # Story Synthesis
│
└── docker-compose.yml         # Service orchestration
```
