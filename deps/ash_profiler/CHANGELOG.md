# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2024-08-20

### Added
- Initial release of AshProfiler
- DSL complexity analysis for Ash resources
- Container environment detection and optimization
- Multiple output formats (console, JSON, HTML)
- Command-line interface via Mix task
- Domain and resource-level performance analysis
- Optimization recommendations engine
- Real-world performance improvements documentation

### Features
- **Core Analysis Engine**
  - Domain discovery and analysis
  - Resource complexity scoring
  - DSL section breakdown analysis
  - Performance bottleneck identification

- **Container Support**
  - Automatic container environment detection
  - System resource analysis (memory, CPU, disk)
  - Performance characteristic testing
  - Container-specific optimization recommendations

- **Reporting System**
  - Console output with color coding
  - JSON reports for CI/CD integration
  - HTML reports with detailed visualizations
  - Customizable complexity thresholds

- **Command Line Tool**
  - `mix ash_profiler` task
  - Flexible command-line options
  - Integration with existing workflows
  - Automated threshold checking

### Documentation
- Comprehensive README with examples
- API documentation with doctests
- Performance optimization guide
- Container deployment recommendations
- CI/CD integration examples