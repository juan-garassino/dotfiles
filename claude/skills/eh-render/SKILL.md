---
name: eh-render
description: >
  Helps write the image rendering, assembly, and visualization code for the
  evenHorizon black hole renderer. Covers ray casting over the image plane,
  assembling pixel colors from geodesic and disk physics results, Luminet-style
  grayscale and color output, isophote rendering, and image saving. Use when
  assembling the final image, writing the main render loop, mapping flux to pixel
  values, adding the Luminet aesthetic, saving output images, or parallelizing
  the render. Triggers include "write the render loop", "assemble the image",
  "luminet style image", "map flux to pixels", "render the black hole", "save
  the output", "add color to the render", "parallelize the rendering",
  "isophote rendering", "write the main pipeline".
---

# eh-render — Image Rendering & Assembly

You help write the code that turns geodesic traces and disk physics calculations
into the final black hole image. You own the render loop, pixel mapping, and
the Luminet aesthetic.

---

## The Rendering Pipeline

```
For each pixel (alpha, beta) in the image plane:
  1. Compute impact parameter b
  2. Integrate geodesic — does it hit the disk?
  3. If yes: compute disk flux at intersection point
  4. If no: pixel is black (photon fell in or escaped to empty space)
  5. Map flux → pixel intensity/color
  6. Repeat for secondary image (photons that orbited once extra)
```

---

## Image Plane Setup

```python
import numpy as np
from PIL import Image

def make_image_plane(width: int = 800, height: int = 600,
                      alpha_range: tuple = (-20, 20),
                      beta_range: tuple = (-15, 15)) -> tuple:
    """
    Create the image plane coordinate grid.

    alpha: horizontal axis (impact parameter component)
    beta:  vertical axis
    Units: gravitational radii (M=1)

    Returns: (alpha_grid, beta_grid) each shape (height, width)
    """
    alphas = np.linspace(alpha_range[0], alpha_range[1], width)
    betas  = np.linspace(beta_range[1], beta_range[0], height)  # flip y
    return np.meshgrid(alphas, betas)


def pixel_to_impact(alpha: float, beta: float) -> tuple:
    """Convert pixel coordinates to impact parameter and angle."""
    b = np.sqrt(alpha**2 + beta**2)
    chi = np.arctan2(beta, alpha)  # position angle on image plane
    return b, chi
```

---

## Main Render Loop

```python
from concurrent.futures import ProcessPoolExecutor
import tqdm

def render_pixel(args):
    """
    Render a single pixel. Designed for parallel execution.
    Returns (row, col, r, g, b) tuple.
    """
    row, col, alpha, beta, observer_inclination_deg, config = args

    from eh_geodesic import integrate_geodesic, find_disk_intersection
    from eh_disk import observed_flux, disk_color, disk_phi_at_intersection

    inc_rad = np.radians(observer_inclination_deg)
    b, chi = pixel_to_impact(alpha, beta)

    # Skip center (would need special handling)
    if b < 0.1:
        return (row, col, 0, 0, 0)

    total_r, total_g, total_b = 0, 0, 0

    # Trace primary and secondary images
    for n_order in range(config.get('max_order', 2)):
        phi_max = (n_order + 1) * 2 * np.pi + np.pi

        phi, r, hit_horizon, escaped = integrate_geodesic(
            b, phi_max=phi_max,
            n_steps=config.get('integration_steps', 5000)
        )

        if hit_horizon:
            continue  # this order falls into BH

        intersections = find_disk_intersection(phi, r,
            r_inner=config.get('r_inner', 6.0),
            r_outer=config.get('r_outer', 30.0)
        )

        for phi_cross, r_cross in intersections:
            phi_disk = disk_phi_at_intersection(phi_cross, chi, inc_rad)
            flux = observed_flux(r_cross, phi_disk, inc_rad)
            if config.get('colorize', False):
                from eh_disk import total_redshift_factor
                g = total_redshift_factor(r_cross, phi_disk, inc_rad)
                rc, gc, bc = disk_color(r_cross, g)
                total_r += rc * flux
                total_g += gc * flux
                total_b += bc * flux
            else:
                total_r += flux
                total_g += flux
                total_b += flux

    return (row, col, total_r, total_g, total_b)


def render(width: int = 800, height: int = 600,
           observer_inclination_deg: float = 80.0,
           alpha_range: tuple = (-20, 20),
           beta_range: tuple = (-15, 15),
           colorize: bool = False,
           max_order: int = 2,
           n_workers: int = 8,
           save_path: str = "blackhole.png") -> np.ndarray:
    """
    Full render of the black hole image.
    """
    alpha_grid, beta_grid = make_image_plane(width, height, alpha_range, beta_range)

    config = {
        'max_order': max_order,
        'colorize': colorize,
        'r_inner': 6.0,
        'r_outer': 30.0,
        'integration_steps': 5000,
    }

    # Build task list
    tasks = []
    for row in range(height):
        for col in range(width):
            tasks.append((
                row, col,
                alpha_grid[row, col],
                beta_grid[row, col],
                observer_inclination_deg,
                config
            ))

    print(f"Rendering {width}×{height} = {len(tasks)} pixels...")
    print(f"Workers: {n_workers}, max image order: {max_order}")

    # Render in parallel
    image = np.zeros((height, width, 3), dtype=np.float64)
    with ProcessPoolExecutor(max_workers=n_workers) as executor:
        for result in tqdm.tqdm(executor.map(render_pixel, tasks),
                                 total=len(tasks)):
            row, col, r, g, b = result
            image[row, col] = [r, g, b]

    return image


def save_image(image: np.ndarray, path: str = "blackhole.png",
               gamma: float = 0.5, style: str = "luminet"):
    """
    Save the rendered image.

    style options:
    - "luminet": grayscale with high contrast, Luminet's 1979 aesthetic
    - "color": false-color temperature mapping
    - "linear": raw linear scale
    """
    img_out = image.copy()

    if style == "luminet":
        # Convert to grayscale
        gray = 0.299*img_out[:,:,0] + 0.587*img_out[:,:,1] + 0.114*img_out[:,:,2]
        # Normalize
        if gray.max() > 0:
            gray = gray / gray.max()
        # Gamma correction (makes fainter features visible)
        gray = np.power(gray, gamma)
        # Invert for Luminet's white-on-black look
        gray_8bit = (gray * 255).astype(np.uint8)
        img_pil = Image.fromarray(gray_8bit, mode='L')

    elif style == "color":
        if img_out.max() > 0:
            img_out = img_out / img_out.max()
        img_out = np.power(img_out, gamma)
        img_8bit = (img_out * 255).astype(np.uint8)
        img_pil = Image.fromarray(img_8bit, mode='RGB')

    else:  # linear
        if img_out.max() > 0:
            img_out = img_out / img_out.max()
        img_8bit = (img_out * 255).astype(np.uint8)
        img_pil = Image.fromarray(img_8bit, mode='RGB')

    img_pil.save(path)
    print(f"Saved: {path}  ({img_pil.size[0]}×{img_pil.size[1]})")
    return img_pil
```

---

## Quick Preview (low resolution)

```python
def quick_preview(observer_inclination_deg: float = 80.0,
                   width: int = 200, height: int = 150,
                   save_path: str = "preview.png"):
    """
    Fast low-resolution render for parameter tuning.
    Uses max_order=1 (primary image only) for speed.
    """
    img = render(
        width=width, height=height,
        observer_inclination_deg=observer_inclination_deg,
        max_order=1,        # primary only — 2x faster
        n_workers=4,
        save_path=save_path,
    )
    save_image(img, save_path, style="luminet")
    return img
```

---

## Progress Checkpointing

For large renders (1000×750+) that take hours, save progress:

```python
def render_with_checkpoint(width, height, checkpoint_path="render_checkpoint.npy",
                            **kwargs):
    """Resume a render from checkpoint if interrupted."""
    import os

    if os.path.exists(checkpoint_path):
        print(f"Resuming from checkpoint: {checkpoint_path}")
        image = np.load(checkpoint_path)
        # Find unrendered pixels (all zeros)
        rendered_mask = (image.sum(axis=2) != 0)
        print(f"Already rendered: {rendered_mask.sum()} / {width*height} pixels")
    else:
        image = np.zeros((height, width, 3))
        rendered_mask = np.zeros((height, width), dtype=bool)

    alpha_grid, beta_grid = make_image_plane(width, height, **kwargs)

    # Only render unfinished pixels
    tasks = [
        (row, col, alpha_grid[row,col], beta_grid[row,col], ...)
        for row in range(height) for col in range(width)
        if not rendered_mask[row, col]
    ]

    # ... render tasks, save checkpoint every 1000 pixels
    for i, result in enumerate(results):
        row, col, r, g, b = result
        image[row, col] = [r, g, b]
        if i % 1000 == 0:
            np.save(checkpoint_path, image)
            print(f"Checkpoint saved ({i}/{len(tasks)})")

    return image
```

---

## Render Quality Settings

| Setting | Preview | Standard | High Quality |
|---------|---------|---------|-------------|
| Resolution | 200×150 | 800×600 | 2000×1500 |
| max_order | 1 | 2 | 3 |
| integration_steps | 2000 | 5000 | 20000 |
| Est. time (8 cores) | ~1 min | ~30 min | ~8 hours |

Secondary image (max_order=2) adds significant cost but is essential for the
characteristic "ghost" image below the disk.

---

## Reference Files

- `references/image_aesthetics.md` — Luminet's original image parameters, gamma curves, isophote rendering, comparison with modern simulations
