# MyNewsBuddy Flutter Backup

This is a **separate cross-platform backup project** for the existing SwiftUI
Local Companion app. It does not replace or modify `HyperlocalNews`.

## What works now

- iOS, Android, and Web project targets
- Local Companion visual foundation and five-tab navigation
- Backup demo mode that does not require an account
- Live Boston observation from Weather.gov
- Live MBTA rapid-transit alert count
- Render AI-backend health status
- Supabase email/password sign-in and sign-up when configured
- Honest labels for features that have not been migrated yet

## Migration status

| Feature | Status |
| --- | --- |
| App shell and Home design | Initial Flutter version complete |
| Supabase authentication | Implemented; requires build-time configuration |
| Weather.gov | Live Boston observation implemented |
| MBTA | Live alert count implemented |
| RAG Chat | Next |
| Map and live location | Planned |
| Boston Events calendar | Planned |
| Journalist Inbox | Planned |
| Boston 311 / traffic / local news | Not connected in either client yet |

## Run in backup demo mode

```bash
flutter run
```

Choose **Continue in backup demo mode**. Public feeds will load; private
Supabase features stay disabled.

## Run with Supabase

Resume the Supabase project first, then use its current Project URL and public
publishable key:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY \
  --dart-define=BACKEND_BASE_URL=https://mynewsbuddy-api.onrender.com
```

Do not put a Supabase service-role key, Gemini key, or other secret in this
client project.

## Verify

```bash
flutter analyze
flutter test
flutter build web
```

## Recommended next migration step

Port the authenticated Chat vertical slice in this order:

1. `/route` request with the Supabase access token
2. Weather.gov and MBTA evidence serialization
3. `/ask` grounded answer request
4. Citation rendering
5. True information-gap saving to Supabase

Keep the Swift app available until each Flutter feature has been tested on a
real iPhone and in a web browser.
