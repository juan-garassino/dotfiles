# Fix Patterns Reference

Common fix patterns by failure category. Each includes a diagnostic trigger,
the root cause, and before/after examples.

---

## 1. Return Type / Interface Mismatch

**Diagnostic trigger**: `TypeError`, `AttributeError`, `KeyError` on the output of a function,
or eval expecting a field that isn't there.

**Root cause**: Function returns the wrong type or structure; caller and callee drifted.

**Fix approach**: Fix the return structure in the function, then check all call sites.

**Before**:
```python
def get_result(state):
    return state["output"]  # returns str, but caller expects dict
```
**After**:
```python
def get_result(state):
    return {"result": state["output"], "status": "done"}
```

---

## 2. Missing Edge Case / Guard Clause

**Diagnostic trigger**: Failures on specific inputs (empty list, None, zero, very long string),
but passing on normal inputs.

**Root cause**: No handling for boundary conditions.

**Fix approach**: Add guard at function entry. Prefer early returns over nested conditionals.

**Before**:
```python
def process(items):
    first = items[0]  # IndexError when items is empty
    return transform(first)
```
**After**:
```python
def process(items):
    if not items:
        return {"result": None, "reason": "empty input"}
    return transform(items[0])
```

---

## 3. Outdated API Usage

**Diagnostic trigger**: `DeprecationWarning`, `AttributeError: module has no attribute`,
`TypeError: unexpected keyword argument`.

**Root cause**: Library updated and the old API no longer exists or behaves differently.

**Fix approach**: Check the library's changelog or migration guide (web search if needed),
update all call sites in the target file.

**Before (LangChain old)**:
```python
from langchain.chat_models import ChatOpenAI
llm = ChatOpenAI(temperature=0)
response = llm(messages)  # old __call__ pattern
```
**After**:
```python
from langchain_openai import ChatOpenAI
llm = ChatOpenAI(temperature=0)
response = llm.invoke(messages)
```

**Before (LangGraph old)**:
```python
builder.add_conditional_edges(
    "node_a",
    route_fn,
    {"next": "node_b", "end": END}  # mapping form deprecated
)
```
**After**:
```python
builder.add_conditional_edges("node_a", route_fn)
# route_fn must return a node name string or END directly
```

---

## 4. Logic Error in Condition / Routing

**Diagnostic trigger**: Agent takes wrong branch, wrong node executes, infinite loop,
tests pass/fail inverted.

**Root cause**: Boolean logic is wrong, or routing function returns the wrong key.

**Fix approach**: Add debug logging, trace the condition, fix the predicate.

**Before**:
```python
def should_continue(state):
    if state["iteration"] > MAX_ITER:
        return "continue"   # wrong — should be END
    return END
```
**After**:
```python
def should_continue(state):
    if state["iteration"] > MAX_ITER or state["status"] == "done":
        return END
    return "continue"
```

---

## 5. State Mutation Bug (Agentic Graphs)

**Diagnostic trigger**: Tests pass in isolation but fail when run sequentially;
state from a previous test leaks into the next.

**Root cause**: Mutable default argument or shared global state.

**Fix approach**: Always create fresh state objects; never use mutable defaults.

**Before**:
```python
def agent_node(state={"messages": [], "count": 0}):  # shared default!
    state["count"] += 1
    return state
```
**After**:
```python
def agent_node(state: State) -> dict:
    return {"count": state["count"] + 1}  # return delta only, don't mutate
```

---

## 6. LLM Output Parsing Failure

**Diagnostic trigger**: `json.JSONDecodeError`, `KeyError` when extracting LLM response fields,
agent crashes on malformed model output.

**Root cause**: LLM didn't follow the expected format; no error handling around parse.

**Fix approach**: Add robust parsing with fallback, strengthen the prompt's format instructions.

**Before**:
```python
response = llm.invoke(messages)
data = json.loads(response.content)  # crashes if not valid JSON
score = data["score"]
```
**After**:
```python
response = llm.invoke(messages)
try:
    # Strip markdown fences if present
    raw = response.content.strip().removeprefix("```json").removesuffix("```").strip()
    data = json.loads(raw)
    score = data.get("score", 0.0)
except (json.JSONDecodeError, KeyError, AttributeError):
    score = 0.0  # safe default; log the failure
    logger.warning(f"Failed to parse LLM response: {response.content[:200]}")
```

**Prompt fix** — strengthen format instructions:
```python
system = """You are a scorer. Always respond with valid JSON only.
No markdown, no explanation, no preamble.
Required format: {"score": <float 0.0-1.0>, "reason": "<str>"}"""
```

---

## 7. Async/Await Bug

**Diagnostic trigger**: `coroutine was never awaited`, output is a coroutine object not a result,
`RuntimeError: no running event loop`.

**Root cause**: Missing `await`, calling async function from sync context, or nested event loops.

**Before**:
```python
result = async_function()  # returns coroutine, not result
```
**After**:
```python
result = await async_function()  # in async context
# OR in sync context:
result = asyncio.run(async_function())
```

**Jupyter/nested loop fix**:
```python
import nest_asyncio
nest_asyncio.apply()
result = asyncio.run(async_function())
```

---

## 8. Context Window Overflow

**Diagnostic trigger**: `context_length_exceeded`, truncated responses, eval fails because
output is cut off.

**Root cause**: Too much history / context passed to the LLM.

**Fix approach**: Summarize history, truncate older messages, or split into shorter calls.

**Before**:
```python
response = llm.invoke(state["messages"])  # full history — can be huge
```
**After**:
```python
# Keep system + last N turns + current message
MAX_TURNS = 10
messages = state["messages"]
if len(messages) > MAX_TURNS * 2:
    # Summarize old turns
    old = messages[:-MAX_TURNS * 2]
    summary = summarize(old)
    messages = [{"role": "user", "content": f"[History summary]: {summary}"},
                {"role": "assistant", "content": "Understood."}] + messages[-MAX_TURNS * 2:]
response = llm.invoke(messages)
```

---

## Fix Selection Heuristics

When multiple failure types are present in the same iteration:

1. **Fix interface mismatches first** — they cause cascading failures that mask other issues
2. **Fix guard clauses next** — cheap and prevents crashes
3. **Fix logic errors after** — requires more careful reasoning
4. **Fix LLM prompt issues last** — prompt changes are unpredictable; isolate them

Never attempt to fix an architecture issue (wrong graph topology, wrong abstraction) in
the same iteration as a bug fix. Architecture changes need their own iteration.
