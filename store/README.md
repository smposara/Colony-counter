# Google Play release – Colony Counter

Everything needed to publish Colony Counter in the Google Play Console, with the
answer to each form. Work through the checklist from top to bottom.

| | |
|---|---|
| App name | Colony Counter – CFU counting (en) · Colony Counter: นับโคโลนี (th) |
| Package name | `th.in.amphur.colonycounter` (permanent) |
| Version | 0.9.0 (version code 14) |
| Default language | English (United States) – en-US, plus Thai – th-TH |
| App or game | App |
| Free or paid | Free |
| Category | Medical (see the note below) |
| Developer / contact | Pongsak Sarapukdee · sarapukdee@gmail.com · https://cc.amphur.in.th |
| Privacy policy | https://cc.amphur.in.th/privacy.html |

## Files in this folder

| What | File | Play requirement |
|---|---|---|
| App icon | `graphics/icon-512.png` | 512 × 512 PNG, ≤ 1 MB |
| Feature graphic | `graphics/feature-graphic-en.png`, `graphics/feature-graphic-th.png` | 1024 × 500 PNG/JPEG |
| Phone screenshots | `screenshots/en-US/1…8.png`, `screenshots/th-TH/1…8.png` | 2–8 per language, 1080 × 1920 (9:16) |
| Store texts | `listing/en-US.md`, `listing/th-TH.md` (and one `.txt` per field for copy-paste) | name ≤ 30, short ≤ 80, full ≤ 4000, release notes ≤ 500 characters |
| App bundle | CI artifact **colony-counter-aab** → `app-release.aab` | signed with the upload key |
| Privacy policy | `app/web/privacy.html`, published with the web version | public URL |

Screenshots, in order: review a count · plate list · samples · sample result with
replicates · comparison (time-kill chart) · time-lapse · counting accuracy · several
plates in one photo. They come from the web build with demo data and look the same
as the Android app (same Flutter interface).

Tablet screenshots are optional; without them the listing is shown as a phone app.

`screenshots/release-0.7.0/` shows the 0.7.0 feature, drop plates with a layout, in English
and Thai: sample setup with rows of drops and the counting window, a 4 × 3 rows plate with
confluent (TNTC) and empty drops and its drop table, an 8-drop ring, leaving a drop out, and
the sample's result with the drop table and 95 % interval, plus one overview image per
language for testers.

`screenshots/release-0.6.0/` shows the 0.6.0 feature, Petrifilm dry films, in English and
Thai: film setup, an EC film in Gas mode, a yeast & mold film, a crowded film estimated from
grid squares, and a sample's E. coli and coliform results, plus one overview image per
language for testers. The listing's full description and What's new carry the Neogen
trademark notice; keep it whenever Petrifilm is named.

`screenshots/release-0.5.2/` shows the 0.5.2 feature (marks on and off, English and Thai,
plus a side-by-side image for sharing with testers). It is not part of the listing, which
allows 8 phone screenshots per language.

## Promo video (optional)

`video/colony-counter-promo-en.mp4` and `video/colony-counter-promo-th.mp4`: 43 s,
1920 × 1080, no voice or music. The video shows the colony count on a real demo
photo, then the store screenshots with captions.

Play takes a **YouTube link**, not a file:
1. Upload each video to YouTube (studio.youtube.com → Create → Upload videos).
   - Visibility: **Public** or **Unlisted**.
   - Audience: "No, it's not made for kids".
   - Leave monetisation off, because Play does not show videos with ads.
   - Allow embedding. It is on by default; check it under Show more → License and distribution.
2. Optional: add music in YouTube Studio → Editor → Audio, which has free tracks.
3. Play Console → Main store listing → **Video** → paste the English link.
   In the Thai (th-TH) translation, paste the Thai link.

To rebuild the video after the screenshots change, run `node render.js en video
colony-counter-promo-en.mp4` (and `th`) in `video/`. It needs Playwright with
Chromium and ffmpeg. The captions are in `video/promo.html`.

## Before you start

1. **Publish the privacy policy.** Upload the latest web zip to cc.amphur.in.th, then
   check that https://cc.amphur.in.th/privacy.html opens. Play rejects the app if
   the privacy policy URL does not work.
2. **Get the app bundle.** GitHub → Actions → the latest *app* run →
   Artifacts → **colony-counter-aab**. Unzip it to get `app-release.aab`.
   Check in that run's log ("Show signing certificate and permissions") that:
   - the certificate SHA-256 is `11be7d8f061063beeb80d205ea4c3fb221273682bfe26433444a1bdf50c0576a`;
   - the only permission is `android.permission.CAMERA` (plus permissions the
     system adds itself, such as `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`).
3. **Developer account.** A Play Console developer account (one-time US$25) with
   identity verification completed.
   **Personal accounts created after 13 November 2023 must run a closed test with at
   least 12 testers who stay opted in for 14 days in a row** before they can apply
   for production access. Plan for this: invite colleagues or students as testers.

## Checklist in the Play Console

### 1. Create app
- App name: `Colony Counter – CFU counting`
- Default language: English (United States)
- App or game: **App** · Free or paid: **Free**
- Accept the declarations (Developer Program Policies, US export laws).

### 2. App signing
Use **Play App Signing** (the default). Google keeps the app signing key; the key
in the CI secrets becomes your **upload key**. Keep the keystore backup safe: if
the upload key is lost, Google can reset it, but that takes a support request.

### 3. Store listing (Grow → Store presence → Main store listing)
- App name, short description, full description: from `listing/en-US.md`.
- App icon: `graphics/icon-512.png`
- Feature graphic: `graphics/feature-graphic-en.png`
- Phone screenshots: `screenshots/en-US/` (all 8, in file order).
- Add a translation → **Thai (th-TH)**: texts from `listing/th-TH.md`, feature
  graphic `graphics/feature-graphic-th.png`, screenshots `screenshots/th-TH/`.

### 4. Store settings
- App category: **Medical** · Tags: e.g. "Laboratory", "Education", "Utilities".
- Contact details: email `sarapukdee@gmail.com`, website `https://cc.amphur.in.th`.
  (The email is shown publicly on the listing.)

**About the Medical category:** Google applies its health-app policies to it. The
listing and the app say clearly that Colony Counter is a research and teaching tool,
not a medical or diagnostic device, and make no health claims. If review asks for
regulatory documents (as for medical devices) or rejects the category, change the
category to **Education**; nothing else needs to change.

### 5. App content (Policy → App content)

**Privacy policy:** `https://cc.amphur.in.th/privacy.html`

**Ads:** No, the app does not contain ads.

**App access:** All functionality is available without special access (no login).

**Content rating** (IARC questionnaire):
- Email: sarapukdee@gmail.com · Category: **All other app types** (utility/productivity/other).
- Violence, fear, sexuality, language, controlled substances, crude humour,
  gambling: **No** to all.
- Does the app allow users to interact or exchange content with other users? **No.**
- Does the app share the user's current physical location with other users? **No.**
- Does the app allow users to purchase digital goods? **No.**
- Is the app a web browser or search engine? **No.**
- Expected result: Everyone / PEGI 3 / rated for all ages.

**Target audience and content:**
- Target age group: **18 and over** only (lab staff and university students).
- Could the app unintentionally appeal to children? **No.**
- This keeps the app out of the Families programme.

**News app:** No. **COVID-19 contact tracing or status app:** No.
**Government app:** No. **Financial features:** None.

**Data safety:**
- Does your app collect or share any of the required user data types? **No.**
  (Photos, counts and sample data are processed and stored only on the device and
  never sent to you or anyone else. Exports and shares happen only when the user
  chooses a destination in the system share sheet, which Play does not count as
  collection by the app. The Android app has no internet permission.)
- Because nothing is collected, the encryption-in-transit and deletion-request
  questions do not apply. Users can delete their data in the app or by
  uninstalling it (stated in the privacy policy).
- The resulting listing label reads "No data collected" and "No data shared".

**Advertising ID:** Does your app use advertising ID? **No.**

**Health apps declaration** (required for the Medical category):
- Describe the app as a laboratory research and teaching tool that counts microbial
  colonies on agar plates.
- It does not diagnose, treat, monitor or prevent any disease, is not a medical
  device, does not connect to medical devices, and does not collect or store
  personal health information about any person.
- If the form asks you to pick health features, choose the option closest to
  "research / education" and none of the clinical options. If none fits, this is
  the point to switch the category to Education (see above).

**Camera permission:** the camera is a normal runtime permission; no special
declaration form is needed. It is used only to photograph plates and scan plate
labels (explained in the privacy policy). The app uses the system photo picker, so
there is no photos/videos permission to declare.

### 6. Testing and release
1. **Testing → Closed testing:** create a track (e.g. "Lab testers"), add tester
   emails or a Google Group, upload `app-release.aab`, add the release notes from
   `listing/*.md`, roll out. Share the opt-in link with the testers.
2. Keep at least 12 testers opted in for 14 days (personal accounts), collect
   feedback, upload fixes (each upload needs a higher version code; CI uses the
   number after `+` in `app/pubspec.yaml`, e.g. `0.5.1+6`).
3. **Production:** apply for production access when the dashboard allows it, then
   create a production release with the tested bundle. Countries: Thailand first,
   or all countries.
4. Review usually takes from a few days up to a week or two for a new app.

## Updating the store assets later
- Screenshots: rebuild the web version and capture at 360 × 640 with device pixel
  ratio 3 (1080 × 1920). Keep the order above.
- Version: update `version:` in `app/pubspec.yaml` and `kAppVersion` / `kAppBuild`
  in `app/lib/app_info.dart` together (a test checks they match).
