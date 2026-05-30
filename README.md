# Pantry AI — Swift iOS app

A native SwiftUI implementation of the Pantry AI design, backed by a small
FastAPI dev server. Built to the spec in `pantry_handoff_swift.md` with the
design language from `pantry/project/Pantry Mobile.html` — bold ink borders,
hard offset shadows, amber + pastel category accents, and the Funnel Display /
Inter type pairing.

## What's here

```
PantryAI/
├── PantryAI/              ← Swift source
│   ├── App/               ← entry point, AppConfig
│   ├── Models/            ← InventoryItem, Category, SwiftData records
│   ├── Decay/             ← protocol + 4 polymorphic models + factory
│   ├── Services/          ← Gemini, Inventory, Network, Keychain
│   ├── ViewModels/        ← @MainActor MVVM
│   ├── DesignSystem/      ← Theme, typography, ChunkyCard, Ring, PillButton
│   ├── Views/             ← Pantry, Scan (AVFoundation), Recipes, Onboarding, Settings
│   └── Resources/         ← Info.plist, Assets.xcassets
├── backend/               ← FastAPI dev server matching the iOS API contract
└── project.yml            ← XcodeGen spec for generating PantryAI.xcodeproj
```

## What you need to do next

### 1. Generate the Xcode project

This repo ships source files plus an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
`project.yml`. Generating the `.xcodeproj` keeps the project file out of git
and makes it trivially regenerable.

```sh
brew install xcodegen
cd PantryAI
xcodegen generate
open PantryAI.xcodeproj
```

If you'd rather skip XcodeGen, create a new "iOS App" in Xcode at this
directory and drag the `PantryAI/` source folders into it (uncheck "Copy items
if needed", choose "Create groups"). Set deployment target to **iOS 17.0**.

### 2. Add the Funnel Display font (optional, recommended)

The design uses *Funnel Display* (Google Fonts). The app degrades gracefully to
a heavy system rounded font if it's missing, but for a pixel-perfect match:

1. Download the Funnel Display family from <https://fonts.google.com>.
2. Drop the `.ttf` files into `PantryAI/Resources/`.
3. In Xcode → Target → Info, add `UIAppFonts` (array of font filenames).

### 3. Set your Gemini API key

The Gemini key is stored in the iOS Keychain, never in `UserDefaults` or
hardcoded. On first launch:

1. Run the app and complete onboarding (or skip to Household tab).
2. In **Household → Gemini**, paste your key and tap "Save key".
3. Pick `gemini-2.0-flash` for fast scans or `gemini-2.0-pro` for chat depth.

Get a key from <https://aistudio.google.com/app/apikey>.

### 4. Run the FastAPI dev server

```sh
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

The Swift app reads the base URL from `AppConfig.baseURL` — defaulting to
`http://localhost:8000`. To point at a real LAN address or remote host, change
it in **Household → Server**.

> ℹ️ On a physical device, `localhost` resolves to the phone itself. Use your
> Mac's LAN IP (`ipconfig getifaddr en0`) and update the base URL accordingly.

### 5. Build & run

Open the project, select the *PantryAI* scheme, choose an iPhone 15 simulator
or your device, and Cmd-R. Minimum iOS 17.

## How the pieces fit together

- **Decay** is the polymorphic core. `DecayModel` protocol + 4 concrete
  implementations (`Linear`, `Exponential`, `Step`, `Learned`) routed through
  `DecayModelFactory`. Every `InventoryItem` resolves its model lazily, so you
  can swap algorithms by changing the factory or by setting the per-item
  `decayModelOverride`. The Learned model falls back to Linear until it has
  enough usage events to fit an empirical half-life — flip the threshold in
  `LearnedDecayModel.swift` once you have real data.
- **State** lives in SwiftData. Value-type `InventoryItem` / `UsageEvent` are
  what views/services pass around; `InventoryItemRecord` and friends are the
  persisted `@Model` classes. `InventoryService` is the single boundary.
- **Networking** is `async/await` over `URLSession`, no Alamofire. Gemini is
  called directly from the device by default — when you're ready to route via
  the backend, set `AppConfig.callGeminiDirectly = false` and add the proxy
  endpoint to `backend/main.py`.
- **Views** match the prototype's chunky-card aesthetic. `ChunkyCard`,
  `PillButton`, and `Ring` are the three shared primitives — most screens are
  thin compositions of those.

## Design fidelity notes

- The HTML prototype was the source of truth. Colours come straight from the
  CSS variables (`canvas`, `bg`, `ink`, `sky`/`mint`/`rose`/`amber`/`lilac`)
  and live in `Theme.swift`.
- The "chunky drop shadow" (CSS `boxShadow: '0 5px 0 var(--ink)'`) is rendered
  as a translated ink-filled rounded rect behind the card, since SwiftUI
  shadows are blurred by default.
- The avocado-pit mascot is hand-translated to `Path` calls in
  `Mascot.swift` — verify the curves on device and tune if needed.
- The tab bar uses SF Symbols (`tray.full.fill`, `plus`, `fork.knife`,
  `person.2.fill`) as 1:1 stand-ins for the prototype's hand-drawn icons. If
  you want pixel-exact icons, drop the SVGs from `pantry/project/mobile/icons.jsx`
  into the asset catalog and reference them by name.

## Known stubs / next-up work

- **Recipes streaming**: parses Gemini's SSE-style chunks line by line.
  Hardened in the happy path; harder error states (rate limits, mid-stream
  cuts) need a manual retry.
- **Receipt / video pan / email** scan modes from the design are not wired up.
  The handoff doc only spec'd the photo scan flow.
- **Backend sync** is best-effort: the app shows cached SwiftData when the
  backend is offline. The "offline banner" UI from the spec isn't drawn yet —
  hook into `vm.backendOffline` on `PantryViewModel` once you decide where it
  should live.
- **Onboarding swipe** persists likes/dislikes as `RecipePreference`s, but the
  recipe prompt only sends them as flat name strings. Add cuisine/tag metadata
  when you're ready to bias suggestions properly.

## Backend stub at a glance

- `GET  /api/v1/health` — used by the app on launch.
- `GET  /api/v1/inventory` — returns persisted items.
- `POST /api/v1/inventory/upsert` — bulk upsert by case-folded name.
- `DELETE /api/v1/inventory/{id}` — removes one.
- `POST /api/v1/inventory/{id}/usage` — fire-and-forget logging.
- `GET  /api/v1/recipes/suggestions` — placeholder; the app calls Gemini directly.

Persistence is a single JSON file (`pantry_store.json`) so you can read it,
edit it, and reset it easily during development.
