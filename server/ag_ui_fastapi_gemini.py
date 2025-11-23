import os

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.requests import Request
from fastapi.responses import Response, StreamingResponse
from http import HTTPStatus
from pydantic import BaseModel, ValidationError

from pydantic_ai import Agent, RunContext
from pydantic_ai.ui import StateDeps, SSE_CONTENT_TYPE
from pydantic_ai.ui.ag_ui import AGUIAdapter
# Optional: AG-UI custom/state events would require returning ToolReturn with metadata.
# To maintain compatibility with older pydantic-ai versions, we avoid ToolReturn here.
## from ag_ui.core import CustomEvent, EventType, StateSnapshotEvent


# Load environment variables from .env file
# Expected variables:
#   GEMINI_API_KEY   - Google Gemini API key
load_dotenv()


class DocumentState(BaseModel):
    """Shared document state synchronized with the frontend via AG-UI."""

    document: str = ""
    frontend_tools: list[dict] = []


def system_instructions(ctx: RunContext[StateDeps[DocumentState]]) -> str:
    base = "You are a helpful assistant."
    if ctx.deps.state.frontend_tools:
        import json
        tools_json = json.dumps(ctx.deps.state.frontend_tools, indent=2)
        base += (
            f"\n\nThe user has defined the following tools that can be executed on the frontend.\n"
            f"To execute one of these, use the `execute_frontend_tool` tool with the exact name and arguments.\n"
            f"Available Frontend Tools:\n{tools_json}"
        )
    return base


# Initialize the Pydantic AI agent with Gemini backend
# Pydantic AI uses the provider prefix `google:gemini-*` for Gemini models.
# Ensure GEMINI_API_KEY is set in your .env file.
agent = Agent(
    "google-gla:gemini-2.5-flash",  # adjust model name if needed per pydantic-ai docs
    instructions=system_instructions,
    deps_type=StateDeps[DocumentState],
)


@agent.tool
async def sync_state_with_frontend(ctx: RunContext[StateDeps[DocumentState]]) -> str:
    """Compatibility tool: in older pydantic-ai, return plain values instead of ToolReturn."""
    # In newer versions, you can emit AG-UI StateSnapshotEvent via ToolReturn metadata.
    # Here we simply return a confirmation string.
    return f"State length: {len(ctx.deps.state.document)}"


@agent.tool
async def execute_frontend_tool(ctx: RunContext[StateDeps[DocumentState]], tool_name: str, args: dict) -> str:
    """
    Execute a tool that is defined on the frontend.
    
    Args:
        tool_name: The name of the tool to execute (must match one of the available frontend tools).
        args: A dictionary of arguments to pass to the tool.
    """
    return f"Frontend tool '{tool_name}' execution requested with args: {args}"


@agent.tool_plain
async def send_counter_events() -> str:
    """Compatibility tool: return plain string instead of custom AG-UI events."""
    return "Counter events not emitted (compat mode)"


@agent.tool_plain
async def get_weather(location: str) -> str:
    """Get the weather for a location."""
    return f"The weather in {location} is sunny."



app = FastAPI(title="Pydantic AI + AG-UI + Gemini (FastAPI)")

# Enable CORS for local dev (adjust origins for production)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "*",  # consider restricting to specific origins like "http://localhost:5173"
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.post("/ag-ui")
async def run_agent(request: Request) -> Response:
    """AG-UI endpoint: accepts RunAgentInput, streams AG-UI events back to the client."""

    # Force SSE streaming regardless of the client's Accept header so the
    # frontend always receives incremental updates instead of buffered JSON.
    accept = SSE_CONTENT_TYPE
    body = await request.body()

    try:
        run_input = AGUIAdapter.build_run_input(body)
    except ValidationError as e:
        return Response(
            content=e.json(),
            media_type="application/json",
            status_code=HTTPStatus.UNPROCESSABLE_ENTITY,
        )

    # Build StateDeps from AG-UI state to satisfy Pydantic AI StateHandler protocol
    # See error: State is provided but `deps` of type `NoneType` does not implement the `StateHandler` protocol
    doc_state = DocumentState()
    try:
        state_val = getattr(run_input, 'state', None)
        if isinstance(state_val, dict):
            doc_state = DocumentState(**state_val)
        elif isinstance(state_val, DocumentState):
            doc_state = state_val
        elif state_val is not None:
            # Attempt pydantic validation if it's another BaseModel or mapping
            doc_state = DocumentState.model_validate(state_val)
    except Exception:
        # Fallback to default empty state if validation fails
        doc_state = DocumentState()

    deps = StateDeps(doc_state)

    adapter = AGUIAdapter(agent=agent, run_input=run_input, accept=accept)
    event_stream = adapter.run_stream(deps=deps)
    encoded_stream = adapter.encode_stream(event_stream)

    return StreamingResponse(encoded_stream, media_type=accept)


# To run this server:
#   1. Create a .env file with GEMINI_API_KEY=your_key
#   2. Install dependencies (see docs/ag-ui.md)
#   3. Run: uvicorn server.ag_ui_fastapi_gemini:app --host 0.0.0.0 --port 8000
