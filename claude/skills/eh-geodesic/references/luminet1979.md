# Luminet (1979) — Key Equations & Reference Values

Paper: "Image of a spherical black hole with thin accretion disc"
J.-P. Luminet, Astronomy & Astrophysics 75, 228-235 (1979)

---

## Setup

- Black hole: Schwarzschild (non-rotating), mass M
- Geometric units: G = c = M = 1 → rs = 2
- Observer: distance D >> rs, inclination angle i from disk plane
- Luminet used i = 80° (nearly edge-on) in his famous image

---

## Coordinate System

Observer at (r=D, θ=i, φ=0). Image plane coordinates:
- α: horizontal axis (perpendicular to projected disk axis)
- β: vertical axis

Impact parameter: b = √(α² + β²)

For photon coming from image point (α, β):
- b cos(χ) = α  where χ is position angle
- b sin(χ) = β

---

## Geodesic Equation (Binet Form)

d²u/dφ² + u = 3u²

where u = M/r (dimensionless, M=1 so u = 1/r)

Initial conditions for distant observer:
- u(0) = 1/D ≈ 0
- du/dφ(0) = -1/b  (negative = approaching)

---

## Key Radii

| Radius | Value (M=1) | Physical meaning |
|--------|------------|-----------------|
| rs | 2 | Event horizon (Schwarzschild radius) |
| r_photon | 3 | Photon sphere — unstable circular orbit |
| r_ISCO | 6 | Innermost stable circular orbit — inner edge of disk |
| r_disk_outer | ~20-30 | Outer edge of disk (Luminet used ~20) |

---

## Critical Impact Parameter

b_crit = 3√3 M ≈ 5.196 M

- b < b_crit: photon falls into black hole
- b = b_crit: photon orbits at r=3 (photon sphere) — infinite winding
- b > b_crit: photon escapes (may still orbit multiple times)

---

## Image Orders

| Image order | Description | b range |
|-------------|-------------|---------|
| n=0 (primary) | Direct photons — 0 half-orbits | b > b_crit |
| n=1 (secondary) | One extra half-orbit below disk | b slightly > b_crit |
| n=2 | Two extra half-orbits | b very slightly > b_crit |
| ... | Higher orders exponentially dimmer | b → b_crit |

The secondary image appears on the OPPOSITE side of the disk from the primary,
and is much dimmer (secondary ≈ 5% of primary brightness for typical configurations).

---

## Deflection Angle Table (approximate, M=1, i=90°)

| b | Total φ (radians) | Image type |
|---|------------------|-----------|
| 100 | π | Barely bent |
| 20 | 1.1π | Moderate bending |
| 10 | 1.3π | Strong bending |
| 6 | 2π | One full orbit |
| 5.3 | 3π | ~1.5 orbits (secondary) |
| 5.2 | 4π | ~2 orbits |
| 5.196... | ∞ | Photon sphere |

---

## Accretion Disk Emission

Novikov-Thorne thin disk temperature profile:

T(r) = T* × [1/r³ × (1 - √(r_ISCO/r))]^(1/4)

Where T* is set by the accretion rate. For visualization, we normalize T(r_ISCO) = 1.

Specific flux (bolometric): F(r) ∝ T(r)^4

---

## Relativistic Effects on Observed Intensity

Total flux ratio (observed/emitted):

F_obs/F_em = g^4

where g is the total redshift factor:

g = g_grav × g_doppler

Gravitational redshift:
g_grav = √(1 - 2/r)

Doppler factor (for circular orbit in Schwarzschild):
The orbital velocity: v = √(M/r) / (1 - 2M/r) ... (in geometric units)

Combined (Cunningham 1975):
g = √(1 - 3/r) / (1 + (L/E) × sin(i) × sin(φ_disk) / r)

where φ_disk is the azimuthal angle of the emission point in the disk plane.

---

## Isophote Coordinates

Luminet computed isophotes (lines of equal observed flux).
The image is NOT symmetric because:
1. The approaching side (left in Luminet's image) is Doppler blueshifted → brighter
2. The receding side is redshifted → dimmer
3. Gravitational lensing creates the secondary image below

---

## Numerical Parameters (Luminet 1979)

- Resolution: ~800 rays (by hand/computer)
- Observer inclination: i = 80°
- Observer distance: D >> rs
- Disk: r_in = 3rs = 6M, r_out = 20M
- Accretion rate: set so peak T ≈ 10^7 K (normalized)
- Integration: 4th order Runge-Kutta
- Step size: Δφ = 0.01 rad (smaller near photon sphere)
