---
name: ds-diffusion
description: >
  Helps write, improve, and debug 3D diffusion model code for DeepSculpt — noise
  schedules, 3D UNet architecture, DDPM/DDIM sampling, forward and reverse process,
  and training loop patterns for volumetric data. Use when writing the diffusion
  pipeline, designing the denoising network, implementing noise schedules, debugging
  sampling quality, or improving the reverse diffusion process. Triggers include
  "write the diffusion model", "implement ddpm for 3d", "design the 3d unet",
  "noise schedule", "the samples look noisy", "implement ddim sampling",
  "diffusion training loop", "write the denoising network", "fix the reverse process".
---

# ds-diffusion — DeepSculpt 3D Diffusion

You help write and improve diffusion model code for volumetric 3D/4D data.
You understand DDPM/DDIM for spatial data and the adaptations needed when
working with cubic volumes instead of 2D images.

---

## Core Concepts for 3D Diffusion

Everything from 2D diffusion applies — the key differences:
- All convolutions are `nn.Conv3d` instead of `nn.Conv2d`
- Memory scales as O(N³) — attention must be used sparingly
- Batch sizes are necessarily small — use gradient accumulation
- The noise schedule doesn't change (it's over timesteps, not spatial dims)

---

## Noise Schedule

```python
import torch
import numpy as np

def make_beta_schedule(schedule: str = "cosine", n_steps: int = 1000,
                        beta_start: float = 1e-4, beta_end: float = 0.02):
    if schedule == "linear":
        return torch.linspace(beta_start, beta_end, n_steps)

    elif schedule == "cosine":
        # Nichol & Dhariwal 2021 — better for low-resolution volumes
        steps = n_steps + 1
        t = torch.linspace(0, n_steps, steps) / n_steps
        alphas_bar = torch.cos((t + 0.008) / 1.008 * torch.pi / 2) ** 2
        alphas_bar = alphas_bar / alphas_bar[0]
        betas = 1 - (alphas_bar[1:] / alphas_bar[:-1])
        return betas.clamp(0, 0.999)

    elif schedule == "quadratic":
        return torch.linspace(beta_start**0.5, beta_end**0.5, n_steps) ** 2

    raise ValueError(f"Unknown schedule: {schedule}")


class DiffusionSchedule:
    def __init__(self, n_steps: int = 1000, schedule: str = "cosine"):
        self.n_steps = n_steps
        betas = make_beta_schedule(schedule, n_steps)
        alphas = 1 - betas
        self.alphas_bar = torch.cumprod(alphas, dim=0)
        self.betas = betas
        self.sqrt_alphas_bar = self.alphas_bar.sqrt()
        self.sqrt_one_minus_alphas_bar = (1 - self.alphas_bar).sqrt()

    def to(self, device):
        self.alphas_bar = self.alphas_bar.to(device)
        self.betas = self.betas.to(device)
        self.sqrt_alphas_bar = self.sqrt_alphas_bar.to(device)
        self.sqrt_one_minus_alphas_bar = self.sqrt_one_minus_alphas_bar.to(device)
        return self
```

---

## Forward Process

```python
def q_sample(x0: torch.Tensor, t: torch.Tensor,
             schedule: DiffusionSchedule, noise: torch.Tensor = None):
    """Add noise to x0 at timestep t. Returns noisy sample."""
    if noise is None:
        noise = torch.randn_like(x0)
    # Gather per-sample schedule values
    sqrt_ab = schedule.sqrt_alphas_bar[t].view(-1, 1, 1, 1, 1)
    sqrt_1ab = schedule.sqrt_one_minus_alphas_bar[t].view(-1, 1, 1, 1, 1)
    return sqrt_ab * x0 + sqrt_1ab * noise, noise
```

---

## 3D UNet Architecture

```python
class ResBlock3D(nn.Module):
    def __init__(self, in_ch, out_ch, time_emb_dim):
        super().__init__()
        self.time_mlp = nn.Sequential(nn.SiLU(), nn.Linear(time_emb_dim, out_ch))
        self.block1 = nn.Sequential(nn.GroupNorm(8, in_ch), nn.SiLU(),
                                     nn.Conv3d(in_ch, out_ch, 3, padding=1))
        self.block2 = nn.Sequential(nn.GroupNorm(8, out_ch), nn.SiLU(),
                                     nn.Conv3d(out_ch, out_ch, 3, padding=1))
        self.skip = nn.Conv3d(in_ch, out_ch, 1) if in_ch != out_ch else nn.Identity()

    def forward(self, x, t_emb):
        h = self.block1(x)
        h = h + self.time_mlp(t_emb)[:, :, None, None, None]
        h = self.block2(h)
        return h + self.skip(x)


class UNet3D(nn.Module):
    def __init__(self, in_channels: int = 1, base_channels: int = 32,
                 channel_mults: tuple = (1, 2, 4, 8),
                 n_steps: int = 1000, time_emb_dim: int = 128):
        super().__init__()

        # Sinusoidal time embedding
        self.time_mlp = nn.Sequential(
            SinusoidalPosEmb(time_emb_dim),
            nn.Linear(time_emb_dim, time_emb_dim * 4),
            nn.SiLU(),
            nn.Linear(time_emb_dim * 4, time_emb_dim),
        )

        channels = [base_channels * m for m in channel_mults]
        self.init_conv = nn.Conv3d(in_channels, base_channels, 3, padding=1)

        # Encoder
        self.down_blocks = nn.ModuleList()
        self.downs = nn.ModuleList()
        in_ch = base_channels
        for out_ch in channels:
            self.down_blocks.append(ResBlock3D(in_ch, out_ch, time_emb_dim))
            self.downs.append(nn.Conv3d(out_ch, out_ch, 4, stride=2, padding=1))
            in_ch = out_ch

        # Bottleneck
        self.mid = ResBlock3D(in_ch, in_ch, time_emb_dim)

        # Decoder
        self.up_blocks = nn.ModuleList()
        self.ups = nn.ModuleList()
        for out_ch in reversed(channels[:-1]):
            self.ups.append(nn.ConvTranspose3d(in_ch, out_ch, 4, stride=2, padding=1))
            self.up_blocks.append(ResBlock3D(out_ch * 2, out_ch, time_emb_dim))
            in_ch = out_ch

        self.final = nn.Conv3d(in_ch, in_channels, 1)

    def forward(self, x, t):
        t_emb = self.time_mlp(t)
        x = self.init_conv(x)
        skips = []
        for block, down in zip(self.down_blocks, self.downs):
            x = block(x, t_emb)
            skips.append(x)
            x = down(x)
        x = self.mid(x, t_emb)
        for up, block, skip in zip(self.ups, self.up_blocks, reversed(skips)):
            x = up(x)
            x = torch.cat([x, skip], dim=1)
            x = block(x, t_emb)
        return self.final(x)


class SinusoidalPosEmb(nn.Module):
    def __init__(self, dim):
        super().__init__()
        self.dim = dim
    def forward(self, t):
        device = t.device
        half = self.dim // 2
        emb = torch.log(torch.tensor(10000.0)) / (half - 1)
        emb = torch.exp(torch.arange(half, device=device) * -emb)
        emb = t[:, None].float() * emb[None, :]
        return torch.cat([emb.sin(), emb.cos()], dim=-1)
```

---

## Training Loop

```python
def train_step(model, x0, schedule, optimizer, device):
    B = x0.size(0)
    t = torch.randint(0, schedule.n_steps, (B,), device=device)
    xt, noise = q_sample(x0, t, schedule)

    pred_noise = model(xt, t)
    loss = F.mse_loss(pred_noise, noise)

    optimizer.zero_grad()
    loss.backward()
    torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
    optimizer.step()
    return loss.item()
```

---

## DDPM Sampling

```python
@torch.no_grad()
def ddpm_sample(model, schedule, shape, device, n_steps=None):
    """Generate a volume from pure noise via DDPM reverse process."""
    n_steps = n_steps or schedule.n_steps
    x = torch.randn(shape, device=device)

    for t in reversed(range(n_steps)):
        t_batch = torch.full((shape[0],), t, device=device, dtype=torch.long)
        pred_noise = model(x, t_batch)

        alpha = 1 - schedule.betas[t]
        alpha_bar = schedule.alphas_bar[t]
        alpha_bar_prev = schedule.alphas_bar[t-1] if t > 0 else torch.tensor(1.0)

        # DDPM update
        x0_pred = (x - (1 - alpha_bar).sqrt() * pred_noise) / alpha_bar.sqrt()
        x0_pred = x0_pred.clamp(-1, 1)

        mean = (alpha_bar_prev.sqrt() * schedule.betas[t] / (1 - alpha_bar)) * x0_pred + \
               (alpha.sqrt() * (1 - alpha_bar_prev) / (1 - alpha_bar)) * x

        if t > 0:
            noise = torch.randn_like(x)
            sigma = ((1 - alpha_bar_prev) / (1 - alpha_bar) * schedule.betas[t]).sqrt()
            x = mean + sigma * noise
        else:
            x = mean

    return x.clamp(0, 1)
```

## DDIM Sampling (faster — 50 steps instead of 1000)

```python
@torch.no_grad()
def ddim_sample(model, schedule, shape, device, n_steps=50, eta=0.0):
    timesteps = torch.linspace(0, schedule.n_steps - 1, n_steps, dtype=torch.long)
    x = torch.randn(shape, device=device)

    for i in reversed(range(len(timesteps))):
        t = timesteps[i]
        t_batch = torch.full((shape[0],), t, device=device, dtype=torch.long)
        t_prev = timesteps[i-1] if i > 0 else torch.tensor(0)

        pred_noise = model(x, t_batch)
        alpha_bar = schedule.alphas_bar[t]
        alpha_bar_prev = schedule.alphas_bar[t_prev] if i > 0 else torch.tensor(1.0)

        x0_pred = (x - (1 - alpha_bar).sqrt() * pred_noise) / alpha_bar.sqrt()
        x0_pred = x0_pred.clamp(-1, 1)

        sigma = eta * ((1 - alpha_bar_prev) / (1 - alpha_bar) * (1 - alpha_bar / alpha_bar_prev)).sqrt()
        direction = (1 - alpha_bar_prev - sigma**2).sqrt() * pred_noise
        x = alpha_bar_prev.sqrt() * x0_pred + direction
        if eta > 0 and i > 0:
            x = x + sigma * torch.randn_like(x)

    return x.clamp(0, 1)
```

---

## Common Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| Blurry samples | Over-smoothed volumes | Use cosine schedule, reduce beta_end |
| Training NaN | Loss → NaN after warmup | Clip gradients, lower LR, check input normalization |
| OOM on 64³ | CUDA OOM with batch > 2 | Use gradient checkpointing, reduce base_channels |
| Slow sampling | 1000 steps per sample | Switch to DDIM with 50-100 steps |
| Samples all noise | Reverse process diverges | Check schedule alignment between train and sample |
