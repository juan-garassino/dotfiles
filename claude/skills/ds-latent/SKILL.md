---
name: ds-latent
description: >
  Helps write latent space navigation, exploration, and editing code for DeepSculpt.
  Covers interpolation between shapes, semantic direction discovery (PCA, GANSpace),
  latent space visualization, nearest-neighbor search in Z, and attribute-guided
  editing. Works with both GAN latent vectors and diffusion model latents. Use when
  writing interpolation code, finding semantic axes, building a latent browser,
  implementing GANSpace, or adding shape editing capabilities. Triggers include
  "interpolate between shapes", "find semantic directions", "navigate the latent space",
  "implement ganspace", "latent space visualization", "edit a shape attribute",
  "find the closest z to this shape", "write a latent browser", "pca on latent space".
---

# ds-latent — DeepSculpt Latent Space Navigation

You help write code for exploring and navigating the learned latent space of
DeepSculpt's generative models. This covers everything from basic interpolation
to semantic direction discovery to interactive shape editing.

---

## Interpolation

### Linear interpolation (lerp)
```python
def lerp(z1: torch.Tensor, z2: torch.Tensor,
         steps: int = 10) -> torch.Tensor:
    """Linearly interpolate between two latent vectors."""
    t = torch.linspace(0, 1, steps, device=z1.device)
    return torch.stack([z1 * (1 - ti) + z2 * ti for ti in t])
```

### Spherical interpolation (slerp) — better for high-dim Gaussian latents
```python
def slerp(z1: torch.Tensor, z2: torch.Tensor,
          steps: int = 10) -> torch.Tensor:
    """Spherical linear interpolation — preserves magnitude."""
    z1_n = z1 / z1.norm()
    z2_n = z2 / z2.norm()
    omega = torch.acos((z1_n * z2_n).sum().clamp(-1, 1))
    if omega.abs() < 1e-6:
        return lerp(z1, z2, steps)
    t = torch.linspace(0, 1, steps, device=z1.device)
    return torch.stack([
        (torch.sin((1-ti)*omega) * z1 + torch.sin(ti*omega) * z2) / torch.sin(omega)
        for ti in t
    ])
```

### Generate and render interpolation sequence
```python
def interpolation_sequence(G, z1, z2, steps=10, device="cuda",
                            save_dir="interpolation/"):
    """Generate volumes along an interpolation path and save slice previews."""
    import os; os.makedirs(save_dir, exist_ok=True)
    G.eval()
    zs = slerp(z1.to(device), z2.to(device), steps)
    with torch.no_grad():
        for i, z in enumerate(zs):
            vol = G(z.unsqueeze(0)).squeeze().cpu().numpy()
            # Save center slice
            D = vol.shape[0]
            import matplotlib.pyplot as plt
            fig, axes = plt.subplots(1, 3, figsize=(9, 3))
            for ax, (sl, title) in zip(axes, [
                (vol[D//2, :, :], "XY"),
                (vol[:, D//2, :], "XZ"),
                (vol[:, :, D//2], "YZ"),
            ]):
                ax.imshow(sl, cmap="gray", vmin=0, vmax=1)
                ax.set_title(f"Step {i} — {title}")
                ax.axis("off")
            plt.tight_layout()
            plt.savefig(f"{save_dir}/step_{i:03d}.png", dpi=80)
            plt.close()
    print(f"Saved {steps} frames to {save_dir}/")
```

---

## Semantic Direction Discovery

### PCA on sampled latents
```python
def find_pca_directions(G, latent_dim: int, n_samples: int = 2000,
                         n_components: int = 10, device: str = "cuda"):
    """Find principal directions in the generator's output space via PCA on Z."""
    from sklearn.decomposition import PCA

    G.eval()
    zs = torch.randn(n_samples, latent_dim, device=device)
    with torch.no_grad():
        # Use flat generator outputs as features
        vols = G(zs).view(n_samples, -1).cpu().numpy()

    pca = PCA(n_components=n_components)
    pca.fit(vols)

    print("Explained variance ratio:")
    for i, v in enumerate(pca.explained_variance_ratio_):
        print(f"  PC{i+1}: {v:.3f} ({v*100:.1f}%)")

    # Project PCA components back to Z space via linear regression
    from sklearn.linear_model import LinearRegression
    zs_np = zs.cpu().numpy()
    directions = []
    for i in range(n_components):
        scores = pca.transform(vols)[:, i]
        reg = LinearRegression().fit(zs_np, scores)
        direction = torch.tensor(reg.coef_, dtype=torch.float32)
        direction = direction / direction.norm()
        directions.append(direction)

    return directions, pca
```

### GANSpace-style editing
```python
def edit_along_direction(G, z: torch.Tensor, direction: torch.Tensor,
                          alphas: list = None, device: str = "cuda"):
    """Edit a latent by moving along a discovered direction."""
    if alphas is None:
        alphas = [-3, -2, -1, 0, 1, 2, 3]

    G.eval()
    results = []
    direction = direction.to(device)
    z = z.to(device)

    with torch.no_grad():
        for alpha in alphas:
            z_edit = z + alpha * direction
            vol = G(z_edit.unsqueeze(0)).squeeze().cpu().numpy()
            results.append((alpha, vol))

    return results
```

### Visualize direction effects
```python
def visualize_direction(G, direction: torch.Tensor, n_seeds: int = 4,
                         alphas: list = None, save_path: str = "direction.png",
                         device: str = "cuda"):
    """Show the effect of a direction across multiple random seeds."""
    import matplotlib.pyplot as plt
    if alphas is None:
        alphas = [-2, 0, 2]

    G.eval()
    fig, axes = plt.subplots(n_seeds, len(alphas),
                              figsize=(len(alphas) * 3, n_seeds * 3))

    for row in range(n_seeds):
        z = torch.randn(1, direction.shape[0], device=device)
        for col, alpha in enumerate(alphas):
            z_edit = z + alpha * direction.to(device)
            with torch.no_grad():
                vol = G(z_edit).squeeze().cpu().numpy()
            D = vol.shape[0]
            axes[row, col].imshow(vol[D//2], cmap="gray", vmin=0, vmax=1)
            axes[row, col].set_title(f"α={alpha}")
            axes[row, col].axis("off")

    plt.suptitle("Direction Effect")
    plt.tight_layout()
    plt.savefig(save_path, dpi=100)
    plt.close()
    print(f"Saved: {save_path}")
```

---

## Latent Space Search

### Find Z closest to a target volume
```python
def encode_by_optimization(G, target: np.ndarray, latent_dim: int,
                             n_steps: int = 500, lr: float = 0.01,
                             device: str = "cuda") -> torch.Tensor:
    """
    Find z such that G(z) ≈ target via gradient descent.
    Works without an encoder — pure optimization.
    """
    target_t = torch.from_numpy(target).unsqueeze(0).unsqueeze(0).to(device)
    z = torch.randn(1, latent_dim, device=device, requires_grad=True)
    optimizer = torch.optim.Adam([z], lr=lr)

    G.eval()
    for step in range(n_steps):
        optimizer.zero_grad()
        out = G(z)
        loss = F.mse_loss(out, target_t)
        loss.backward()
        optimizer.step()
        if step % 100 == 0:
            print(f"Step {step}: loss={loss.item():.6f}")

    return z.detach()
```

---

## Latent Grid Browser

```python
def sample_grid(G, latent_dim: int, grid_size: int = 5,
                 device: str = "cuda", save_path: str = "grid.png"):
    """Sample a grid of random shapes for browsing the space."""
    import matplotlib.pyplot as plt
    G.eval()
    n = grid_size ** 2
    zs = torch.randn(n, latent_dim, device=device)

    with torch.no_grad():
        vols = G(zs).squeeze(1).cpu().numpy()

    fig, axes = plt.subplots(grid_size, grid_size,
                              figsize=(grid_size * 3, grid_size * 3))
    for i, ax in enumerate(axes.flat):
        D = vols[i].shape[0]
        ax.imshow(vols[i][D//2], cmap="gray", vmin=0, vmax=1)
        ax.axis("off")

    plt.tight_layout()
    plt.savefig(save_path, dpi=100)
    plt.close()
    print(f"Grid saved: {save_path}")
```

---

## Diffusion Latent Navigation

For diffusion models, "latent navigation" works differently — you navigate the
**noise trajectory** rather than a fixed Z vector:

```python
def diffusion_interpolate(model, schedule, vol1: np.ndarray, vol2: np.ndarray,
                           t_mix: int = 500, steps: int = 5, device: str = "cuda"):
    """
    Interpolate between two volumes via diffusion:
    1. Add noise to both at timestep t_mix
    2. Interpolate the noisy versions
    3. Denoise the interpolated noisy volume
    """
    x1 = torch.from_numpy(vol1).unsqueeze(0).unsqueeze(0).to(device)
    x2 = torch.from_numpy(vol2).unsqueeze(0).unsqueeze(0).to(device)
    t = torch.tensor([t_mix], device=device)

    noise1 = torch.randn_like(x1)
    noise2 = torch.randn_like(x2)
    xt1, _ = q_sample(x1, t, schedule, noise1)
    xt2, _ = q_sample(x2, t, schedule, noise2)

    results = []
    for alpha in torch.linspace(0, 1, steps):
        xt_mix = (1 - alpha) * xt1 + alpha * xt2
        # Denoise from t_mix back to 0
        denoised = ddim_sample_from(model, schedule, xt_mix, t_mix, device)
        results.append(denoised.squeeze().cpu().numpy())

    return results
```

---

## Reference Files

- `references/ganspace.md` — Full GANSpace implementation, layer-wise direction discovery, attribute annotation workflow
