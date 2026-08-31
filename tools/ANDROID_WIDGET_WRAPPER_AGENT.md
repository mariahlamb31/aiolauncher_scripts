# Android widget wrapper workflow for coding agents

Use this workflow when the user provides an emulator or device with an app installed and asks for an AIO Launcher script wrapper around one of that app's Android widgets. The Lua dumper does not need to be installed: AIO Launcher exposes a file-based inspector that is driven directly through ADB. Its explicit activity alias requires the privileged system permission `android.permission.DUMP`, which is granted to the ADB shell but not ordinary apps.

## Preconditions

- A single ADB device is connected, or its serial is supplied with `-s SERIAL`.
- The target app and an AIO Launcher build containing the protected inspector endpoint are installed.
- The device is unlocked. Keep it visible because Android may ask for widget binding permission or open the provider's configuration activity.
- Run commands from the root of this repository. Store disposable artifacts outside tracked script directories, for example under `/tmp`.

Start with a preflight. It verifies the inspector endpoint and records the installed AIO and target-app versions plus the snapshot schema reported by the device:

```sh
tools/android-widget-inspector.sh doctor com.example.app /tmp/example-widget
```

Use the reported AIO version for `aio_version` when developing against unreleased APIs. Do not assume that a stable version such as `7.5.0` is satisfied by an older beta build.

## Capture the widget

1. List every provider belonging to the requested package:

   ```sh
   tools/android-widget-inspector.sh list com.example.app /tmp/example-widget
   ```

   Read `providers.json`. If it contains multiple plausible providers and the user's request does not disambiguate them, compare labels and dimensions; ask the user only when that still changes the product being wrapped. Preserve the returned `user_id` when the same provider exists in more than one Android profile.

2. Bind, configure, render, and capture the selected provider. The default is intentionally unbounded because forcing a small size can hide most of a virtualized collection:

   ```sh
   tools/android-widget-inspector.sh start \
       com.example.app/com.example.app.ExampleWidgetProvider \
       - - /tmp/example-widget/states/01-populated
   ```

   Pass a size such as `4x2` only when the wrapper intentionally depends on that size. Replace the second `-` with the `user_id` from `providers.json` when needed. Complete any Android confirmation or provider configuration UI on the device. The command waits for a stable render and pulls:

   - `snapshot.json`: ordered machine-readable nodes, environment and package metadata;
   - `preview.png`: what the underlying Android widget rendered;
   - `status.json`: operation state and diagnostics.

   A collection summary is available in `snapshot.json.collections`. Check `total_count`, the visible position range and both `can_scroll_*` flags. If more rows exist, page the live collection and save each materialized range:

   ```sh
   tools/android-widget-inspector.sh scroll node_7 forward \
       /tmp/example-widget/pages/populated-scroll-1
   ```

   The handle may be a collection container or any node belonging to that collection. Scroll captures are discovery pages, not separate semantic states; keep them outside `states/` unless the wrapper will actually receive that scrolled layout.

   Do not discard a node only because `visible` is false. Some providers attach a working click target to a zero-sized, clipped, or temporarily hidden RemoteViews child. Use the PNG and a safe live click to decide whether it represents a user-visible action.

3. Build a state suite instead of relying on the first successful capture. Use ordered names because suite replay follows lexical order:

   ```sh
   # Change the underlying app/widget to an empty source, then:
   tools/android-widget-inspector.sh save 03-empty /tmp/example-widget

   # Change it back to populated data, then:
   tools/android-widget-inspector.sh save 04-populated-again /tmp/example-widget
   ```

   At minimum cover populated, empty, and populated-after-empty states. When applicable also cover loading/error, a long or multiline item, source/list switching, every supported size, and any state revealed by a safe widget action. This is a transition test: do not capture only isolated final screens.

   A state may have an optional replay context. Pass a JSON file as the third argument to `save`; it may contain `folded` and the persisted `prefs` object:

   ```json
   { "folded": true, "prefs": { "selected_list": "work" } }
   ```

   ```sh
   tools/android-widget-inspector.sh save 05-work-list \
       /tmp/example-widget /tmp/work-list-context.json
   ```

   Without an explicit `folded` value, replay checks both expanded and folded rendering. The snapshot itself records its dimensions, so capturing states at each supported size supplies the size matrix.

   Use `click HANDLE` only for an action that is safe and necessary; never activate purchases, sends, deletes, account changes, or similarly consequential actions without explicit user direction. The click output includes `device-screen.png` and `foreground.txt`. For an external action, use `verify-click HANDLE PACKAGE ACTIVITY_SUBSTRING|-` so a merely non-empty side effect cannot pass as the right destination. For a selector or other in-widget action, use `verify-state-change HANDLE`; it fails unless the recaptured structured state changed. If an action opens the provider app, return to AIO Launcher before requesting another capture.

4. Inspect every JSON/PNG pair. Do not infer meaning from text alone. Prefer stable evidence in this order: `resource_id`, collection/item grouping, structural `path`, node `kind`, content description, nearby parent/child structure, and finally position. An empty state may omit the entire collection, so every required field and action needs a fallback that was observed in that state. Record the observed package version and capture size with the wrapper notes.

## Generate the wrapper

- Start from `tools/android-widget-wrapper.lua.template` and existing wrappers in `community/` or `samples/`.
- Use the public `widgets` module, `bridge:snapshot()` and `bridge:click_handle()`. This workflow does not use `aio_api.lua`; that file belongs to AIO Launcher's internal script generator.
- Match nodes anew inside every `on_app_widget_updated(bridge)` call. `node_N` handles and `click_target` values belong to one rendered snapshot and must never be hardcoded or persisted.
- Prefer exact `resource_id` matching. Add a path/kind fallback only when the captured widget omits resource IDs, and make missing or ambiguous fields visible as a useful unavailable/error state.
- Store only the current snapshot's `click_target` values for `on_click()`. A text node can delegate to a clickable ancestor, so click the supplied target rather than reconstructing a hierarchy name.
- Keep setup idempotent with `widgets:bound()`, persist the allocated id in `prefs`, and handle `widgets:setup()` returning `nil`. Do not pass a fixed size to `request_updates()` for a scrollable widget unless that limitation is intentional and verified.
- Treat expanded and folded output as separate actions. `show_text()` and a folded `show_lines()` row use click index `0`; expanded `show_lines()` rows use `1..N`.
- Keep the user prompt natural in any generator fixture. Put stable API contracts in docs/tests, not prompt-specific text checks or third-party-specific production validators.

## Replay and real-device verification

Run the candidate through the complete ordered state suite before installing it:

```sh
tools/android-widget-inspector.sh replay-suite \
    community/example-app-widget.lua \
    /tmp/example-widget/states \
    /tmp/example-widget/replay
```

For a single saved fixture use `replay-snapshot SCRIPT SNAPSHOT OUTPUT_DIR`. Replay rejects incomplete/synthetic snapshots and snapshots from a package other than `uses_app`; `--allow-synthetic` exists only for developing fake-runtime fixtures and must not be used to accept or rewrite a production wrapper. `replay.txt` contains `REPLAY_STATE` boundaries, the actual `widget_handles` reached by every `REPLAY_ACTION`, and `REPLAY_LONG_ACTION` records when the wrapper defines `on_long_click`. Unless a state context selects one folding mode, both expanded and folded indices are exercised. Any `ERROR:` is a runtime failure. Review every `effect=none`: it is allowed for informational rows, but is a defect for a visible action. Replay proves handle reachability, not PendingIntent semantics; use `verify-click` or `verify-state-change` for each safe real action.

Then install the single script and verify it with the real provider:

```sh
./manage-scripts.sh install community/example-app-widget.lua
```

The manager validates exact metadata, rejects hardcoded `node_N` handles, updates the single existing plain or repository-prefixed copy instead of creating another alias, and verifies the installed checksum. It refuses ambiguous duplicates; inspect them and use `install --target NAME SCRIPT`, or explicitly use `install --dedupe SCRIPT` to retain one matching copy. Use `./manage-scripts.sh validate SCRIPT` for a local preflight.

Run the exact installed bytes through the app-side runtime with a representative live snapshot, rather than accidentally smoke-testing a newer local file:

```sh
tools/android-widget-inspector.sh smoke-installed \
    community/example-app-widget.lua \
    /tmp/example-widget/states/01-populated/snapshot.json \
    /tmp/example-widget/installed-smoke
```

The smoke command also fails for a stale or duplicate installed copy, or when AIO's own Scripts discovery does not expose it as a widget with a name and `uses_app`. Check the resulting real card once on the home screen, then verify initial binding/configuration, normal refresh, populated → empty → populated transitions, every exposed click, missing fields, and at least one launcher restart. Finish by releasing the temporary inspector widget id:

```sh
tools/android-widget-inspector.sh cleanup /tmp/example-widget
```

Keep the capture artifacts out of the repository. Commit only the wrapper and any generally useful documentation or test changes.
