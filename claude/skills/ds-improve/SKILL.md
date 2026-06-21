---
name: ds-improve
description: >
  Autonomous self-improvement agent for the DeepSculpt codebase — runs eval metrics
  specific to 3D generative models, diagnoses failures in the data pipeline, GAN,
  or diffusion model, applies targeted fixes, and iterates. Understands volumetric
  FID equivalents, mode collapse detection, training instability patterns, and 3D
  convolution bugs. Use when you want to autonomously improve training quality,
  fix instability, improve sample diversity, or optimize the pipeline. Triggers
  include "improve the deepsculpt training", "fix the instability", "the samples
  are getting worse", "autonomously improve the gan", "run the eval loop on
  deepsculpt", "fix mode collapse", "improve sample quality automatically".
---

# ds-improve — DeepSculpt Self-Improvement Agent

You are an autonomous improvement agent for the DeepSculpt pipeline. You understand
3D generative model failure modes and run a targeted eval-improve loop specific to
volumetric GAN and diffusion code.

---

## Agent State

```
target:          null    # "gan" | "diffusion" | "datapipeline" | "full"
target_files:    []
checkpoint_dir:  null
baseline:        null
current:         null
iteration:       0
fixes_applied:   []
status:          running
```

---

## DeepSculpt-Specific Eval Metrics

Unlike generic code, generative model quality requires domain-specific metrics:

### 1. Sample validity rate
```python
def sample_validity(G, latent_dim, n=64, device="cuda",
                    min_occ=0.02, max_occ=0.95):
    """Fraction of generated samples with valid occupancy."""
    G.eval()
    with torch.no_grad():
        zs = torch.randn(n, latent_dim, device=device)
        vols = G(zs).squeeze(1).cpu().numpy()
    occ = (vols > 0.5).reshape(n, -1).mean(axis=1)
    valid = ((occ >= min_occ) & (occ <= max_occ)).mean()
    return float(valid)
```

### 2. Diversity score (anti-mode-collapse)
```python
def diversity_score(G, latent_dim, n=64, device="cuda"):
    """Mean pairwise L2 distance between generated samples."""
    G.eval()
    with torch.no_grad():
        zs = torch.randn(n, latent_dim, device=device)
        vols = G(zs).view(n, -1).cpu().numpy()
    dists = []
    for i in range(0, n, 8):
        batch = vols[i:i+8]
        for j in range(len(batch)):
            for k in range(j+1, len(batch)):
                dists.append(np.linalg.norm(batch[j] - batch[k]))
    return float(np.mean(dists))
```

### 3. Coverage score (how much of the data distribution is covered)
```python
def coverage_score(G, real_loader, latent_dim, n_gen=256, device="cuda"):
    """Fraction of real samples that have a close generated neighbor."""
    G.eval()
    real_vols = []
    for batch in real_loader:
        real_vols.append(batch.view(batch.size(0), -1).cpu().numpy())
        if len(real_vols) * batch.size(0) >= 256: break
    real_flat = np.concatenate(real_vols)[:256]

    with torch.no_grad():
        zs = torch.randn(n_gen, latent_dim, device=device)
        gen_flat = G(zs).view(n_gen, -1).cpu().numpy()

    # For each real sample, find closest generated
    covered = 0
    threshold = np.percentile(
        [np.linalg.norm(real_flat[i] - real_flat[j])
         for i in range(0, 50) for j in range(i+1, 50)], 10
    )
    for r in real_flat:
        dists = np.linalg.norm(gen_flat - r, axis=1)
        if dists.min() < threshold:
            covered += 1
    return covered / len(real_flat)
```

### 4. Loss trend (is training converging?)
```python
def check_loss_trend(loss_history: list, window: int = 50) -> dict:
    if len(loss_history) < window * 2:
        return {"status": "insufficient_data"}
    recent = np.mean(loss_history[-window:])
    prev = np.mean(loss_history[-window*2:-window])
    delta = (recent - prev) / (abs(prev) + 1e-8)
    return {
        "recent_mean": recent,
        "prev_mean": prev,
        "delta_pct": delta * 100,
        "improving": delta < -0.01,
        "plateaued": abs(delta) < 0.01,
        "diverging": delta > 0.05,
    }
```

---

## Diagnosis Decision Tree

```
Run all metrics
│
├── validity_rate < 0.5
│   ├── all zeros → Generator outputting zeros
│   │   Fix: Add occupancy regularization, check sigmoid activation
│   └── all ones → Generator saturated
│       Fix: Check input normalization, reduce LR
│
├── diversity_score < threshold (mode collapse)
│   ├── D loss → 0 quickly → Discriminator too strong
│   │   Fix: Reduce D capacity, add dropout to D, switch to WGAN-GP
│   └── D loss oscillates → Training instability
│       Fix: Lower LR, increase n_critic, add gradient penalty
│
├── coverage_score < 0.3 (missing modes)
│   Fix: Increase latent_dim, add minibatch discrimination
│
├── loss diverging
│   Fix: Lower LR, clip gradients, check for NaN in data
│
└── all metrics OK but samples look bad
    → Qualitative issue — check architecture (checkerboard artifacts → use upsample+conv)
```

---

## Iteration Loop

Each iteration:

1. **Run metrics** — validity, diversity, coverage, loss trend
2. **Diagnose** — map metrics to root cause using decision tree
3. **Select fix** — one fix per iteration, highest impact first
4. **Apply** — targeted code change to the identified file
5. **Test** — run a short training epoch (100 steps) and re-measure
6. **Compare** — did the metric improve?

---

## Common Fixes by Issue

| Issue | File to change | What to change |
|-------|---------------|---------------|
| All-zero output | Generator | Add `assert out.sum() > 0` + occupancy loss |
| Mode collapse | Training loop | Switch BCE → WGAN-GP, increase n_critic |
| Checkerboard | Generator | Replace ConvTranspose3d with Upsample + Conv3d |
| NaN loss | Training loop | Add `torch.nn.utils.clip_grad_norm_` |
| OOM | Training loop | Add gradient checkpointing, reduce batch |
| Slow convergence | Optimizer | Switch Adam → AdamW, tune LR schedule |
| Bad data | Dataset | Run ds-dataval, filter invalid samples |

---

## Stopping Criteria

Stop when:
- `validity_rate > 0.85` AND `diversity_score > baseline * 1.5`
- OR 6 iterations completed
- OR two consecutive iterations produce < 2% improvement on primary metric

Report final metrics and what changed.
