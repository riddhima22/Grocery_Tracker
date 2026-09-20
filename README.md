# FreshTrack — Smart Pantry & Grocery Expiry Tracker

FreshTrack is an AI-powered smart kitchen management system that eliminates food waste by tracking pantry inventory, predicting expiration dates, inferring meal consumption, looking up barcode products, generating personalized recipes from expiring ingredients, and scheduling push notification alerts.

---

## 🌟 Key Features

1. **Closed-Loop Meal Logging & Pantry Deduction**
   - Take a photo of your meal or enter a natural language description (e.g. *"I cooked chicken curry with rice and tomatoes"*).
   - Multimodal Gemini AI infers ingredient candidates and matches them against active pantry items.
   - Explicit confirmation UI lets you inspect candidate items and tweak quantities before atomic, row-locked pantry deduction.
   - Auto-deduction when marking recipes as cooked.

2. **Barcode Product Lookup**
   - Live barcode scanning using `mobile_scanner`.
   - Server-side integration with **Open Food Facts API v2** plus local user pantry history fallback.
   - Pre-fills item forms with product name, brand, category, unit, calories, and allergens.

3. **Smart Expiry Tracking & Shelf Life Prediction**
   - Temperature, humidity, storage zone, and ripeness aware prediction engine.
   - Color-coded freshness statuses (`fresh`, `expiring`, `expired`).
   - Daily Celery beat push notification alerts at 3 days and 1 day prior to expiration.

4. **AI Recipe Generator**
   - Chef-level recipe generation prioritizing near-expiry pantry items.
   - Takes diet preferences, household size, and allergen warnings into account.

5. **Grocery List Replenishment**
   - Smart replenishment list generation based on consumption history and low stock levels.
   - One-tap "Mark Purchased" moves items directly into kitchen inventory.

---

## 🏗️ Architecture & Monorepo Structure

```
grocery_track/
├── lib/                          # Flutter Mobile Application (Material 3 + Provider)
│   ├── config/                   # Design tokens, routing, theme
│   ├── core/                     # API client, services (scanner, notifications, storage)
│   ├── data/                     # REST Repositories & Data Models
│   └── features/                 # Feature-first modules
│       ├── auth/                 # Sign-in, sign-up, verification
│       ├── dashboard/            # Health analytics, expiry alert banner, AI search
│       ├── groceries/            # Pantry inventory, zone breakdown
│       ├── meals/                # Meal photo logging & confirmation UI
│       ├── recipes/              # Chef recipe generation & cook workflow
│       ├── grocery_list/         # Replenishment list
│       └── scan/                 # Receipt/Produce image scan & Barcode scanner
│
├── backend/                      # Django REST Framework API
│   ├── apps/
│   │   ├── accounts/             # Custom User model, SimpleJWT Auth
│   │   ├── groceries/            # Pantry items, deduction service, Open Food Facts lookup
│   │   ├── meals/                # MealLog, MealIngredientCandidate, AI inference
│   │   ├── recipes/              # AI recipe generation & cook deduction
│   │   ├── grocery_lists/        # Replenishment lists & pantry integration
│   │   ├── notifications/        # FCM token registration & Celery beat expiry alerts
│   │   └── scans/                # Multimodal receipt/produce scan sessions
│   ├── integrations/
│   │   ├── ai/                   # AIService facade, Gemini & OpenAI clients, schemas, prompts
│   │   └── ocr/                  # Vision OCR & date extraction parser
│   ├── common/                   # Global exception handler & response envelope renderer
│   └── config/                   # Settings (base, development, production)
│
├── docker-compose.yml            # Production docker stack (Django + Postgres + Redis + Celery)
└── .github/workflows/ci.yml      # CI pipeline for automated testing
```

---

## 🤖 AI Provider Fallback Architecture

FreshTrack uses an `AIService` facade with dynamic multi-provider fallback. The system attempts requests using the primary provider (Google Gemini) and automatically falls back to secondary providers (OpenAI GPT-4o-mini) if rate limits, network outages, or API errors occur.

### AI Configuration & Environment Variables

| Variable | Default | Description |
|---|---|---|
| `AI_PROVIDER_ORDER` | `gemini,openai` | Ordered list of AI providers to try for inference |
| `GEMINI_API_KEY` | `""` | Google Gemini API key (`google-genai` SDK) |
| `GEMINI_MODEL_NAME` | `gemini-2.5-flash` | Multimodal model for scans & meal inference |
| `GEMINI_RECIPE_MODEL_NAME` | `gemini-2.5-flash` | Model for recipe generation |
| `OPENAI_API_KEY` | `""` | OpenAI API key for fallback provider |
| `OPENAI_MODEL_NAME` | `gpt-4o-mini` | OpenAI vision & JSON model for fallback |

### How Provider Fallback Works
1. When a multimodal vision scan, meal ingredient inference, or recipe generation request arrives, `AIService` inspects `AI_PROVIDER_ORDER`.
2. It attempts execution with the first enabled provider (e.g. Gemini).
3. If the primary provider raises an exception (e.g. 429 Rate Limit, 503 Service Unavailable, or invalid API key), `AIService` catches the failure, logs a warning, and seamlessly retries with the next provider (e.g. OpenAI).
4. If all configured providers fail, an explicit exception is raised so API endpoints return standardized 502/500 error envelopes without corrupting database transactions.

---

## 🚀 Quick Start (Local Development)

### 1. Prerequisites
- Python 3.11+
- Flutter 3.19+
- Docker & Docker Compose (optional for full stack)

### 2. Backend Setup
```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements/development.txt

# Copy example environment variables
cp .env.example .env

# Run migrations
python manage.py migrate --settings=config.settings.development

# Start development server
python manage.py runserver --settings=config.settings.development
```

#### 🔑 OCR Credential Setup (Google Cloud Vision)
- **Google Cloud Vision OCR** requires a dedicated service-account key JSON file configured via the `GOOGLE_APPLICATION_CREDENTIALS` environment variable (distinct from `GEMINI_API_KEY`), in a GCP project with the **Cloud Vision API** enabled and billing active.
- **Graceful Fallback**: If `GOOGLE_APPLICATION_CREDENTIALS` is not set or the GCP Vision client cannot initialize, OCR silently disables itself. Multimodal grocery scanning and date estimation still operate seamlessly using Gemini Vision alone (without supplementary OCR date verification).

### 3. Flutter App Setup
```bash
flutter pub get
flutter run
```

---

## 🐳 Docker Deployment

To launch the full production environment (PostgreSQL + Redis + Django Web API + Celery Worker + Celery Beat):

```bash
docker-compose up --build -d
```

---

## 🧪 Running Tests

### Backend Tests
```bash
cd backend
python manage.py test --settings=config.settings.development
```

### Flutter Tests
```bash
flutter test
```

---

## 🔒 Security & Deployment Checklist
- `CORS_ALLOW_ALL_ORIGINS = False` in `config/settings/base.py`.
- Django System Check `check_secret_key_not_insecure` enforces strong `SECRET_KEY` when `DEBUG=False`.
- All inventory updates use atomic transactions with `select_for_update()` row-level locks.
- IDOR protection enforced on all ViewSets via `request.user` queryset scoping.
- Standard response envelope: `{"success": true, "data": {...}, "message": "..."}`.
