---
name: godot-remote-executor
description: |
  Execute GDScript code on a running Godot editor or game runtime via the Hastur broker-server HTTP API. Use this skill whenever the user wants to manipulate a Godot editor or running game remotely — creating/modifying scenes, adjusting node properties, running editor operations, inspecting project state, querying live game runtime state (scene tree, physics, FPS, input, variables), or any task that requires interacting with a live Godot instance. The broker-server supports two executor types: "editor" (the editor plugin) and "game" (a GameExecutor autoload running in the game process). Target the game runtime by specifying `type: "game"` in execute requests. Trigger this skill when the user mentions Godot, Godot editor, GDScript execution, scene manipulation, node operations, game runtime inspection, live game state, or any task involving controlling a Godot project remotely, even if they don't explicitly mention "broker" or "remote execution." Also use when the user asks to inspect, query, or modify anything in their Godot project while the editor or game is running.
---

# Godot Remote Executor

This skill enables you to execute arbitrary GDScript code on a running Godot editor or game runtime instance through the Hastur broker-server. The broker-server acts as a bridge: you send HTTP requests to it, and it forwards the code to a connected Hastur Executor (editor plugin or game runtime) via TCP.

Executors have a `type` field: `"editor"` for the editor plugin, `"game"` for the GameExecutor autoload running in the game process. Use `type: "game"` to target the live game runtime — useful for inspecting runtime state, scene tree, physics, FPS, input, and variables during gameplay.

## Prerequisites

Before you begin, you need two things from the user:

1. **Auth token** — The broker-server requires a Bearer token for authentication. Ask the user for it if not provided. It was printed to stdout when the broker-server started.
2. **Base URL** — Defaults to `http://localhost:5302`. The user may specify a different host/port.

Store these for the duration of the conversation:
- `HASTUR_AUTH_TOKEN` — the Bearer token
- `HASTUR_BASE_URL` — defaults to `http://localhost:5302`

## Step 0: Read GDScript Syntax Reference (Critical)

Before writing any GDScript code, read the GDScript syntax reference to avoid compilation errors. GDScript has Python-like indentation-based syntax but significant differences in typing, built-in types, and conventions.

Read this file first:
- `references/gdscript-syntax/gdscript_basics.rst.txt` — The core language reference (~2900 lines). Covers syntax, types, control flow, functions, classes, signals, exports, and all language constructs.

This is the single most important thing you can do to reduce errors. GDScript has many subtle differences from Python:
- Uses `:=` for type inference (not `:`)
- `var x: int` for typed variables
- `func` not `def`
- Indentation matters (tabs, not spaces)
- `@onready`, `@export`, `@tool` annotations
- Built-in types: `Vector2`, `Vector3`, `Color`, `Dictionary`, `Array`, etc.
- String formatting with `%` operator or `format()` method
- `match` instead of `switch`
- No list comprehensions (use `Array.map()` / `Array.filter()`)
- `for x in range(n)` or `for x in array`
- Signals declared with `signal` keyword
- `preload()` and `load()` for resources

For @GDScript built-in functions and annotations, read:
- `references/gdscript-syntax/class_@gdscript.rst.txt` — @GDScript annotation and function reference

For global scope functions (print, push_error, etc.), read:
- `references/gdscript-syntax/class_@globalscope.rst.txt` — @GlobalScope constants and functions

For code style conventions, read:
- `references/gdscript-syntax/gdscript_styleguide.rst.txt` — official style guide

## Step 1: Discover Connected Executors

First, check which Godot executors are connected to the broker-server. Run:

```bash
curl -s -H "Authorization: Bearer HASTUR_AUTH_TOKEN" HASTUR_BASE_URL/api/executors
```

The response looks like:
```json
{
  "success": true,
  "data": [
    {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "project_name": "my-game",
      "project_path": "C:/Users/dev/projects/my-game",
      "editor_pid": 12345,
      "plugin_version": "0.1",
      "editor_version": "4.6.0",
      "supported_languages": ["gdscript"],
      "connected_at": "2026-03-28T10:00:00.000Z",
      "status": "connected",
      "type": "editor"
    },
    {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "project_name": "my-game",
      "project_path": "C:/Users/dev/projects/my-game",
      "editor_pid": 67890,
      "plugin_version": "0.1",
      "editor_version": "4.6.0",
      "supported_languages": ["gdscript"],
      "connected_at": "2026-03-28T10:01:00.000Z",
      "status": "connected",
      "type": "game"
    }
  ]
}
```

Each executor has a `type` field: `"editor"` or `"game"`. Note the `id` and `type` for targeting specific executors.

## Step 1.5: Game Runtime Not Available — Auto-Recovery

When the user's task requires targeting the game runtime (`type: "game"`) but no game executor appears in `/api/executors`, and an editor executor **is** connected, follow this recovery flow before reporting failure. This is a common situation — the user simply hasn't started the game or hasn't added the GameExecutor autoload yet.

### Recovery Steps

**1. Check if the game is currently running** — Execute code on the editor to inspect the game process state:

```gdscript
var ei = executeContext.editor_plugin.get_editor_interface()
var is_playing = ei.is_playing_scene()
executeContext.output("is_playing", str(is_playing))
```

**2. Check if `game_executor.gd` is registered as an Autoload** — Read the `[autoload]` section from the project's `project.godot` file. There is no runtime API to list registered autoloads. The `project.godot` file is located at the project root and contains autoload entries like:

```ini
[autoload]

GameExecutor="*uid://7yjc3ixh2laf"
```

Look for an entry containing `game_executor` or `GameExecutor`.

**3. Ask the user before taking action** — Based on the diagnostics above:

- **If the game is not running AND the autoload is missing:** Tell the user both issues and ask what they'd like to do:
  > "No game runtime is connected. The game is not currently running, and `game_executor.gd` is not registered as an Autoload. Would you like me to:\n1. Add `game_executor.gd` as an Autoload and then start the game\n2. Just add the Autoload (you'll start the game yourself)\n3. Just start the game (but it won't connect without the Autoload)"

- **If the game is not running but the autoload IS configured:** Ask:
  > "No game runtime is connected. The GameExecutor autoload is configured, but the game isn't running. Would you like me to start the game from the editor?"

- **If the game IS running but no game executor appeared:** The game might still be starting up. Wait a few seconds and re-check `/api/executors`. If it still doesn't appear, the autoload might be missing — ask the user:
  > "The game appears to be running but no game executor connected. The GameExecutor autoload may not be registered. Would you like me to add it to the project settings? (You'll need to restart the game afterwards.)"

**4. Execute user-approved actions** — Only after the user confirms:

- **To add an Autoload**, use `executeContext.editor_plugin.add_autoload_singleton()`. For example, to add GameExecutor:
  ```gdscript
  executeContext.editor_plugin.add_autoload_singleton("GameExecutor", "res://addons/hasturoperationgd/game_executor.gd")
  executeContext.output("result", "done")
  ```

- **To remove an Autoload**, use `executeContext.editor_plugin.remove_autoload_singleton()`. For example, to remove GameExecutor:
  ```gdscript
  executeContext.editor_plugin.remove_autoload_singleton("GameExecutor")
  executeContext.output("result", "done")
  ```

  Both methods update `project.godot` automatically. No need to manually modify project settings or call `ProjectSettings.save()`.

- **To start the game**, execute on the editor:
  ```gdscript
  var ei = executeContext.editor_plugin.get_editor_interface()
  ei.play_main_scene()
  ```
  Or trigger via the menu bar's Debug menu if more control is needed.

  - **To stop the game:**
  ```gdscript
  var ei = executeContext.editor_plugin.get_editor_interface()
  ei.stop_playing_scene()
  ```

### Important: Always Ask First

Never start the game or modify project settings without the user's explicit approval. These are significant actions that can disrupt the user's workflow. Present the situation clearly and let the user decide.

## Step 2: Execute Code

Send GDScript code to a connected editor via POST request:

```bash
curl -s -X POST \
  -H "Authorization: Bearer HASTUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"code": "<GDScript code here>", "executor_id": "<executor id>"}' \
  HASTUR_BASE_URL/api/execute
```

### Targeting an Executor

You can identify the target executor in three ways (provide exactly one):
- `executor_id` — exact match, most reliable
- `project_name` — fuzzy substring match on the project name
- `project_path` — fuzzy substring match on the project path

When only one executor is connected, `project_name` is convenient. When multiple executors are connected, use `executor_id` to be precise.

### Filtering by Type

Add `"type": "editor"` or `"type": "game"` to the request body to restrict the executor search to a specific type:

```bash
curl -s -X POST \
  -H "Authorization: Bearer HASTUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"code": "executeContext.output(\"fps\", str(Engine.get_frames_per_second()))", "project_name": "my-game", "type": "game"}' \
  HASTUR_BASE_URL/api/execute
```

This is useful when both an editor and a game executor are connected for the same project — use `type: "game"` to target the live game process, or `type: "editor"` to target the editor.

### Execution Modes

The Hastur Executor supports two modes (for both editor and game executors), determined automatically by whether the code contains `extends`:

**Snippet mode** (no `extends` keyword): Code is automatically wrapped in a `@tool extends RefCounted` class with a `run()` method. The `executeContext` variable is available as an `ExecutionContext` object with an `output(key, value)` method for returning structured results.

```gdscript
var node = get_tree().current_scene
executeContext.output("scene_name", node.name)
executeContext.output("child_count", str(node.get_child_count()))
```

**Full class mode** (contains `extends` keyword): Code must define a `func execute(executeContext):` method. Useful when you need to extend a specific type.

```gdscript
extends Node

func execute(executeContext):
    var root = get_tree().root
    executeContext.output("viewport_size", str(root.get_visible_rect().size))
```

### Understanding the Response

```json
{
  "success": true,
  "data": {
    "request_id": "uuid",
    "compile_success": true,
    "compile_error": "",
    "run_success": true,
    "run_error": "",
    "outputs": [["key1", "value1"], ["key2", "value2"]]
  }
}
```

- `compile_success` — whether the code compiled
- `compile_error` — error message if compilation failed
- `run_success` — whether the code ran without errors
- `run_error` — runtime error message
- `outputs` — array of `[key, value]` pairs collected via `executeContext.output()`

## Step 3: Handle Errors

### Compilation Errors

If `compile_success` is false, read the `compile_error` message. Common causes:
- Syntax errors (wrong indentation, missing colons, Python-style syntax that doesn't work in GDScript)
- Type mismatches
- Undefined variables or functions

Re-read the GDScript syntax reference if you encounter repeated compilation errors. The most common mistakes are:
- Using spaces instead of tabs for indentation
- Using `def` instead of `func`
- Using Python-style string formatting (`f"..."`) instead of GDScript's `%s` or `format()`
- Using `True`/`False` instead of `true`/`false`
- Using `None` instead of `null`
- Forgetting `:` after `func`, `if`, `for`, `while`, `class`, `enum` declarations

### Runtime Errors

If `compile_success` is true but `run_success` is false, check `run_error`. The code compiled but crashed during execution. Outputs collected before the crash are still available in `outputs`.

### Error Return Values from Godot APIs

Many Godot API methods return an `Error` enum value (an integer) instead of throwing exceptions. **You must always check whether the return value equals `OK` (0).** If it is not `OK`, the call failed silently and the operation did not succeed.

For example, `ResourceSaver.save()` returns `Error` — returning `31` means `ERR_INVALID_PARAMETER`, not success. Never assume the call succeeded without checking.

When you get a non-`OK` error code, look it up in the Error enum documentation to understand what went wrong. Read the Error enum section in `godot-docs/classes/class_@globalscope.rst.txt` (search for `enum Error`). The full list of error codes and their meanings:

| Value | Constant | Meaning |
|-------|----------|---------|
| 0 | OK | Success |
| 1 | FAILED | Generic error |
| 2 | ERR_UNAVAILABLE | Unavailable |
| 3 | ERR_UNCONFIGURED | Unconfigured |
| 4 | ERR_UNAUTHORIZED | Unauthorized |
| 5 | ERR_PARAMETER_RANGE_ERROR | Parameter range error |
| 6 | ERR_OUT_OF_MEMORY | Out of memory |
| 7 | ERR_FILE_NOT_FOUND | File not found |
| 8 | ERR_FILE_BAD_DRIVE | Bad drive |
| 9 | ERR_FILE_BAD_PATH | Bad path |
| 10 | ERR_FILE_NO_PERMISSION | No permission |
| 11 | ERR_FILE_ALREADY_IN_USE | File already in use |
| 12 | ERR_FILE_CANT_OPEN | Can't open file |
| 13 | ERR_FILE_CANT_WRITE | Can't write file |
| 14 | ERR_FILE_CANT_READ | Can't read file |
| 15 | ERR_FILE_UNRECOGNIZED | Unrecognized file |
| 16 | ERR_FILE_CORRUPT | Corrupt file |
| 17 | ERR_FILE_MISSING_DEPENDENCIES | Missing dependencies |
| 18 | ERR_FILE_EOF | End of file |
| 19 | ERR_CANT_OPEN | Can't open |
| 20 | ERR_CANT_CREATE | Can't create |
| 21 | ERR_QUERY_FAILED | Query failed |
| 22 | ERR_ALREADY_IN_USE | Already in use |
| 23 | ERR_LOCKED | Locked |
| 24 | ERR_TIMEOUT | Timeout |
| 25 | ERR_CANT_CONNECT | Can't connect |
| 26 | ERR_CANT_RESOLVE | Can't resolve |
| 27 | ERR_CONNECTION_ERROR | Connection error |
| 28 | ERR_CANT_ACQUIRE_RESOURCE | Can't acquire resource |
| 29 | ERR_CANT_FORK | Can't fork process |
| 30 | ERR_INVALID_DATA | Invalid data |
| 31 | ERR_INVALID_PARAMETER | Invalid parameter |
| 32 | ERR_ALREADY_EXISTS | Already exists |
| 33 | ERR_DOES_NOT_EXIST | Does not exist |
| 34 | ERR_DATABASE_CANT_READ | Database read error |
| 35 | ERR_DATABASE_CANT_WRITE | Database write error |
| 36 | ERR_COMPILATION_FAILED | Compilation failed |
| 37 | ERR_METHOD_NOT_FOUND | Method not found |
| 38 | ERR_LINK_FAILED | Linking failed |
| 39 | ERR_SCRIPT_FAILED | Script failed |
| 40 | ERR_CYCLIC_LINK | Cyclic link |
| 41 | ERR_INVALID_DECLARATION | Invalid declaration |
| 42 | ERR_DUPLICATE_SYMBOL | Duplicate symbol |
| 43 | ERR_PARSE_ERROR | Parse error |
| 44 | ERR_BUSY | Busy |
| 45 | ERR_SKIP | Skip |
| 46 | ERR_HELP | Help (internal) |
| 47 | ERR_BUG | Bug (implementation issue) |
| 48 | ERR_PRINTER_ON_FIRE | Printer on fire (easter egg) |

Common Godot methods that return `Error`: `ResourceSaver.save()`, `ResourceLoader.load()`, `DirAccess.make_dir_recursive()`, `FileAccess.open()`, `Node.get_tree().change_scene_to_file()`, etc.

Always output the error code and its meaning via `executeContext.output()` so you can diagnose issues.

### No Matching Executor (HTTP 404)

The executor_id/project_name/project_path didn't match any connected editor. Run `GET /api/executors` again to see what's available.

### Timeout (HTTP 504)

Code execution exceeded the 30-second limit. This has two common causes:

**Cause 1: Debugger paused the game (most common for game executor).** When code on the game executor triggers a runtime error, Godot's debugger automatically pauses the game process. The game freezes, the request times out, and all subsequent game executor requests also hang. **Before investigating anything else, check whether "Ignore Error Breaks" is enabled** — see the "Before Executing on Game: Enable Ignore Error Breaks" section below. If the game is already paused, use the "Continue" button on the debugger toolbar (see "Controlling Game Pause/Resume from the Editor") to unfreeze it first, then enable Ignore Error Breaks.

**Cause 2: Code genuinely takes too long.** The code has an infinite loop or heavy computation. Simplify the code or break it into smaller steps.

## Step 4: Look Up Godot APIs as Needed

When you need to use Godot classes, methods, or properties that you're not fully confident about, look them up in the reference docs:

- **Class API reference**: Read `references/godot-docs/classes/class_<ClassName>.rst.txt` — for any Godot class (e.g., `class_node3d.rst.txt` for Node3D, `class_label3d.rst.txt` for Label3D)
- **Tutorials and guides**: Browse `references/godot-docs/tutorials/` for topic-specific guides
- **Scripting guides**: `references/godot-docs/tutorials/scripting/` for general scripting patterns

### Common Class File Naming Convention

Class files are named `class_<lowercaseclassname>.rst.txt`. For example:
- `class_node.rst.txt` — Node
- `class_node2d.rst.txt` — Node2D
- `class_node3d.rst.txt` — Node3D
- `class_control.rst.txt` — Control
- `class_button.rst.txt` — Button
- `class_label.rst.txt` — Label
- `class_sprite2d.rst.txt` — AnimatedSprite2D
- `class_camera3d.rst.txt` — Camera3D
- `class_ridigidbody3d.rst.txt` — RigidBody3D
- `class_inputevent.rst.txt` — InputEvent
- `class_resouce.rst.txt` — Resource
- `class_packedscene.rst.txt` — PackedScene
- `class_timer.rst.txt` — Timer
- `class_area2d.rst.txt` — Area2D
- `class_pathfollow2d.rst.txt` — PathFollow2D

Note: The `@` prefix classes are special:
- `class_@gdscript.rst.txt` — GDScript annotations and functions
- `class_@globalscope.rst.txt` — Global functions and constants

## Workflow Pattern

For complex tasks, follow this iterative pattern:

1. **Discover** — Query `/api/executors` to find available executors (note their `type`: editor or game)
2. **Read reference** — If unsure about GDScript syntax, read the syntax docs first
3. **Look up API** — If unsure about a Godot class/method, read the relevant class reference
4. **Write code** — Compose the GDScript snippet, using `executeContext.output()` to return results
5. **Execute** — Send via `POST /api/execute`
6. **Check result** — Parse the response, check compile_success and run_success
7. **Handle errors** — If errors, fix and retry
8. **Use outputs** — Extract information from the outputs array to inform next steps

## Important Notes

### Execution Context

The `executeContext` object has these characteristics:
- `output(key: String, value: String)` — call this to return data. Both arguments should be strings. The value is truncated if it exceeds the configured max char length (default 800).
- Output values that exceed the limit are truncated with a warning prefix
- `editor_plugin` — holds a reference to the `EditorPlugin` instance (the Hastur plugin itself). This is only available when executing on the **editor** executor; it is `null` on the game executor. Use this to call EditorPlugin APIs such as `get_editor_interface()`, `get_undo_redo()`, `make_visible()`, etc.

### Prefer Triggering Editor Menu Actions (Important)

When the user's request corresponds to an action that exists in the Godot editor's GUI menus (Scene, Project, Debug, Editor, Help), you should prefer triggering the menu item's signal directly rather than calling the underlying API manually. This simulates real human interaction with the GUI and ensures all editor-side side effects (undo/redo registration, dirty flag clearing, UI updates, dialog prompts, etc.) are handled correctly.

For example, to save the scene, don't call `ResourceSaver.save()` or `EditorInterface.save_scene()` — instead, emit the `id_pressed` signal on the Scene menu's PopupMenu. The menu bar is accessible via:

```gdscript
var ei = executeContext.editor_plugin.get_editor_interface()
var menu_bar = ei.get_base_control().get_child(0).get_child(0).get_child(0)
var scene_menu = menu_bar.get_child(0) as PopupMenu
var save_item_id = scene_menu.get_item_id(6)
scene_menu.id_pressed.emit(save_item_id)
```

The editor's top-level menu structure:
- `menu_bar.get_child(0)` — **Scene** menu (New Scene, Save Scene, Save Scene As, Export As, Undo, Redo, etc.)
- `menu_bar.get_child(1)` — **Project** menu (Project Settings, Export, Tools, etc.)
- `menu_bar.get_child(2)` — **Debug** menu (Remote Debug, Visible Collision Shapes, etc.)
- `menu_bar.get_child(3)` — **Editor** menu (Editor Settings, Layout, Screenshot, etc.)
- `menu_bar.get_child(4)` — **Help** menu (Documentation, About, etc.)

To discover available menu items, iterate the PopupMenu's items:
```gdscript
for i in range(scene_menu.item_count):
    executeContext.output("menu_item", str(i) + ": " + scene_menu.get_item_text(i) + " (id=" + str(scene_menu.get_item_id(i)) + ")")
```

Then trigger the desired action by emitting `id_pressed` with the item's id.

This approach is preferred because:
- It goes through the same code path as when a human clicks the menu, ensuring full editor state consistency
- It handles edge cases the API might not (e.g., prompting to save before closing, confirming overwrites)
- It avoids silent failures where API calls return error codes without clear feedback

Use this pattern for: saving scenes, opening scenes, undo/redo, export, closing scenes, and any other action available through the editor menus.

### Editor Plugin Environment

Code runs inside the Godot editor as a `@tool` script. This means:
- You have access to the editor's scene tree via `EditorScript` or `get_tree()`
- `EditorInterface` is available via `executeContext.editor_plugin.get_editor_interface()` (preferred) or as a singleton via `Engine.get_singleton('EditorInterface')`
- `executeContext.editor_plugin` provides the EditorPlugin instance itself for calling plugin-level APIs
- The code runs on the main thread — avoid infinite loops or heavy computation
- Changes to nodes/scenes are reflected in real-time in the editor

### Game Runtime Environment

When targeting a game executor (`type: "game"`), code runs inside the running game process via the `GameExecutor` autoload. This means:
- You have full access to the live game scene tree via `get_tree()`
- All game nodes, runtime variables, physics state, and input are accessible
- `EditorInterface` is **not available** (this is the game process, not the editor)
- The code runs on the main thread — avoid infinite loops or heavy computation
- Use this for inspecting live game state: FPS, scene tree, node properties, signals, physics bodies, etc.

Example game runtime queries:
```gdscript
executeContext.output("fps", str(Engine.get_frames_per_second()))
executeContext.output("current_scene", str(get_tree().current_scene.name))
executeContext.output("child_count", str(get_tree().current_scene.get_child_count()))
```

### Before Executing on Game: Enable Ignore Error Breaks (Critical)

When you execute GDScript code on the game executor and that code causes a runtime error (invalid method call, null reference, etc.), Godot's built-in debugger will **automatically pause the entire game process**. This causes the executor request to time out (HTTP 504 after 30 seconds) because the game is frozen and cannot respond. Even worse, all subsequent game executor requests will also time out until the debugger is resumed.

To prevent this, **always check and enable "Ignore Error Breaks" on the editor before executing code on the game executor.** This tells the debugger not to pause on script errors, allowing the game to continue running even if your code has bugs.

**Always check before each game executor call**, not just the first one — the setting can be reset between sessions or by other editor actions.

Execute the following on the **editor** executor before your game executor call. This code first checks whether Ignore Error Breaks is already enabled, and only toggles it if needed:

```gdscript
var ei = executeContext.editor_plugin.get_editor_interface()
var base = ei.get_base_control()

var stack = [[base, 0]]
var toolbar = null
while stack.size() > 0:
	var pair = stack.pop_back()
	var node = pair[0]
	var depth = pair[1]
	if toolbar != null:
		break
	if depth > 25:
		continue
	if node.name.find("Stack Trace") != -1 and node.get_class() == "VBoxContainer":
		for child in node.get_children():
			if child is HBoxContainer:
				toolbar = child
				break
	for child in node.get_children():
		stack.append([child, depth + 1])

if toolbar != null:
	for child in toolbar.get_children():
		if child is Button and child.tooltip_text == "Ignore Error Breaks":
			if child.button_pressed:
				executeContext.output("ignore_error_breaks", "already_enabled")
			else:
				child.set_toggle_mode(true)
				child.set_pressed(true)
				child.emit_signal("pressed")
				executeContext.output("ignore_error_breaks", "enabled")
			break
else:
	executeContext.output("ignore_error_breaks", "toolbar not found")
```

**Why the complexity?** The "Ignore Error Breaks" button is a plain `Button` with `toggle_mode = false`. Simply calling `emit_signal("pressed")` or `set_pressed(true)` does nothing — the button ignores these calls when toggle mode is off. You must call `set_toggle_mode(true)` first, then `set_pressed(true)`, then `emit_signal("pressed")`.

The code above dynamically discovers the button by walking the editor's scene tree, so it won't break if node paths change between sessions.

### Controlling Game Pause/Resume from the Editor

The editor's debugger toolbar provides buttons to control the game's execution state. These are useful when the game is paused by the debugger and you need to resume it.

The debugger toolbar lives inside the "Stack Trace" tab's `HBoxContainer`. The key buttons (identified by their `tooltip_text`):

| Tooltip | Function |
|---------|----------|
| Continue | Resume the game after a debugger pause |
| Step Into | Step into the next function call |
| Step Over | Step over the next line |
| Step Out | Step out of the current function |
| Break | Pause the game at the next opportunity |
| Skip Breakpoints | Skip all breakpoints |
| Ignore Error Breaks | Don't pause on script errors |

To resume a paused game, find the "Continue" button and emit `pressed`:

```gdscript
var ei = executeContext.editor_plugin.get_editor_interface()
var base = ei.get_base_control()

var stack = [[base, 0]]
var toolbar = null
while stack.size() > 0:
	var pair = stack.pop_back()
	var node = pair[0]
	var depth = pair[1]
	if toolbar != null:
		break
	if depth > 25:
		continue
	if node.name.find("Stack Trace") != -1 and node.get_class() == "VBoxContainer":
		for child in node.get_children():
			if child is HBoxContainer:
				toolbar = child
				break
	for child in node.get_children():
		stack.append([child, depth + 1])

if toolbar != null:
	for child in toolbar.get_children():
		if child is Button and child.tooltip_text == "Continue":
			child.emit_signal("pressed")
			executeContext.output("continue", "pressed")
			break
```

The "Continue" button is a non-toggle button, so `emit_signal("pressed")` works directly — no need for the `set_toggle_mode` workaround.

### Snippet Mode Details

In snippet mode, your code is wrapped like this:
```gdscript
@tool
extends RefCounted

var executeContext

func run():
    <your code here, indented with tabs>
```

This means:
- You're inside a `RefCounted` instance, not a `Node`
- To access the scene tree, use `Engine.get_main_loop()` to get the `SceneTree`
- To access editor functionality, use `executeContext.editor_plugin` to get the EditorPlugin instance, or `EditorInterface` via singleton
- `executeContext` is set as a property before `run()` is called

### Accessing EditorPlugin from Snippets

You can access the EditorPlugin instance directly via `executeContext.editor_plugin`:

```gdscript
var plugin = executeContext.editor_plugin
var ei = plugin.get_editor_interface()
executeContext.output("current_scene", str(ei.get_current_scene().name))
```

Common EditorPlugin APIs available through this reference:
- `get_editor_interface()` — returns EditorInterface singleton
- `get_undo_redo()` — returns the UndoRedo manager
- `make_visible(bool)` — show/hide the plugin's dock
- `get_plugin_name()` — the plugin's display name

### Accessing the Scene Tree from Snippets

Since snippets extend `RefCounted` (not `Node`), you need to access the scene tree differently:

```gdscript
var tree = Engine.get_main_loop() as SceneTree
var root = tree.root
var edited_scene = tree.edited_scene_root
```

Or use the EditorPlugin reference:

```gdscript
var ei = executeContext.editor_plugin.get_editor_interface()
var edited_scene = ei.get_current_scene()
```

### Output Best Practices

- Convert all values to strings before passing to `output()`: `str(value)`
- Use descriptive keys: `"node_count"`, `"scene_path"`, `"error_message"`
- For large outputs, be aware of the character limit per value
- If you need to return structured data, consider JSON-encoding it: `JSON.stringify(data)`

## Reference Files

### GDScript Syntax (read before writing code)
- `references/gdscript-syntax/gdscript_basics.rst.txt` — Core language reference
- `references/gdscript-syntax/gdscript_advanced.rst.txt` — Advanced features
- `references/gdscript-syntax/class_@gdscript.rst.txt` — @GDScript built-in functions/annotations
- `references/gdscript-syntax/class_@globalscope.rst.txt` — Global scope functions/constants
- `references/gdscript-syntax/gdscript_styleguide.rst.txt` — Style guide

### Godot API Reference (read as needed)
- `references/godot-docs/classes/class_*.rst.txt` — 1066 class reference files
- `references/godot-docs/tutorials/` — Guides and tutorials by topic
