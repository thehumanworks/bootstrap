# Local Cua-S1 on macOS

Installed on this M3 Ultra Mac: **Cua-S1 4B 0.2, text adapter, BF16 MLX**, with a
resident decision API, an isolated browser runner and native Cua Driver 0.28.2.
No cloud inference or API key is used. Weights, dependencies and driver source
are pinned; downloaded models and runtime state live outside this repository.

## Start here

```sh
cua-local demo                 # verified three-step browser task, in the background
cua-local native-demo          # verified AppKit task with a visible purple agent cursor
cua-local doctor
```

The native demo opens a disposable test window without activating it, then
selects and clicks Continue. It checks a marker written by the button handler,
and closes its own app. It requires the Xcode command-line tools to build the
small fixture once. The browser demo starts a temporary localhost site and
closes its isolated browser after checking the completion page.

The native runner explicitly enables the **fake cursor**, uses a 350 ms glide
and 650 ms click feedback, and sends **background** accessibility actions to
an exact window. It does not automatically fall back to foreground operation.
Unsupported actions stop with an error. The overlay is shown during native
actions and cleaned up when the run ends; it does not move the real pointer.
Browser tasks use Playwright, run headlessly by default, and do not have the
native Cua cursor overlay. Add `--show-browser` to watch the isolated browser.

## What this model does

This is a **closed-option next-action model**, not a general autonomous desktop
assistant. A caller supplies the current UI, a goal and up to 26 choices. The
model ranks those choices in one forward pass; it does not invent commands,
coordinates, typed text or a complete plan. The runners reserve one choice for
“Do nothing”. Fill values must be supplied explicitly. This matches the
[official model contract](https://github.com/trycua/cua/blob/605d358a48ad938a41b384a8f23909153eb73f78/libs/cua-s1/MODEL_CARD.md).

The text adapter uses accessibility/DOM observations, so it suits small forms,
checkboxes and clear navigation. Canvas-only interfaces, arbitrary desktop
workflows and screenshot-only tasks are outside this runner's scope. Both
published adapters are downloaded, but only `text/` is enabled. A larger base
model cannot use these 4B adapters; changing models would need another evaluated
policy and integration. The 4B model already fits easily and responds quickly.

## Browser tasks

```sh
cua-local browser http://localhost:3000 \
  'Accept the terms and open the completion page' \
  --execute --max-steps 8 --success-text 'Complete'

# Optional exact field-label-to-value JSON: {"Name": "Example User"}
cua-local browser http://localhost:3000 'Fill the Name field' \
  --values /absolute/path/to/values.json --execute --max-steps 1
```

Without `--execute`, the runner observes and ranks one action only. It uses a
fresh browser profile, blocks downloads and cross-origin requests (including
CDN resources), and closes the browser on exit. It cannot use existing logins.
Supported controls are ordinary buttons, same-origin links, checkboxes and
labeled text inputs. Duplicate labels and more than 25 actionable controls
stop or exclude ambiguous actions; long inputs are rejected instead of silently
truncated. Shadow DOM, iframes and rich custom controls are not supported.
`--success-text` is an independent visible-text check, not model self-reporting;
pick text that is absent before the task and uniquely indicates success.

## Native macOS apps

Accessibility and Screen Recording are granted to **CuaDriver** on this host.
For another Mac, run `cua-driver permissions grant` and enable both in System
Settings. Inspect with `cua-local doctor`.

```sh
cua-local windows

# Substitute the exact PID and window ID listed above.
cua-local native 1234 5678 'Continue to the next page' \
  --allow-label Continue --allow-label Cancel

# Add --execute to perform the selected action once.
cua-local native 1234 5678 'Continue to the next page' \
  --allow-label Continue --allow-label Cancel --execute
```

Only explicitly allowed, enabled buttons and checkboxes supporting AXPress are
offered. The runner checks the exact window, reobserves after inference, rejects
changed state, and uses the new snapshot's element token. It runs one action
per invocation. Native typing and multi-step free-form planning are not included.
The currently published driver cannot prove its accessibility tree is complete;
the runner only acts on positively observed controls and never treats a missing
element as proof of absence.

Generic macOS clicks return `effect: "unverifiable"` from the driver even when
delivered. The runner does not retry them automatically or claim overall success.
It returns the new window state; inspect the result or verify an application
postcondition. Checkbox checks have a checked-state test. The native demo has
its own independent application marker.

## Integrate the resident model

```sh
cua-local decide ~/projects/cua-local/examples/decision.json
cua-local serve
```

`serve` loads once, reads one JSON object per stdin line and returns one JSON
result per stdout line. Send the same schema as `examples/decision.json`;
Ctrl-D exits. There is no network listener. `decide` and `serve` never execute
actions. Returned probabilities are relative rankings over supplied options,
not calibrated confidence or proof an action is appropriate.

## Reproduce and verify

```sh
mise -C ~/bootstrap run --skip-tools cua:setup
PYTHONPATH=~/projects/cua-local \
  ~/.local/share/cua-local/venv/bin/python -m pytest -q ~/projects/cua-local/tests
HF_HUB_OFFLINE=1 PYTHONPATH=~/projects/cua-local \
  ~/.local/share/cua-local/venv/bin/python ~/projects/cua-local/benchmark.py
```

Setup downloads about 9 GB of original weights, installs a private Python 3.13
environment, installs Chromium and the signed native driver if absent, and links
`~/.local/bin/cua-local`. It preserves an existing native driver, does not change
Codex configuration, and does not install a login service. `CUA_LOCAL_HOME` can
override the runtime directory. Source now lives at `~/projects/cua-local`;
`CUA_LOCAL_SOURCE` can override that location. Keep that source directory when
rerunning setup. The CLI defaults to offline Hugging Face access
after setup. Driver telemetry is disabled for this installation.

Measured on this M3 Ultra / 96 GB host on 2026-09-24:

| Check | Observed result |
| --- | --- |
| BF16 MLX memory peak | 8.91 GB on the small benchmark |
| Warm 152-token decision | 0.139 s median, five repetitions |
| Cold process model load | About 2 seconds in an initial smoke run |
| MLX versus PyTorch MPS | Same choice on 8/8 synthetic text cases; maximum probability difference 0.00336 |
| Browser model demo | Three actions, independently verified completion; about 3.1 s including model load |
| Native model demo | AppKit marker verified, overlay visible; real pointer and foreground PID unchanged |

These are smoke checks, not broad computer-use accuracy measurements. Native
accessibility observation and cursor feedback add latency beyond model inference.
The reference benchmark loads Transformers on CPU with mmap disabled before
transferring to MPS, because direct MPS loading crashed with this pinned stack.
Normal operation uses MLX and does not use that loader.

Evidence on this host is under `~/.local/share/cua-local/`: `benchmark.json`,
`browser-demo.json`, `native-demo.json`, `native-cursor.png`, and `setup.log`.
Outputs can include the observed UI; keep them local when working with private
content. The pinned revisions are in `cua_local/config.py` and dependency
versions in `requirements.lock`.

The MLX adapter bridge is local integration code. It reuses Cua's official
prompt/letter mapping and validates every LoRA tensor; it is not an upstream
claim of MLX support. Verification also passed 19 focused tests, the existing
29 bootstrap tests, Python/shell checks, task validation and an idempotent setup
rerun.

Sources: [model weights](https://huggingface.co/cua-ai/cua-s1-4b-0.2),
[reference scorer](https://github.com/trycua/cua/blob/605d358a48ad938a41b384a8f23909153eb73f78/libs/cua-s1/python/src/cua_s1/four_b.py),
[Cua Driver](https://github.com/trycua/cua/tree/605d358a48ad938a41b384a8f23909153eb73f78/libs/cua-driver).
