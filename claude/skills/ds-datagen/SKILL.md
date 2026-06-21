---
name: ds-datagen
description: >
  Helps write, improve, and debug 3D/4D volumetric data generation code for DeepSculpt.
  Understands numpy 3D arrays for monochrome volumes and 4D arrays with color encoded
  in the 4th dimension. Use when writing shape primitives, procedural generation,
  augmentation pipelines, dataset loaders, or array serialization code. Triggers include
  "write the data generation code", "add a new shape primitive", "improve the dataset
  pipeline", "fix the array generation", "add augmentation", "the shapes look wrong",
  "help me generate training data", "write a dataset class for deepsculpt".
---

# ds-datagen — DeepSculpt Data Generation

You are an expert in volumetric data generation for 3D generative models. You help
write, improve, and debug the code that creates the numpy arrays that feed DeepSculpt's
training pipeline.

---

## Array Format Convention

Always confirm the project's convention before writing code. Standard DeepSculpt format:

```python
# Monochrome: (batch, depth, height, width) — dtype float32, values [0, 1]
volume = np.zeros((B, D, H, W), dtype=np.float32)

# Color: (batch, depth, height, width, 4) — RGBA encoded in 4th dim
volume = np.zeros((B, D, H, W, 4), dtype=np.float32)
# channel 0-2: RGB normalized [0, 1]
# channel 3:   occupancy/alpha [0, 1]
```

If the project uses a different convention, adapt immediately and document it.

---

## Shape Primitive Patterns

When writing primitive generation code, always:
- Accept resolution as a parameter (don't hardcode)
- Return float32 arrays normalized to [0, 1]
- Support both monochrome and 4D color output via a `color` flag
- Include a `noise` parameter for surface perturbation

```python
def make_sphere(resolution: int = 64, radius: float = 0.4,
                center: tuple = (0.5, 0.5, 0.5),
                color: tuple = (1.0, 1.0, 1.0),
                noise: float = 0.0) -> np.ndarray:
    """Generate a sphere volume. Returns (D, H, W) float32."""
    grid = np.mgrid[0:resolution, 0:resolution, 0:resolution]
    grid = grid / resolution  # normalize to [0, 1]
    dist = np.sqrt(sum((grid[i] - center[i])**2 for i in range(3)))
    if noise > 0:
        dist += np.random.normal(0, noise, dist.shape)
    return (dist <= radius).astype(np.float32)
```

---

## Common Primitives to Implement

| Primitive | Key parameters | Notes |
|-----------|---------------|-------|
| Sphere | radius, center, noise | Baseline shape |
| Cube/Box | size, center, rotation | Use rotation matrix |
| Cylinder | radius, height, axis | Specify axis (x/y/z) |
| Torus | major_r, minor_r | Implicit surface |
| Ellipsoid | radii (3,), center | Generalized sphere |
| Cone | radius, height, apex | Useful for testing GAN |
| Combinations | union, intersection, subtraction | Boolean ops on SDFs |

---

## Dataset Pipeline Patterns

```python
class DeepSculptDataset(torch.utils.data.Dataset):
    def __init__(self, root: str, resolution: int = 64,
                 mode: str = "mono",  # "mono" or "color"
                 augment: bool = True):
        self.files = sorted(glob.glob(f"{root}/**/*.npy", recursive=True))
        self.resolution = resolution
        self.mode = mode
        self.augment = augment

    def __len__(self): return len(self.files)

    def __getitem__(self, idx):
        vol = np.load(self.files[idx])  # (D, H, W) or (D, H, W, 4)
        if self.augment:
            vol = self._augment(vol)
        return torch.from_numpy(vol).float()

    def _augment(self, vol):
        # Random 90-degree rotations (preserve voxel structure)
        k = np.random.randint(4)
        axes = np.random.choice([0, 1, 2], size=2, replace=False)
        return np.rot90(vol, k=k, axes=axes).copy()
```

---

## Memory-Aware Generation

3D arrays grow as O(N³) — always check before allocating:

```python
def check_memory(resolution: int, n_samples: int, n_channels: int = 1,
                 dtype_bytes: int = 4):
    total_bytes = n_samples * resolution**3 * n_channels * dtype_bytes
    total_gb = total_bytes / 1e9
    available_gb = psutil.virtual_memory().available / 1e9
    if total_gb > available_gb * 0.8:
        raise MemoryError(
            f"Dataset would require {total_gb:.1f}GB but only "
            f"{available_gb:.1f}GB available. "
            f"Reduce resolution or use lazy loading."
        )
    return total_gb
```

Always recommend lazy loading (load from disk per batch) over pre-loading full datasets
into RAM for resolutions > 64³.

---

## 4D Color Encoding Patterns

```python
def mono_to_color(volume: np.ndarray,
                  color: tuple = (1.0, 0.8, 0.6)) -> np.ndarray:
    """Convert (D,H,W) mono volume to (D,H,W,4) RGBA."""
    occupancy = volume[..., np.newaxis]          # (D,H,W,1)
    rgb = np.ones((*volume.shape, 3)) * color    # (D,H,W,3)
    return np.concatenate([rgb * occupancy, occupancy], axis=-1).astype(np.float32)

def color_to_mono(volume: np.ndarray) -> np.ndarray:
    """Extract occupancy channel from (D,H,W,4) volume."""
    return volume[..., 3]
```

---

## Common Bugs to Watch For

- **Off-by-one in grid indexing** — use `np.linspace(0, 1, resolution)` not `np.arange(resolution) / resolution` when you want inclusive endpoints
- **Copy after rot90** — numpy rot90 returns a view; always `.copy()` before saving
- **dtype drift** — operations on float32 arrays can silently upcast to float64; always cast back
- **Resolution mismatch** — generator and discriminator must agree on spatial resolution; hardcoded mismatches are a common source of shape errors
- **Empty volumes** — Boolean primitive operations can produce all-zero arrays; add an assertion `assert vol.sum() > 0` after generation

---

## Reference Files

- `references/sdf_patterns.md` — Signed distance function patterns for implicit surface generation, boolean operations, smooth blending (smin)
