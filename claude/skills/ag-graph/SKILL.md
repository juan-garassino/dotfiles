---
name: ag-graph
description: >
  Design, build, and optimize agentic graph systems — including LangGraph, LlamaIndex workflows,
  or custom from-scratch implementations. Use this skill whenever the user wants to architect a
  multi-agent system, design a stateful agent graph, optimize an existing agentic pipeline, build
  a supervisor/worker agent topology, create conditional branching logic between agents, or implement
  agent memory and state management. Triggers include "build me a langgraph agent", "design an agentic
  pipeline", "multi-agent system", "agent graph", "supervisor agent", "router agent",
  "tool-calling agent graph", "llamaindex workflow", "from-scratch agent loop", "agentic optimizer",
  "improve my agent architecture", or any request involving coordinated agents with shared state,
  conditional routing, or cyclic/iterative agent execution. Also use when the user wants to evaluate
  or benchmark their agentic system's quality, latency, or token efficiency.
---

# Agentic Graph Builder & Optimizer

Design, implement, and optimize stateful multi-agent graph systems. Covers three tiers:

| Tier | Framework | When to use |
|------|-----------|-------------|
| **LangGraph** | `langgraph` + `langchain` | Production-grade, state machines, human-in-the-loop, streaming |
| **LlamaIndex Workflows** | `llama_index.core.workflow` | RAG-heavy pipelines, document intelligence, event-driven |
| **From-Scratch** | Pure Python + LLM API | Full control, minimal deps, research / custom infra |

Read the user's request carefully to pick the right tier — or ask if unclear.

---

## Phase 1: Intent Capture

Before writing any code, nail down the architecture requirements. Ask if not clear:

1. **What is the agent trying to accomplish?** (end-to-end task description)
2. **What are the tools / data sources?** (APIs, DBs, RAG indexes, code interpreters, etc.)
3. **What is the expected input / output?** (user message? structured JSON? file?)
4. **Does the graph need cycles?** (iterative refinement, retry on failure, reflection loops)
5. **Is human-in-the-loop needed?** (approval gates, clarification prompts)
6. **What are the performance constraints?** (latency, cost, parallelism)
7. **Framework preference?** (LangGraph / LlamaIndex / scratch — or choose for them)

---

## Phase 2: Graph Design

Produce a design artifact before writing code. This is the contract the implementation must satisfy.

### Node Taxonomy

Every node in the graph is one of:

| Type | Role | Example |
|------|------|---------|
| **Orchestrator / Supervisor** | Routes tasks to workers, decides when done | `supervisor_node` |
| **Worker / Specialist** | Executes a focused subtask with tools | `search_agent`, `coder_agent` |
| **Judge / Critic** | Evaluates quality, triggers retry or accept | `eval_node` |
| **Memory** | Reads/writes shared context, summaries, vector store | `memory_node` |
| **Formatter** | Transforms data between agent interfaces | `output_formatter` |
| **Gate / Router** | Conditional branching logic only, no LLM call | `should_continue` |

### Edge Taxonomy

| Type | When to use |
|------|------------|
| **Unconditional** | Node A always goes to Node B |
| **Conditional** | Route based on node output field or state flag |
| **Parallel fan-out** | Send same input to N workers simultaneously |
| **Join / aggregator** | Wait for N parallel workers, merge results |
| **Cycle / self-loop** | Retry, reflect, or iterate until condition met |

### Graph Design Template (produce this for the user)

```
GRAPH: <GraphName>

STATE SCHEMA:
  - messages: list[Message]
  - task: str
  - context: dict
  - iteration: int
  - status: Literal["running", "done", "failed"]

NODES:
  [entry] → supervisor
  supervisor → {search_agent | coder_agent | eval_node}  (conditional)
  search_agent → supervisor
  coder_agent → eval_node
  eval_node → {supervisor | END}  (conditional: quality_score < threshold → retry)

ENTRY POINT: supervisor
EXIT CONDITIONS: status == "done" OR iteration > MAX_ITER

PARALLELISM: search_agent runs in parallel fan-out (up to 3 concurrent)
CYCLES: supervisor ↔ workers (max 10 iterations)
HUMAN GATES: None / After eval_node if confidence < 0.7
```

Show this design to the user and get sign-off before coding.

---

## Phase 3: Implementation

### LangGraph Implementation

Read `references/langgraph.md` for full patterns and boilerplate.

**Key structural rules:**
- Define `StateGraph` with a typed `TypedDict` state — never use a plain dict
- Each node is a pure function `(state: State) -> dict` returning only the fields it mutates
- Conditional edges use a router function that returns a node name string
- Add `.compile()` and optionally a `MemorySaver` checkpointer for persistence
- Use `Command` for nodes that need to dynamically route AND update state simultaneously (LangGraph ≥ 0.2)

**Minimal skeleton:**

```python
from typing import Annotated, Literal
from typing_extensions import TypedDict
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages

class State(TypedDict):
    messages: Annotated[list, add_messages]
    status: str
    iteration: int

def supervisor(state: State) -> dict:
    # decide next step
    ...

def worker(state: State) -> dict:
    # do work
    ...

def route(state: State) -> Literal["worker", "__end__"]:
    if state["status"] == "done":
        return END
    return "worker"

builder = StateGraph(State)
builder.add_node("supervisor", supervisor)
builder.add_node("worker", worker)
builder.add_edge(START, "supervisor")
builder.add_conditional_edges("supervisor", route)
builder.add_edge("worker", "supervisor")

graph = builder.compile()
```

### LlamaIndex Workflow Implementation

Read `references/llamaindex.md` for full patterns and boilerplate.

**Key structural rules:**
- Subclass `Workflow`; each step is a method decorated with `@step`
- Steps communicate via `Event` subclasses — never pass raw dicts between steps
- Use `StartEvent` as the entry and `StopEvent` to terminate
- Enable `verbose=True` during development; use `draw_all_possible_flows()` to visualize
- For RAG: compose `QueryEngineTool` into a `FunctionCallingAgent` inside a workflow step

**Minimal skeleton:**

```python
from llama_index.core.workflow import (
    Workflow, step, Event, StartEvent, StopEvent
)

class ResearchEvent(Event):
    query: str

class MyWorkflow(Workflow):
    @step
    async def ingest(self, ev: StartEvent) -> ResearchEvent:
        return ResearchEvent(query=ev.input)

    @step
    async def research(self, ev: ResearchEvent) -> StopEvent:
        result = ...  # RAG or tool call
        return StopEvent(result=result)

workflow = MyWorkflow(timeout=60, verbose=True)
result = await workflow.run(input="user query")
```

### From-Scratch Implementation

Read `references/scratch.md` for full patterns and boilerplate.

**When to use:** minimal dependencies, custom infra, research, or when LangGraph/LlamaIndex are overkill.

**Architecture:**

```python
# Core loop pattern
class AgentGraph:
    def __init__(self, nodes: dict[str, Callable], edges: dict[str, str | Callable]):
        self.nodes = nodes
        self.edges = edges

    def run(self, entry: str, state: dict, max_iter: int = 20) -> dict:
        current = entry
        for i in range(max_iter):
            state = self.nodes[current](state)
            next_node = self.edges[current]
            if callable(next_node):
                current = next_node(state)
            else:
                current = next_node
            if current == "END":
                break
        return state
```

Build the state schema as a `dataclass` or `TypedDict`. Tool calls are just functions in `node_fn`'s closure. Parallelism via `asyncio.gather`.

---

## Phase 4: Optimization

Once a working graph exists, optimize on three axes:

### 4a. Quality Optimization

**Judge node pattern** — Add a critic/evaluator node after any generation step:

```python
def judge_node(state: State) -> dict:
    score = llm.evaluate(state["output"], rubric=RUBRIC)
    return {"quality_score": score, "should_retry": score < THRESHOLD}
```

**Reflection loop** — Let the agent critique its own output before returning:
```
worker → judge → [retry → worker | accept → END]
```

**Multi-agent debate** — Route same task to 2 workers, let a mediator pick the better answer.

### 4b. Latency Optimization

- **Parallel fan-out**: Identify independent subtasks and run them concurrently via `Send` (LangGraph) or `asyncio.gather` (scratch)
- **Streaming**: Enable token-level streaming at LLM call sites; pipe to user before full response
- **Cache deterministic nodes**: Memoize tool results using `functools.lru_cache` or Redis for repeated queries
- **Prune the graph**: Remove intermediate formatting/memory nodes that don't add value

### 4c. Cost Optimization

- Route simple subtasks to cheaper/smaller models (mini/haiku/flash) and complex ones to frontier models
- Summarize long conversation histories before passing to nodes with large context
- Cap `max_iter` and use exponential backoff on retries
- Use structured output (`response_format=json_schema`) to avoid re-parsing failures

---

## Phase 5: Evaluation Framework

A well-designed agentic system needs its own eval loop. See `references/eval.md` for a full multi-turn eval pipeline template (matches Juan's nutrition agent architecture pattern).

**Core metrics per graph run:**

| Metric | How to measure |
|--------|----------------|
| Task completion | Did the agent reach `StopEvent` / `END` cleanly? |
| Relevancy | Judge LLM: is the output relevant to the input? |
| Faithfulness | For RAG nodes: is the output grounded in retrieved context? |
| Scope adherence | Did the agent stay within its defined tool/domain scope? |
| Latency | Wall-clock time from `graph.run()` entry to exit |
| Token efficiency | Total tokens / quality score (cost-adjusted) |
| Iteration count | How many cycles before termination? |

**GPT-4o / Claude judge template:**

```python
JUDGE_PROMPT = """
You are evaluating an AI agent's response.
Task: {task}
Agent output: {output}

Rate the following on a scale of 0.0–1.0:
- relevancy: Does the output address the task?
- faithfulness: Is it grounded in facts/context provided?
- scope_adherence: Did the agent stay within its allowed tools and domain?

Return JSON only: {{"relevancy": 0.X, "faithfulness": 0.X, "scope_adherence": 0.X}}
"""
```

---

## Common Patterns Cheat Sheet

| Pattern | When | Sketch |
|---------|------|--------|
| **ReAct loop** | Single agent, tool use | `think → act → observe → think...` |
| **Plan-and-execute** | Complex multi-step tasks | `planner → [worker × N] → synthesizer` |
| **Supervisor-worker** | Heterogeneous subtasks | `supervisor → route → specialist → supervisor` |
| **Hierarchical** | Large-scale delegation | `manager → supervisor → worker` (nested graphs) |
| **Reflection** | Quality-sensitive generation | `generator → critic → [retry | accept]` |
| **Parallel RAG** | Multi-source retrieval | `fan-out → [retriever × N] → merge → synthesizer` |
| **MapReduce** | Batch document processing | `map(chunk → extract) → reduce(extractions → report)` |

---

## Reference Files

Load these on demand — don't preload all of them:

- `references/langgraph.md` — Full LangGraph patterns, `Command`, streaming, checkpointing, human-in-the-loop
- `references/llamaindex.md` — Full LlamaIndex Workflow patterns, RAG integration, agent tools
- `references/scratch.md` — From-scratch agent loop, async patterns, tool dispatch, state management
- `references/eval.md` — Multi-turn eval pipeline, judge templates, metric aggregation
