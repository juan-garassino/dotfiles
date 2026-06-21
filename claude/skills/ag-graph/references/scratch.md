# From-Scratch Agentic Systems Reference

Use this when you want full control: no framework deps, custom infra, research code, or when LangGraph/LlamaIndex would add more complexity than they remove.

---

## Core Loop Architecture

```python
from dataclasses import dataclass, field
from typing import Any, Callable, Literal
import asyncio
import json

@dataclass
class AgentState:
    """Single source of truth flowing through all nodes."""
    messages: list[dict] = field(default_factory=list)
    task: str = ""
    context: dict = field(default_factory=dict)
    tool_results: list[dict] = field(default_factory=list)
    iteration: int = 0
    status: Literal["running", "done", "failed"] = "running"
    output: Any = None

NodeFn = Callable[[AgentState], AgentState]
RouterFn = Callable[[AgentState], str]

class AgentGraph:
    def __init__(self, max_iter: int = 20):
        self.nodes: dict[str, NodeFn] = {}
        self.edges: dict[str, str | RouterFn] = {}
        self.entry: str = ""
        self.max_iter = max_iter

    def add_node(self, name: str, fn: NodeFn) -> "AgentGraph":
        self.nodes[name] = fn
        return self

    def add_edge(self, from_node: str, to_node: str) -> "AgentGraph":
        self.edges[from_node] = to_node
        return self

    def add_conditional_edge(self, from_node: str, router: RouterFn) -> "AgentGraph":
        self.edges[from_node] = router
        return self

    def set_entry(self, node: str) -> "AgentGraph":
        self.entry = node
        return self

    def run(self, initial_state: AgentState) -> AgentState:
        state = initial_state
        current = self.entry

        for i in range(self.max_iter):
            state.iteration = i
            if current == "END" or state.status in ("done", "failed"):
                break
            if current not in self.nodes:
                raise ValueError(f"Node '{current}' not found")

            state = self.nodes[current](state)

            edge = self.edges.get(current, "END")
            current = edge(state) if callable(edge) else edge

        return state
```

---

## Tool Dispatch System

```python
from typing import get_type_hints
import inspect

class ToolRegistry:
    def __init__(self):
        self._tools: dict[str, Callable] = {}
        self._schemas: dict[str, dict] = {}

    def register(self, fn: Callable) -> Callable:
        name = fn.__name__
        self._tools[name] = fn
        self._schemas[name] = self._build_schema(fn)
        return fn

    def _build_schema(self, fn: Callable) -> dict:
        hints = get_type_hints(fn)
        sig = inspect.signature(fn)
        return {
            "name": fn.__name__,
            "description": fn.__doc__ or "",
            "parameters": {
                "type": "object",
                "properties": {
                    k: {"type": self._py_to_json_type(v), "description": ""}
                    for k, v in hints.items()
                    if k != "return"
                },
                "required": [
                    k for k, p in sig.parameters.items()
                    if p.default is inspect.Parameter.empty
                ],
            }
        }

    def _py_to_json_type(self, t) -> str:
        return {str: "string", int: "integer", float: "number", bool: "boolean"}.get(t, "string")

    @property
    def schemas(self) -> list[dict]:
        return list(self._schemas.values())

    def call(self, name: str, args: dict) -> Any:
        if name not in self._tools:
            return {"error": f"Unknown tool: {name}"}
        try:
            return self._tools[name](**args)
        except Exception as e:
            return {"error": str(e)}

# Usage
registry = ToolRegistry()

@registry.register
def search_web(query: str) -> str:
    """Search the web for current information."""
    # ... implementation
    return "results"

@registry.register
def read_file(path: str) -> str:
    """Read the contents of a file."""
    with open(path) as f:
        return f.read()
```

---

## LLM Client Abstraction

```python
import anthropic
from openai import OpenAI

class LLMClient:
    def __init__(self, provider: str = "anthropic", model: str = "claude-opus-4-5"):
        self.provider = provider
        self.model = model
        if provider == "anthropic":
            self._client = anthropic.Anthropic()
        elif provider == "openai":
            self._client = OpenAI()

    def complete(
        self,
        messages: list[dict],
        tools: list[dict] | None = None,
        system: str | None = None,
        temperature: float = 0.0,
        max_tokens: int = 4096,
    ) -> dict:
        if self.provider == "anthropic":
            kwargs = dict(
                model=self.model,
                max_tokens=max_tokens,
                messages=messages,
                temperature=temperature,
            )
            if system:
                kwargs["system"] = system
            if tools:
                kwargs["tools"] = tools
            resp = self._client.messages.create(**kwargs)
            return {
                "content": resp.content,
                "stop_reason": resp.stop_reason,
                "tool_calls": [
                    {"name": b.name, "input": b.input}
                    for b in resp.content if b.type == "tool_use"
                ],
                "text": next(
                    (b.text for b in resp.content if b.type == "text"), ""
                ),
            }
        else:
            raise NotImplementedError(f"Provider {self.provider} not supported")
```

---

## ReAct Node (Think-Act-Observe Loop)

```python
def make_react_node(llm: LLMClient, registry: ToolRegistry, system: str) -> NodeFn:
    def react_node(state: AgentState) -> AgentState:
        messages = state.messages.copy()

        while True:
            response = llm.complete(
                messages=messages,
                tools=registry.schemas,
                system=system,
            )

            # No tool calls → final answer
            if not response["tool_calls"]:
                state.messages = messages + [{"role": "assistant", "content": response["text"]}]
                state.output = response["text"]
                state.status = "done"
                return state

            # Execute tool calls
            messages.append({"role": "assistant", "content": response["content"]})
            tool_results = []
            for call in response["tool_calls"]:
                result = registry.call(call["name"], call["input"])
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": call.get("id", call["name"]),
                    "content": json.dumps(result),
                })
                state.tool_results.append({"tool": call["name"], "result": result})

            messages.append({"role": "user", "content": tool_results})

    return react_node
```

---

## Async Parallel Fan-Out

```python
async def parallel_workers(
    state: AgentState,
    tasks: list[str],
    worker_fn: Callable[[str], str],
    max_concurrent: int = 5,
) -> list[str]:
    semaphore = asyncio.Semaphore(max_concurrent)

    async def bounded_worker(task: str) -> str:
        async with semaphore:
            return await asyncio.to_thread(worker_fn, task)

    return await asyncio.gather(*[bounded_worker(t) for t in tasks])

# In a node:
def fan_out_node(state: AgentState) -> AgentState:
    results = asyncio.run(parallel_workers(
        state,
        tasks=state.context["chunks"],
        worker_fn=process_chunk,
        max_concurrent=5,
    ))
    state.context["chunk_results"] = results
    return state
```

---

## Memory / Context Management

```python
from collections import deque

class RollingMemory:
    """Keep the last N turns in context. Summarize older turns."""
    def __init__(self, max_turns: int = 10, llm: LLMClient = None):
        self.recent = deque(maxlen=max_turns * 2)  # *2 for user+assistant pairs
        self.summary: str = ""
        self.llm = llm

    def add(self, role: str, content: str):
        if len(self.recent) >= self.recent.maxlen and self.llm:
            self._compress()
        self.recent.append({"role": role, "content": content})

    def _compress(self):
        old_turns = list(self.recent)[:len(self.recent)//2]
        conv_text = "\n".join(f"{m['role']}: {m['content']}" for m in old_turns)
        result = self.llm.complete(
            messages=[{"role": "user", "content": f"Summarize this conversation:\n{conv_text}"}]
        )
        self.summary = result["text"]
        for _ in range(len(old_turns)):
            self.recent.popleft()

    def as_messages(self) -> list[dict]:
        messages = list(self.recent)
        if self.summary:
            messages.insert(0, {"role": "user", "content": f"[Prior context]: {self.summary}"})
            messages.insert(1, {"role": "assistant", "content": "Understood."})
        return messages
```

---

## Full Example: Plan-and-Execute Graph

```python
def build_plan_execute_graph(llm: LLMClient, registry: ToolRegistry) -> AgentGraph:
    graph = AgentGraph(max_iter=15)

    def planner(state: AgentState) -> AgentState:
        resp = llm.complete(
            messages=[{"role": "user", "content": f"Create a step-by-step plan for: {state.task}"}],
            system="Output a numbered list of steps. Be specific.",
        )
        steps = [l.strip() for l in resp["text"].split("\n") if l.strip() and l[0].isdigit()]
        state.context["plan"] = steps
        state.context["step_idx"] = 0
        return state

    react_node = make_react_node(llm, registry, "Execute the given step using available tools.")

    def executor(state: AgentState) -> AgentState:
        idx = state.context["step_idx"]
        plan = state.context["plan"]
        step_task = plan[idx]
        state.messages = [{"role": "user", "content": f"Step: {step_task}"}]
        state = react_node(state)
        state.context["step_results"] = state.context.get("step_results", []) + [state.output]
        state.context["step_idx"] = idx + 1
        state.status = "running"  # keep going
        return state

    def synthesizer(state: AgentState) -> AgentState:
        results_text = "\n".join(
            f"Step {i+1}: {r}" for i, r in enumerate(state.context["step_results"])
        )
        resp = llm.complete(
            messages=[{"role": "user", "content": f"Original task: {state.task}\n\nStep results:\n{results_text}\n\nSynthesize a final answer."}]
        )
        state.output = resp["text"]
        state.status = "done"
        return state

    def route_executor(state: AgentState) -> str:
        idx = state.context.get("step_idx", 0)
        plan = state.context.get("plan", [])
        if idx >= len(plan):
            return "synthesizer"
        return "executor"

    graph.add_node("planner", planner)
    graph.add_node("executor", executor)
    graph.add_node("synthesizer", synthesizer)
    graph.add_edge("planner", "executor")
    graph.add_conditional_edge("executor", route_executor)
    graph.add_edge("synthesizer", "END")
    graph.set_entry("planner")

    return graph

# Run
graph = build_plan_execute_graph(llm, registry)
initial = AgentState(task="Analyze the Q3 sales data and write a summary report.")
final = graph.run(initial)
print(final.output)
```

---

## Pitfalls to Avoid

- **State mutation** — always work on copies in pure functional nodes to avoid bugs
- **Unbounded loops** — always enforce `max_iter` and check `status` in the router
- **Tool errors** — wrap all tool calls in try/except; the agent should handle tool failures gracefully
- **Context window bloat** — summarize history every N turns (see `RollingMemory` above)
- **Blocking in async** — use `asyncio.to_thread` for sync LLM calls in async contexts
