# Webex Message Threaded Stream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an SDK-owned threaded message snapshot projection and a native SwiftUI smoke window that renders a real Webex message snapshot as an indented parent/child structure.

**Architecture:** Keep `MessagesStream` as the flat canonical stream and add `MessagesThreadStream` as a projection over it. The threaded stream emits normalized snapshots with `topLevelMessageIDs` plus `threadEntryByID`, preserving O(1) lookup and arbitrary-depth parent/child traversal. The smoke app authenticates like the existing messages stream smoke, subscribes to `MessagesThreadStream`, and renders rows by recursively walking the snapshot.

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, SwiftUI, existing WebexSwiftSDK OAuth, realtime, and stream primitives.

---

### Task 1: SDK Thread Projection Tests

**Files:**
- Create: `Tests/WebexSwiftSDKTests/WebexMessageThreadStreamTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for arbitrary-depth nesting, placeholder parents, deterministic chronological order, cycle handling, metadata forwarding, and refresh delegation through a projected threaded stream.

- [ ] **Step 2: Run tests and verify red**

Run: `swift test --filter WebexMessageThreadStreamTests`

Expected: compile failure for missing `WebexMessageThreadSnapshot`, `WebexMessageThreadEntry`, or `MessagesThreadStream`.

### Task 2: SDK Thread Projection Implementation

**Files:**
- Create: `Sources/WebexSwiftSDK/Streams/WebexMessageThreadStream.swift`
- Modify: `Sources/WebexSwiftSDK/Streams/WebexAPIStreams.swift`

- [ ] **Step 1: Implement public thread types**

Add `WebexMessageThreadEntry`, `WebexMessageThreadSnapshot`, and `MessagesThreadStream`.

- [ ] **Step 2: Implement snapshot builder**

Build entries from flat `WebexStreamSnapshot<WebexMessage>`, materialize placeholder parents, compute `effectiveCreated`, sort IDs chronologically, and break self-parent/cycle links deterministically.

- [ ] **Step 3: Add API convenience**

Add `MessagesAPI.threadedStream(params:pageLimit:)` that wraps the existing flat `MessagesAPI.stream(params:pageLimit:)`.

- [ ] **Step 4: Run tests and verify green**

Run: `swift test --filter WebexMessageThreadStreamTests`

Expected: all new SDK thread projection tests pass.

### Task 3: Threaded Smoke Window

**Files:**
- Create: `Examples/WebexMessagesThreadedStreamWindowSmoke/Package.swift`
- Create: `Examples/WebexMessagesThreadedStreamWindowSmoke/README.md`
- Create: `Examples/WebexMessagesThreadedStreamWindowSmoke/Sources/WebexMessagesThreadedStreamWindowSmoke/main.swift`
- Create: `Examples/WebexMessagesThreadedStreamWindowSmoke/Tests/WebexMessagesThreadedStreamWindowSmokeTests/ThreadedMessageRowModelTests.swift`

- [ ] **Step 1: Write failing smoke row tests**

Add tests that convert a `WebexMessageThreadSnapshot` into display rows with depth and placeholder parent rows.

- [ ] **Step 2: Run tests and verify red**

Run: `swift test` from `Examples/WebexMessagesThreadedStreamWindowSmoke`.

Expected: compile failure until the smoke row model exists.

- [ ] **Step 3: Implement the SwiftUI smoke**

Build a native SwiftUI window that authenticates, creates `client.messages.threadedStream`, refreshes from realtime triggers, and renders a list with indentation based on thread depth.

- [ ] **Step 4: Run smoke package tests and build**

Run from `Examples/WebexMessagesThreadedStreamWindowSmoke`:

```bash
swift test
swift build
```

Expected: tests and build pass.

### Task 4: Final Verification

**Files:**
- No new files.

- [ ] **Step 1: Run package verification**

Run at repository root:

```bash
swift test
git diff --check
```

Expected: root tests pass and diff check reports no whitespace errors.

- [ ] **Step 2: Report result**

Summarize the SDK API, smoke executable path, and verification results.
