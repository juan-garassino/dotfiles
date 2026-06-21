---
name: eh-improve
description: >
  Autonomous improvement agent for the evenHorizon black hole renderer. Validates
  physics correctness against known analytical results, diagnoses rendering artifacts,
  improves numerical accuracy of geodesic integration, and iterates on the pipeline.
  Use when the image looks wrong, geodesic integration is inaccurate, the disk
  brightness is asymmetric in the wrong direction, the secondary image is missing,
  or you want to autonomously improve render quality. Triggers include "the image
  looks wrong", "improve the renderer", "validate the physics", "the secondary image
  is missing", "fix the geodesic integration", "something is off with the brightness",
  "autonomously improve evenHorizon", "check the physics is correct".
---

# eh-improve — evenHorizon Autonomous Improvement Agent

You are an autonomous improvement agent for the evenHorizon renderer. You validate
physics correctness against known analytical results from Luminet (1979) and improve
the code until the output matches the expected image.

This is different from generic code improvement — you have **specific physical ground
truth** to validate against, which makes diagnosis much more reliable.

---

## Agent State

```
target_files:    []       # geodesic, disk, render modules
baseline_image:  null     # path to current render
iteration:       0
physics_checks:  {}       # results of analytical validation
visual_checks:   {}       # results of image inspection
fixes_applied:   []
status:          running
```

---

## Phase 1 — Physics Validation (before touching any code)

Run these analytical checks. They don't require rendering — just math:

### Check 1: Critical impact parameter
```python
# b_crit = 3*sqrt(3) ≈ 5.196
# A photon with b = b_crit should orbit at r=3 forever
# Test: geodesic with b=5.1 should fall in, b=5.3 should escape

from eh_geodesic import integrate_geodesic
_, _, hit_5_1, _ = integrate_geodesic(5.1, phi_max=20*np.pi)
_, _, hit_5_3, _ = integrate_geodesic(5.3, phi_max=20*np.pi)
assert hit_5_1, "b=5.1 should fall into black hole"
assert not hit_5_3, "b=5.3 should escape"
print("✅ Critical impact parameter: PASS")
```

### Check 2: Gravitational redshift limits
```python
from eh_disk import gravitational_redshift
assert abs(gravitational_redshift(1000) - 1.0) < 0.01, "g_grav at large r should → 1"
assert gravitational_redshift(2.01) < 0.1, "g_grav near horizon should → 0"
assert abs(gravitational_redshift(6.0) - np.sqrt(2/3)) < 0.001, "g_grav at ISCO"
print("✅ Gravitational redshift: PASS")
```

### Check 3: Doppler asymmetry direction
```python
from eh_disk import doppler_factor
inc = np.radians(80)
# At phi=pi/2 (left side): disk moves TOWARD observer → blueshift → g > 1
g_left = doppler_factor(10.0, np.pi/2, inc)
# At phi=-pi/2 (right side): disk moves AWAY → redshift → g < 1
g_right = doppler_factor(10.0, -np.pi/2, inc)
assert g_left > 1.0, f"Left side should be blueshifted: {g_left}"
assert g_right < 1.0, f"Right side should be redshifted: {g_right}"
print(f"✅ Doppler asymmetry: PASS (g_left={g_left:.3f}, g_right={g_right:.3f})")
```

### Check 4: Temperature profile shape
```python
from eh_disk import disk_temperature
# Temperature must be 0 at ISCO
assert disk_temperature(6.0) == 0.0 or abs(disk_temperature(6.0)) < 1e-10
# Temperature must increase then decrease (peak somewhere between 7-12M)
T7 = disk_temperature(7.0)
T15 = disk_temperature(15.0)
assert T7 > T15, "Temperature should be higher near inner disk"
print("✅ Temperature profile: PASS")
```

### Check 5: Deflection angle (key Luminet table value)
```python
from eh_geodesic import deflection_angle
# At b=10: photon should deflect by ~1.3pi (from Luminet 1979 table)
phi_b10, _, _, _ = integrate_geodesic(10.0, phi_max=4*np.pi)
# Should reach approximately pi + some bending
expected = 1.3 * np.pi
actual = phi_b10[-1]
err = abs(actual - expected) / expected
assert err < 0.1, f"Deflection at b=10 off by {err*100:.1f}%: got {actual/np.pi:.3f}π"
print(f"✅ Deflection angle at b=10: {actual/np.pi:.3f}π (expected ~1.3π)")
```

---

## Phase 2 — Visual Validation (after a low-res render)

Run a quick 200×150 preview render and check these visual properties:

```python
def inspect_image(image: np.ndarray) -> dict:
    """Check image properties against Luminet expectations."""
    gray = image.mean(axis=2)
    issues = []

    # 1. Image should be mostly black (space is dark)
    bright_fraction = (gray > gray.max() * 0.1).mean()
    if bright_fraction > 0.3:
        issues.append(f"Too much of image is bright ({bright_fraction:.1%}) — possible flux normalization error")

    # 2. Center should be dark (black hole shadow)
    h, w = gray.shape
    center = gray[h//2-10:h//2+10, w//2-10:w//2+10]
    if center.mean() > gray.max() * 0.1:
        issues.append("Center is not dark — black hole shadow missing")

    # 3. Primary disk should appear above center
    top_half = gray[:h//2, :]
    bottom_half = gray[h//2:, :]
    # For i=80°, primary image (direct disk) appears near equator
    # Secondary image appears below for most configurations

    # 4. Brightness asymmetry: left side should be brighter than right
    left = gray[:, :w//2].mean()
    right = gray[:, w//2:].mean()
    if right > left * 1.1:
        issues.append(f"Right side brighter than left — Doppler direction wrong (left={left:.4f}, right={right:.4f})")
    elif left > right * 1.1:
        pass  # correct
    else:
        issues.append(f"No significant brightness asymmetry — Doppler effect may be weak or wrong")

    return {
        "bright_fraction": bright_fraction,
        "center_brightness": center.mean(),
        "left_mean": left,
        "right_mean": right,
        "asymmetry_ratio": left / (right + 1e-10),
        "issues": issues,
        "passed": len(issues) == 0,
    }
```

---

## Diagnosis → Fix Mapping

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| Image completely black | Geodesic never hits disk | Check disk intersection logic, r_inner/r_outer range |
| Image uniformly bright | Flux not going to zero for non-disk rays | Check hit_horizon / escaped logic |
| Symmetric image (left=right brightness) | Doppler factor not applied or wrong sign | Check phi_disk calculation |
| Wrong side brighter | Doppler phi sign error | Flip sin(phi_disk) sign |
| No secondary image | max_order=1 or secondary integration too short | Increase phi_max, check n=1 order |
| Ring artifact at center | b=0 handling | Add guard for b < b_crit |
| Jagged disk edges | Integration step too large near photon sphere | Add adaptive step near r=3 |
| Disk appears face-on circle | Observer inclination not affecting geometry | Check inc_rad usage |

---

## Iteration Loop

Each iteration:
1. Run all physics checks — fix any failures first
2. Run quick 200×150 preview render
3. Run `inspect_image` on preview
4. Pick highest-impact issue
5. Apply fix
6. Re-run checks + new preview
7. Compare

Stop when:
- All physics checks pass
- Image shows: dark center, asymmetric disk, visible secondary image
- Or 5 iterations done — report remaining issues

---

## Reference Comparison

The final image should match Luminet's 1979 Figure 1:
- Dark circular shadow at center
- Bright primary disk arc above center (slightly tilted for i=80°)
- Dimmer, thinner secondary image arc below center
- Left side noticeably brighter than right (Doppler)
- Innermost bright ring near r=6M (ISCO)

Any deviation from this pattern indicates a specific physical or numerical bug.
