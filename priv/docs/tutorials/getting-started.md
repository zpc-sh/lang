# Getting Started with LANG

Welcome to LANG! This tutorial will take you from zero to your first successful API call in under 10 minutes.

## 🎯 What You'll Learn

By the end of this tutorial, you'll be able to:
- Set up your LANG account and API key
- Make your first API call
- Analyze a document and understand the results
- Integrate LANG into your workflow

## 📋 Prerequisites

- Basic command line knowledge
- Internet connection
- Text editor or terminal access

## 🚀 Step 1: Get Your API Key

### Option A: Web Interface (Recommended)

1. **Visit the LANG Platform**
   ```
   https://lang.nocsi.com
   ```

2. **Create Your Account**
   - Click "Sign Up" 
   - Enter your email and create a password
   - Verify your email address

3. **Generate Your API Key**
   - Go to [API Portal](https://lang.nocsi.com/api-portal)
   - Click "Generate New Key"
   - Give it a descriptive name (e.g., "Tutorial Key")
   - Copy your key - it starts with `lang_`

### Option B: Quick CLI Setup

```bash
# Install LANG CLI (optional but helpful)
curl -sSL https://lang.nocsi.com/install.sh | bash

# Create account and get API key
lang auth signup
lang auth login
lang keys create "My First Key"
```

⚠️ **Important**: Save your API key securely - you won't be able to see it again!

## 🔧 Step 2: Test Your Connection

Let's verify everything is working:

```bash
# Test API connection
curl -H "Authorization: Bearer YOUR_API_KEY_HERE" \
     https://lang.nocsi.com/api/health

# Expected response:
# {"status":"ok","version":"1.0","timestamp":"..."}
```

If you see the `"status":"ok"` response, you're ready to go!

## 📄 Step 3: Your First Analysis

Let's analyze some text to see LANG in action:

### Simple Text Analysis

```bash
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "function calculateTotal(items) {\n  let total = 0;\n  for (let item of items) {\n    total += item.price;\n  }\n  return total;\n}",
    "format": "javascript",
    "options": {
      "include_suggestions": true,
      "include_metrics": true
    }
  }'
```

### Understanding the Response

You'll get a comprehensive analysis like this:

```json
{
  "analysis_id": "ana_xyz123",
  "status": "completed",
  "results": {
    "complexity": {
      "cyclomatic": 2,
      "cognitive": 3,
      "maintainability_index": 85
    },
    "suggestions": [
      {
        "type": "improvement",
        "message": "Consider using reduce() for more functional style",
        "line": 2,
        "severity": "low"
      }
    ],
    "metrics": {
      "lines_of_code": 6,
      "function_count": 1,
      "estimated_reading_time": "5 seconds"
    },
    "insights": [
      "Well-structured function with clear intent",
      "Good variable naming conventions",
      "Consider error handling for edge cases"
    ]
  }
}
```

## 📋 Step 4: Analyze a File

Now let's analyze a real file from your system:

### Upload and Analyze

```bash
# Analyze a local file
curl -X POST https://lang.nocsi.com/api/v2/filesystem/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -F "file=@/path/to/your/script.js" \
  -F "options={\"deep_analysis\": true}"
```

### Batch Analysis

```bash
# Analyze multiple files at once
curl -X POST https://lang.nocsi.com/api/v2/filesystem/batch \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -F "files[]=@script1.js" \
  -F "files[]=@script2.js" \
  -F "files[]=@README.md"
```

## 🔍 Step 5: Explore Different Content Types

### Markdown Document Analysis

```bash
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "# Project Overview\n\nThis project implements a **text analysis** system.\n\n## Features\n\n- Fast processing\n- Multiple formats\n- REST API",
    "format": "markdown",
    "options": {
      "check_links": true,
      "extract_headings": true,
      "readability_analysis": true
    }
  }'
```

### Configuration File Analysis

```bash
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "{\n  \"name\": \"my-app\",\n  \"version\": \"1.0.0\",\n  \"dependencies\": {\n    \"express\": \"^4.18.0\"\n  }\n}",
    "format": "json",
    "options": {
      "validate_schema": true,
      "security_check": true
    }
  }'
```

## 🛠️ Step 6: Using the Results

### Save Analysis Results

```bash
# Save results to file
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{"content": "...", "format": "javascript"}' \
  > analysis_results.json

# Pretty print the results
cat analysis_results.json | jq '.'
```

### Filter Specific Insights

```bash
# Get only suggestions
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{"content": "...", "format": "javascript"}' \
  | jq '.results.suggestions'

# Get only high-severity issues
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{"content": "...", "format": "javascript"}' \
  | jq '.results.suggestions[] | select(.severity == "high")'
```

## 🌐 Step 7: Web Interface

Don't want to use the API directly? Try the web interface:

1. **Go to the Analysis Dashboard**
   ```
   https://lang.nocsi.com/analyze
   ```

2. **Upload or Paste Content**
   - Drag & drop files
   - Paste text directly
   - Connect to GitHub repos

3. **View Interactive Results**
   - Visual complexity metrics
   - Clickable suggestions
   - Downloadable reports

## 🔗 Step 8: Next Steps

Congratulations! You've successfully:
- ✅ Set up your LANG account
- ✅ Generated an API key  
- ✅ Made your first API calls
- ✅ Analyzed different content types
- ✅ Processed the results

### What's Next?

1. **[Integrate with Your IDE](./ide-integration.md)** - Add LANG to VS Code, Vim, or Emacs
2. **[Automation Tutorial](./automation.md)** - Set up automated analysis in CI/CD
3. **[Advanced Features](./advanced-features.md)** - Explore semantic analysis and custom rules
4. **[Team Setup](./team-setup.md)** - Configure LANG for your team

### Common Use Cases to Explore

- **[Code Review Automation](../use-cases/code-review.md)**
- **[Documentation Quality](../use-cases/documentation.md)**
- **[Security Scanning](../use-cases/security.md)**
- **[Performance Optimization](../use-cases/performance.md)**

## 🆘 Troubleshooting

### Common Issues

#### "Authentication failed"
```bash
# Check your API key format
echo $YOUR_API_KEY | grep "^lang_"

# Verify key is active
curl -H "Authorization: Bearer $YOUR_API_KEY" \
     https://lang.nocsi.com/api/auth/verify
```

#### "Rate limit exceeded"
```bash
# Check your current usage
curl -H "Authorization: Bearer $YOUR_API_KEY" \
     https://lang.nocsi.com/api/usage/current
```

#### "Unsupported format"
```bash
# List supported formats
curl https://lang.nocsi.com/api/formats

# Force format detection
curl -X POST https://lang.nocsi.com/api/v2/text/analyze \
  -H "Authorization: Bearer $YOUR_API_KEY" \
  -d '{"content": "...", "format": "javascript", "options": {"force_format": true}}'
```

### Getting Help

- 📖 **[Full Documentation](../index.md)**
- 💬 **[Community Support](https://discord.gg/lang)**
- 📧 **[Email Support](mailto:support@lang.nocsi.com)**
- 🐛 **[Report Issues](https://github.com/lang-platform/lang/issues)**

## 🎉 Welcome to LANG!

You're now ready to supercharge your development workflow with intelligent text analysis. The LANG platform will help you:

- **Write better code** with real-time suggestions
- **Maintain higher quality** with automated reviews
- **Save time** with intelligent automation
- **Learn continuously** from analysis insights

Happy analyzing! 🚀

---

**⏱️ Completed this tutorial?** Share your experience and help us improve: [Feedback Form](https://lang.nocsi.com/feedback?tutorial=getting-started)