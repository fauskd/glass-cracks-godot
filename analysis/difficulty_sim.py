"""
Glass Cracks difficulty simulation.

Question: how often can a *perfect-aim* player clear each level, given only
the random jitter of each hit?  This is the upper bound of the win rate, so it
shows which levels are possible, which are too hard, and how the curve rises.

1. Find the best aim points for each level (equal-area pieces) with an
   iterative optimiser (Lloyd steps + random search).
2. Play 2,000 simulated attempts per level: aim at those points, add the
   game's jitter (uniform in a circle), measure every piece's area share.
"""
import numpy as np, json
from matplotlib.path import Path

LEVELS = [  # same numbers as main.gd
    ("First Crack", "rect", 2, 0.20, 8.0), ("Three Ways", "rect", 3, 0.20, 12.0),
    ("Sharp Corners", "triangle", 3, 0.20, 12.0), ("Window Pane", "rect", 4, 0.15, 15.0),
    ("Honeycomb", "hexagon", 4, 0.15, 18.0), ("Slanted", "trapezoid", 5, 0.15, 20.0),
    ("Six Shards", "hexagon", 6, 0.12, 22.0), ("Shatterpoint", "rect", 7, 0.10, 25.0)]
C = np.array([400.0, 330.0])

def shape(name):
    w, h = 260.0, 170.0
    if name == "triangle": pts = [(0, -h - 20), (w, h), (-w, h)]
    elif name == "hexagon": pts = [(np.cos(a) * 230, np.sin(a) * 200) for a in np.linspace(0, 2 * np.pi, 7)[:-1]]
    elif name == "trapezoid": pts = [(-150, -h), (150, -h), (w, h), (-w, h)]
    else: pts = [(-w, -h), (w, -h), (w, h), (-w, h)]
    return np.array(pts) + C

def grid(poly, step=4.0):
    xs = np.arange(poly[:, 0].min(), poly[:, 0].max(), step)
    ys = np.arange(poly[:, 1].min(), poly[:, 1].max(), step)
    g = np.array(np.meshgrid(xs, ys)).reshape(2, -1).T
    return g[Path(poly).contains_points(g)]

def shares(seeds, pts):
    d = ((pts[:, None, :] - seeds[None, :, :]) ** 2).sum(-1)
    return np.bincount(d.argmin(1), minlength=len(seeds)) / len(pts)

def worst_error(seeds, pts):
    n = len(seeds); return np.abs(shares(seeds, pts) * n - 1).max()

def best_aim(poly, n, pts, rng):
    best, best_e = None, 9
    for _ in range(6):                               # restarts
        s = pts[rng.choice(len(pts), n, replace=False)].astype(float)
        for _ in range(40):                          # Lloyd steps
            lab = ((pts[:, None] - s[None]) ** 2).sum(-1).argmin(1)
            s = np.array([pts[lab == k].mean(0) if (lab == k).any() else s[k] for k in range(n)])
        e = worst_error(s, pts)
        for _ in range(1500):                        # random search to equalise areas
            t = s + rng.normal(0, 6, s.shape)
            if not Path(poly).contains_points(t).all(): continue
            et = worst_error(t, pts)
            if et < e: s, e = t, et
        if e < best_e: best, best_e = s, e
    return best, best_e

def jitter(aim, r, poly, rng):
    out = aim.copy()
    for i, a in enumerate(aim):
        for _ in range(20):
            ang, rad = rng.uniform(0, 2 * np.pi), r * np.sqrt(rng.uniform())
            c = a + rad * np.array([np.cos(ang), np.sin(ang)])
            if Path(poly).contains_point(c): out[i] = c; break
    return out

if __name__ == "__main__":
    rng = np.random.default_rng(7); rows = []
    for name, shp, n, tol, jit in LEVELS:
        poly = shape(shp); pts = grid(poly); aim, e0 = best_aim(poly, n, pts, rng)
        wins = 0; errs = []
        for _ in range(2000):
            e = worst_error(jitter(aim, jit, poly, rng), pts); errs.append(e); wins += e <= tol
        rows.append({"level": name, "hits": n, "tolerance": tol, "jitter": jit,
                     "aim_error": float(e0), "win_rate": wins / 2000,
                     "median_worst_error": float(np.median(errs)), "aim": aim.tolist(), "errors": [float(x) for x in errs]})
        print(f"{name:14s} n={n} tol={tol:.2f} jit={jit:4.1f}  perfect-aim error {e0:.3f}  win rate {wins/2000:6.1%}")
    json.dump(rows, open("difficulty_results.json", "w"), indent=1)
