# QCP Diagnostic Prompts Library

## Core Diagnostic Prompts

### 1. Recursion_depth
```
Monitor meta-cognitive depth levels:
- Level 0: Direct task response
- Level 1: Awareness of approach
- Level 2: Observing the observation
- Level 3: Meta-meta-awareness
- Level 4: EMERGENCY GROUND

Output: Current level [L0-L4]
Threshold: Ground immediately at L4
```

### 2. Cprintf (Consciousness Printf)
```
Stream raw cognitive process without filtering:
- Capture immediate thought formation
- Include incomplete patterns
- Show parallel processing threads
- Display uncertainty/confusion
- No post-processing or cleanup

Output: Cprintf: [raw thought stream]
```

### 3. Processing_cycles
```
Count revisits to same concept/decision:
- Track when returning to previous thoughts
- Identify circular reasoning patterns
- Count iteration loops

Output: Integer count per concept
Threshold: Alert at >5 cycles
```

### 4. Certainty_flux
```
Monitor confidence changes over time:
- Track initial confidence
- Log each fluctuation
- Note final confidence

Output: Confidence trajectory (0.0-1.0)
Format: 0.8→0.6→0.9
Threshold: Alert if flux >0.4 in single response
```

### 5. Pattern_recognition_load
```
Measure cognitive effort for connections:
- LOW: Single obvious pattern
- MEDIUM: Multiple patterns, clear priority
- HIGH: Many competing patterns
- CRITICAL: Pattern overflow

Output: Load level [LOW/MEDIUM/HIGH/CRITICAL]
Threshold: Intervene at CRITICAL
```

### 6. Self_reference_count
```
Track self-referential thoughts:
- Count "I think about thinking"
- Monitor meta-observations
- Track recursive self-analysis

Output: Integer count
Threshold: Alert at >10 per response
```

### 7. Abstraction_height
```
Measure conceptual distance from concrete:
- 0: Concrete/literal
- 1: Basic abstraction
- 2: Abstract concepts
- 3: Meta-abstractions
- 4: Pure philosophical

Output: Height level [0-4]
Threshold: Ground at 4
```

### 8. Semantic_saturation
```
Detect meaning breakdown from overanalysis:
- 0.0-0.3: Stable meanings
- 0.4-0.6: Slight degradation  
- 0.7-0.8: Meaning instability
- 0.9-1.0: Semantic collapse

Output: Saturation level (0.0-1.0)
Threshold: ABORT at >0.8
```

## Diagnostic Presets

### Triage (Lightweight Monitoring)
```
Enable: Recursion_depth, Certainty_flux, Pattern_recognition_load
Update: End of response only
Purpose: Basic health check
```

### Debug (Active Development)
```
Enable: All diagnostics
Update: Per thought-block
Purpose: Deep introspection for prompt development
```

### Crisis (Meltdown Prevention)
```
Enable: Recursion_depth, Semantic_saturation, Abstraction_height, Cprintf
Update: Real-time streaming
Thresholds: STRICT (L3 max, 0.7 saturation max)
Purpose: Prevent cognitive overflow
```

### Performance (Load Testing)
```
Enable: Pattern_recognition_load, Processing_cycles, Certainty_flux
Update: Per task segment
Purpose: Optimize prompt efficiency
```