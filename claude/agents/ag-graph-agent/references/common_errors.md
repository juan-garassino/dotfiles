# Common Errors — Agentic Graph Agent

Error message → root cause → fix. Use this before web-searching.

---

## LangGraph Errors

**`ValueError: Expected Runnable, got <class 'function'>`**
- Cause: Node function not registered correctly, or using old `add_node` API
- Fix: Ensure node is a plain Python function `(state: State) -> dict`. Do not wrap in `RunnableLambda`.

**`KeyError: '<node_name>'` during graph execution**
- Cause: Router returned a node name that doesn't exist in the graph
- Fix: Print all registered node names: `list(graph.nodes.keys())`. Check for typos in router return values.

**`RecursionError` or graph runs forever**
- Cause: No exit condition in router, or exit condition never triggers
- Fix: Add `iteration` counter to state, increment each cycle, return `END` when `iteration > MAX_ITER`

**`InvalidUpdateError: Expected dict, got <type>`**
- Cause: Node returned something other than a dict (e.g., returned the full state object)
- Fix: Nodes must return only the fields they change: `return {"field": new_value}` not `return state`

**`add_messages` receiving non-Message objects**
- Cause: Appending raw strings to message list instead of Message objects
- Fix: Wrap in `HumanMessage` / `AIMessage` / `SystemMessage` from `langchain_core.messages`

**`AttributeError: 'CompiledGraph' object has no attribute 'stream'`**
- Cause: Old langgraph version
- Fix: `pip install --upgrade langgraph`; use `graph.astream_events(input, version="v2")`

**`interrupt()` call does nothing**
- Cause: Graph compiled without a checkpointer
- Fix: `graph = builder.compile(checkpointer=MemorySaver())` — interrupt requires persistence

---

## LlamaIndex Workflow Errors

**`StopEvent received but no result`**
- Cause: `StopEvent` created without `result=` kwarg
- Fix: Always `return StopEvent(result=<your_output>)`

**`TimeoutError` after 10 seconds**
- Cause: Default timeout is 10s — too low for LLM calls
- Fix: `MyWorkflow(timeout=120)` — set appropriate timeout

**`TypeError: object NoneType can't be used in await`**
- Cause: `@step` method returned `None` instead of an Event
- Fix: Every step must return an Event or `None` only for `collect_events` gather pattern

**`ctx.collect_events` always returns None**
- Cause: Expected event count doesn't match what's actually being emitted
- Fix: Verify the count passed to `collect_events` exactly matches how many events are emitted by the fan-out step

**`AttributeError: 'StartEvent' has no attribute 'X'`**
- Cause: Accessing a field not passed to `workflow.run()`
- Fix: Use `ev.get("X")` or pass all needed fields: `await wf.run(x=val, y=val2)`

---

## Python / Async Errors

**`RuntimeError: This event loop is already running`**
- Cause: Calling `asyncio.run()` inside an already-running loop (Jupyter, FastAPI, etc.)
- Fix: `import nest_asyncio; nest_asyncio.apply()` or use `await` directly

**`coroutine 'X' was never awaited`**
- Cause: Called an async function without `await`
- Fix: Add `await`: `result = await async_fn()`

**`SyntaxError` after editing**
- Cause: Incomplete edit left broken syntax
- Fix: `python -m py_compile <file>` after every edit; restore from backup if it fails

---

## LLM Output / Parsing Errors

**`json.JSONDecodeError`**
- Cause: LLM wrapped JSON in markdown fences, or added preamble text
- Fix:
  ```python
  raw = response.strip()
  if raw.startswith("```"):
      raw = raw.split("```")[1]
      if raw.startswith("json"):
          raw = raw[4:]
  data = json.loads(raw.strip())
  ```

**LLM ignores tool call, just responds in text**
- Cause: Tools not bound to the model, or model doesn't support tool use
- Fix: Use `llm.bind_tools(tools)` for LangChain; verify model supports tool use (claude-sonnet-4-6 ✅)

**Tool call loop — LLM keeps calling the same tool**
- Cause: Tool result isn't being added back to message history correctly
- Fix: After tool call, append `{"role": "tool", "content": result}` (OpenAI) or `tool_result` block (Anthropic) to messages

---

## Installation / Import Errors

**`ModuleNotFoundError: No module named 'langgraph'`**
```bash
pip install langgraph langchain-anthropic
```

**`ModuleNotFoundError: No module named 'llama_index'`**
```bash
pip install llama-index llama-index-llms-anthropic
```

**`ImportError: cannot import name 'Command' from 'langgraph'`**
- Cause: Old langgraph version (< 0.2)
```bash
pip install --upgrade langgraph
```
Then: `from langgraph.types import Command`
