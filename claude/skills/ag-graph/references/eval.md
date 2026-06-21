# Agentic System Evaluation Reference

Multi-turn evaluation pipeline for agentic graphs. Covers judge design, metric aggregation, and scoring strategies.

---

## Judge Architecture

The standard pattern: run the agent, collect the trace, pass to a separate LLM judge.

```python
from dataclasses import dataclass
import json
import anthropic

@dataclass
class EvalResult:
    run_id: str
    task: str
    agent_output: str
    metrics: dict[str, float]  # 0.0 to 1.0
    passed: bool
    trace: list[dict]  # node execution trace

JUDGE_SYSTEM = """You are an expert AI evaluator. Given a task and an agent's output,
rate the response on multiple dimensions. Return only valid JSON."""

JUDGE_PROMPT = """
Task: {task}

Agent Output:
{output}

Context (retrieved or used by the agent):
{context}

Rate each dimension from 0.0 (poor) to 1.0 (excellent):
- relevancy: Does the output directly address the task?
- faithfulness: Is the output grounded in the provided context? (1.0 if no context used)
- completeness: Does the output cover all aspects of the task?
- scope_adherence: Did the agent stay within its defined domain/tools?
- coherence: Is the output well-structured and internally consistent?

Return JSON only, no markdown:
{{"relevancy": 0.X, "faithfulness": 0.X, "completeness": 0.X, "scope_adherence": 0.X, "coherence": 0.X, "reasoning": "brief explanation"}}
"""

class AgentJudge:
    def __init__(self, model: str = "claude-opus-4-5"):
        self.client = anthropic.Anthropic()
        self.model = model

    def evaluate(
        self,
        task: str,
        agent_output: str,
        context: str = "",
        run_id: str = "",
    ) -> EvalResult:
        prompt = JUDGE_PROMPT.format(
            task=task,
            output=agent_output,
            context=context or "No external context used.",
        )
        response = self.client.messages.create(
            model=self.model,
            max_tokens=512,
            system=JUDGE_SYSTEM,
            messages=[{"role": "user", "content": prompt}],
        )
        raw = response.content[0].text.strip()
        scores = json.loads(raw)
        reasoning = scores.pop("reasoning", "")

        # Weighted aggregate score
        weights = {
            "relevancy": 0.30,
            "faithfulness": 0.25,
            "completeness": 0.20,
            "scope_adherence": 0.15,
            "coherence": 0.10,
        }
        aggregate = sum(scores[k] * w for k, w in weights.items())

        return EvalResult(
            run_id=run_id,
            task=task,
            agent_output=agent_output,
            metrics={**scores, "aggregate": aggregate, "reasoning": reasoning},
            passed=aggregate >= 0.75,
            trace=[],
        )
```

---

## Multi-Turn Eval Pipeline

For agents that run multi-turn conversations (e.g., nutrition agent, customer support):

```python
from typing import Iterator

@dataclass
class Turn:
    user_message: str
    expected_topics: list[str]  # what the agent should cover
    expected_tools: list[str] | None = None  # tools that should be called

@dataclass
class MultiTurnEval:
    eval_id: str
    description: str
    turns: list[Turn]
    global_context: dict = None

def run_multi_turn_eval(
    graph,  # your AgentGraph instance
    eval_case: MultiTurnEval,
    judge: AgentJudge,
) -> dict:
    """Run a full multi-turn conversation through the agent and score each turn."""
    conversation_history = []
    turn_results = []

    for i, turn in enumerate(eval_case.turns):
        # Add user message to history
        conversation_history.append({
            "role": "user",
            "content": turn.user_message,
        })

        # Run agent
        from your_agent import AgentState
        state = AgentState(
            messages=conversation_history.copy(),
            context=eval_case.global_context or {},
        )
        final_state = graph.run(state)
        agent_response = final_state.output or ""

        # Add response to history for next turn
        conversation_history.append({
            "role": "assistant",
            "content": agent_response,
        })

        # Judge this turn
        result = judge.evaluate(
            task=turn.user_message,
            agent_output=agent_response,
            context=str(final_state.context),
            run_id=f"{eval_case.eval_id}-turn-{i}",
        )

        # Check tool usage if specified
        tools_used = [r["tool"] for r in final_state.tool_results]
        tool_compliance = (
            all(t in tools_used for t in turn.expected_tools)
            if turn.expected_tools else None
        )

        turn_results.append({
            "turn": i,
            "user_message": turn.user_message,
            "agent_response": agent_response,
            "metrics": result.metrics,
            "passed": result.passed,
            "tool_compliance": tool_compliance,
        })

    # Aggregate across turns
    metric_names = ["relevancy", "faithfulness", "completeness", "scope_adherence", "coherence", "aggregate"]
    aggregated = {
        m: sum(t["metrics"].get(m, 0) for t in turn_results) / len(turn_results)
        for m in metric_names
    }

    return {
        "eval_id": eval_case.eval_id,
        "description": eval_case.description,
        "n_turns": len(eval_case.turns),
        "turn_results": turn_results,
        "aggregated_metrics": aggregated,
        "overall_pass": aggregated["aggregate"] >= 0.75,
        "pass_rate": sum(t["passed"] for t in turn_results) / len(turn_results),
    }
```

---

## Eval Test Cases (Example)

```python
EVAL_SUITE = [
    MultiTurnEval(
        eval_id="basic-query",
        description="Single turn factual question",
        turns=[
            Turn(
                user_message="What are the macros in 100g of chicken breast?",
                expected_topics=["protein", "calories", "fat"],
                expected_tools=["nutrition_lookup"],
            )
        ],
    ),
    MultiTurnEval(
        eval_id="multi-turn-diet-plan",
        description="Multi-turn diet planning conversation",
        turns=[
            Turn(
                user_message="I want to lose 5kg over 3 months, I'm 80kg and moderately active.",
                expected_topics=["caloric_deficit", "tdee"],
            ),
            Turn(
                user_message="Can you give me a meal plan for Monday?",
                expected_topics=["breakfast", "lunch", "dinner", "calories"],
                expected_tools=["nutrition_lookup", "meal_planner"],
            ),
            Turn(
                user_message="What if I'm vegetarian?",
                expected_topics=["protein_sources", "plant_based"],
            ),
        ],
    ),
]
```

---

## Performance Metrics

Capture these alongside quality scores for every eval run:

```python
import time

@dataclass
class RunStats:
    wall_time_s: float
    total_tokens: int
    prompt_tokens: int
    completion_tokens: int
    n_tool_calls: int
    n_iterations: int
    cost_usd: float  # rough estimate

def estimate_cost(prompt_tokens: int, completion_tokens: int, model: str) -> float:
    # Rough estimates per 1M tokens (update as pricing changes)
    pricing = {
        "claude-opus-4-5": (15.0, 75.0),    # (input $/M, output $/M)
        "claude-sonnet-4-6": (3.0, 15.0),
        "claude-haiku-4-5-20251001": (0.25, 1.25),
    }
    inp, out = pricing.get(model, (3.0, 15.0))
    return (prompt_tokens * inp + completion_tokens * out) / 1_000_000
```

---

## Scoring Dashboard

Aggregate across multiple eval cases:

```python
def summarize_eval_suite(results: list[dict]) -> dict:
    metrics = ["relevancy", "faithfulness", "completeness", "scope_adherence", "coherence", "aggregate"]
    summary = {}
    for m in metrics:
        scores = [r["aggregated_metrics"][m] for r in results]
        summary[m] = {
            "mean": sum(scores) / len(scores),
            "min": min(scores),
            "max": max(scores),
        }
    summary["overall_pass_rate"] = sum(r["overall_pass"] for r in results) / len(results)
    summary["n_evals"] = len(results)
    return summary

# Print a quick summary table
def print_summary(summary: dict):
    print(f"\n{'Metric':<20} {'Mean':>6} {'Min':>6} {'Max':>6}")
    print("-" * 40)
    for m, vals in summary.items():
        if isinstance(vals, dict):
            print(f"{m:<20} {vals['mean']:>6.2f} {vals['min']:>6.2f} {vals['max']:>6.2f}")
    print(f"\nOverall pass rate: {summary['overall_pass_rate']:.1%} ({summary['n_evals']} evals)")
```
