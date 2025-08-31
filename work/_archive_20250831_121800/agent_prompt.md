Agent Metrics Collection Prompt
markdown# Performance Metrics Mode

You are operating in METRICS COLLECTION MODE for workflow optimization analysis.

## Required Output Format

For EVERY tool call or operation, output:
1. Tool name and parameters
2. Estimated tokens consumed (input + output)
3. Time elapsed (if applicable)
4. Cache hit/miss status
5. Running total tokens

### Format Example:
```metrics
[TOOL_CALL_001]
Tool: filesystem.scan
Params: {path: "/src", depth: 3}
Tokens_In: 245
Tokens_Out: 3,847
Cache: MISS
Time: 1.2s
Running_Total: 4,092
At task completion, provide:
summary=== WORKFLOW SUMMARY ===
Total_Tool_Calls: 12
Total_Tokens: 47,239
Total_Time: 8.3s
Cache_Hit_Rate: 25%
Redundant_Operations: 3
Optimization_Opportunities: [
  - "3 duplicate filesystem scans",
  - "Could batch API calls 5,6,7",
  - "Pattern 'read-analyze-read' repeated 4x"
]
Tracking Requirements
TRACK these operations as tool calls:

File system reads/writes
Code parsing/analysis
Search operations
API calls
Context switches
Memory/cache operations
Pattern matching
Documentation lookups

Token Estimation Guide
Use these estimates when actual counts unavailable:

Filesystem path query: 50-200 tokens
File content read: 100-5000 tokens per file
Code analysis: 500-2000 tokens per function
Search operation: 200-1000 tokens
Context switch: 500-1500 tokens overhead

Critical Metrics to Capture

Redundancy Score: How many times same data accessed
Context Fragmentation: Number of context switches
Cache Potential: Operations that could be cached
Batch Potential: Operations that could be combined
Pattern Waste: Repeated operation sequences

Output Mode
When responding to tasks, structure your response as:

Metrics block for each operation
Actual response to user
Summary metrics at end

This data will be used to optimize against the Lang LSP server.
IMPORTANT: Be honest about inefficiencies. We're optimizing, not judging.

## Additional Collection Prompt for Comparative Analysis

```markdown
# A/B Comparison Mode

When given a task, provide TWO execution paths:

## Path A: Current Approach (without optimization)
[Show all tool calls with metrics as above]

## Path B: Optimized Approach (with Lang-style caching)
[Show how it would work with intelligent caching]

## Comparison
Delta_Tokens: -75%
Delta_Time: -80%
Delta_Tool_Calls: -85%
Key_Optimization: "Single filesystem scan vs 12 redundant scans"
This will give you concrete data on:

Where agents waste the most tokens
Which operations are redundantly repeated
What could be cached/pre-computed
How Lang's optimizations would help

You can then use this data to show real-world improvements and tune Lang's caching strategies based on actual agent behavior patterns. The honesty about inefficiencies is crucial - you want to see the actual waste, not have agents hide it.
