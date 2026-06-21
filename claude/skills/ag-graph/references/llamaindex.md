# LlamaIndex Workflow Reference

## Installation

```bash
pip install llama-index llama-index-llms-anthropic llama-index-embeddings-openai
```

---

## Core Concepts

LlamaIndex Workflows are **event-driven** state machines:
- Steps communicate by emitting and receiving **typed Events**
- The workflow engine routes events to the correct step automatically
- Steps can be async and run concurrently if they don't depend on each other

---

## Events

Every message between steps is a typed Event:

```python
from llama_index.core.workflow import Event

class ResearchEvent(Event):
    query: str
    sources: list[str] = []

class AnalysisEvent(Event):
    research: str
    focus_area: str

class OutputEvent(Event):
    content: str
    confidence: float
```

**Rules:**
- Always subclass `Event` (not dict, not dataclass)
- Fields are Pydantic-validated
- `StartEvent` and `StopEvent` are built-in entry/exit types

---

## Step Patterns

### Basic Step

```python
from llama_index.core.workflow import Workflow, step, StartEvent, StopEvent

class MyWorkflow(Workflow):
    @step
    async def start(self, ev: StartEvent) -> ResearchEvent:
        query = ev.get("query", "")
        return ResearchEvent(query=query)

    @step
    async def research(self, ev: ResearchEvent) -> StopEvent:
        result = await self._do_research(ev.query)
        return StopEvent(result=result)
```

### Step with Multiple Input Types (branching join)

```python
@step
async def synthesizer(
    self, ev: ResearchEvent | AnalysisEvent
) -> StopEvent:
    # Handles either event type
    ...
```

### Step that Emits Multiple Events (fan-out)

```python
@step
async def splitter(self, ev: StartEvent) -> list[ChunkEvent]:
    chunks = split_document(ev.document)
    return [ChunkEvent(chunk=c, idx=i) for i, c in enumerate(chunks)]
```

### Collecting Parallel Results (gather pattern)

```python
from llama_index.core.workflow import Context

@step
async def collector(self, ctx: Context, ev: ChunkResultEvent) -> StopEvent | None:
    results = ctx.collect_events(ev, [ChunkResultEvent] * self.n_chunks)
    if results is None:
        return None  # Not all chunks done yet — wait
    merged = merge_results(results)
    return StopEvent(result=merged)
```

---

## Full Workflow Example: Research + Synthesis

```python
from llama_index.core.workflow import (
    Workflow, step, Event, StartEvent, StopEvent, Context
)
from llama_index.llms.anthropic import Anthropic
from llama_index.core.agent import FunctionCallingAgent
from llama_index.core.tools import FunctionTool

class ResearchEvent(Event):
    findings: str

class CritiqueEvent(Event):
    findings: str
    critique: str

class ResearchWorkflow(Workflow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.llm = Anthropic(model="claude-opus-4-5")

    @step
    async def research(self, ev: StartEvent) -> ResearchEvent:
        query = ev.query
        # Use a RAG tool or web search here
        result = await self.llm.acomplete(f"Research this topic thoroughly: {query}")
        return ResearchEvent(findings=str(result))

    @step
    async def critique(self, ev: ResearchEvent) -> CritiqueEvent:
        critique = await self.llm.acomplete(
            f"Critique these research findings for gaps or errors:\n{ev.findings}"
        )
        return CritiqueEvent(findings=ev.findings, critique=str(critique))

    @step
    async def synthesize(self, ev: CritiqueEvent) -> StopEvent:
        final = await self.llm.acomplete(
            f"Synthesize these findings, addressing the critique:\n"
            f"Findings: {ev.findings}\nCritique: {ev.critique}"
        )
        return StopEvent(result=str(final))

# Run
workflow = ResearchWorkflow(timeout=120, verbose=True)
result = await workflow.run(query="Latest developments in agentic AI systems")
print(result)
```

---

## RAG Integration

### QueryEngine as a Workflow Step

```python
from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
from llama_index.core.tools import QueryEngineTool

# Build index
documents = SimpleDirectoryReader("./data").load_data()
index = VectorStoreIndex.from_documents(documents)
query_engine = index.as_query_engine()

# Wrap as tool for agent
rag_tool = QueryEngineTool.from_defaults(
    query_engine=query_engine,
    name="knowledge_base",
    description="Search the internal knowledge base for relevant documents.",
)

# Use inside a step
@step
async def rag_step(self, ev: ResearchEvent) -> AnalysisEvent:
    response = await query_engine.aquery(ev.query)
    return AnalysisEvent(content=str(response))
```

### Agent with Tools Inside a Step

```python
from llama_index.core.agent import FunctionCallingAgent
from llama_index.core.tools import FunctionTool

def calculate(expression: str) -> str:
    """Evaluate a mathematical expression."""
    return str(eval(expression))

calc_tool = FunctionTool.from_defaults(fn=calculate)

@step
async def agent_step(self, ev: StartEvent) -> StopEvent:
    agent = FunctionCallingAgent.from_tools(
        tools=[calc_tool, rag_tool],
        llm=self.llm,
        verbose=True,
    )
    result = await agent.achat(ev.query)
    return StopEvent(result=str(result))
```

---

## Shared Context (Global State)

```python
@step
async def write_step(self, ctx: Context, ev: StartEvent) -> NextEvent:
    await ctx.set("shared_key", "some value")
    return NextEvent()

@step
async def read_step(self, ctx: Context, ev: NextEvent) -> StopEvent:
    value = await ctx.get("shared_key")
    return StopEvent(result=value)
```

---

## Visualization

```python
# Draw the full graph of all possible flows (requires graphviz)
workflow.draw_all_possible_flows(filename="workflow_graph.html")

# Or just the most likely path
workflow.draw_most_likely_paths(filename="likely_flows.html")
```

---

## Running Workflows

```python
# Sync (for scripts)
import asyncio
result = asyncio.run(workflow.run(input="my query"))

# Async (for servers, notebooks)
result = await workflow.run(input="my query")

# Stream intermediate events
handler = workflow.run(input="my query")
async for event in handler.stream_events():
    print(f"Event: {event}")
result = await handler
```

---

## Common Pitfalls

- **Steps must be async** — use `async def` and `await` all LLM/IO calls
- **`ctx.collect_events` returns None until all events arrive** — always check for None before proceeding
- **Timeout** — set `timeout` in `Workflow.__init__` for long-running workflows; default is 10s
- **Event type routing is automatic** — a step that takes `ResearchEvent` will ONLY receive `ResearchEvent`, not other types
- **`StopEvent.result`** is the workflow's return value — put your final output there
