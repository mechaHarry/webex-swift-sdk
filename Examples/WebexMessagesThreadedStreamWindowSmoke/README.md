# Webex Messages Threaded Stream Window Smoke

This smoke opens a native macOS window backed by `MessagesThreadStream`. It lists a real message snapshot as an indented parent/child structure, including placeholder parent rows when a reply points at a parent message that is not present in the current snapshot. Top-level thread groups are shown newest first; replies inside each thread are shown oldest to newest so the latest reply lands at the bottom of that thread.

When realtime reports that a message was deleted and the current stream can match that deleted ID to a message it already knows about, the in-memory threaded snapshot keeps a local tombstone row. Tombstones are not persisted; a clean app start rebuilds from the public REST response and loses prior tombstones.

## Run

```sh
cd Examples/WebexMessagesThreadedStreamWindowSmoke
export WEBEX_CLIENT_ID="..."
export WEBEX_CLIENT_SECRET="..."
export WEBEX_ROOM_ID="..."
swift run WebexMessagesThreadedStreamWindowSmoke
```

Optional environment:

- `WEBEX_REDIRECT_URI`, default `http://127.0.0.1:8282/oauth/callback`
- `WEBEX_SCOPES`, default `spark:all spark:kms`
- `WEBEX_MESSAGES_PAGE_SIZE`, default `25`
- `WEBEX_MESSAGES_STREAM_PAGE_LIMIT`, default `1`
- `WEBEX_KEYCHAIN_SERVICE`, default `com.webex.swift-sdk.messages-threaded-stream-window-smoke`

Use **Refresh** to manually refresh the snapshot and **Next Page** to load the next REST page when Webex reports one. Realtime message create, update, and delete triggers automatically refresh the same stream.
