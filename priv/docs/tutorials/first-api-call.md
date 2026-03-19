# Your First API Call with LANG

This tutorial will guide you through making your very first API call to LANG and understanding the response. You'll go from having an API key to getting meaningful analysis results in just a few minutes.

## 🎯 What You'll Accomplish

By the end of this tutorial, you'll have:
- Made your first successful API call to LANG
- Analyzed a piece of code and understood the results
- Learned how to interpret LANG's analysis output
- Set up for more advanced usage

**Time Required:** 5-10 minutes

## 📋 Prerequisites

- Your LANG API key (starts with `lang_`)
- Command line access (Terminal, Command Prompt, or PowerShell)
- Basic familiarity with curl or similar HTTP tools

> **Don't have an API key yet?** Get one at [lang.nocsi.com/api-portal](https://lang.nocsi.com/api-portal) - it takes 30 seconds!

## 🚀 Step 1: Test Your Connection

Let's start by verifying your API key works:

```bash
curl -H "Authorization: Bearer YOUR_API_KEY_HERE" \
     https://lang.nocsi.com/api/health
```

**Replace `YOUR_API_KEY_HERE` with your actual API key!**

### Expected Response
```json
{
  "status": "ok",
  "version": "1.0.0",
  "timestamp": "2024-01-15T10:30:00Z",
  "user": {
    "id": "user_abc123",
    "organization": "your-org"
  }
}
```

✅ **Success!** If you see `"status": "ok"`, you're ready to proceed.

❌ **Troubleshooting:**
- `401 Unauthorized`: Check your API key format and validity
- `403 Forbidden`: Your API key might be inactive or have insufficient permissions
- Connection timeout: Check your internet connection

## 📄 Step 2: Analyze Your First Code Sample

Now let's analyze a simple JavaScript function. We'll use a common example that demonstrates LANG's capabilities:

```bash
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "function calculateTotal(items) {\n  let total = 0;\n  for (let i = 0; i < items.length; i++) {\n    total += items[i].price;\n  }\n  return total;\n}",
    "format": "javascript",
    "options": {
      "include_suggestions": true,
      "include_metrics": true,
      "include_insights": true
    }
  }'
```

### Understanding the Request

- **URL**: `https://lang.nocsi.com/api/v2/text/analyze` - The text analysis endpoint
- **Method**: POST - We're sending content for analysis
- **Headers**: 
  - `Authorization`: Your API key for authentication
  - `Content-Type`: Tells the API we're sending JSON
- **Body**:
  - `content`: The code we want analyzed (with `\n` for line breaks)
  - `format`: Tells LANG this is JavaScript code
  - `options`: What kind of analysis we want

## 🔍 Step 3: Understanding the Response

You'll receive a comprehensive JSON response like this:

```json
{
  "analysis_id": "ana_abc123xyz",
  "status": "completed",
  "timestamp": "2024-01-15T10:31:42Z",
  "processing_time_ms": 234,
  "results": {
    "complexity": {
      "cyclomatic": 2,
      "cognitive": 3,
      "maintainability_index": 78.5
    },
    "metrics": {
      "lines_of_code": 6,
      "statements": 4,
      "functions": 1,
      "estimated_reading_time": "8 seconds"
    },
    "suggestions": [
      {
        "type": "improvement",
        "severity": "low",
        "line": 3,
        "column": 7,
        "message": "Consider using for...of loop for better readability",
        "suggestion": "for (let item of items) { total += item.price; }",
        "category": "style"
      },
      {
        "type": "enhancement",
        "severity": "info", 
        "line": 2,
        "message": "Consider using reduce() for a more functional approach",
        "suggestion": "return items.reduce((total, item) => total + item.price, 0);",
        "category": "refactoring"
      }
    ],
    "insights": [
      "This is a well-structured function with clear intent",
      "The function handles basic array iteration correctly",
      "Consider adding input validation for edge cases",
      "The naming convention is clear and descriptive"
    ],
    "quality_score": 7.8,
    "language_confidence": 0.98
  }
}
```

### Breaking Down the Response

**🔢 Complexity Metrics:**
- `cyclomatic: 2` - This function has 2 possible execution paths (normal flow + loop)
- `cognitive: 3` - Fairly easy to understand cognitively
- `maintainability_index: 78.5` - Good maintainability (70+ is good)

**📊 Code Metrics:**
- `lines_of_code: 6` - Physical lines in the function
- `functions: 1` - One function analyzed
- `estimated_reading_time: "8 seconds"` - How long to understand this code

**💡 Suggestions:**
- **Low severity**: Style improvements (optional but good practice)
- **Info severity**: Alternative approaches for consideration

**🎯 Quality Score: 7.8/10** - This is good quality code!

## 🔧 Step 4: Try Different Code Examples

### Example 2: Analyze a More Complex Function

```bash
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "function processUsers(users, filters) {\n  if (!users || !users.length) return [];\n  \n  let result = users;\n  \n  if (filters.active !== undefined) {\n    result = result.filter(u => u.active === filters.active);\n  }\n  \n  if (filters.role) {\n    result = result.filter(u => u.role === filters.role);\n  }\n  \n  if (filters.department) {\n    result = result.filter(u => {\n      if (u.department && u.department.name) {\n        return u.department.name.toLowerCase().includes(filters.department.toLowerCase());\n      }\n      return false;\n    });\n  }\n  \n  return result.sort((a, b) => a.name.localeCompare(b.name));\n}",
    "format": "javascript",
    "options": {
      "include_suggestions": true,
      "security_scan": true,
      "performance_analysis": true
    }
  }'
```

This will show you:
- Higher complexity metrics
- Performance suggestions
- Security considerations (if any)
- More detailed refactoring opportunities

### Example 3: Analyze Python Code

```bash
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "def calculate_fibonacci(n):\n    if n <= 1:\n        return n\n    else:\n        return calculate_fibonacci(n-1) + calculate_fibonacci(n-2)",
    "format": "python",
    "options": {
      "include_suggestions": true,
      "performance_analysis": true
    }
  }'
```

LANG will detect this as an inefficient recursive implementation and suggest optimizations!

## 📋 Step 5: Working with Real Files

Instead of pasting code in JSON, you can analyze actual files:

```bash
# Create a sample file
echo 'function greet(name) {
  if (name) {
    console.log("Hello " + name + "!");
  } else {
    console.log("Hello World!");
  }
}' > sample.js

# Upload and analyze the file
curl -X POST https://lang.nocsi.com/api/v2/filesystem/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -F "file=@sample.js"
```

## 🎨 Step 6: Different Output Formats

### Get Only Suggestions
```bash
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "your code here",
    "format": "javascript"
  }' | jq '.results.suggestions'
```

### Get Just the Quality Score
```bash
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "your code here", 
    "format": "javascript"
  }' | jq '.results.quality_score'
```

### Pretty Print Everything
```bash
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "your code here",
    "format": "javascript"
  }' | jq '.'
```

## 🚨 Common Issues & Solutions

### "Invalid JSON" Error
**Problem:** Malformed JSON in request body
**Solution:** Use a JSON validator, ensure proper escaping of quotes and newlines

```bash
# Good: Properly escaped newlines
"content": "function test() {\n  return true;\n}"

# Bad: Literal line breaks
"content": "function test() {
  return true;
}"
```

### "Unsupported Format" Error  
**Problem:** LANG doesn't recognize the file format
**Solution:** Check supported formats or force a specific format

```bash
# List supported formats
curl https://lang.nocsi.com/api/formats

# Force format detection
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -d '{"content": "...", "format": "javascript", "options": {"force_format": true}}'
```

### "Rate Limit Exceeded"
**Problem:** Too many requests too quickly
**Solution:** Check your usage and add delays between requests

```bash
# Check current usage
curl -H "Authorization: Bearer YOUR_API_KEY" \
     https://lang.nocsi.com/api/usage/current
```

## 🎉 Congratulations!

You've successfully:
- ✅ Made your first API call to LANG
- ✅ Analyzed JavaScript and potentially Python code
- ✅ Understood complexity metrics and suggestions
- ✅ Learned to work with different output formats
- ✅ Troubleshot common issues

## 🚀 What's Next?

Now that you've mastered the basics, explore these next steps:

1. **[Integrate with Your IDE](./ide-integration.md)** - Get LANG suggestions in your editor
2. **[Set Up Automated Analysis](./automation.md)** - Add LANG to your CI/CD pipeline  
3. **[Batch File Analysis](./batch-processing.md)** - Analyze entire projects
4. **[Custom Rules](./custom-rules.md)** - Create team-specific quality standards

### Quick Reference Card

```bash
# Health check
curl -H "Authorization: Bearer YOUR_KEY" https://lang.nocsi.com/api/health

# Analyze text
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"content": "CODE_HERE", "format": "FORMAT"}'

# Analyze file
curl -X POST https://lang.nocsi.com/api/v2/filesystem/analyze \
  -H "Authorization: Bearer YOUR_KEY" \
  -F "file=@filename.ext"

# Pretty print with jq
... | jq '.'

# Get just suggestions
... | jq '.results.suggestions'
```

## 💬 Getting Help

**Questions about your results?** 
- [Community Forum](https://community.lang.nocsi.com)
- [Discord Chat](https://discord.gg/lang) 
- [Email Support](mailto:support@lang.nocsi.com)

**Found a bug or have feedback?**
- [GitHub Issues](https://github.com/lang-platform/lang/issues)
- [Feature Requests](https://lang.nocsi.com/feedback)

---

**🎯 Pro Tip:** Save your API key as an environment variable to avoid typing it every time:
```bash
export LANG_API_KEY="your_actual_key_here"
curl -H "Authorization: Bearer $LANG_API_KEY" https://lang.nocsi.com/api/health
```

Happy analyzing! 🚀