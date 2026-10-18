# DSH Chat

A small native macOS chat window for quick questions, powered by the local [DSH Swift SDK](https://github.com/stevemurr/dsh-swift). Open it from the menu bar or a global shortcut, ask a question, and hide it when you are done. The compact, keyboard-first surface takes inspiration from Raycast AI Chat.

## Run

Requires macOS 15 or later, Swift 6 tooling, and a checkout of `dsh-swift` beside this repository. Start a local DSH host with its local bridge enabled, then build and launch:

```sh
Scripts/build-app.sh --release --run
```

The app bundle is written to `dist/DSH Chat.app` and ad hoc signed for local use. Use `--debug` for a development build, or omit `--run` to build without launching. The package can also be checked with `swift build`.

The SDK discovers the host from `~/.dsh/mobile/dev-auth.json`. Set `DSH_HOME` to use another DSH directory; its handoff file is `$DSH_HOME/mobile/dev-auth.json`. The build script forwards this variable when launching a fresh app with `--run`. Finder launches use the default location unless the app's launch environment sets `DSH_HOME`. The host supplies authentication, models, and tools. This app does not install or start DSH.

## Everyday use

| Shortcut | Action |
| --- | --- |
| Option Space | Show or hide chat; change it in Settings |
| Return | Send a message |
| Shift Return | Insert a line break |
| Escape or Command W | Hide chat |
| Command N | Start a new chat |
| Shift Command H | Show or hide the conversation sidebar |
| Command comma | Open Settings |

No folder or workspace selection is required. Questions use a standalone host session. Web search is on by default and asks the host to search when helpful. The switch sets a prompt preference and does not change the host's tool allowlist. Turning it off asks the model to answer without browsing. Search availability and behavior depend on the host's tools and model.

Recent conversations appear in the left sidebar. Search by title or choose a chat to resume it. The sidebar stays open when changing conversations or starting a new chat, and remembers whether you last left it expanded or collapsed.

Answers use the available conversation width with readable Markdown, headings, code blocks, and wrapping table cells. Scrollbars overlay the content and fade when idle. The entire app follows macOS light or dark appearance automatically, including open conversations, the composer, and Settings.

Thinking and tool activity share compact, expandable cards. A spinner marks work in progress, a checkmark marks completed activity, and an error indicator marks a failed tool call. Expand a card to inspect its details.

The window hides when focus moves to another app unless you pin it. Hiding keeps the conversation running. Use **Stop** to cancel an active response. Recent chat references and titles are saved in app preferences; messages remain on the DSH host. Removing an entry from this app's history does not delete its host session.

## Development

The Swift package builds the `DSHChat` executable against the local `../dsh-swift` package. `Scripts/build-app.sh` adds the macOS bundle metadata and icon. DSH Chat runs as a regular macOS app with its own application menus, Dock icon, and Command-Tab entry. Activating it from the Dock or Command-Tab reveals the chat window; the menu bar shortcut and global hotkey remain available.

The bundle is intended for local development. Distribution signing and notarization are not configured. See [the host boundary decision](docs/architecture/ADR-001-local-host.md) for the responsibility split between the app and SDK.

Run `swift test` for the isolated conversation and Markdown checks. Set `DSH_CHAT_LIVE_CHECK=1` to also verify local authentication and the model catalog. The separate `DSH_CHAT_LIVE_QUESTION=1` check creates one real session and asks a public web question, using your host's model and tools. It stops if the host requests a decision.

Set `DSH_CHAT_PREVIEW_PATH` to an absolute PNG path when running `PresentationTests` to render the native surface without displaying a desktop window.
