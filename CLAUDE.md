# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Firestorm is a third-party viewer (client) for Second Life and OpenSim, derived from Linden Lab's open-source viewer (LGPL). Most of the code is upstream Linden Lab (LL) code; Firestorm changes are layered on top and must stay mergeable with future LL updates. `master` is the nightly branch; official release branches are named `Firestorm_X.Y.Z`. Viewer version lives in `indra/newview/VIEWER_VERSION.txt`.

## Building (Linux)

Full guide: `doc/building_linux.md` (also `building_windows.md`, `building_macos.md`). Reference platform is Ubuntu 22.04, GCC 11, x86_64 only.

Prerequisites (once):
- `pip install -r requirements.txt` (installs `autobuild`, ideally inside a `.venv`)
- Clone `https://github.com/FirestormViewer/fs-build-variables.git` next to this repo and `export AUTOBUILD_VARIABLES_FILE=$HOME/src/fs-build-variables/variables`

Configure and build:
```
autobuild configure -A 64 -c ReleaseFS_open                     # first time; fetches prebuilt 3rd-party packages
autobuild configure -A 64 -c ReleaseFS_open -- -DLL_TESTS:BOOL=TRUE --chan="MyBuild"
autobuild build -A 64 -c ReleaseFS_open                         # repeat the same switches as configure
```
- Self-compilers use the `*_open` configs (no KDU, no FMOD). `ReleaseOS` / `RelWithDebInfoOS` enable OpenSim support; `RelWithDebInfoFS_open` adds debug info.
- Switches after `--` are handled by `scripts/configure_firestorm.sh` (see its `showUsage`: `--clean`, `--opensim`, `--havok`, `--fmodstudio`, `--kdu`, `--ninja`, `--jobs N`, `--vscode` for compile_commands.json, `--no-package`, etc.).
- Output goes to `build-linux-x86_64/`; the runnable viewer is under `build-linux-x86_64/newview/packaged/` (`./firestorm`).
- `autobuild installables edit ...` (e.g. for a local FMOD package) modifies `autobuild.xml`; do not commit that change.

## Tests

Tests are off by default (`LL_TESTS` in `indra/cmake/Variables.cmake`); configure with `-DLL_TESTS:BOOL=TRUE` to enable. They use the TUT framework (`indra/test/`) and are declared per library in its `CMakeLists.txt` via `LL_ADD_PROJECT_UNIT_TESTS` / `LL_ADD_INTEGRATION_TEST` (`indra/cmake/LLAddBuildTest.cmake`). Test sources live in `<lib>/tests/<name>_test.cpp`.

Each test is its own CMake target named `PROJECT_<lib>_TEST_<name>`, run automatically as a post-build step. To build/run a single test, from the build directory:
```
cd build-linux-x86_64 && make PROJECT_llcommon_TEST_bitpack     # or ninja ... if configured with --ninja
```
`<lib>_tests` builds all tests of one library.

## Lint / formatting

pre-commit hooks (`.pre-commit-config.yaml`, run with `pre-commit run --all-files`): license/copyright headers, LLSD validity, no trigraphs, final newline, spaces not tabs, XML well-formedness, no trailing whitespace. Indentation is 4 spaces (`.editorconfig`); `.clang-format` exists but the codebase is not globally reformatted — don't reformat untouched code (it pollutes LL merges).

## Mandatory convention: FS comment tags (from CONTRIBUTING.md)

When modifying **upstream LL code**, preserve the original code in comments and wrap the change in tags so mergers can compare with future LL updates:
```c++
// <FS:YI> [FIRE-999] Fix the buggy code
// int buggy_code = TRUE;
bool fixed_code = true;
// </FS:YI>
```
Single-line change shorthand: `bool x = false; // </FS:YI> [FIRE-23456] reason`. Plain `<FS>` or short author tags (`<FS:Ansariel>`, `<FS:Zi>`, ...) are used throughout. If the code is already inside an FS block, no new block is needed. Tags not required in Firestorm-created files (`fs*`), RLVa code (`rlv*`, marked `// [RLVa:KB]`), or OpenSim-only code. Commit message headers reference the JIRA ticket: `[FIRE-12345] Short description`.

## Architecture

All source is under `indra/`, a CMake tree of layered `ll*` libraries consumed by the viewer app in `indra/newview/`:
- Foundation: `llcommon` (LLSD data type, logging `LL_INFOS/LL_WARNS`, singletons, event pumps, coroutines), `llmath`, `llfilesystem`, `llxml`.
- Networking: `llmessage` (Second Life UDP message system, template in `scripts/messages/`), `llcorehttp` (HTTP/capabilities).
- Rendering/platform: `llrender` (OpenGL; shaders in `indra/newview/app_settings/shaders/`), `llwindow`, `llimage`/`llimagej2coj`/`llkdu` (JPEG2000).
- Domain: `llprimitive`, `llinventory`, `llappearance`, `llcharacter`, `llaudio`, `llwebrtc` (voice), `llplugin` + `media_plugins` (CEF/VLC out-of-process media).
- UI: `llui` is a widget toolkit driven by XUI XML. Floaters/panels are C++ classes (`llfloater*.cpp`, `llpanel*.cpp`, Firestorm ones `fsfloater*`/`fspanel*`) registered with `LLFloaterReg` and bound to XML layouts.

`indra/newview/` conventions:
- Upstream files are `ll*`; Firestorm additions are `fs*`, `ao*`, `rlv*` etc. Prefer putting new Firestorm features in new `fs*` files to minimise diffs in `ll*` files.
- UI layouts: `skins/<skin>/xui/<lang>/*.xml`. `skins/default/xui/en/` is the base; other skins (`firestorm`, `ansastorm`, `starlight`, `vintage`, ...) and languages override only the files/strings they change. Skins are registered in `skins/skins.xml`; colors in `skins/<skin>/colors.xml` (+ `themes/`), images in `textures/textures.xml`.
- Debug settings (persistent preferences, `gSavedSettings`): declared in `app_settings/settings.xml` (LL) and `settings_firestorm.xml`; per-account in `settings_per_account.xml`. A new setting must be declared there before use.
- OpenSim-specific code is guarded by `#ifdef OPENSIM` (OpenSim and Havok are mutually exclusive build options).
- Packaging logic for all platforms: `indra/newview/viewer_manifest.py`.
