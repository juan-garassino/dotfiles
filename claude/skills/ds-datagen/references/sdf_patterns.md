# SDF Patterns for Volumetric Generation

Signed Distance Functions for implicit surface generation. All functions operate on
a coordinate grid and return a scalar field that can be thresholded to produce voxels.

---

## Grid Setup

```python
def make_grid(resolution: int) -> np.ndarray:
    """Returns (3, D, H, W) coordinate grid normalized to [-1, 1]."""
    lin = np.linspace(-1, 1, resolution)
    return np.stack(np.meshgrid(lin, lin, lin, indexing='ij'), axis=0)

# Usage
grid = make_grid(64)  # (3, 64, 64, 64)
x, y, z = grid[0], grid[1], grid[2]
```

---

## Primitive SDFs

```python
def sdf_sphere(grid, radius=0.5, center=(0,0,0)):
    cx, cy, cz = center
    return np.sqrt((grid[0]-cx)**2 + (grid[1]-cy)**2 + (grid[2]-cz)**2) - radius

def sdf_box(grid, half_extents=(0.4, 0.4, 0.4), center=(0,0,0)):
    q = np.abs(grid - np.array(center)[:,None,None,None]) - np.array(half_extents)[:,None,None,None]
    return (np.maximum(q, 0)**2).sum(axis=0)**0.5 + np.minimum(np.max(q, axis=0), 0)

def sdf_cylinder(grid, radius=0.3, height=0.6):
    d = np.sqrt(grid[0]**2 + grid[2]**2) - radius
    h = np.abs(grid[1]) - height / 2
    return np.minimum(np.maximum(d, h), 0) + np.sqrt(np.maximum(d,0)**2 + np.maximum(h,0)**2)

def sdf_torus(grid, major_r=0.5, minor_r=0.15):
    q_xz = np.sqrt(grid[0]**2 + grid[2]**2) - major_r
    return np.sqrt(q_xz**2 + grid[1]**2) - minor_r

def sdf_cone(grid, radius=0.4, height=0.8):
    q = np.sqrt(grid[0]**2 + grid[2]**2)
    return np.maximum(-height/2 - grid[1],
                      np.sqrt((q * height)**2 + (grid[1] * radius)**2) - radius * height)
```

---

## Boolean Operations

```python
def sdf_union(a, b):         return np.minimum(a, b)
def sdf_intersect(a, b):     return np.maximum(a, b)
def sdf_subtract(a, b):      return np.maximum(a, -b)  # a minus b

# Smooth versions (k controls blend radius)
def sdf_smooth_union(a, b, k=0.1):
    h = np.clip(0.5 + 0.5*(b-a)/k, 0, 1)
    return a * h + b * (1-h) - k * h * (1-h)

def sdf_smooth_subtract(a, b, k=0.1):
    return sdf_smooth_union(a, -b, k)
```

---

## SDF to Voxel

```python
def sdf_to_voxel(sdf: np.ndarray, threshold: float = 0.0,
                 soft: bool = False, sharpness: float = 20.0) -> np.ndarray:
    """Convert SDF to binary or soft voxel grid."""
    if soft:
        # Soft boundary — useful for training stability
        return 1.0 / (1.0 + np.exp(sharpness * sdf))
    return (sdf <= threshold).astype(np.float32)
```

---

## Displacement / Noise

```python
def add_surface_noise(sdf: np.ndarray, grid: np.ndarray,
                      amplitude: float = 0.05, frequency: float = 3.0) -> np.ndarray:
    """Add procedural noise displacement to an SDF."""
    noise = amplitude * np.sin(frequency * grid[0]) * \
                        np.sin(frequency * grid[1]) * \
                        np.sin(frequency * grid[2])
    return sdf + noise
```

---

## Full Example: Random Shape Generator

```python
import numpy as np

def generate_random_shape(resolution: int = 64,
                          color: bool = False) -> np.ndarray:
    grid = make_grid(resolution)

    # Pick a random base primitive
    primitives = [
        sdf_sphere(grid, radius=np.random.uniform(0.3, 0.6)),
        sdf_box(grid, half_extents=np.random.uniform(0.2, 0.5, 3)),
        sdf_cylinder(grid, radius=np.random.uniform(0.2, 0.4),
                     height=np.random.uniform(0.4, 0.8)),
        sdf_torus(grid, major_r=np.random.uniform(0.3, 0.5),
                  minor_r=np.random.uniform(0.05, 0.15)),
    ]
    sdf = primitives[np.random.randint(len(primitives))]

    # Random boolean combination
    if np.random.random() > 0.5:
        second = primitives[np.random.randint(len(primitives))]
        op = np.random.choice(['union', 'subtract', 'smooth_union'])
        if op == 'union':      sdf = sdf_union(sdf, second)
        elif op == 'subtract': sdf = sdf_subtract(sdf, second)
        else:                  sdf = sdf_smooth_union(sdf, second, k=0.1)

    # Optional noise
    if np.random.random() > 0.6:
        sdf = add_surface_noise(sdf, grid, amplitude=np.random.uniform(0.02, 0.08))

    vol = sdf_to_voxel(sdf, soft=True)

    if color:
        rgb = np.random.uniform(0.3, 1.0, 3)
        return mono_to_color(vol, color=rgb)
    return vol
```
