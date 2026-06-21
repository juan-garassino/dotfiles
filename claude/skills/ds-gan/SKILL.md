---
name: ds-gan
description: >
  Helps write, improve, and debug 3D GAN code for DeepSculpt — generator and
  discriminator architectures using 3D convolutions, loss functions, training loop
  patterns, and mode collapse detection. Use when designing the GAN architecture,
  writing 3D conv layers, debugging training instability, improving loss functions,
  or fixing gradient issues specific to volumetric GANs. Triggers include "write
  the generator", "design the discriminator", "the gan is collapsing", "3d
  convolution architecture", "improve the loss function", "the training is unstable",
  "write the gan training loop", "fix mode collapse", "wasserstein loss for 3d gan".
---

# ds-gan — DeepSculpt 3D GAN

You help write and improve GAN code for volumetric 3D/4D data. You understand
the specific failure modes of 3D GANs and how architecture and training choices
compound when working with cubic volumes.

---

## Architecture Conventions

### Input / Output shapes

```python
# Generator: Z → Volume
# Input:  (B, latent_dim)
# Output: (B, 1, D, H, W)     monochrome
#         (B, 4, D, H, W)     color (RGBA channels-first)

# Discriminator: Volume → Real/Fake score
# Input:  (B, 1, D, H, W) or (B, 4, D, H, W)
# Output: (B, 1)              vanilla GAN
#         (B,)                WGAN
```

**Always use channels-first** `(B, C, D, H, W)` for PyTorch 3D convolutions.
The dataset returns channels-last `(D, H, W, C)` — add a `.permute()` in the
training loop, not in the model.

---

## Generator Architecture

```python
import torch
import torch.nn as nn

class Generator3D(nn.Module):
    def __init__(self, latent_dim: int = 128, resolution: int = 64,
                 base_channels: int = 256, out_channels: int = 1):
        super().__init__()
        self.resolution = resolution
        self.init_size = resolution // 16   # 4 for res=64

        self.fc = nn.Linear(latent_dim, base_channels * self.init_size**3)

        self.conv_blocks = nn.Sequential(
            # (B, 256, 4, 4, 4)
            nn.BatchNorm3d(base_channels),
            *self._upsample_block(base_channels, base_channels // 2),   # → 8³
            *self._upsample_block(base_channels // 2, base_channels // 4),  # → 16³
            *self._upsample_block(base_channels // 4, base_channels // 8),  # → 32³
            *self._upsample_block(base_channels // 8, base_channels // 16), # → 64³
            nn.Conv3d(base_channels // 16, out_channels, 3, padding=1),
            nn.Sigmoid(),  # output [0, 1]
        )

    def _upsample_block(self, in_ch, out_ch):
        return [
            nn.Upsample(scale_factor=2, mode="trilinear", align_corners=False),
            nn.Conv3d(in_ch, out_ch, 3, padding=1),
            nn.BatchNorm3d(out_ch),
            nn.LeakyReLU(0.2, inplace=True),
        ]

    def forward(self, z):
        x = self.fc(z)
        x = x.view(x.size(0), -1, self.init_size, self.init_size, self.init_size)
        return self.conv_blocks(x)
```

---

## Discriminator Architecture

```python
class Discriminator3D(nn.Module):
    def __init__(self, resolution: int = 64, in_channels: int = 1,
                 base_channels: int = 16):
        super().__init__()

        def disc_block(in_ch, out_ch, bn=True):
            layers = [nn.Conv3d(in_ch, out_ch, 4, stride=2, padding=1)]
            if bn: layers.append(nn.BatchNorm3d(out_ch))
            layers.append(nn.LeakyReLU(0.2, inplace=True))
            return layers

        self.model = nn.Sequential(
            *disc_block(in_channels, base_channels, bn=False),  # 64→32
            *disc_block(base_channels, base_channels * 2),       # 32→16
            *disc_block(base_channels * 2, base_channels * 4),   # 16→8
            *disc_block(base_channels * 4, base_channels * 8),   # 8→4
            nn.Flatten(),
            nn.Linear(base_channels * 8 * (resolution // 16)**3, 1),
        )

    def forward(self, vol):
        return self.model(vol)
```

---

## Loss Functions

### Vanilla GAN (BCE)
```python
criterion = nn.BCEWithLogitsLoss()

def gan_losses(D, G, real, z, device):
    B = real.size(0)
    real_labels = torch.ones(B, 1, device=device)
    fake_labels = torch.zeros(B, 1, device=device)

    # Discriminator
    fake = G(z).detach()
    d_loss = criterion(D(real), real_labels) + criterion(D(fake), fake_labels)

    # Generator
    fake = G(z)
    g_loss = criterion(D(fake), real_labels)

    return d_loss, g_loss
```

### WGAN-GP (recommended for 3D — more stable)
```python
def gradient_penalty(D, real, fake, device, lambda_gp=10):
    B = real.size(0)
    alpha = torch.rand(B, 1, 1, 1, 1, device=device)
    interpolated = (alpha * real + (1 - alpha) * fake).requires_grad_(True)
    d_interp = D(interpolated)
    gradients = torch.autograd.grad(
        outputs=d_interp, inputs=interpolated,
        grad_outputs=torch.ones_like(d_interp),
        create_graph=True, retain_graph=True
    )[0]
    gradients = gradients.view(B, -1)
    gp = ((gradients.norm(2, dim=1) - 1) ** 2).mean()
    return lambda_gp * gp

def wgan_gp_losses(D, G, real, z, device):
    fake = G(z)
    d_loss = -D(real).mean() + D(fake.detach()).mean() + gradient_penalty(D, real, fake.detach(), device)
    g_loss = -D(fake).mean()
    return d_loss, g_loss
```

---

## Training Loop Pattern

```python
def train_epoch(G, D, loader, opt_G, opt_D, device,
                n_critic=5, use_wgan=True):
    G.train(); D.train()
    metrics = {"d_loss": [], "g_loss": [], "occ_rate": []}

    for i, real in enumerate(loader):
        real = real.to(device)
        if real.ndim == 5 and real.shape[-1] == 4:  # channels-last color
            real = real.permute(0, 4, 1, 2, 3)      # → channels-first
        B = real.size(0)
        z = torch.randn(B, G.latent_dim, device=device)

        # Train discriminator (n_critic times per G update)
        for _ in range(n_critic):
            opt_D.zero_grad()
            d_loss, _ = wgan_gp_losses(D, G, real, z, device) if use_wgan \
                        else gan_losses(D, G, real, z, device)
            d_loss.backward(); opt_D.step()

        # Train generator
        opt_G.zero_grad()
        _, g_loss = wgan_gp_losses(D, G, real, z, device) if use_wgan \
                    else gan_losses(D, G, real, z, device)
        g_loss.backward(); opt_G.step()

        # Track occupancy of generated samples (mode collapse indicator)
        with torch.no_grad():
            fake = G(torch.randn(8, G.latent_dim, device=device))
            occ = (fake > 0.5).float().mean().item()

        metrics["d_loss"].append(d_loss.item())
        metrics["g_loss"].append(g_loss.item())
        metrics["occ_rate"].append(occ)

    return {k: np.mean(v) for k, v in metrics.items()}
```

---

## Mode Collapse Detection

```python
def detect_mode_collapse(G, latent_dim: int, device,
                          n_samples: int = 64, threshold: float = 0.05) -> dict:
    """Generate samples and measure diversity."""
    G.eval()
    with torch.no_grad():
        z = torch.randn(n_samples, latent_dim, device=device)
        samples = G(z).cpu().numpy()

    # Pairwise diversity: mean L2 distance between samples
    flat = samples.reshape(n_samples, -1)
    dists = []
    for i in range(0, n_samples, 8):
        batch = flat[i:i+8]
        for j in range(len(batch)):
            for k in range(j+1, len(batch)):
                dists.append(np.linalg.norm(batch[j] - batch[k]))

    mean_dist = np.mean(dists)
    collapsed = mean_dist < threshold

    return {
        "mean_pairwise_distance": mean_dist,
        "collapsed": collapsed,
        "mean_occupancy": float((samples > 0.5).mean()),
        "occupancy_std": float((samples > 0.5).reshape(n_samples, -1).mean(axis=1).std()),
    }
```

---

## Common 3D GAN Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| Mode collapse | All outputs look the same | Switch to WGAN-GP, increase latent dim |
| Checkerboard artifacts | Grid pattern in voxels | Use trilinear upsample + conv instead of ConvTranspose3d |
| Training instability | Loss oscillates wildly | Lower LR for G, increase n_critic |
| Memory OOM | CUDA out of memory | Reduce base_channels or batch size first |
| Generator outputs all zeros | G found a bad minimum | Add occupancy regularization loss |
| Discriminator too strong | D loss → 0 immediately | Reduce D capacity or add noise to real samples |

---

## Reference Files

- `references/architecture_variants.md` — ProgressiveGAN 3D, StyleGAN3D sketch, patch discriminator patterns
