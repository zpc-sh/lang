# Configuration Guide

Complete configuration reference for the LANG Universal Text Intelligence Platform. This guide covers all configuration options from basic setup to advanced enterprise deployments.

## 🚀 Quick Configuration

### **Basic Setup**
```bash
# Create configuration file
touch .langrc

# Basic configuration
{
  "api_key": "lang_your_api_key_here",
  "endpoint": "https://lang.nocsi.com",
  "timeout": 30000,
  "max_file_size": "10MB",
  "concurrent_requests": 5
}
```

### **Environment Variables**
```bash
# Essential environment variables
export LANG_API_KEY="lang_your_api_key_here"
export LANG_ENDPOINT="https://lang.nocsi.com"
export LANG_TIMEOUT=30000
export LANG_MAX_FILE_SIZE="10MB"
export LANG_LOG_LEVEL="info"
```

## 📋 Configuration Files

### **Project Configuration (.langrc)**
Project-specific settings in JSON format:

```json
{
  "project": {
    "name": "My Project",
    "version": "1.0.0",
    "description": "Project description"
  },
  "analysis": {
    "enabled": true,
    "depth": "deep",
    "real_time": true,
    "cache_results": true
  },
  "rules": {
    "complexity": {
      "max_cyclomatic": 10,
      "max_cognitive": 15,
      "warn_threshold": 7
    },
    "quality": {
      "min_maintainability": 70,
      "enforce_documentation": true,
      "naming_conventions": "camelCase"
    },
    "security": {
      "level": "high",
      "scan_dependencies": true,
      "detect_secrets": true,
      "check_vulnerabilities": true
    }
  },
  "file_patterns": {
    "include": [
      "src/**/*.js",
      "src/**/*.ts",
      "lib/**/*.py",
      "docs/**/*.md"
    ],
    "exclude": [
      "node_modules/**",
      "dist/**",
      "*.min.js",
      "vendor/**"
    ]
  },
  "integrations": {
    "github": {
      "enabled": true,
      "auto_comment": true,
      "pr_analysis": true
    },
    "slack": {
      "webhook_url": "https://hooks.slack.com/...",
      "channels": ["#dev", "#quality"]
    },
    "jira": {
      "url": "https://company.atlassian.net",
      "project_key": "DEV",
      "auto_create_issues": false
    }
  }
}
```

### **User Configuration (~/.langconfig)**
Global user settings:

```json
{
  "user": {
    "name": "Developer Name",
    "email": "developer@company.com",
    "organization": "company-id"
  },
  "defaults": {
    "analysis_depth": "standard",
    "output_format": "json",
    "include_suggestions": true,
    "auto_fix": false
  },
  "api": {
    "endpoint": "https://lang.nocsi.com",
    "timeout": 30000,
    "retry_attempts": 3,
    "rate_limit": 100
  },
  "cache": {
    "enabled": true,
    "ttl": 3600,
    "max_size": "100MB",
    "location": "~/.lang/cache"
  },
  "editor": {
    "preferred": "vscode",
    "auto_format": true,
    "show_inline_suggestions": true,
    "highlight_issues": true
  }
}
```

### **Team Configuration (lang-team.json)**
Team-wide settings and standards:

```json
{
  "team": {
    "name": "Development Team",
    "organization": "company-name",
    "standards_version": "2.1"
  },
  "quality_standards": {
    "code_quality": {
      "min_maintainability_index": 75,
      "max_cyclomatic_complexity": 8,
      "max_function_length": 50,
      "max_file_length": 500
    },
    "documentation": {
      "min_coverage": 80,
      "require_examples": true,
      "check_spelling": true,
      "enforce_style_guide": true
    },
    "testing": {
      "min_coverage": 85,
      "require_unit_tests": true,
      "require_integration_tests": false
    }
  },
  "custom_rules": [
    {
      "name": "no-console-logs",
      "pattern": "console\\.log\\(",
      "severity": "warning",
      "message": "Remove console.log statements before production"
    },
    {
      "name": "require-error-handling",
      "pattern": "fetch\\(|axios\\.",
      "severity": "info",
      "message": "Consider adding error handling for HTTP requests"
    }
  ],
  "approval_rules": {
    "require_review": true,
    "min_reviewers": 2,
    "block_on_quality_issues": true,
    "auto_approve_minor_changes": false
  }
}
```

## 🔧 Environment-Specific Configuration

### **Development Environment**
```json
{
  "environment": "development",
  "debug": true,
  "verbose_logging": true,
  "analysis": {
    "real_time": true,
    "cache_aggressive": false,
    "include_experimental": true
  },
  "performance": {
    "timeout": 60000,
    "concurrent_requests": 3,
    "queue_size": 50
  },
  "features": {
    "hot_reload": true,
    "auto_suggestions": true,
    "preview_mode": true
  }
}
```

### **Staging Environment**
```json
{
  "environment": "staging",
  "debug": false,
  "analysis": {
    "depth": "standard",
    "cache_results": true,
    "production_rules": true
  },
  "performance": {
    "timeout": 30000,
    "concurrent_requests": 5,
    "rate_limit": 200
  },
  "monitoring": {
    "enabled": true,
    "metrics_endpoint": "https://metrics.company.com",
    "alert_threshold": 5000
  }
}
```

### **Production Environment**
```json
{
  "environment": "production",
  "debug": false,
  "analysis": {
    "depth": "optimized",
    "cache_results": true,
    "batch_processing": true
  },
  "performance": {
    "timeout": 15000,
    "concurrent_requests": 10,
    "rate_limit": 1000,
    "circuit_breaker": true
  },
  "security": {
    "strict_mode": true,
    "encrypt_cache": true,
    "audit_logging": true,
    "ip_whitelist": ["10.0.0.0/8"]
  },
  "monitoring": {
    "enabled": true,
    "health_checks": true,
    "performance_tracking": true,
    "error_reporting": true
  }
}
```

## 🏢 Enterprise Configuration

### **Multi-Tenant Setup**
```json
{
  "enterprise": {
    "multi_tenant": true,
    "tenant_isolation": "strict",
    "resource_quotas": true
  },
  "tenants": {
    "default_config": {
      "analysis_quota": 10000,
      "storage_quota": "1GB",
      "concurrent_sessions": 50
    },
    "custom_configs": {
      "enterprise-client": {
        "analysis_quota": 100000,
        "storage_quota": "10GB",
        "concurrent_sessions": 200,
        "dedicated_resources": true
      }
    }
  },
  "authentication": {
    "sso_enabled": true,
    "saml_endpoint": "https://sso.company.com/saml",
    "oauth_providers": ["google", "github", "azure"],
    "mfa_required": true
  }
}
```

### **High Availability Configuration**
```json
{
  "high_availability": {
    "enabled": true,
    "failover_mode": "automatic",
    "health_check_interval": 30,
    "recovery_timeout": 300
  },
  "load_balancing": {
    "strategy": "round_robin",
    "sticky_sessions": false,
    "health_checks": true
  },
  "backup": {
    "enabled": true,
    "frequency": "daily",
    "retention_days": 30,
    "incremental": true,
    "encryption": true
  },
  "disaster_recovery": {
    "enabled": true,
    "rpo": 3600,
    "rto": 900,
    "backup_regions": ["us-west-2", "eu-west-1"]
  }
}
```

## 🔍 Analysis Configuration

### **Language-Specific Settings**
```json
{
  "languages": {
    "javascript": {
      "parser": "babylon",
      "ecma_version": 2022,
      "jsx": true,
      "typescript_support": true,
      "custom_rules": ["react-hooks", "es6-imports"]
    },
    "python": {
      "version": "3.9",
      "style_guide": "pep8",
      "type_checking": true,
      "frameworks": ["django", "flask", "fastapi"]
    },
    "rust": {
      "edition": "2021",
      "clippy_lints": "all",
      "cargo_check": true,
      "unsafe_analysis": true
    },
    "go": {
      "version": "1.19",
      "go_fmt": true,
      "go_vet": true,
      "race_detection": true
    }
  }
}
```

### **Analysis Depth Configuration**
```json
{
  "analysis_levels": {
    "quick": {
      "syntax_check": true,
      "basic_metrics": true,
      "simple_suggestions": true,
      "timeout": 5000
    },
    "standard": {
      "syntax_check": true,
      "complexity_analysis": true,
      "security_scan": true,
      "dependency_check": true,
      "timeout": 15000
    },
    "deep": {
      "full_ast_analysis": true,
      "semantic_analysis": true,
      "cross_reference_check": true,
      "performance_analysis": true,
      "documentation_coverage": true,
      "timeout": 60000
    },
    "comprehensive": {
      "all_checks": true,
      "machine_learning": true,
      "predictive_analysis": true,
      "historical_comparison": true,
      "timeout": 300000
    }
  }
}
```

### **Custom Parser Configuration**
```json
{
  "custom_parsers": {
    "domain_specific": {
      "enabled": true,
      "parsers": [
        {
          "name": "config_parser",
          "extensions": [".myconfig"],
          "parser_module": "company.parsers.config",
          "validation_schema": "config-schema.json"
        },
        {
          "name": "template_parser",
          "extensions": [".tpl", ".template"],
          "parser_module": "company.parsers.template",
          "syntax_highlighting": true
        }
      ]
    }
  }
}
```

## 🔐 Security Configuration

### **Authentication Settings**
```json
{
  "authentication": {
    "methods": ["api_key", "jwt", "oauth"],
    "api_key": {
      "prefix": "lang_",
      "length": 64,
      "expiration": "never",
      "rotation_reminder": 90
    },
    "jwt": {
      "algorithm": "RS256",
      "expiration": 3600,
      "refresh_enabled": true,
      "issuer": "lang.nocsi.com"
    },
    "oauth": {
      "providers": ["github", "google", "microsoft"],
      "scopes": ["read", "write"],
      "callback_url": "https://lang.nocsi.com/auth/callback"
    }
  }
}
```

### **Access Control**
```json
{
  "access_control": {
    "rbac_enabled": true,
    "roles": {
      "viewer": {
        "permissions": ["read_analysis", "view_reports"],
        "resource_access": ["own_projects"]
      },
      "developer": {
        "permissions": ["read_analysis", "create_analysis", "view_reports"],
        "resource_access": ["own_projects", "team_projects"]
      },
      "admin": {
        "permissions": ["*"],
        "resource_access": ["*"]
      }
    },
    "ip_restrictions": {
      "enabled": false,
      "whitelist": ["10.0.0.0/8", "192.168.0.0/16"],
      "blacklist": []
    }
  }
}
```

## 📊 Monitoring & Logging

### **Logging Configuration**
```json
{
  "logging": {
    "level": "info",
    "format": "json",
    "output": ["console", "file"],
    "file_config": {
      "path": "/var/log/lang/app.log",
      "max_size": "100MB",
      "max_files": 10,
      "compress": true
    },
    "structured_logging": true,
    "correlation_id": true,
    "sensitive_data_masking": true
  }
}
```

### **Metrics & Monitoring**
```json
{
  "monitoring": {
    "enabled": true,
    "metrics": {
      "collection_interval": 60,
      "retention_days": 90,
      "export_format": "prometheus"
    },
    "health_checks": {
      "enabled": true,
      "endpoint": "/health",
      "interval": 30,
      "timeout": 5000,
      "checks": ["database", "cache", "external_apis"]
    },
    "alerting": {
      "enabled": true,
      "channels": ["slack", "email", "pagerduty"],
      "thresholds": {
        "error_rate": 0.05,
        "response_time": 5000,
        "queue_size": 1000
      }
    }
  }
}
```

## ⚡ Performance Configuration

### **Caching Strategy**
```json
{
  "cache": {
    "enabled": true,
    "backend": "redis",
    "redis": {
      "host": "localhost",
      "port": 6379,
      "db": 0,
      "password": null,
      "ssl": false
    },
    "ttl": {
      "analysis_results": 3600,
      "user_sessions": 1800,
      "api_responses": 300
    },
    "compression": {
      "enabled": true,
      "algorithm": "gzip",
      "level": 6
    }
  }
}
```

### **Queue Configuration**
```json
{
  "queues": {
    "backend": "oban",
    "default_queue": "analysis",
    "queues": {
      "analysis": {
        "concurrency": 10,
        "max_attempts": 3,
        "priority": "normal"
      },
      "reports": {
        "concurrency": 5,
        "max_attempts": 1,
        "priority": "low"
      },
      "notifications": {
        "concurrency": 20,
        "max_attempts": 5,
        "priority": "high"
      }
    },
    "retry_strategy": {
      "exponential_backoff": true,
      "max_delay": 300,
      "jitter": true
    }
  }
}
```

## 🔧 Configuration Management

### **Configuration Validation**
```bash
# Validate configuration file
lang config validate .langrc

# Check configuration syntax
lang config check --strict

# Test configuration connectivity
lang config test --all
```

### **Configuration Migration**
```bash
# Migrate from old format
lang config migrate --from v1 --to v2 .langrc

# Backup current configuration
lang config backup --output config-backup.json

# Restore configuration
lang config restore config-backup.json
```

### **Environment Variables Override**
```bash
# Override any config value with environment variables
# Format: LANG_CONFIG_<SECTION>_<KEY>=value

export LANG_CONFIG_API_TIMEOUT=45000
export LANG_CONFIG_ANALYSIS_DEPTH=deep
export LANG_CONFIG_CACHE_ENABLED=true
export LANG_CONFIG_LOGGING_LEVEL=debug
```

## 📚 Configuration Examples

### **Minimal Configuration**
```json
{
  "api_key": "lang_your_api_key"
}
```

### **Development Team Configuration**
```json
{
  "api_key": "lang_dev_key",
  "rules": {
    "complexity": {"max_cyclomatic": 15},
    "quality": {"min_maintainability": 60}
  },
  "integrations": {
    "github": {"enabled": true}
  }
}
```

### **Enterprise Configuration**
```json
{
  "enterprise": true,
  "sso": {"provider": "okta"},
  "high_availability": {"enabled": true},
  "audit_logging": {"enabled": true},
  "custom_rules": {"config_file": "company-rules.json"}
}
```

## 🔍 Troubleshooting Configuration

### **Common Issues**
- **Invalid JSON format**: Use a JSON validator
- **Missing required fields**: Check the schema documentation
- **Permission errors**: Verify file ownership and permissions
- **Environment variable conflicts**: Check for duplicate settings

### **Debugging Commands**
```bash
# Show current configuration
lang config show

# Show configuration sources
lang config sources

# Validate and show errors
lang config validate --verbose

# Test configuration connectivity
lang config test --endpoint https://lang.nocsi.com
```

## 📖 Configuration Reference

### **Complete Schema**
For the complete configuration schema and all available options, see:
- **[Configuration Schema](./schema.md)** - Complete JSON schema
- **[Environment Variables](./environment-variables.md)** - All environment options
- **[API Configuration](./api-configuration.md)** - API-specific settings
- **[Security Configuration](./security-configuration.md)** - Security options

### **Migration Guides**
- **[v1 to v2 Migration](./migration-v1-v2.md)** - Upgrade guide
- **[Legacy Configuration](./legacy-configuration.md)** - Supporting old formats
- **[Breaking Changes](./breaking-changes.md)** - Version change notes

---

**Need help with configuration?** Check our **[Configuration FAQ](./faq.md)** or **[Contact Support](mailto:support@lang.nocsi.com)** for enterprise assistance.