# API Patterns — Current (2025)

Known-good patterns for LangGraph, LlamaIndex, and Anthropic APIs.
Check dates — these frameworks move fast.

---

## LangGraph (≥ 0.2)

### State definition
```python
from typing import Annotated
from typing_extensions import TypedDict
from langgraph.graph.message import add_messages

class State(TypedDict):
    messages: Annotated[list, add_messages]  # ALWAYS use add_messages for message lists
    status: str
```

### Conditional edges (current pattern — no mapping dict)
```python
# ✅ Current
builder.add_conditional_edges("node", router_fn)
# router_fn returns a node name string or END

# ❌ Old — mapping dict form was deprecated
builder.add_conditional_edges("node", router_fn, {"a": "node_a", "b": END})
```

### Command (route + update in one node)
```python
from langgraph.types import Command
from typing import Literal

def supervisor(state: State) -> Command[Literal["worker", "__end__"]]:
    # ... decide
    return Command(goto="worker", update={"status": "running"})
```

### Send (parallel fan-out)
```python
from langgraph.types import Send

def fan_out(state: State) -> list[Send]:
    return [Send("worker", {"item": x}) for x in state["items"]]

builder.add_conditional_edges("splitter", fan_out, ["worker"])
```

### Compile with checkpointer
```python
from langgraph.checkpoint.memory import MemorySaver
memory = MemorySaver()
graph = builder.compile(checkpointer=memory)
config = {"configurable": {"thread_id": "thread-1"}}
result = graph.invoke(input, config=config)
```

### Human-in-the-loop
```python
from langgraph.types import interrupt

def gate_node(state: State) -> dict:
    decision = interrupt({"question": "Approve?", "data": state["draft"]})
    return {"approved": decision == "yes"}

graph = builder.compile(checkpointer=memory, interrupt_before=["gate_node"])
# Resume:
graph.invoke(Command(resume="yes"), config=config)
```

### Streaming
```python
async for event in graph.astream_events(input, version="v2"):
    if event["event"] == "on_chat_model_stream":
        print(event["data"]["chunk"].content, end="", flush=True)
```

---

## LlamaIndex Workflows (≥ 0.10)

### Basic structure
```python
from llama_index.core.workflow import (
    Workflow, step, Event, StartEvent, StopEvent, Context
)

class MyEvent(Event):
    data: str

class MyWorkflow(Workflow):
    @step
    async def handle(self, ev: StartEvent) -> MyEvent:
        return MyEvent(data=ev.input)

    @step
    async def finish(self, ev: MyEvent) -> StopEvent:
        return StopEvent(result=ev.data)

wf = MyWorkflow(timeout=60, verbose=True)
result = await wf.run(input="hello")
```

### Parallel gather
```python
@step
async def collector(self, ctx: Context, ev: PartialEvent) -> StopEvent | None:
    results = ctx.collect_events(ev, [PartialEvent] * self.n)
    if results is None:
        return None  # waiting for more
    return StopEvent(result=merge(results))
```

### Agent as a step
```python
from llama_index.core.agent import FunctionCallingAgent
from llama_index.core.tools import FunctionTool

@step
async def agent_step(self, ev: StartEvent) -> StopEvent:
    agent = FunctionCallingAgent.from_tools(tools=[...], llm=self.llm)
    resp = await agent.achat(ev.input)
    return StopEvent(result=str(resp))
```

### Visualization
```python
wf.draw_all_possible_flows("flows.html")   # requires pyvis
```

---

## Anthropic API (claude-sonnet-4-6 / claude-opus-4-6)

### Basic message
```python
import anthropic
client = anthropic.Anthropic()

msg = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}],
)
text = msg.content[0].text
```

### Tool use
```python
tools = [{
    "name": "search",
    "description": "Search the web",
    "input_schema": {
        "type": "object",
        "properties": {"query": {"type": "string"}},
        "required": ["query"],
    }
}]

msg = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    tools=tools,
    messages=[{"role": "user", "content": "Search for LangGraph examples"}],
)

for block in msg.content:
    if block.type == "tool_use":
        print(block.name, block.input)
```

### Structured output (JSON mode via prompt)
```python
system = "Respond with valid JSON only. No markdown. No explanation."
msg = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=512,
    system=system,
    messages=[{"role": "user", "content": "Rate this: {'score': <float>}"}],
)
import json
data = json.loads(msg.content[0].text)
```

### Streaming
```python
with client.messages.stream(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}],
) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)
```

---

## Common Version Gotchas

| Library | Gotcha | Fix |
|---------|--------|-----|
| langgraph | `add_conditional_edges` mapping dict removed in 0.2 | Remove the dict, return node name directly |
| langgraph | `Command` requires `Literal` type annotation on return | Always annotate `-> Command[Literal["a","b"]]` |
| langchain | `ChatOpenAI` moved from `langchain.chat_models` | Use `from langchain_openai import ChatOpenAI` |
| langchain | `.run()` removed | Use `.invoke()` |
| llama_index | `GPTVectorStoreIndex` renamed to `VectorStoreIndex` | Update import |
| llama_index | Workflows require `async def` steps | All `@step` methods must be `async` |
| anthropic | `claude-opus-4-5` → `claude-opus-4-6` latest | Check `anthropic.HUMAN_PROMPT` removed too |
