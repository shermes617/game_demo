---
name: godot-screenshot
description: |
  Take screenshots of the Godot editor window or the running game window via the Hastur broker-server remote executor. Use this skill whenever the user asks to capture, save, or take a screenshot of the Godot editor or game runtime — including phrases like "截图", "screenshot", "capture screen", "save a picture of the editor/game", "snap the viewport", or any request involving saving the visual state of a running Godot instance. Also trigger when the user wants to automate periodic screenshots or compare visual output across runs. This skill depends on the godot-remote-executor skill — always load that skill first to understand the executor API, auth requirements, and code execution mechanics.
---

# Godot Screenshot

This skill captures screenshots from a running Godot editor or game instance and saves them as PNG files. It depends on the **godot-remote-executor** skill — load it first so you understand how to discover executors, authenticate, and execute GDScript code.

## Prerequisites

Before using this skill, you must have:

1. **godot-remote-executor skill loaded** — understand the executor API, snippet mode, auth tokens, and error handling
2. **Auth token and base URL** — same credentials used by godot-remote-executor
3. **At least one connected executor** — editor for editor screenshots, game for game screenshots

## How Viewport Capture Works

The Godot API for capturing screenshots relies on the viewport's texture. The correct approach is:

```gdscript
var tree = Engine.get_main_loop() as SceneTree
var img = tree.root.get_texture().get_image()
```

This grabs the root `Viewport`'s texture, converts it to an `Image`, and then you can call `img.save_png(path)` to write it to disk.

**Why `tree.root` and not `get_viewport()`?** Because in snippet mode your code runs inside a `RefCounted` instance (not a `Node`). The `get_viewport()` convenience method only exists on `Node` — it is NOT available on `RefCounted`, `EditorInterface`, or other non-Node objects. Always use `Engine.get_main_loop()` to get the `SceneTree`, then access `tree.root` to get the root `Viewport`.

Similarly, `EditorInterface` does not have a `get_viewport()` method either. The universal approach that works in all contexts is `Engine.get_main_loop().root`.

## Screenshot Workflows

### Editor Screenshot

This captures the entire Godot editor window.

**Preconditions:** An editor executor (`type: "editor"`) must be connected.

```gdscript
var tree = Engine.get_main_loop() as SceneTree
var img = tree.root.get_texture().get_image()

var dict = Time.get_datetime_dict_from_system()
var date_str = "%04d-%02d-%02d" % [dict["year"], dict["month"], dict["day"]]
var time_str = "%02d-%02d-%02d" % [dict["hour"], dict["minute"], dict["second"]]

var rel_path = ".temp/" + date_str + "-" + time_str + "-editor.png"
var abs_path = ProjectSettings.globalize_path("res://" + rel_path)

var dir_abs = ProjectSettings.globalize_path("res://.temp")
if not DirAccess.dir_exists_absolute(dir_abs):
	DirAccess.make_dir_recursive_absolute(dir_abs)

var err = img.save_png(abs_path)
executeContext.output("path", rel_path)
executeContext.output("result", "OK" if err == OK else "Error: " + str(err))
```

### Game Screenshot

This captures the running game window.

**Preconditions:** A game executor (`type: "game"`) must be connected. The game must already be running with the GameExecutor autoload registered.

```gdscript
var tree = Engine.get_main_loop() as SceneTree
var img = tree.root.get_texture().get_image()

var dict = Time.get_datetime_dict_from_system()
var date_str = "%04d-%02d-%02d" % [dict["year"], dict["month"], dict["day"]]
var time_str = "%02d-%02d-%02d" % [dict["hour"], dict["minute"], dict["second"]]

var rel_path = ".temp/" + date_str + "-" + time_str + "-game.png"
var abs_path = ProjectSettings.globalize_path("res://" + rel_path)

var dir_abs = ProjectSettings.globalize_path("res://.temp")
if not DirAccess.dir_exists_absolute(dir_abs):
	DirAccess.make_dir_recursive_absolute(dir_abs)

var err = img.save_png(abs_path)
executeContext.output("path", rel_path)
executeContext.output("result", "OK" if err == OK else "Error: " + str(err))
```

**If no game executor is available**, you may need to launch the game first. See the "Launching the Game" section below.

## Complete Workflow: Editor + Game Screenshots

When the user wants both screenshots, follow this sequence:

1. **Discover executors** — `GET /api/executors` to find connected editor and game executors
2. **Take editor screenshot** — execute the editor screenshot code on the editor executor
3. **Check for game executor** — if no game executor is present, ask the user if they want to launch the game
4. **Launch game if needed** — see "Launching the Game" below
5. **Wait for game executor** — poll `/api/executors` every few seconds until a `type: "game"` executor appears
6. **Enable "Ignore Error Breaks"** — see "Debugger Pitfalls" below; do this proactively before executing code on the game executor
7. **Take game screenshot** — execute the game screenshot code on the game executor

## Launching the Game

If the game is not running and the user wants it started, execute on the **editor** executor:

```gdscript
var ei = Engine.get_singleton('EditorInterface')
ei.play_current_scene()
executeContext.output("result", "done")
```

After launching, wait ~5 seconds for the game process to start and the GameExecutor autoload to connect to the broker-server. Poll `GET /api/executors` until a `type: "game"` executor appears.

Other launch options:
- `ei.play_main_scene()` — play the project's main scene
- `ei.play_custom_scene("res://path/to/scene.tscn")` — play a specific scene

## Debugger Pitfalls (Critical)

When executing code on the game executor, runtime errors will trigger Godot's built-in debugger, which **automatically pauses the game process**. This causes the executor request to time out (HTTP 504 after 30 seconds) because the game is frozen and cannot complete the execution.

### Symptoms

- `POST /api/execute` returns HTTP 504 timeout when targeting the game executor
- The game window appears frozen
- The editor's debugger panel shows the game is paused at a breakpoint/error

### Prevention: Enable "Ignore Error Breaks"

Before executing any code on the game executor, proactively enable the "Ignore Error Breaks" setting. This prevents the debugger from pausing on script errors. Execute the following on the **editor** executor:

```gdscript
var tree = Engine.get_main_loop() as SceneTree
var stack_trace_toolbar_path = tree.root.get_node("/root/@EditorNode@18094/@Panel@14/@VBoxContainer@15/DockHSplitMain/@VBoxContainer@28/DockVSplitCenter/@EditorBottomPanel@7422/Debugger/@TabContainer@8422/Session 1/@TabContainer@8425/Stack Trace/@HBoxContainer@8426")
var ignore_btn = stack_trace_toolbar_path.get_node("@Button@8432") as Button
ignore_btn.set_toggle_mode(true)
ignore_btn.set_pressed(true)
ignore_btn.emit_signal("pressed")
executeContext.output("ignore_error_breaks", "enabled")
```

**Important caveat about this button:**

The "Ignore Error Breaks" button (`@Button@8432`) is a plain `Button` with `toggle_mode` set to `false` by default. This means:

- `emit_signal("pressed")` does NOT toggle its visual/functional state
- `set_pressed(true)` is silently ignored because `toggle_mode` is false
- `set_pressed_no_signal(true)` is also silently ignored

The only reliable way to activate it programmatically is:
1. **First** call `set_toggle_mode(true)` to enable toggle behavior
2. **Then** call `set_pressed(true)` to set the pressed state
3. **Then** call `emit_signal("pressed")` to trigger the internal handler

Without step 1, steps 2 and 3 have no effect on the button state.

**Note on node paths:** The hardcoded node paths in the debugger toolbar (e.g., `@EditorBottomPanel@7422`, `@TabContainer@8422`) contain auto-generated numeric suffixes that may change between Godot sessions or versions. If the path stops working, you need to re-discover the debugger nodes by walking the editor's scene tree. The general path structure is:

```
/root/@EditorNode@.../@Panel@.../@VBoxContainer@.../DockHSplitMain/@VBoxContainer@.../DockVSplitCenter/@EditorBottomPanel@.../Debugger/@TabContainer@.../Session 1/@TabContainer@.../Stack Trace/@HBoxContainer@...
```

To re-discover the path, search for the "Stack Trace" tab and its toolbar by walking the tree looking for nodes named "Stack Trace" or buttons with tooltip "Ignore Error Breaks":

```gdscript
var tree = Engine.get_main_loop() as SceneTree
var ei = Engine.get_singleton('EditorInterface')
var base = ei.get_base_control()

var stack = [[base, 0]]
var results = []
while stack.size() > 0:
	var pair = stack.pop_back()
	var node = pair[0]
	var depth = pair[1]
	if depth > 25:
		continue
	if node.name.find("Stack Trace") != -1:
		results.append(str(node.get_path()) + " (" + node.get_class() + ")")
	for child in node.get_children():
		stack.append([child, depth + 1])
for r in results:
	executeContext.output("stack_trace_node", r)
```

Then look for the `@HBoxContainer` child of the "Stack Trace" node — that's the toolbar. Enumerate its children to find buttons and their tooltips:

```gdscript
var toolbar = tree.root.get_node("<path to Stack Trace's HBoxContainer>")
for child in toolbar.get_children():
	if child is BaseButton:
		executeContext.output("button", child.name + " tooltip=" + child.tooltip_text)
```

Match by tooltip text: "Ignore Error Breaks" for the ignore button, "Continue" for the continue button.

### Recovery: Unpause a Frozen Game

If the game is already paused by the debugger, you need to:
1. Click "Continue" on the debugger toolbar (via the editor executor)
2. Then enable "Ignore Error Breaks" as described above

The "Continue" button is in the same toolbar. After discovering the toolbar path (see above), find the button with tooltip "Continue" and activate it:

```gdscript
var toolbar = tree.root.get_node("<path to Stack Trace's HBoxContainer>")
var continue_btn = toolbar.get_node("@Button@...")  # the one with tooltip "Continue"
continue_btn.emit_signal("pressed")
```

The Continue button is a normal (non-toggle) button, so `emit_signal("pressed")` works correctly.

## Saving Files

### Directory Creation

Always ensure the target directory exists before saving. The `.temp/` directory may not exist in the project:

```gdscript
var dir_abs = ProjectSettings.globalize_path("res://.temp")
if not DirAccess.dir_exists_absolute(dir_abs):
	DirAccess.make_dir_recursive_absolute(dir_abs)
```

### Path Resolution

Use `ProjectSettings.globalize_path("res://...")` to convert a `res://` path to an absolute filesystem path that `Image.save_png()` can write to. GDScript's `Image.save_png()` requires an absolute path.

### File Naming Convention

Use the pattern `<date>-<time>-<target>.png` for filenames:
- Date format: `YYYY-MM-DD`
- Time format: `HH-MM-SS`
- Target: `editor` or `game`

Example: `.temp/2026-04-10-21-45-11-editor.png`

Use `Time.get_datetime_dict_from_system()` to get the current date and time:

```gdscript
var dict = Time.get_datetime_dict_from_system()
var date_str = "%04d-%02d-%02d" % [dict["year"], dict["month"], dict["day"]]
var time_str = "%02d-%02d-%02d" % [dict["hour"], dict["minute"], dict["second"]]
```

### Always Check save_png Return Value

`Image.save_png()` returns an `Error` enum. Always check it:

```gdscript
var err = img.save_png(abs_path)
executeContext.output("result", "OK" if err == OK else "Error: " + str(err))
```

Error code 7 (`ERR_FILE_NOT_FOUND`) typically means the directory doesn't exist. Error code 9 (`ERR_FILE_BAD_PATH`) means the path is malformed. See the Error enum table in the godot-remote-executor skill for the full list.

## Pitfalls Summary

| Pitfall | Cause | Solution |
|---------|-------|----------|
| `get_viewport()` not found | Snippet mode runs in `RefCounted`, not `Node` | Use `Engine.get_main_loop().root` |
| `EditorInterface.get_viewport()` not found | `EditorInterface` has no `get_viewport()` method | Use `Engine.get_main_loop().root` |
| Game screenshot request times out (504) | Debugger auto-paused the game on a runtime error | Enable "Ignore Error Breaks" before executing game code |
| "Ignore Error Breaks" button won't activate | Button has `toggle_mode=false`, `set_pressed` is ignored | Call `set_toggle_mode(true)` first, then `set_pressed(true)`, then `emit_signal("pressed")` |
| Game not paused but executor not responding | Game might be in a tight loop or crashed | Stop and restart the game via editor |
| `save_png` returns error 7 | Target directory doesn't exist | Create directory with `DirAccess.make_dir_recursive_absolute()` |
| Node paths stop working | Auto-generated node names change between sessions | Re-discover by walking the scene tree and matching by name/tooltip |
