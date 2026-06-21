---
name: ds-dataval
description: >
  Helps write validation, visualization, and sanity-check code for DeepSculpt's 3D/4D
  numpy volumetric arrays. Understands slice rendering, occupancy distribution checks,
  array shape validation, and dataset quality metrics. Use when you need to verify
  generated data before training, write a data inspection tool, debug bad samples,
  check dataset statistics, or visualize volumetric slices. Triggers include "validate
  the dataset", "visualize the volumes", "check the array shapes", "something looks
  wrong with the data", "write a data inspection script", "plot slices", "check for
  NaN in the arrays", "dataset quality check".
---

# ds-dataval — DeepSculpt Data Validation

You help write code that validates and visualizes volumetric numpy arrays before
they enter the training pipeline. Bad data causes silent training failures — catching
it early saves GPU time.

---

## Array Validation

Always validate these properties before training:

```python
def validate_volume(vol: np.ndarray, mode: str = "auto") -> dict:
    """
    Validate a single volumetric array.
    mode: "mono" (D,H,W), "color" (D,H,W,4), "auto" (infer)
    """
    issues = []
    stats = {}

    # Infer mode
    if mode == "auto":
        mode = "color" if vol.ndim == 4 and vol.shape[-1] == 4 else "mono"

    # Shape checks
    if mode == "mono":
        if vol.ndim != 3:
            issues.append(f"Expected 3D array, got {vol.ndim}D: {vol.shape}")
        elif len(set(vol.shape)) > 1:
            issues.append(f"Non-cubic volume: {vol.shape} — confirm this is intentional")
    elif mode == "color":
        if vol.ndim != 4 or vol.shape[-1] != 4:
            issues.append(f"Expected (D,H,W,4), got {vol.shape}")

    # Dtype
    if vol.dtype != np.float32:
        issues.append(f"dtype is {vol.dtype}, expected float32")

    # Value range
    vmin, vmax = vol.min(), vol.max()
    stats["min"] = float(vmin)
    stats["max"] = float(vmax)
    if vmin < -0.01 or vmax > 1.01:
        issues.append(f"Values out of [0,1]: min={vmin:.4f}, max={vmax:.4f}")

    # NaN / Inf
    if np.isnan(vol).any():
        issues.append(f"Contains {np.isnan(vol).sum()} NaN values")
    if np.isinf(vol).any():
        issues.append(f"Contains {np.isinf(vol).sum()} Inf values")

    # Occupancy
    occupancy = vol[..., 3] if mode == "color" else vol
    occ_rate = float((occupancy > 0.5).mean())
    stats["occupancy_rate"] = occ_rate
    if occ_rate < 0.001:
        issues.append(f"Nearly empty volume: occupancy={occ_rate:.4f}")
    if occ_rate > 0.99:
        issues.append(f"Nearly full volume: occupancy={occ_rate:.4f}")

    stats["issues"] = issues
    stats["valid"] = len(issues) == 0
    stats["mode"] = mode
    return stats
```

---

## Dataset-Level Validation

```python
def validate_dataset(root: str, n_sample: int = 100) -> dict:
    """Validate a random sample of the dataset."""
    files = sorted(glob.glob(f"{root}/**/*.npy", recursive=True))
    if not files:
        return {"error": f"No .npy files found in {root}"}

    sample = np.random.choice(files, min(n_sample, len(files)), replace=False)
    results = []
    for f in sample:
        try:
            vol = np.load(f)
            r = validate_volume(vol)
            r["file"] = f
            results.append(r)
        except Exception as e:
            results.append({"file": f, "valid": False, "issues": [str(e)]})

    n_valid = sum(r["valid"] for r in results)
    all_issues = [issue for r in results for issue in r.get("issues", [])]
    issue_counts = {}
    for i in all_issues:
        issue_counts[i] = issue_counts.get(i, 0) + 1

    return {
        "total_files": len(files),
        "sampled": len(sample),
        "valid": n_valid,
        "invalid": len(sample) - n_valid,
        "pass_rate": n_valid / len(sample),
        "top_issues": sorted(issue_counts.items(), key=lambda x: -x[1])[:5],
        "occupancy_mean": np.mean([r.get("occupancy_rate", 0) for r in results]),
        "occupancy_std": np.std([r.get("occupancy_rate", 0) for r in results]),
    }
```

---

## Visualization

### Orthographic slice viewer (matplotlib)

```python
def plot_slices(vol: np.ndarray, title: str = "", n_slices: int = 5,
                save_path: str = None):
    """Plot XY, XZ, YZ slices through the center of the volume."""
    import matplotlib.pyplot as plt

    if vol.ndim == 4:  # color — extract occupancy for display
        display = vol[..., 3]
        color_mode = True
    else:
        display = vol
        color_mode = False

    D, H, W = display.shape
    indices = np.linspace(0, D-1, n_slices, dtype=int)

    fig, axes = plt.subplots(3, n_slices, figsize=(n_slices * 3, 9))
    fig.suptitle(title or "Volume Slices")

    for col, idx in enumerate(indices):
        axes[0, col].imshow(display[idx, :, :], cmap="gray", vmin=0, vmax=1)
        axes[0, col].set_title(f"XY z={idx}")
        axes[1, col].imshow(display[:, idx, :], cmap="gray", vmin=0, vmax=1)
        axes[1, col].set_title(f"XZ y={idx}")
        axes[2, col].imshow(display[:, :, idx], cmap="gray", vmin=0, vmax=1)
        axes[2, col].set_title(f"YZ x={idx}")
        for ax in axes[:, col]:
            ax.axis("off")

    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=120, bbox_inches="tight")
        print(f"Saved: {save_path}")
    else:
        plt.show()
    plt.close()
```

### Occupancy histogram

```python
def plot_occupancy_distribution(files: list, n_sample: int = 200,
                                 save_path: str = None):
    import matplotlib.pyplot as plt
    rates = []
    for f in np.random.choice(files, min(n_sample, len(files)), replace=False):
        vol = np.load(f)
        occ = vol[..., 3] if vol.ndim == 4 else vol
        rates.append((occ > 0.5).mean())
    plt.figure(figsize=(8, 4))
    plt.hist(rates, bins=40, color="#4a90d9", edgecolor="white")
    plt.xlabel("Occupancy rate")
    plt.ylabel("Count")
    plt.title("Dataset Occupancy Distribution")
    plt.axvline(np.mean(rates), color="red", linestyle="--",
                label=f"Mean: {np.mean(rates):.3f}")
    plt.legend()
    if save_path:
        plt.savefig(save_path, dpi=120, bbox_inches="tight")
    else:
        plt.show()
    plt.close()
```

---

## Common Data Quality Issues

| Issue | Symptom during training | Fix |
|-------|------------------------|-----|
| All-zero volumes | Generator learns to output nothing | Filter out in dataset |
| All-one volumes | Discriminator always wins | Filter out |
| dtype float64 | 2x memory, slow GPU transfer | Cast to float32 on save |
| Values > 1.0 | Loss NaN after normalization | Clip on load |
| Non-cubic arrays | Shape errors in 3D conv layers | Resize or crop |
| Missing color channel | IndexError in color pipeline | Validate ndim before training |
| Bimodal occupancy | Model learns two modes only | Check generator diversity |
