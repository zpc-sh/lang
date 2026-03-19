# Format Support Guide

LANG Universal Text Intelligence Platform supports a comprehensive range of file formats and content types. This guide covers supported formats, parsing capabilities, and format-specific features.

## 📄 Supported File Formats

### **Text & Documentation**

#### **Markdown** (.md, .markdown, .mdown)
- **Features**: Full CommonMark + GitHub Flavored Markdown support
- **Analysis**: Structure extraction, link validation, table parsing
- **Special**: Live preview, TOC generation, broken link detection
- **Example**:
  ```bash
  curl -X POST https://lang.nocsi.com/api/analyze \
    -H "Content-Type: application/json" \
    -d '{"content": "# Header\nContent here", "format": "markdown"}'
  ```

#### **Plain Text** (.txt, .text)
- **Features**: Natural language processing, sentiment analysis
- **Analysis**: Readability metrics, language detection, topic extraction
- **Special**: Smart paragraph detection, citation extraction

#### **Rich Text Format** (.rtf)
- **Features**: Style-aware parsing, embedded object extraction
- **Analysis**: Formatting analysis, content structure
- **Special**: Cross-platform compatibility

#### **reStructuredText** (.rst, .rest)
- **Features**: Sphinx-compatible parsing, directive support
- **Analysis**: Documentation structure, cross-references
- **Special**: Python ecosystem integration

### **Programming Languages**

#### **JavaScript/TypeScript** (.js, .ts, .jsx, .tsx)
- **Features**: Full AST parsing, JSDoc extraction, React component analysis
- **Analysis**: Code quality, complexity metrics, security scanning
- **Special**: npm dependency analysis, bundler optimization
- **Tree-sitter**: Advanced syntax highlighting and navigation

#### **Python** (.py, .pyw, .pyi)
- **Features**: AST analysis, docstring parsing, type hint support
- **Analysis**: PEP compliance, complexity analysis, security scanning
- **Special**: Virtual environment detection, package analysis

#### **Rust** (.rs)
- **Features**: Full syntax support, macro expansion, trait analysis
- **Analysis**: Memory safety, performance optimization, documentation coverage
- **Special**: Cargo.toml integration, cross-compilation support

#### **Go** (.go)
- **Features**: Package analysis, interface detection, goroutine analysis
- **Analysis**: Performance profiling, race condition detection
- **Special**: Module system support, build tag analysis

#### **Java** (.java, .kt)
- **Features**: Class hierarchy analysis, annotation processing
- **Analysis**: Design patterns, performance optimization
- **Special**: Maven/Gradle integration, Android support

#### **C/C++** (.c, .cpp, .h, .hpp)
- **Features**: Preprocessor handling, header analysis
- **Analysis**: Memory safety, performance optimization
- **Special**: Cross-platform compatibility, embedded systems support

#### **Elixir** (.ex, .exs)
- **Features**: OTP pattern recognition, GenServer analysis
- **Analysis**: Fault tolerance patterns, performance optimization
- **Special**: Phoenix framework integration, LiveView support

#### **Other Languages**
- **Ruby** (.rb): Rails framework support, gem analysis
- **PHP** (.php): Framework detection, security scanning
- **Swift** (.swift): iOS/macOS framework integration
- **Dart** (.dart): Flutter widget analysis
- **Scala** (.scala): Functional programming patterns
- **Haskell** (.hs): Type system analysis, purity checking

### **Web Technologies**

#### **HTML** (.html, .htm, .xhtml)
- **Features**: Semantic analysis, accessibility checking
- **Analysis**: SEO optimization, performance metrics
- **Special**: Web standards compliance, responsive design analysis

#### **CSS/SCSS/LESS** (.css, .scss, .sass, .less)
- **Features**: Selector analysis, property optimization
- **Analysis**: Performance impact, browser compatibility
- **Special**: Framework detection (Bootstrap, Tailwind, etc.)

#### **XML/XSLT** (.xml, .xsl, .xslt)
- **Features**: Schema validation, namespace handling
- **Analysis**: Structure optimization, data integrity
- **Special**: SOAP/REST API documentation

#### **JSON/YAML** (.json, .yaml, .yml)
- **Features**: Schema validation, structure analysis
- **Analysis**: Data integrity, optimization suggestions
- **Special**: API specification support (OpenAPI, JSON Schema)

### **Configuration Files**

#### **Docker** (Dockerfile, .dockerignore)
- **Features**: Multi-stage build analysis, security scanning
- **Analysis**: Image optimization, best practices
- **Special**: Container security assessment

#### **Kubernetes** (.yaml with k8s resources)
- **Features**: Resource validation, policy checking
- **Analysis**: Security policies, resource optimization
- **Special**: Helm chart analysis

#### **CI/CD Configs**
- **GitHub Actions** (.github/workflows/*.yml)
- **GitLab CI** (.gitlab-ci.yml)
- **Jenkins** (Jenkinsfile)
- **CircleCI** (.circleci/config.yml)

### **Data Formats**

#### **CSV** (.csv, .tsv)
- **Features**: Schema detection, data profiling
- **Analysis**: Data quality, statistical analysis
- **Special**: Large file streaming support

#### **Database**
- **SQL** (.sql): Query optimization, schema analysis
- **Migration files**: Schema evolution tracking
- **ORM configs**: Model relationship analysis

### **Archive & Binary**

#### **Archives** (.zip, .tar.gz, .7z)
- **Features**: Recursive content analysis, metadata extraction
- **Analysis**: Compression efficiency, security scanning
- **Special**: Nested archive support

#### **PDF** (.pdf)
- **Features**: Text extraction, metadata analysis
- **Analysis**: Document structure, accessibility
- **Special**: OCR integration for scanned documents

#### **Images** (.png, .jpg, .gif, .svg)
- **Features**: Metadata extraction, format optimization
- **Analysis**: Accessibility alt-text suggestions
- **Special**: SVG code analysis, optimization recommendations

## 🔧 Format-Specific Features

### **Advanced Parsing**

#### **Tree-sitter Integration**
Languages with advanced parsing support:
```bash
# Available tree-sitter parsers
langs = [
  "javascript", "typescript", "python", "rust", "go", 
  "java", "c", "cpp", "elixir", "ruby", "php", "swift"
]

# Query syntax elements
curl -X POST https://lang.nocsi.com/api/v2/parse \
  -d '{"content": "function test() {}", "language": "javascript", "query": "(function_declaration name: (identifier) @function)"}'
```

#### **Semantic Analysis**
Format-aware semantic understanding:
- **Code**: Function signatures, variable scope, import dependencies
- **Documentation**: Cross-references, broken links, citation validation
- **Config**: Dependency resolution, security policy validation
- **Data**: Schema compliance, referential integrity

### **Content Intelligence**

#### **Language Detection**
Automatic format detection:
```javascript
{
  "detectedFormat": "javascript",
  "confidence": 0.95,
  "alternativeFormats": ["typescript"],
  "encoding": "utf-8",
  "lineEndings": "lf"
}
```

#### **Metadata Extraction**
Format-specific metadata:
- **Code files**: Author, creation date, modification history
- **Documents**: Title, headings, word count, reading time
- **Config files**: Version, dependencies, environment targets
- **Images**: Dimensions, color profile, compression settings

## 📊 Analysis Capabilities by Format

### **Code Quality Metrics**

#### **Complexity Analysis**
- **Cyclomatic Complexity**: Control flow complexity
- **Cognitive Complexity**: Human comprehension difficulty  
- **Maintainability Index**: Overall maintainability score
- **Technical Debt**: Estimated refactoring effort

#### **Security Analysis**
- **Vulnerability Detection**: Known security issues
- **Dependency Scanning**: Outdated/vulnerable dependencies
- **Secret Detection**: Hardcoded credentials, API keys
- **Best Practices**: Security compliance checking

#### **Performance Metrics**
- **Runtime Performance**: Big-O complexity analysis
- **Memory Usage**: Memory allocation patterns
- **I/O Operations**: File system and network usage
- **Optimization Opportunities**: Performance improvement suggestions

### **Documentation Quality**

#### **Content Analysis**
- **Readability**: Flesch-Kincaid, SMOG, ARI scores
- **Completeness**: Missing sections, incomplete information
- **Consistency**: Style guide compliance, terminology usage
- **Accessibility**: Screen reader compatibility, alt-text coverage

#### **Structure Analysis**
- **Hierarchy**: Heading structure, nesting depth
- **Navigation**: Table of contents, internal links
- **Cross-references**: Link validation, citation checking
- **Formatting**: Style consistency, markup validation

## 🚀 Advanced Format Support

### **Custom Format Registration**

Register custom file formats:
```elixir
# Register custom format
Lang.Formats.register(%{
  name: "custom_config",
  extensions: [".myconfig"],
  mime_type: "application/x-custom-config",
  parser: MyApp.CustomConfigParser,
  analyzers: [
    MyApp.Analyzers.ConfigValidator,
    MyApp.Analyzers.SecurityChecker
  ]
})
```

### **Plugin Architecture**

Extend format support with plugins:
```javascript
// Custom format plugin
class CustomFormatPlugin {
  constructor() {
    this.name = 'custom-format';
    this.extensions = ['.custom'];
  }
  
  parse(content) {
    // Custom parsing logic
    return {
      ast: this.buildAST(content),
      metadata: this.extractMetadata(content),
      errors: this.validate(content)
    };
  }
  
  analyze(ast) {
    // Custom analysis logic
    return {
      metrics: this.calculateMetrics(ast),
      suggestions: this.generateSuggestions(ast),
      insights: this.extractInsights(ast)
    };
  }
}
```

### **Batch Processing**

Process multiple formats efficiently:
```bash
# Batch analysis with format auto-detection
curl -X POST https://lang.nocsi.com/api/v2/batch \
  -F "files[]=@document.md" \
  -F "files[]=@script.js" \
  -F "files[]=@config.yaml" \
  -F "options={\"autoDetect\": true, \"deepAnalysis\": true}"
```

## ⚡ Performance Considerations

### **Large File Handling**

#### **Streaming Processing**
- Files > 10MB: Automatic streaming mode
- Memory-efficient parsing for large datasets
- Progress tracking for long operations
- Cancellation support for expensive operations

#### **Caching Strategy**
- **Parse Cache**: AST caching for unchanged files
- **Analysis Cache**: Result caching based on content hash
- **Metadata Cache**: File property caching
- **Dependency Cache**: Import/require resolution caching

### **Optimization Techniques**

#### **Lazy Loading**
- Parse only requested sections
- Load metadata before full content
- Progressive enhancement for large files
- On-demand dependency resolution

#### **Parallel Processing**
- Multi-core utilization for batch operations
- Concurrent analysis of independent files
- Distributed processing for enterprise workloads
- Queue-based processing with priority scheduling

## 🔍 Format Detection

### **Automatic Detection**

LANG automatically detects file formats using:
1. **File Extension**: Primary detection method
2. **MIME Type**: HTTP content-type headers
3. **Magic Bytes**: Binary file signatures
4. **Content Analysis**: Syntax pattern matching
5. **Contextual Clues**: Directory structure, related files

### **Detection Override**

Force specific format handling:
```bash
# Override format detection
curl -X POST https://lang.nocsi.com/api/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "content": "...",
    "format": "javascript",
    "options": {
      "forceFormat": true,
      "strictParsing": true
    }
  }'
```

## 📚 Format-Specific Documentation

### **Language References**
- **[JavaScript/TypeScript Guide](./languages/javascript.md)**
- **[Python Development Guide](./languages/python.md)**
- **[Rust Integration Guide](./languages/rust.md)**
- **[Elixir/Phoenix Guide](./languages/elixir.md)**

### **Configuration Guides**
- **[Docker Analysis Guide](./config/docker.md)**
- **[Kubernetes Security Guide](./config/kubernetes.md)**
- **[CI/CD Integration Guide](./config/cicd.md)**

### **Data Format Guides**
- **[Database Schema Analysis](./data/database.md)**
- **[API Specification Analysis](./data/api-specs.md)**
- **[Data Quality Assessment](./data/quality.md)**

## 🆘 Troubleshooting

### **Common Issues**

#### **Unsupported Format**
```bash
# Check supported formats
curl https://lang.nocsi.com/api/formats

# Request format support
curl -X POST https://lang.nocsi.com/api/format-request \
  -d '{"extension": ".myext", "description": "Custom format", "sample": "..."}'
```

#### **Parsing Errors**
- **Syntax Errors**: Invalid syntax in source files
- **Encoding Issues**: Character encoding problems
- **Large Files**: Memory or timeout issues
- **Binary Files**: Attempting to parse non-text content

#### **Analysis Limitations**
- **Complex Macros**: Preprocessor limitations
- **Dynamic Code**: Runtime behavior analysis
- **Obfuscated Code**: Minified or encoded content
- **Legacy Formats**: Deprecated format versions

### **Best Practices**

1. **File Organization**: Consistent naming and structure
2. **Encoding Standards**: UTF-8 for all text files
3. **Format Consistency**: Standardized formatting within projects
4. **Documentation**: Clear format specifications for custom types
5. **Version Control**: Track format evolution over time

---

**Need support for a specific format?** Check our **[Format Request Process](./format-requests.md)** or **[Custom Parser Development Guide](./custom-parsers.md)**.