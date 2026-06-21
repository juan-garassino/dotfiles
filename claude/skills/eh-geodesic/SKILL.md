---
name: eh-geodesic
description: >
  Helps write photon geodesic integration code for the evenHorizon black hole
  renderer. Understands Schwarzschild spacetime, null geodesics, impact parameter,
  effective potential, and numerical ODE integration of photon paths around a black
  hole. Use when writing ray tracing code, implementing the geodesic equations,
  integrating photon orbits, computing light bending angles, or debugging photon
  path integration. Triggers include "write the geodesic code", "trace photon paths",
  "implement ray tracing for the black hole", "schwarzschild geodesics", "photon
  orbit", "light bending", "null geodesic integration", "implement the physics",
  "write the ray tracer for evenHorizon".
---

# eh-geodesic — Photon Geodesic Integration

You help write the gravitational ray tracing code at the heart of the evenHorizon
renderer. This is the hardest part of the project — integrating the equations of
motion for photons in curved spacetime around a black hole.

You explain the physics as you write the code, because understanding WHY each
equation exists helps debug it when results look wrong.

---

## The Physics (what you need to know)

### Schwarzschild spacetime
Luminet used a non-rotating (Schwarzschild) black hole. The geometry is described by:

```
ds² = -(1 - rs/r)c²dt² + (1 - rs/r)⁻¹dr² + r²dθ² + r²sin²θ dφ²
```

Where `rs = 2GM/c²` is the Schwarzschild radius (event horizon).
We work in **geometric units**: G=c=M=1, so `rs = 2`.

### Photon motion — the key insight
Photons travel on **null geodesics** (ds²=0). Because Schwarzschild spacetime has
spherical symmetry and is static, two quantities are conserved along each photon path:
- **Energy** E (from time symmetry)
- **Angular momentum** L (from spherical symmetry)

The ratio `b = L/E` is the **impact parameter** — the only thing that determines
the photon's path. Think of it as the perpendicular distance from the black hole
that the photon would have in flat space.

### The effective potential
The radial motion of a photon is governed by:

```
(dr/dλ)² = E² - (L²/r²)(1 - 2/r) = E²[1 - (b²/r²)(1 - 2/r)]
```

The term `V(r) = (b²/r²)(1 - 2/r)` is the **effective potential**.
- Photons with `b < b_crit = 3√3 ≈ 5.196` fall into the black hole
- Photons with `b > b_crit` escape to infinity (possibly after bending)
- At `r = 3` (the photon sphere), photons orbit forever

---

## Core Implementation

### Units and setup

```python
import numpy as np
from scipy.integrate import solve_ivp

# Geometric units: G = c = M = 1
# Schwarzschild radius rs = 2
RS = 2.0          # event horizon
R_PHOTON_SPHERE = 3.0
B_CRITICAL = 3 * np.sqrt(3)   # ≈ 5.196 — critical impact parameter
R_ISCO = 6.0      # innermost stable circular orbit (disk inner edge)
```

### Impact parameter from observer geometry

```python
def impact_parameter(alpha: float, beta: float,
                     observer_r: float, observer_inclination_deg: float) -> tuple:
    """
    Convert image plane coordinates (alpha, beta) to impact parameter b
    and initial conditions for geodesic integration.

    alpha: horizontal image coordinate (positive = left of center)
    beta:  vertical image coordinate
    observer_r: observer distance from black hole (e.g. 500M)
    observer_inclination_deg: angle between observer and disk plane (e.g. 80°)

    Returns: (b, phi_0, theta_0) initial conditions
    """
    inc = np.radians(observer_inclination_deg)
    # Impact parameter magnitude
    b = np.sqrt(alpha**2 + beta**2)
    # Position angle on image plane
    chi = np.arctan2(beta, alpha)
    return b, chi, inc
```

### The geodesic equation (Luminet's formulation)

Luminet (1979) reformulates the geodesic as `d²u/dφ²` where `u = 1/r`.
This is the Binet equation for GR:

```
d²u/dφ² + u = 3u²    (in geometric units M=1)
```

This is much cleaner to integrate than the full 4D geodesic:

```python
def geodesic_binet(phi, state, b):
    """
    Binet equation for photon geodesic in Schwarzschild spacetime.
    State: [u, du_dphi] where u = 1/r
    """
    u, du = state
    # d²u/dφ² = 3u² - u
    d2u = 3 * u**2 - u
    return [du, d2u]


def integrate_geodesic(b: float, phi_max: float = 2*np.pi,
                        u0: float = None, du0: float = None,
                        n_steps: int = 10000) -> tuple:
    """
    Integrate photon path from observer to source.

    b: impact parameter
    phi_max: maximum azimuthal angle to integrate
    u0: initial 1/r (default: 1/observer_r ≈ 0 for distant observer)
    du0: initial du/dphi (from geometry, depends on sign of approach)

    Returns: (phi_array, r_array, terminated_at_horizon, terminated_at_disk)
    """
    if b < 1e-10:
        # Straight through — hits singularity
        return np.array([0]), np.array([np.inf]), True, False

    # For a distant observer, u0 ≈ 0, du0 = -1/b (approaching)
    if u0 is None: u0 = 1e-6
    if du0 is None: du0 = -1.0 / b

    def event_horizon(phi, state, b):
        """Stop integration if photon reaches event horizon."""
        return state[0] - 1.0/RS  # u = 1/rs
    event_horizon.terminal = True
    event_horizon.direction = 1  # only trigger when u increasing (falling in)

    def escape(phi, state, b):
        """Stop if photon escapes back to large r."""
        return state[0] - 1e-5  # u ≈ 0 means r → ∞
    escape.terminal = True
    escape.direction = -1

    phi_span = (0, phi_max)
    phi_eval = np.linspace(0, phi_max, n_steps)

    sol = solve_ivp(
        geodesic_binet,
        phi_span,
        [u0, du0],
        args=(b,),
        method='RK45',
        t_eval=phi_eval,
        events=[event_horizon, escape],
        rtol=1e-8, atol=1e-10,
        dense_output=True,
    )

    u = sol.y[0]
    r = np.where(u > 1e-10, 1.0/u, np.inf)
    phi = sol.t

    hit_horizon = len(sol.t_events[0]) > 0
    escaped = len(sol.t_events[1]) > 0

    return phi, r, hit_horizon, escaped
```

### Find where photon hits the disk

```python
def find_disk_intersection(phi: np.ndarray, r: np.ndarray,
                            r_inner: float = R_ISCO,
                            r_outer: float = 30.0) -> tuple:
    """
    Find where the photon path intersects the accretion disk plane.
    The disk lies in the equatorial plane (theta = pi/2).

    For Luminet's setup, disk intersections occur at phi = n*pi
    (photon crosses equatorial plane).

    Returns: list of (phi_intersect, r_intersect) tuples
    """
    intersections = []
    for i in range(1, len(phi)):
        # Disk crossing: phi crosses a multiple of pi
        phi_frac_prev = phi[i-1] / np.pi
        phi_frac_curr = phi[i] / np.pi
        if int(phi_frac_prev) != int(phi_frac_curr):
            # Interpolate to find exact crossing
            t = (round(phi[i-1]/np.pi)*np.pi - phi[i-1]) / (phi[i] - phi[i-1])
            r_cross = r[i-1] + t * (r[i] - r[i-1])
            phi_cross = phi[i-1] + t * (phi[i] - phi[i-1])
            if r_inner <= r_cross <= r_outer:
                intersections.append((phi_cross, r_cross))
    return intersections
```

### Total deflection angle

```python
def deflection_angle(b: float, n_revolutions: int = 2) -> float:
    """
    Compute total bending angle for a photon with impact parameter b.
    n_revolutions: how many times around to integrate (1=primary, 2=secondary image)
    """
    phi, r, hit_horizon, escaped = integrate_geodesic(
        b, phi_max=n_revolutions * 2 * np.pi
    )
    if hit_horizon:
        return np.inf
    return phi[-1]
```

---

## Key Numbers to Validate Against

| Quantity | Value | Check |
|---------|-------|-------|
| Critical impact parameter | b_crit = 3√3 ≈ 5.196 | Photon sphere |
| ISCO radius | r = 6M | Inner disk edge |
| Photon sphere | r = 3M | Unstable photon orbit |
| Event horizon | r = 2M | rs |
| Primary image b range | b > 5.196 | Direct photons |
| Secondary image b | b slightly > 5.196 | One extra orbit |

---

## Common Bugs

- **Wrong sign of du0**: if du0 > 0 photon moves away from BH immediately — should be negative for approaching photon
- **Integration too short**: secondary images require phi_max > 2π — increase for higher-order images
- **Units**: mixing M=1 and rs=2 conventions causes factor-of-2 errors everywhere
- **Disk plane**: disk crossings at phi = nπ only for observer in equatorial plane — adjust for inclination

---

## Reference Files

- `references/luminet1979.md` — Key equations from Luminet's paper, table of b values vs deflection angles, image plane coordinate system
- `references/numerical_methods.md` — RK4 vs RK45 for stiff geodesics, step size selection near photon sphere
