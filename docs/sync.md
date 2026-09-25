# iPhone, iPad and sync

**What:** Checkpoint runs on iPhone and iPad as well as the Mac, and your plans can follow you between them.
**Why:** plans are often made at a desk and worked through somewhere else, on a test device, in a meeting or on the train.

## The iOS app

Same plans, same features. On iPhone:

- The ticket bar sits at the bottom of the plan list: paste a key or link, pick Dev or QA, tap ✨.
  Run options (Quick/Deep, template, scenarios) live in the slider icon at the end of the field.
- The research feed rises as a sheet while a plan is written; it closes and the plan opens when done.
- Inside a plan, **Plan / Research / Chat** sits on top, **ⓘ** opens the ticket details, and everything
  else (export, re-run, pin, tags, reminders, archive) is under **⋯**.
- **Attach Evidence** in a task's ⋯ menu takes a photo, picks from your library, or picks a file.
- Export uses the share sheet, so a plan can go to Mail, Slack, Files or AirDrop.

iPad gets a split view like the Mac, with the ticket bar across the top.

**Mac only:** reading a local codebase for scenarios, and the floating mini checklist.

## Sync

Settings → **Sync** (also offered during onboarding) has three choices.

### Sync folder: free, works in every build

Pick a folder and Checkpoint keeps its data there; whatever syncs that folder (iCloud Drive, Dropbox,
a network share) carries it to your other devices.

1. **Mac:** Settings → Sync → *Sync folder*. The picker opens in iCloud Drive; choose it (or any folder)
   and Checkpoint makes a `Checkpoint` folder inside.
2. **iPhone / iPad:** Settings → Sync → *Sync folder* → Browse → iCloud Drive → the same `Checkpoint` folder.

Inside, each plan, folder and smart folder is its own small JSON file, deleted items are listed in
`deleted.json`, and evidence files sit under `evidence/`. Checkpoint checks for changes every 20 seconds
and whenever you edit something; **Sync Now** forces a pass.

**When the same plan changes on two devices,** the most recent edit wins for that plan. Different
plans never conflict. Folders and smart folders take the copy in the sync folder.

### iCloud: the App Store build

iCloud sync goes straight through your iCloud account, with nothing to pick. It uses CloudKit, which needs
the app to be signed by a paid Apple Developer team with an iCloud container, so it shows as
*coming soon* in builds you make yourself. Use a sync folder in iCloud Drive there instead.

### What syncs

Plans (tasks, verdicts, notes, tags, pins, reminders, timer, chat), folders, smart folders and evidence
files. **API keys and tracker sign-ins never sync.** They stay in each device's Keychain, so connect
each device once.

## Turning on iCloud (for maintainers)

The CloudKit code ships in every build but only runs when the build names a container.
To switch it on in a signed build:

1. In the Apple Developer portal, create an iCloud container, e.g. `iCloud.com.josephshenton.checkpoint`.
2. In `project.yml`, for **both** targets:
   - set `DEVELOPMENT_TEAM` to your team;
   - set the build setting `CHECKPOINT_CLOUDKIT_CONTAINER: iCloud.com.josephshenton.checkpoint`;
   - add the entitlements:

     ```yaml
     com.apple.developer.icloud-container-identifiers: [iCloud.com.josephshenton.checkpoint]
     com.apple.developer.icloud-services: [CloudKit]
     ```

     plus `aps-environment: development` on iOS (`com.apple.developer.aps-environment` on macOS) so
     changes arrive by push. The iOS target also needs `UIBackgroundModes: [remote-notification]`
     in its Info.plist properties.
3. `xcodegen generate`, then build signed (`./build.sh --sign …` on the Mac; Xcode for iOS).

Leave the container setting empty and the app never touches CloudKit, because creating a container
without the entitlement would crash.
