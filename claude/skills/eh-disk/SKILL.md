---
name: eh-disk
description: >
  Helps write accretion disk physics code for the evenHorizon black hole renderer.
  Covers the Novikov-Thorne temperature profile, relativistic Doppler beaming,
  gravitational redshift, observed flux computation, and disk emission spectrum.
  Use when implementing disk physics, computing the brightness of disk emission
  points, calculating Doppler factors, gravitational redshift, or the color/intensity
  mapping from disk temperature to pixel value. Triggers include "write the disk
  physics", "compute the doppler factor", "accretion disk temperature", "gravitational
  redshift", "disk emission", "observed flux", "why is one side brighter", "implement
  the brightness calculation", "disk color from temperature".
---

# eh-disk — Accretion Disk Physics

You help write the physics code that computes how bright each point on the accretion
disk appears to the observer. This involves three effects that all matter:

1. **Intrinsic emission** — how much light the disk emits at each radius
2. **Gravitational redshift** — the black hole's gravity dims and reddens light
3. **Doppler beaming** — the disk rotates, brightening the approaching side dramatically

The combination of all three produces Luminet's asymmetric, crescent-shaped image.

---

## The Physics (plain language)

### Why the disk is brighter on one side
The accretion disk rotates. One side moves toward the observer (blueshifted,
appearing brighter and bluer), the other moves away (redshifted, dimmer and redder).
This is relativistic Doppler beaming — the effect is much stronger than classical
Doppler because of the high orbital velocities near the black hole (v ≈ 0.5c at ISCO).

### Why the disk dims near the center
Gravitational redshift: photons climbing out of the black hole's gravity well lose
energy. At r = 6M (ISCO), the gravitational redshift factor is √(1-2/r) = √(2/3) ≈ 0.816.
Closer to the horizon, this goes to zero — light is infinitely redshifted at the horizon.

### The temperature profile
The disk is heated by viscous dissipation. The Novikov-Thorne model gives:
T(r) ∝ r^(-3/4) × f(r)^(1/4)
where f(r) = 1 - √(r_ISCO/r) is a correction that forces T→0 at the inner edge.

---

## Core Implementation

```python
import numpy as np

# Geometric units: G = c = M = 1
R_ISCO = 6.0   # inner edge of disk
RS = 2.0       # event horizon

def disk_temperature(r: float, r_isco: float = R_ISCO) -> float:
    """
    Novikov-Thorne thin disk temperature profile (normalized).
    Returns T(r)/T_peak — a value in [0, 1].

    r: emission radius (in units of M)
    """
    if r <= r_isco:
        return 0.0
    # Temperature profile: T ∝ [f(r)/r³]^(1/4)
    f = 1.0 - np.sqrt(r_isco / r)
    T4 = f / r**3
    return T4**(1/4)


# Normalize to peak temperature
def make_temperature_profile(r_min=R_ISCO, r_max=30, n=1000):
    rs = np.linspace(r_min * 1.001, r_max, n)
    Ts = np.array([disk_temperature(r) for r in rs])
    T_peak = Ts.max()
    return rs, Ts / T_peak


def gravitational_redshift(r: float) -> float:
    """
    Gravitational redshift factor for emission at radius r.
    g_grav = sqrt(1 - rs/r) = sqrt(1 - 2/r)  in units M=1

    Photon loses this fraction of its energy climbing out of the well.
    """
    if r <= RS:
        return 0.0
    return np.sqrt(1.0 - RS / r)


def orbital_velocity(r: float) -> float:
    """
    Circular orbital velocity at radius r (Schwarzschild, in units c=1).
    v = sqrt(M/r) / (1 - rs/r)   ... geometric units M=1

    At ISCO (r=6): v ≈ 0.5c — highly relativistic!
    """
    if r <= RS:
        return 1.0  # formally
    return np.sqrt(1.0 / r) / (1.0 - RS / r)


def doppler_factor(r: float, phi_disk: float,
                    observer_inclination_rad: float) -> float:
    """
    Relativistic Doppler factor for a disk element at (r, phi_disk).

    phi_disk: azimuthal angle of emission point in disk plane
              0 = near side, pi = far side, pi/2 = left side (approaching)
    observer_inclination_rad: observer angle from disk normal
                              0 = face-on, pi/2 = edge-on

    Returns g_doppler = observed_frequency / emitted_frequency
    g > 1: blueshift (approaching side → brighter)
    g < 1: redshift (receding side → dimmer)

    Uses Cunningham (1975) formula.
    """
    v = orbital_velocity(r)
    sin_i = np.sin(observer_inclination_rad)
    cos_phi = np.cos(phi_disk)

    # Component of orbital velocity toward observer
    # Disk rotates: approaching side at phi_disk = pi/2 (left)
    v_los = v * sin_i * np.sin(phi_disk)  # line-of-sight velocity

    # Special relativistic Doppler (+ gravitational from separate factor)
    gamma = 1.0 / np.sqrt(1.0 - v**2)
    g_doppler = 1.0 / (gamma * (1.0 - v_los))

    return g_doppler


def total_redshift_factor(r: float, phi_disk: float,
                           observer_inclination_rad: float) -> float:
    """
    Combined redshift factor g = g_grav × g_doppler.
    This is what multiplies the emitted frequency to get observed frequency.
    """
    g_grav = gravitational_redshift(r)
    g_dopp = doppler_factor(r, phi_disk, observer_inclination_rad)
    return g_grav * g_dopp


def observed_flux(r: float, phi_disk: float,
                   observer_inclination_rad: float,
                   temperature_normalized: float = None) -> float:
    """
    Observed specific flux from a disk element at (r, phi_disk).

    The key result: F_obs ∝ g^4 × F_emitted
    The g^4 factor comes from:
      - g for frequency shift of each photon
      - g for change in photon arrival rate (time dilation)
      - g² for solid angle change (aberration)

    temperature_normalized: T(r)/T_peak — if None, computed internally.
    """
    if r <= R_ISCO or r > 50:
        return 0.0

    g = total_redshift_factor(r, phi_disk, observer_inclination_rad)

    if temperature_normalized is None:
        temperature_normalized = disk_temperature(r)

    # Emitted bolometric flux ∝ T^4
    F_emitted = temperature_normalized**4

    # Observed flux
    F_obs = g**4 * F_emitted

    return max(0.0, F_obs)
```

---

## Disk Geometry

```python
def disk_phi_at_intersection(geodesic_phi_arrival: float,
                               image_chi: float,
                               observer_inclination_rad: float) -> float:
    """
    Given a photon's azimuthal arrival angle (from geodesic integration)
    and the image plane position angle chi, compute the disk azimuthal
    angle phi_disk at the emission point.

    This connects the ray tracing output to the disk physics input.

    geodesic_phi_arrival: total phi traveled by photon (from integration)
    image_chi: position angle on image plane (arctan2(beta, alpha))
    """
    # Luminet eq. (4): disk azimuthal angle
    # phi_disk = pi - chi  for primary image (n=0)
    # phi_disk = 2*pi - chi  for secondary (n=1)
    # General: phi_disk depends on number of half-orbits
    n_half_orbits = int(geodesic_phi_arrival / np.pi)
    if n_half_orbits % 2 == 0:
        phi_disk = np.pi - image_chi
    else:
        phi_disk = 2 * np.pi - image_chi
    return phi_disk % (2 * np.pi)
```

---

## Spectrum and Color

```python
def blackbody_peak_wavelength(T_normalized: float,
                               T_peak_K: float = 1e7) -> float:
    """Wien's law: peak wavelength in nm."""
    T_K = T_normalized * T_peak_K
    if T_K <= 0:
        return np.inf
    return 2.898e6 / T_K  # nm


def wavelength_to_rgb(wavelength_nm: float) -> tuple:
    """Approximate wavelength (nm) → RGB (0-1). Visible: 380-750nm."""
    w = wavelength_nm
    if w < 380 or w > 750:
        # UV/X-ray from hot disk → map to blue-white
        if w < 380:
            return (0.6, 0.7, 1.0)
        return (1.0, 0.3, 0.0)  # infrared → orange-red

    if w < 440:   r, g, b = (440-w)/(440-380), 0, 1
    elif w < 490: r, g, b = 0, (w-440)/(490-440), 1
    elif w < 510: r, g, b = 0, 1, (510-w)/(510-490)
    elif w < 580: r, g, b = (w-510)/(580-510), 1, 0
    elif w < 645: r, g, b = 1, (645-w)/(645-580), 0
    else:         r, g, b = 1, 0, 0
    return (r, g, b)


def disk_color(r: float, g_factor: float,
               T_peak_K: float = 1e7) -> tuple:
    """
    Map disk emission point to RGB color.

    Combines:
    - Temperature → blackbody spectrum → base color
    - g_factor → Doppler+gravitational shift of spectrum
    - Intensity scaling by g^4
    """
    T_norm = disk_temperature(r)
    T_obs_norm = T_norm * g_factor      # observed temperature (redshifted)
    wav = blackbody_peak_wavelength(T_obs_norm, T_peak_K)
    r_c, g_c, b_c = wavelength_to_rgb(wav)

    # Intensity scale by g^4 × T^4
    intensity = (g_factor**4) * (T_norm**4)
    intensity = np.clip(intensity, 0, 1)

    return (r_c * intensity, g_c * intensity, b_c * intensity)
```

---

## Validation Checks

```python
def validate_disk_physics():
    """Quick sanity checks — run these after implementing."""
    print("=== Disk Physics Validation ===")

    # 1. Temperature at ISCO should be 0
    T_isco = disk_temperature(R_ISCO)
    print(f"T(r=6, ISCO): {T_isco:.6f}  (should be ~0)")

    # 2. Gravitational redshift at event horizon → 0
    g_eh = gravitational_redshift(RS + 0.001)
    print(f"g_grav at r=2.001: {g_eh:.6f}  (should be ~0)")

    # 3. Gravitational redshift at large r → 1
    g_inf = gravitational_redshift(1000)
    print(f"g_grav at r=1000: {g_inf:.6f}  (should be ~1)")

    # 4. Doppler: approaching side (phi=pi/2) should be > 1
    inc = np.radians(80)
    g_approach = doppler_factor(R_ISCO, np.pi/2, inc)
    g_recede   = doppler_factor(R_ISCO, -np.pi/2, inc)
    print(f"g_dopp approaching: {g_approach:.4f}  (should be > 1)")
    print(f"g_dopp receding:    {g_recede:.4f}  (should be < 1)")

    # 5. Total flux ratio approaching vs receding ~ 10:1 at ISCO
    F_approach = observed_flux(R_ISCO * 1.05, np.pi/2, inc)
    F_recede   = observed_flux(R_ISCO * 1.05, -np.pi/2, inc)
    print(f"Flux ratio (approach/recede): {F_approach/(F_recede+1e-10):.2f}  (expect ~5-20)")
```

---

## Reference Files

- `references/cunningham1975.md` — Cunningham's transfer function formulas, exact Doppler+redshift equations for Kerr/Schwarzschild
