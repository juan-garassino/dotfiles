# Eval Parsers Reference

Format-specific patterns for reading eval output into the structured summary used by the improve loop.

---

## pytest + pytest-json-report

### Setup
```bash
pip install pytest-json-report
pytest tests/ -v --tb=short --json-report --json-report-file=/tmp/eval_results.json
```

### Parse
```python
import json

def parse_pytest(path="/tmp/eval_results.json"):
    with open(path) as f:
        data = json.load(f)
    
    summary = data["summary"]
    passed = summary.get("passed", 0)
    failed = summary.get("failed", 0)
    total = summary.get("total", 0)
    
    failures = []
    for test in data.get("tests", []):
        if test["outcome"] == "failed":
            failures.append({
                "id": test["nodeid"],
                "message": test.get("call", {}).get("longrepr", ""),
                "duration": test.get("call", {}).get("duration", 0),
            })
    
    return {
        "passed": passed,
        "failed": failed,
        "total": total,
        "pass_rate": passed / total if total else 0,
        "failures": failures,
    }
```

### Cluster failures by type
```python
def cluster_failures(failures):
    clusters = {}
    for f in failures:
        msg = f["message"]
        # Extract error type from traceback
        error_type = "Unknown"
        for line in msg.split("\n"):
            if "Error:" in line or "Exception:" in line or "assert" in line.lower():
                error_type = line.strip()[:80]
                break
        clusters.setdefault(error_type, []).append(f["id"])
    return clusters
```

---

## Custom Eval Script (JSON output)

### Expected contract
Your eval script should write a JSON file like:
```json
{
  "score": 0.84,
  "pass_rate": 0.84,
  "total": 25,
  "passed": 21,
  "failed": 4,
  "details": [
    {
      "id": "case_001",
      "passed": true,
      "score": 0.95,
      "input": "...",
      "output": "...",
      "expected": "...",
      "reason": ""
    },
    {
      "id": "case_002",
      "passed": false,
      "score": 0.40,
      "input": "...",
      "output": "...",
      "expected": "...",
      "reason": "Output missing key field X"
    }
  ]
}
```

### Parse
```python
def parse_custom_eval(path="/tmp/eval_results.json"):
    with open(path) as f:
        data = json.load(f)
    
    details = data.get("details", [])
    failures = [d for d in details if not d.get("passed", True)]
    
    return {
        "score": data.get("score", data.get("pass_rate", 0)),
        "passed": data.get("passed", 0),
        "failed": data.get("failed", len(failures)),
        "total": data.get("total", len(details)),
        "pass_rate": data.get("pass_rate", data.get("score", 0)),
        "failures": [
            {
                "id": f.get("id", "unknown"),
                "message": f.get("reason", "No reason given"),
                "input": f.get("input", ""),
                "output": f.get("output", ""),
                "expected": f.get("expected", ""),
                "score": f.get("score", 0.0),
            }
            for f in failures
        ],
    }
```

### If the script doesn't output JSON
Capture stdout and parse with LLM:
```python
import subprocess
result = subprocess.run(["python", "eval.py"], capture_output=True, text=True)
raw_output = result.stdout + result.stderr
# Pass raw_output to the LLM with a prompt to extract:
# - pass rate or score
# - list of failures with IDs and error messages
```

---

## LLM-as-Judge Output

### Expected contract
```json
{
  "run_id": "run_001",
  "cases": [
    {
      "id": "case_001",
      "scores": {
        "relevancy": 0.9,
        "faithfulness": 0.85,
        "completeness": 0.7,
        "scope_adherence": 1.0
      },
      "aggregate": 0.86,
      "passed": true,
      "reasoning": "Output addresses the query well but lacks detail on X"
    }
  ],
  "summary": {
    "mean_aggregate": 0.78,
    "pass_rate": 0.72
  }
}
```

### Parse
```python
def parse_llm_judge(path="/tmp/judge_results.json"):
    with open(path) as f:
        data = json.load(f)
    
    cases = data.get("cases", [])
    failures = [c for c in cases if not c.get("passed", True)]
    
    # Per-metric averages
    metric_names = ["relevancy", "faithfulness", "completeness", "scope_adherence"]
    metric_avgs = {}
    for m in metric_names:
        vals = [c["scores"].get(m, 0) for c in cases if "scores" in c]
        metric_avgs[m] = sum(vals) / len(vals) if vals else 0
    
    return {
        "score": data["summary"].get("mean_aggregate", 0),
        "pass_rate": data["summary"].get("pass_rate", 0),
        "total": len(cases),
        "passed": len(cases) - len(failures),
        "failed": len(failures),
        "metric_avgs": metric_avgs,
        "failures": [
            {
                "id": f["id"],
                "message": f.get("reasoning", ""),
                "scores": f.get("scores", {}),
                "aggregate": f.get("aggregate", 0),
                "worst_metric": min(f.get("scores", {}).items(), key=lambda x: x[1])[0]
                    if f.get("scores") else "unknown",
            }
            for f in failures
        ],
    }
```

### Diagnosing LLM judge failures
Group by worst metric to prioritize fixes:
```python
def prioritize_judge_failures(failures):
    by_metric = {}
    for f in failures:
        m = f.get("worst_metric", "unknown")
        by_metric.setdefault(m, []).append(f)
    return sorted(by_metric.items(), key=lambda x: -len(x[1]))
```

---

## Benchmark / Metric File

### Pattern: metrics.json produced by a benchmark run
```json
{
  "accuracy": 0.82,
  "f1": 0.79,
  "precision": 0.85,
  "recall": 0.74,
  "latency_p50_ms": 340,
  "latency_p99_ms": 1200,
  "cost_per_run_usd": 0.0034
}
```

### Parse and compare to baseline
```python
def parse_metrics(path="metrics.json", baseline_path="/tmp/baseline_metrics.json"):
    with open(path) as f:
        current = json.load(f)
    
    baseline = {}
    try:
        with open(baseline_path) as f:
            baseline = json.load(f)
    except FileNotFoundError:
        pass
    
    comparison = {}
    for key, val in current.items():
        b = baseline.get(key)
        delta = val - b if b is not None else None
        comparison[key] = {
            "current": val,
            "baseline": b,
            "delta": delta,
            "improved": delta > 0 if delta is not None else None,
        }
    
    return comparison
```

### Determine primary metric
Some benchmarks have a single primary metric; others are multi-dimensional.
Ask the user upfront or infer from the benchmark documentation:
- Classification: accuracy or F1
- Generation: BLEU, ROUGE, or LLM-judge score
- Retrieval: NDCG, MRR, recall@k
- Latency: p50 or p99
- Agentic: task completion rate + score combo
