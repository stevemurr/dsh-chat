# ADR-001: Keep quick chat on the local DSH host

## Context

This app is a lightweight macOS surface for general questions and web research. It needs a global show/hide shortcut and a conversation without asking the user to choose a project. The existing DSH Swift SDK already provides local host discovery, authentication, session requests, and streaming conversation state.

## Decision

Use AppKit for a regular macOS app, menu bar, activating chat panel, and global shortcut, and SwiftUI for chat content. The app owns the standard application menu bar and appears in the Dock and Command-Tab, while retaining quick show/hide. Consume the public `DSHKit`, `DSHProtocol`, and `DSHSession` products from the neighboring `dsh-swift` checkout. Create standalone sessions without registering or selecting a workspace. Let DSH own the agent, model, web tools, and durable session history.

## Consequences

The app stays small and shares the host's authentication and tool configuration. A working local DSH bridge is required. Search quality and availability depend on the host. The search switch sets prompt instructions; it does not enforce a tool allowlist. The app can present host activity and user decisions but does not implement a separate web-search service or agent loop. The local package path and ad hoc signing support development; a distribution build will need a published SDK dependency and signing configuration.
