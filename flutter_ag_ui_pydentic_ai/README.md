# flutter_ag_ui_pydentic_ai

Flutter client for chatting with the existing Pydantic AI agent served by FastAPI.

## Chat with your agent

This app includes a chat screen at `lib/chat_page.dart` that streams responses
from the backend endpoint implemented in `server/ag_ui_fastapi_gemini.py`.

### Prereqs

- Start the FastAPI server (adjust host/port as needed):

```bash
uvicorn server.ag_ui_fastapi_gemini:app --host 0.0.0.0 --port 8000
```

- In `lib/chat_page.dart`, set `baseUrl` to point to your server, e.g. a LAN IP:

```
String baseUrl = 'http://192.168.1.10:8000/ag-ui';
```

Notes:
- On a physical device, `localhost` will not work. Use your computer's LAN IP.
- On iOS, plain HTTP to LAN may be blocked by App Transport Security (ATS). For
	development, either use HTTPS via a tunnel (e.g. ngrok) or add a temporary ATS
	exception.

### Run

```bash
flutter pub get
flutter run
```

## How it works

The chat page sends a POST to `/ag-ui` with Accept `application/jsonl` and parses
streamed JSONL events (TEXT_MESSAGE_START, TEXT_MESSAGE_CONTENT, TEXT_MESSAGE_END)
to render incremental assistant output.
