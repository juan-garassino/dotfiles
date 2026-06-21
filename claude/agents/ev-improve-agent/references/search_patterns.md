# Web Search Patterns for Self-Improve

Query templates by failure type. Keep queries short (3-6 words), specific, and include
version numbers when visible in the traceback.

---

## API / Library Changes

**Pattern**: `DeprecationWarning`, `TypeError: unexpected keyword argument`, `AttributeError`, `ImportError`

**Query templates**:
```
<library> <method> deprecated <year>
<library> <version> breaking changes
<library> <old_api> migrate to <new_api>
<library> <error_type> fix
```

**Examples**:
```
langgraph conditional_edges deprecated 2024
langchain invoke vs run migration
openai ChatCompletion to chat.completions
transformers AutoModel from_pretrained new
```

**What to look for**: Official migration guides, GitHub changelogs, release notes.
Prefer official docs and GitHub issues over Stack Overflow for library API changes.

---

## Async / Concurrency Errors

**Pattern**: `RuntimeError: This event loop is already running`, `coroutine was never awaited`,
`asyncio.run() cannot be called from a running event loop`

**Query templates**:
```
asyncio nested event loop python fix
<library> async context manager pattern
asyncio gather exception handling
<framework> async run from sync context
```

**Examples**:
```
asyncio nest_asyncio jupyter
langgraph async stream events pattern
llama_index workflow async step pattern
```

**What to look for**: The pattern `nest_asyncio` for notebook contexts, `asyncio.to_thread`
for sync calls in async context, `loop.run_until_complete` pitfalls.

---

## ML / Deep Learning Errors

**Pattern**: CUDA OOM, tensor shape mismatches, NaN loss, gradient issues

**Query templates**:
```
pytorch <error> fix
<model_name> cuda out of memory solution
gradient exploding <architecture> fix
nan loss <optimizer> pytorch
```

**Examples**:
```
pytorch gradient checkpointing memory
transformers model parallel cuda
torch autocast dtype mismatch
PPO reward normalization nan
```

**What to look for**: GitHub issues on the specific model repo, PyTorch forums, Hugging Face forums.

---

## Agentic / LLM Output Errors

**Pattern**: Output doesn't match expected format, tool calls malformed, JSON parse errors,
infinite loops in agent graph

**Query templates**:
```
<framework> structured output json mode
<llm> tool calling format <version>
<framework> agent loop termination condition
<framework> <node_type> conditional edge example
```

**Examples**:
```
langgraph should_continue pattern
claude tool_use format anthropic
openai function calling json schema required
langgraph command goto node pattern
```

**What to look for**: Official cookbook examples, framework docs on structured output,
known issues with specific model versions and tool use.

---

## Eval-Specific Searches

**Pattern**: Score unexpectedly low despite correct-looking output, metric not improving
despite code changes

**Query templates**:
```
<eval_name> metric definition formula
<benchmark_name> baseline score typical
<metric> low score common causes
<judge_model> prompt template best practices
```

**Examples**:
```
RAGAS faithfulness metric definition
BERTScore low score tokenization
LLM judge calibration prompt template
relevancy score RAG evaluation
```

**What to look for**: The actual formula behind the metric (it's often surprising), known
biases in LLM judges, calibration tips.

---

## Search Result Evaluation

When you get results back, evaluate them:

**Trust more**:
- Official library documentation (docs.*)
- GitHub repository issues/discussions (github.com/<org>/<repo>/issues)
- arXiv papers for ML techniques
- Anthropic / OpenAI / Google official blogs for their own models

**Trust less**:
- Medium articles with generic titles
- Stack Overflow answers > 2 years old for fast-moving libraries
- Anything that tells you to monkey-patch a framework's internals

**Red flags**:
- The suggested fix changes core library behavior without explanation
- The answer is from a model that hallucinated the API (check if the method actually exists)
- The fix works around the symptom without addressing the root cause

---

## Iteration Search Strategy

If a fix didn't work across 2 iterations:
1. **Search for the specific error message** (not the general concept) — often reveals a GitHub issue with the exact fix
2. **Add the version number** to the query — behavior changed significantly between versions
3. **Search for alternatives** — `<approach> alternatives` or `<approach> vs <alternative>`
4. **Search for the test that's failing**, not the code — sometimes the eval expectation is wrong
