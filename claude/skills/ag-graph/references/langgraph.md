# LangGraph Reference

## Installation

```bash
pip install langgraph langchain-anthropic langchain-openai
# Optional: persistence
pip install langgraph-checkpoint-sqlite  # or -postgres
```

## State Design

The state is the single source of truth that flows through all nodes.

```python
from typing import Annotated, Literal
from typing_extensions import TypedDict
from langgraph.graph.message import add_messages

# Use add_messages reducer for message lists (append-only, never overwrite)
class State(TypedDict):
    messages: Annotated[list, add_messages]
    task: str
    plan: list[str]
    results: list[str]
    iteration: int
    status: Literal["running", "needs_review", "done", "failed"]
    quality_score: float
```

**Rules:**
- Always use `TypedDict` (not `BaseModel` or plain dict)
- Use `Annotated[list, add_messages]` for message history — prevents full overwrites
- For custom reducers: `Annotated[list, lambda a, b: a + b]`
- Nodes return only the fields they mutate; unchanged fields are preserved automatically

---

## Node Patterns

### LLM Node (basic)

```python
from langchain_anthropic import ChatAnthropic

llm = ChatAnthropic(model="claude-opus-4-5", temperature=0)

def agent_node(state: State) -> dict:
    response = llm.invoke(state["messages"])
    return {"messages": [response]}
```

### Tool-Calling Node

```python
from langchain_core.tools import tool
from langgraph.prebuilt import ToolNode

@tool
def search(query: str) -> str:
    """Search the web for information."""
    return "search results..."

@tool
def python_repl(code: str) -> str:
    """Execute Python code and return the output."""
    ...

tools = [search, python_repl]
tool_node = ToolNode(tools)

# Bind tools to the LLM
llm_with_tools = llm.bind_tools(tools)
```

### Supervisor Node (routes to workers)

```python
from langchain_core.messages import SystemMessage

WORKERS = ["researcher", "coder", "writer"]

def supervisor_node(state: State) -> dict:
    system = SystemMessage(content=f"""
You are a supervisor. Given the conversation, decide which worker to act next,
or output FINISH if the task is complete.
Workers: {WORKERS}
Output only the worker name or FINISH.
""")
    response = llm.invoke([system] + state["messages"])
    return {"next_worker": response.content.strip()}
```

### Conditional Router Function

```python
def route_supervisor(state: State) -> str:
    worker = state.get("next_worker", "")
    if worker == "FINISH":
        return END
    return worker  # must match a node name in the graph
```

---

## Graph Construction

### Basic Sequential Graph

```python
from langgraph.graph import StateGraph, START, END

builder = StateGraph(State)

builder.add_node("planner", planner_node)
builder.add_node("executor", executor_node)
builder.add_node("evaluator", evaluator_node)

builder.add_edge(START, "planner")
builder.add_edge("planner", "executor")
builder.add_conditional_edges(
    "evaluator",
    lambda s: "executor" if s["quality_score"] < 0.8 else END,
)
builder.add_edge("executor", "evaluator")

graph = builder.compile()
```

### Supervisor-Worker Graph (full pattern)

```python
from langgraph.graph import StateGraph, START, END

builder = StateGraph(State)
builder.add_node("supervisor", supervisor_node)
builder.add_node("researcher", researcher_node)
builder.add_node("coder", coder_node)
builder.add_node("writer", writer_node)

builder.add_edge(START, "supervisor")
builder.add_conditional_edges("supervisor", route_supervisor)
for worker in ["researcher", "coder", "writer"]:
    builder.add_edge(worker, "supervisor")  # always return to supervisor

graph = builder.compile()
```

### Parallel Fan-Out with Send

```python
from langgraph.types import Send

def fan_out(state: State) -> list[Send]:
    return [
        Send("worker", {"task": chunk, "chunk_id": i})
        for i, chunk in enumerate(state["chunks"])
    ]

builder.add_conditional_edges("splitter", fan_out, ["worker"])
```

---

## Command (Dynamic Routing + State Update)

Use `Command` when a node needs to BOTH update state AND decide the next node dynamically. Available in LangGraph ≥ 0.2.

```python
from langgraph.types import Command

def supervisor(state: State) -> Command[Literal["researcher", "coder", "__end__"]]:
    decision = llm.invoke(...)
    if decision == "DONE":
        return Command(goto=END, update={"status": "done"})
    return Command(goto=decision, update={"next_worker": decision})
```

---

## Persistence & Checkpointing

```python
from langgraph.checkpoint.sqlite import SqliteSaver

with SqliteSaver.from_conn_string("./checkpoints.db") as memory:
    graph = builder.compile(checkpointer=memory)
    config = {"configurable": {"thread_id": "session-123"}}
    result = graph.invoke({"messages": [...]}, config=config)

    # Resume from same thread_id picks up where it left off
    result2 = graph.invoke({"messages": [new_message]}, config=config)
```

---

## Human-in-the-Loop (Interrupt)

```python
from langgraph.types import interrupt

def approval_gate(state: State) -> dict:
    # Pauses the graph, sends state to UI, waits for human input
    decision = interrupt({"output": state["draft"], "prompt": "Approve this?"})
    return {"approved": decision == "yes"}

# Compile with interrupt_before/interrupt_after
graph = builder.compile(
    checkpointer=memory,
    interrupt_before=["approval_gate"],  # pause BEFORE this node runs
)
```

---

## Streaming

```python
# Stream tokens (LLM output as it generates)
for chunk in graph.stream({"messages": [...]}, stream_mode="values"):
    print(chunk)

# Stream events (node entry/exit + tokens)
async for event in graph.astream_events({"messages": [...]}, version="v2"):
    if event["event"] == "on_chat_model_stream":
        print(event["data"]["chunk"].content, end="", flush=True)
```

---

## Subgraphs

```python
# Build inner graph
inner_builder = StateGraph(InnerState)
# ... add nodes and edges
inner_graph = inner_builder.compile()

# Add as a node in the outer graph
outer_builder = StateGraph(OuterState)
outer_builder.add_node("sub_pipeline", inner_graph)
```

---

## ReAct Agent (Prebuilt)

```python
from langgraph.prebuilt import create_react_agent

agent = create_react_agent(
    model=llm,
    tools=tools,
    state_modifier="You are a helpful assistant.",
)
result = agent.invoke({"messages": [HumanMessage("What is the weather in Berlin?")]})
```

---

## Common Pitfalls

- **Never mutate state in-place** inside a node — always return a new dict with only changed keys
- **Cycles must have an exit condition** — always check `iteration` or `status` in your router
- **`add_messages` is append-only** — if you need to overwrite history, use a custom reducer
- **Thread IDs for checkpointing** — use unique, stable thread IDs per conversation session
- **`ToolNode` requires `tool_calls` in messages** — make sure LLM is called with `bind_tools`
