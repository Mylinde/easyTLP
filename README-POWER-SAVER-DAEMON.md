# TLP Power Saver Daemon (tlp-psd)

A lightweight, intelligent, self-learning daemon that automatically switches between TLP power profiles based on system workload and behavioral patterns.

## Overview

**tlp-psd** continuously monitors system load and intelligently switches between three power profiles:

- **SAV** (power-saver): Aggressive power saving for idle/light workloads
  - SMT-aware CPU core scaling via cgroups v2 on systems with systemd. Scaled will be the system.slice and the user.slice.
- **BAL** (balanced): Balanced mode for typical work  
- **PRF** (performance): Maximum performance for heavy computational tasks


### Key Capabilities

**Zero Configuration**: Works optimally for any system without tuning  
**Self-Learning**: Personalizes thresholds based on your workload patterns  
**Pattern Recognition**: Detects and remembers recurring workload patterns  
**PROACTIVE SWITCHING**: Switches before workload escalates  
**Predictive System**: Learns whether trends are reliable for your system  
**Adaptive Learning**: Automatically tunes learning frequency based on trend confidence  
**State Persistence**: Survives daemon restarts and learns across sessions  
**Energy Optimized**: Maximizes battery life while maintaining responsiveness  
**Lightweight**: <1% CPU overhead, <800KB RAM

### Integration: scx_p2dq Kernel Scheduler

**tlp-psd includes the eBPF-based scx_p2dq scheduler 1.1.3** for adaptive kernel-level workload balancing.

#### What is scx_p2dq?
scx_p2dq is a modern **eBPF-based CPU scheduler** (using Linux's sched_ext framework) that intelligently manages per-core task scheduling. Unlike the default CFS (Completely Fair Scheduler), p2dq makes real-time decisions about which task runs on which core, optimizing for:
- **Task placement** based on cache locality and core utilization
- **Energy efficiency** through intelligent core grouping
- **Responsiveness** with priority-aware scheduling

**[→ For more information and detailed documentation, see the scx_p2dq README](scx/scheds/rust/scx_p2dq/README.md)**

#### Benefits for Battery Life & Responsiveness
- **Reduced CPU migrations**: Tasks stay on warm cores → lower L3 cache misses
- **Better cache utilization**: Cores share L3 caches efficiently → faster task execution
- **Adaptive core bundling**: Groups related tasks on adjacent cores → fewer frequency/voltage transitions
- **Energy-aware scheduling**: Considers power efficiency when placing tasks
- **Works with tlp-psd profiles**: Optimizes within SAV/BAL/PRF profiles for coordinated system-wide benefits

#### Why tlp-psd + scx_p2dq?
- **tlp-psd** switches high-level power profiles and predicts workload trends
- **scx_p2dq** optimizes low-level core utilization within each profile
- **Together**: Two-layer optimization for both power saving AND responsiveness

#### Automatic Operation
- **Hardware detection**: Enables advanced features on supported CPUs (AMD PSS)
- **No configuration needed**: Works out-of-the-box with sensible defaults
- **Graceful fallback**: Daemon continues without p2dq if unavailable (with warning)

**While **tlp-psd manages high-level power profiles** (SAV/BAL/PRF) and workload prediction, **scx_p2dq optimizes CPU core utilization within each profile**, ensuring that the system architecture itself adapts intelligently to your workload.

**The daemon runs only on battery power and stops automatically when AC is connected.**

### What Makes This Unique?

This is believed to be the **only Linux power management daemon** with:
1. **Unsupervised pattern learning** that adapts to your workload
2. **Proactive profile switching** (predicts load before it escalates)
3. **Two-confirmation validation** (eliminates false patterns automatically)
4. **Persistent cross-session learning** (improves every day you use it)
5. **Zero-dependency implementation** (pure shell + awk, no Python/ML frameworks)
6. **Kernel-level scheduler integration** (eBPF-based scx_p2dq for adaptive core balancing)

## How It Works

### Dual-Stage Profile Switching (Every configured cycle)

The daemon runs a continuous loop with **intelligent priority-based switching**:

#### **STAGE 1: Proactive Pattern-Matching (High Priority)**
If the daemon recognizes the current workload pattern with high confidence (HITS ≥ 2):
1. **Check current lag sequence** against learned permanent patterns
2. **Match at ≥90% similarity** with ±3 point tolerance (robust, high-confidence matching)
3. **Switch profile IMMEDIATELY** (don't wait for thresholds)
4. **Scale CPU cores FIRST**, then apply profile (ensures full core availability)
6. **Record pattern match** for validation
7. **Skip Stage 2** (threshold logic doesn't override)

**Result:** System reacts **milliseconds before** threshold-based!

#### **STAGE 2: Threshold-Based Fallback (Normal Logic)**
If no pattern matched OR pattern confidence is low:
1. **Measure lag score** (0-100) from CPU utilization and I/O-wait
2. **Sync target with current state** (prevents redundant same-profile switches)
3. **Apply adaptive thresholds** (personalized per workload)
4. **Decide profile** (SAV/BAL/PRF) with hysteresis to prevent oscillation
5. **Scale CPU cores**, then apply profile via TLP and set PM QoS constraints
7. **Record sample** in rolling history buffer

**Result:** Fallback to proven threshold logic if patterns unknown

### Intelligent Learning Cycle (Adaptive)

Every learning interval, the daemon executes the **EVALUATE→CALCULATE→PREDICT** cycle:

```
EVALUATE Phase:
  Compare previous PREDICTION_AVG vs actual LONGTERM_AVG
  → Update TREND_CONFIDENCE (0-100%)
  
CALCULATE Phase:
  Analyze historical distribution
  → Update optimal_low and optimal_offset
  
PREDICT Phase:
  Make weighted prediction for next period
  → Store for next evaluation cycle
  
Adapt Learning Interval (Confidence-Based):
  TREND_CONFIDENCE ≥ 75%: (excellent confidence, optimized)
  TREND_CONFIDENCE ≥ 50%: (good confidence, balanced)
  TREND_CONFIDENCE ≥ 25%: (learning phase, still adapting)
  TREND_CONFIDENCE < 25%: (early exploration, fast learning)
```

**📊 [See Proactive Dual-Stage Workflow Diagram →](docs/daemon_complete_workflow.svg)** for the complete two-stage architecture, pattern matching flow, and learning cycle.

### State Persistence

All learned parameters are saved to `/var/lib/tlp/psd-state.conf`:

```bash
LONGTERM_AVG=6           # Average lag score from current observation period
TREND_CONFIDENCE=85      # 0-100: How predictable are load trends?
ADAPT_THR_LOW=5          # SAV ↔ BAL boundary (below=SAV, above=BAL)
ADAPT_THR_HIGH=22        # BAL ↔ PRF boundary (below=BAL, above=PRF)
OPTIMAL_LOW=10           # Learned optimal SAV/BAL boundary (alternative)
LONGTERM_PERIOD=120      # Observation window (seconds) - dynamically calculated
HISTORY_SCORES=[...]     # All samples from current observation window
HISTORY_COUNT=30         # Number of samples in current window
LEARNING_INTERVAL=120    # Current learning/evaluation frequency (seconds)
PREDICTION_HITS=107      # Correct predictions made
PREDICTION_TOTAL=359     # Total prediction evaluations

# Learned permanent patterns (one line per pattern):
HIT_PATTERN_1_SCORES='3,4,5,4,3,5,6,4,0,0' HITS=12 TARGET_PROFILE='SAV'
HIT_PATTERN_2_SCORES='10,15,25,40,35,30,20,15,10,8' HITS=8 TARGET_PROFILE='BAL'
# ... more patterns ...
```

**All state persists across reboots** - daemon immediately returns to optimal settings!

### Status Example

Check daemon status with `tlp-psd status`:

```
=== TLP Power Saver Daemon Status ===

Daemon Runtime:
  2 days 4 hours 31 minutes 18 seconds

Estimated fullcharge Battery Life:
  5 hours 56 minutes 24 seconds

Intelligence:
  Confidence Level: 100/100 (14 min learning cycle)

Predictions:
  Accuracy: 458/538 (85%)

Learned Patterns:
  Total: 33 (SAV: 12, BAL: 18, PRF: 3)

Proactive Switches:
  Executed: 265

Profile Distribution:
  SAV: 90% | BAL: 8% | PRF: 2%

Energy Consumption:
  SAV: 310.95 Wh | BAL: 21.70 Wh | PRF: 4.78 Wh | Total: 337.43 Wh | Average: 6.42 Wh/h

Current Profile:
  SAV
```

## Self-Learning System

### How It Learns

The daemon continuously adapts its switching thresholds based on workload:

**(Fresh Install):**
- Starts with conservative defaults
- Records the load history
- Analyzes distribution pattern
- Evaluates whether predictions were accurate
- Recalculates optimal switching points
- Adjusts parameters automatically
- Persists learned state

**Example: Light Workload**

```
Initial state:
  SAV threshold: 5 (default)
  Load distribution: 0-5 range (85%), occasional spikes

  Daemon learns: "This system is idle most of the time"
  Adjustment: SAV threshold → 10
  Result: Spends 30% more time in power-saving mode

  Distribution stabilizes around 0-10 range
  Daemon confidence: 85%+
  Behavior: Very stable profile switching, maximum energy savings
```

### What Gets Learned

| Parameter | Purpose | Learns From |
|---|---|---|
| `ADAPT_THR_LOW` | SAV ↔ BAL boundary | Load distribution (0-5% of samples) |
| `ADAPT_THR_HIGH` | BAL ↔ PRF boundary | Load distribution (percentile analysis) |
| `OPTIMAL_LOW` | Fallback SAV threshold | Historical patterns |
| `TREND_CONFIDENCE` | Prediction reliability | Comparison of predicted vs actual load |
| `LEARNING_INTERVAL` | Optimal learning pace | Prediction accuracy |

### Monitoring Learning

```bash
# Check current learned state
doas cat /var/lib/tlp/psd-state.conf | head -20

# Example output showing learned thresholds:
LONGTERM_AVG=6
ADAPT_THR_LOW=5
ADAPT_THR_HIGH=22
TREND_CONFIDENCE=85
```

**What these numbers tell you:**

```
LONGTERM_AVG=6
  → Your typical lag score is 6
  → System spends most time doing light work

ADAPT_THR_LOW=5, ADAPT_THR_HIGH=22
  → Below 5: SAV profile (power-saving!)
  → 5-22: BAL profile (balanced)
  → Above 22: PRF profile (performance)
  → (Automatically personalized to YOUR usage!)

TREND_CONFIDENCE=85
  → Daemon is 85% confident in its predictions
  → Can use trend-based forecasting reliably
```

---

## Adaptive Threshold System

### Real-Time Threshold Adaptation

Every `SAV_DYNAMIC_INTERVAL` seconds (default 4s, configurable), the daemon:

1. **Calculates longterm_avg** (average of samples within the current observation window)
2. **Sets adaptive thresholds:**
   ```
   SAV threshold = longterm_avg - THRESHOLD_OFFSET
   PRF threshold = longterm_avg + THRESHOLD_OFFSET
   ```
3. **Applies hysteresis** to prevent oscillation

**Example: Light Workload System**

```
longterm_avg = 8 (very light)
THRESHOLD_OFFSET = 12

Result:
  SAV enters at: 8 - 12 = -4 (max 0, so 0-4 range)
  BAL range: 4-20
  PRF enters at: 8 + 12 = 20+

→ System spends 80% time in SAV (power-saving!)
```

**Example: Heavy Workload System**

```
longterm_avg = 65 (heavy)
THRESHOLD_OFFSET = 12

Result:
  SAV enters at: 65 - 12 = 53
  BAL range: 53-77
  PRF enters at: 65 + 12 = 77+

→ System hovers in BAL/PRF (performance-focused)
```

### Why Adaptive Thresholds?

Static thresholds (25, 75) don't fit every system:
- Light idle systems get stuck in BAL (not power-efficient)
- Heavy workload systems never reach SAV (wrong mode)
- Adaptive thresholds center on actual workload

---

## Predictive System

### How Predictions Work

The daemon learns whether trends are reliable for predicting future load:

```bash
Trend Calculation:
  trend = longterm_avg - last_profile_score

Prediction:
  predicted_avg = longterm_avg + (trend * TREND_CONFIDENCE / 100)
```

**Example: Rising Load**

```
History:
  t=0min: avg=5 (SAV)
  t=6min: avg=12 (BAL)
  trend = 12 - 5 = +7

Prediction with 80% confidence:
  predicted = 12 + (7 * 80/100) = 12 + 5.6 = 17.6
  
Actual result t=12min:
  actual = 18
  error = 18 - 17.6 = 0.4
  Result: Correct prediction! TREND_CONFIDENCE += 5
```

### Staged Evaluation

The daemon evaluates predictions in stages to safely build confidence:

| Stage | Sample Threshold | Confidence Boost | Penalty |
|---|---|---|---|
| Early | 40% of learning period | +5% correct | -10% wrong |
| Mid | 60% of learning period | +10% correct | -15% wrong |
| Late | 80% of learning period | +15% correct | -20% wrong |
| Full | 100% of learning period | +20% correct | -25% wrong |

**Dynamic Calculation:** Thresholds are calculated as percentages of the **dynamically-calculated observation period** (which starts at 120s minimum and adapts based on TREND_CONFIDENCE + prediction accuracy).

The formulas are:
```
EVAL_EARLY_THRESHOLD = LONGTERM_PERIOD × 40%
EVAL_MID_THRESHOLD   = LONGTERM_PERIOD × 60%
EVAL_LATE_THRESHOLD  = LONGTERM_PERIOD × 80%
EVAL_FULL_THRESHOLD  = LONGTERM_PERIOD × 100%
```

**Examples (with INTERVAL=4s and LONGTERM_PERIOD starting at 120s):**

With fresh start (LONGTERM_PERIOD=120s):
- Early: 48 samples = 192s ≈ 3.2 min
- Mid: 72 samples = 288s ≈ 4.8 min
- Late: 96 samples = 384s ≈ 6.4 min
- Full: 120 samples = 480s ≈ 8 min

With highly confident system (LONGTERM_PERIOD grows as TREND_CONFIDENCE increases):
- LONGTERM_PERIOD could become 240s-600s+ depending on confidence
- Thresholds automatically scale with the observation window
- More confident systems → longer observation windows → slower stage progression

**Note:** LONGTERM_PERIOD changes dynamically, so each daemon restart may have different threshold timings based on accumulated confidence.

**Why stages?** Early evaluations might be lucky. Only trust trends after they've proven themselves across multiple samples!

---

## Adaptive Learning Interval

### How Learning Frequency Adapts

The daemon automatically adjusts how often it re-evaluates based on trend confidence:

```
Trend Confidence    →  Learning Interval  →  Result
≥ 75%               →  Full Period           → Stable system, minimal overhead
≥ 50%               →  80% of Period         → Moderate confidence
≥ 25%               →  60% of Period         → Low confidence, more frequent checks
< 25%               →  40% of Period         → Uncertain, frequent re-evaluation
```

**Note:** Higher confidence = *longer* intervals (system is stable, less frequent updates needed). Lower confidence = *shorter* intervals (system is uncertain, needs more frequent checking).

### Example Learning Progression

**t=20 minutes (First evaluation, low confidence):**
```
TREND_CONFIDENCE: 20%
Result: LEARNING_INTERVAL = 40% of period ← Frequent re-evaluation (uncertain)
```

**t=50 minutes (Multiple evaluations, building confidence):**
```
TREND_CONFIDENCE: 60%
Result: LEARNING_INTERVAL = 80% of period ← Slower updates (more stable)
```

**t=2+ hours (Stable state, high confidence):**
```
TREND_CONFIDENCE: 85%
Result: LEARNING_INTERVAL = 100% of period ← Longest interval (system proven stable)
```

### Why Adaptive Intervals?

- **Uncertain systems** (chaotic workloads): Learn frequently with short intervals (40% period)
- **Predictable systems** (light office work): Longer intervals, minimal overhead (100% period)
- **Medium confidence**: Balanced frequency (60-80% period)
- **No tuning needed**: The daemon figures it out automatically!

---

## Intelligent Pattern Recognition & Proactive Switching

### The Game-Changer: Proactive vs Reactive

**Profile Switching (Reactive):**
```
System load rises gradually: 5 → 10 → 15 → 20 → 25
                                                  ↑
                                           Threshold triggered!
                                           Profile switches NOW
                                           (already overloaded for 2-3 seconds)
```

**Profile Switching (Proactive):**
```
Pattern-learning Phase:
  Load sequence: 3,4,5,4,6,5,7,10,25,40  (typical work)
  Threshold trigger point: 25
  System records this pattern
  
Next occurrence:
  Load sequence: 3,4,5,4,6,5,7,8,9...  (same pattern starting)
                          ↑↑↑ Pattern recognized!
                          Switch profile BEFORE load escalates
                          (predict: going to 25+ based on history)
                          
Result: Profile ready BEFORE system gets busy!
```

**Time-to-Responsiveness Comparison:**
- Threshold-based: ~2-3 seconds lag (wait for threshold + system reaction)
- Pattern-based: ~0.5 seconds (pattern match + profile switch)
- **Improvement: 5-6x faster response**

### Pattern Learning Flow

The daemon uses an intelligent **self-filtering pattern memory** that avoids artificial limits. Instead of a fixed top-10, patterns are validated through real-world repetition:

**How It Works:**

1. **First occurrence** → Pattern becomes a **Candidate**:
   ```bash
   /var/lib/tlp/candidates.conf (temporary file, one line per candidate):
   3,4,5,4,3,5,6,4,0,0:SAV
   ```
   (Format: 10 lag scores, colon separator, target profile)

2. **Pattern matches again?** → **Promoted to Permanent**:
   ```bash
   /var/lib/tlp/psd-state.conf (persistent file):
   HIT_PATTERN_1_SCORES='3,4,5,4,3,5,6,4,0,0' HITS=2 TARGET_PROFILE='SAV'
   ```
   (Now includes HITS count and persisted as variable assignment)

3. **Pattern matching** → Current workload compared against ALL permanent patterns:
   - Calculate similarity with each permanent pattern (0-100%)
   - Find **best matching pattern** (±3 point tolerance per sample)
   - If similarity ≥ 90%: **Pattern recognized!**
   - Use success history to boost confidence

4. **Automatic candidate management**:
   - Only candidates waiting for 2nd occurrence
   - No artificial slots or limits
   - Patterns proven by repetition, not guessed
   - One candidate at a time (simple, effective)

### Why Two-Confirmation is Better

**One-Hit Patterns Ignored (Filtered Automatically):**
```
Bad: System learns from every anomaly
  → 100 different workloads per day
  → Memory fills with garbage
  → Pattern matching becomes slow/useless

Good: Only proven recurring patterns stored
  → Only 5-10 real daily patterns learned
  → Junk automatically discarded
  → Fast pattern matching, light memory
```

### Pattern Recognition in Action

After 2-3 days of normal use:

```bash
# Check permanent patterns (proven recurring, have HITS count):
doas cat /var/lib/tlp/psd-state.conf | grep 'HIT_PATTERN'

HIT_PATTERN_1_SCORES='3,4,5,4,3,5,6,4,0,0' HITS=12 TARGET_PROFILE='SAV'
HIT_PATTERN_2_SCORES='10,15,25,40,35,30,20,15,10,8' HITS=8 TARGET_PROFILE='BAL'
HIT_PATTERN_3_SCORES='25,30,35,40,38,35,32,28,25,20' HITS=3 TARGET_PROFILE='PRF'

# Check temporary candidates (new patterns, waiting for 2nd occurrence):
doas cat /var/lib/tlp/candidates.conf

4,3,6,7,8,5,6,8,20,27:BAL
3,5,5,5,5,3,8,17,0,0:BAL
9,10,10,5,8,8,5,0,0,0:SAV
```

### Pattern Matching Algorithm

When evaluating whether current workload matches a stored pattern:

```
SIMILARITY = Number of samples within ±3 points of stored pattern
           / Total samples compared
           × 100%

Example - Perfect Match:
  Permanent pattern: [5, 4, 3, 5, 4, 3, 2, 4, 5, ...]
  Current workload:  [5, 5, 3, 5, 3, 3, 2, 5, 4, ...]
  Difference:        [0, 1, 0, 0, 1, 0, 0, 1, 1, ...]
  Within ±3:         [✓ ✓  ✓  ✓  ✓  ✓  ✓  ✓  ✓]
  Similarity = 9/9 = 100% → Perfect match! Pattern recognized.

Example - No Match:
  Permanent pattern: [5, 4, 3, 5, 4, 3, 2, 4, 5, ...]
  Different work:    [18,22,20,21,19,23,21,20,22,...]
  Difference:        [13,18,17,16,15,20,19,16,17,...]
  Within ±2:         [✗  ✗  ✗  ✗  ✗  ✗  ✗  ✗  ✗]
  Similarity = 0/9 = 0% → No match, not this pattern.
```

### Pattern Persistence & Cross-Session Learning

Permanent patterns survive daemon restarts and system reboots:

```bash
# Permanent patterns (persist across reboots):
/var/lib/tlp/psd-state.conf
  ↓ (survives reboot, daemon restart, system moves)

# Temporary candidates (auto-cleaned if redundant):
/var/lib/tlp/candidates.conf
  ↓ (removed if ≥80% similar to permanent pattern)
```

**What this means:**
- All patterns instantly recognized
- System has learned exactly the real work patterns
- No junk patterns cluttering memory (automatically filtered)
- Pattern memory is self-optimizing and automatically minimal

---

## Configuration

All parameters read from:
1. `/etc/tlp.conf` (main)
2. `/etc/tlp.d/*.conf` (drop-in config)
3. `/etc/tlp/defaults.conf` (fallback)

### Core Parameters

```bash
# Enable/disable daemon
POWER_SAVER_ENABLE=1

# Sampling interval (seconds) - how often to record a lag score
SAV_DYNAMIC_INTERVAL=4

# Number of samples for moving average
SAV_DYNAMIC_SAMPLES=4

# Hysteresis (points) - prevent oscillation
SAV_DYNAMIC_HYSTERESIS=5

# Minimum delay between profile switches (seconds)
SAV_DYNAMIC_MIN_DELAY=2

# Observation window is DYNAMICALLY CALCULATED (not a static config)
# Formula: (TREND_CONFIDENCE + prediction_accuracy) × SAV_DYNAMIC_INTERVAL
# Result is rounded to nearest minute, default fallback: 120 seconds

# Distance from longterm_avg for thresholds (points)
SAV_DYNAMIC_THRESHOLD_OFFSET=13

# Minimum score change to trigger profile switch (points)
SAV_DYNAMIC_SWITCH_DELTA=4
```

### What Each Parameter Controls

| Parameter | Effect |
|---|---|
| `SAV_DYNAMIC_INTERVAL=4` | Sampling interval in seconds (how often to measure lag score) |
| `SAV_DYNAMIC_SAMPLES=4` | Moving average window (average over last N samples) |
| `SAV_DYNAMIC_HYSTERESIS=5` | Need 5 point jump to exit current state (prevents bouncing) |
| `SAV_DYNAMIC_THRESHOLD_OFFSET=13` | Thresholds are ±13 from average (wider = more stable) |
| `SAV_DYNAMIC_SWITCH_DELTA=4` | Need 4 point change from last switch (prevents single-sample jitter) |
| `SAV_DYNAMIC_LONGTERM_PERIOD` | **Dynamically calculated** at daemon start based on TREND_CONFIDENCE + prediction accuracy. Formula: `(confidence + accuracy%) × INTERVAL`, rounded to nearest minute (default 120s minimum) |

### Typical Configurations

**Conservative (Very Stable Thresholds):**
```bash
SAV_DYNAMIC_THRESHOLD_OFFSET=20    # ±20 points (wider bands)
SAV_DYNAMIC_SWITCH_DELTA=10        # 10 point minimum (less responsive)
SAV_DYNAMIC_HYSTERESIS=8           # 8 point hysteresis (sticky)
```

**Aggressive (Responsive Switching):**
```bash
SAV_DYNAMIC_THRESHOLD_OFFSET=10    # ±10 points (tighter bands)
SAV_DYNAMIC_SWITCH_DELTA=2         # 2 point minimum (very responsive)
SAV_DYNAMIC_HYSTERESIS=3           # 3 point hysteresis (easy to switch)
```

**Default (Balanced):** (Already configured - no changes needed!)

---

## Understanding the Lag Score (0-100)

The daemon measures system load as a composite "lag score":

**0-25: Light Load (SAV ZONE)**
- System is nearly idle
- Light text editing, web browsing
- Profile: SAV (Power-Saver)

**25-75: Medium Load (BAL ZONE)**
- Normal working load
- Multiple apps, moderate compilation
- Profile: BAL (Balanced)

**75-100: Heavy Load (PRF ZONE)**
- High computational demand
- Video encoding, heavy builds
- Profile: PRF (Performance)

### How Lag Score Is Calculated

```bash
lag_score = (CPU utilization) + (I/O wait penalty) + (process queue factor)
```

**Components:**

1. **CPU Utilization (40%)**
   - Read from `/proc/stat`
   - Fast, accurate CPU measurement

2. **I/O Wait Penalty (40%)**
   - If I/O-wait > 50%, boost lag by 30 points
   - Detects disk-bound operations (database queries, file I/O)

3. **Load Average Factor (20%)**
   - If load avg > CPU count, boost by 20 points
   - Detects process queue buildup

4. **PM QoS Integration**
   - If applications request low latency, boost lag (performance mode)
   - Respects system requirements

---

## Monitoring & Debugging

### View Current State

```bash
doas cat /var/lib/tlp/psd-state.conf
```

Example output:
```
LONGTERM_AVG=6                          # Current 10-min average
ADAPT_THR_LOW=5                         # SAV ↔ BAL boundary
ADAPT_THR_HIGH=22                       # BAL ↔ PRF boundary
TREND_CONFIDENCE=85                     # 0-100: trend prediction reliability
LEARNING_INTERVAL=480                   # Current learning frequency (seconds)
PREDICTION_HITS=107                     # Correct predictions
PREDICTION_TOTAL=359                    # Total predictions (accuracy = 107/359 = 30%)
HISTORY_COUNT=125                       # Samples in 10-min window
```

### Enable Debug Logging

```bash
# Edit /etc/tlp.conf:
TLP_DEBUG="power-saver"

# View logs:
journalctl -u tlp-psd -f
```

### Monitor Specific Events

```bash
# Profile switches:
journalctl -u tlp-psd -f 2>&1 | grep "state="

# Learning updates:
journalctl -u tlp-psd -f 2>&1 | grep "Adjusting"

# Predictions:
journalctl -u tlp-psd -f 2>&1 | grep -i "prediction"

# Interval adaptation:
journalctl -u tlp-psd -f 2>&1 | grep "interval"
```

### Example Log Analysis

**Normal operation:**
```
state=SAV avg=3 applied profile: SAV          # Profile switched to SAV
Adaptive thresholds updated: low=5 high=35    # Thresholds recalculated
Prediction CORRECT: predicted=8, actual=9    # Learning working!
Learning interval adapted: accuracy=75% → 300s
```

**Learning in progress:**
```
State loaded: longterm_avg=6, optimal_low=10  # Loaded from previous session
Restored history: 125 samples, buckets=...    # History restored

State saved: longterm_avg=6, optimal_low=10   # Parameters persisted
(history_count=125)
```

---

## Battery Protection

The daemon includes automatic battery capacity management:

**When battery capacity < 20%:**
- PRF (Performance) profile → capped to BAL (Balanced)
- BAL profile → unchanged
- SAV profile → unchanged

This flexible approach:
- Reduces power consumption when critical
- Maintains Balance responsiveness
- Doesn't completely lock system to slow mode

---

## Performance Impact

| Metric | Value | Negligible? |
|---|---|---|
| CPU Overhead | < 0.1% | Yes |
| Memory Usage | ~350 KB | Yes |
| Disk I/O | Minimal (state only) | Yes |
| Latency Impact | None (async) | Yes |

---

## Troubleshooting

### "System never enters SAV profile"
- **Cause:** Workload genuinely doesn't idle (always 20+)
- **Check:** `journalctl -u tlp-psd -f` watch adaptive thresholds
- **Solution:** If workload is heavy by design, this is correct behavior!

### "System oscillates between profiles too much"
- **Check:** `TREND_CONFIDENCE` - if low (<40%), system is still learning
- **Solution:** Wait 1-2 hours for learning to stabilize
- **Manual fix:** Increase `SAV_DYNAMIC_HYSTERESIS=8` or `SAV_DYNAMIC_SWITCH_DELTA=8`

### "Not seeing LEARNING_INTERVAL adapt"
- **Check:** `PREDICTION_TOTAL` - need at least 5 predictions before interval changes
- **Solution:** Wait for learning cycle to complete (every 6-10 min)

### "State file not updating"
- **Check:** Daemon running? `systemctl status tlp-psd`
- **Solution:** Ensure `/var/lib/tlp/` is writable: `sudo ls -la /var/lib/tlp/`

---

## Architecture

The daemon is designed as a lightweight, stateless complementary service:

- **Separation of Concerns:** Daemon decides, TLP executes
- **External Execution:** Uses `/usr/sbin/tlp` command (no internal conflicts)
- **No D-Bus:** Simple, lightweight, no complex IPC
- **File-Based State:** Simple persistence mechanism
- **Battery-Only:** Automatic AC detection and shutdown

---

## License

GPL-2.0-or-later (same as TLP)

