# API Usage Migration Guide

## Overview

We are migrating from the old `Lang.Accounts.APIUsage` system to a new event-driven architecture using `Lang.Events.ApiUsageEvent`. This provides better separation of concerns and aligns with our event-sourcing strategy.

## Architecture Changes

### Old System
- `Lang.Accounts.APIUsage` - Ash resource in Accounts domain
- `Lang.Accounts.APIUsageLogger` - Service module with Redis caching
- Tight coupling with Accounts domain

### New System  
- `Lang.Events.ApiUsageEvent` - Ash resource in Events domain
- `Lang.Events.ApiUsageLogger` - Service module with Redis caching
- Proper event-driven architecture
- Better separation from Accounts domain

### Transition Layer
- `Lang.APIUsage` - Unified interface that delegates to either backend
- Configurable via `:api_usage_backend` setting

## Migration Steps

### 1. Deploy New Code
The new code is backward compatible. Deploy it first.

### 2. Run Migration (Optional)
If you want to migrate historical data:

```elixir
# In production console
Lang.Migration.ApiUsageToEvents.migrate()

# Verify migration
Lang.Migration.ApiUsageToEvents.verify_migration()
```

### 3. Switch Backend
Update config to use new backend:

```elixir
# config/runtime.exs
config :lang, :api_usage_backend, :events  # default
# or keep using legacy temporarily
config :lang, :api_usage_backend, :legacy
```

### 4. Update Code References
All code should use `Lang.APIUsage` instead of direct module references:

```elixir
# Before
alias Lang.Accounts.APIUsageLogger
APIUsageLogger.log_usage(user_id, :analyze)

# After  
alias Lang.APIUsage
APIUsage.log_usage(user_id, :analyze)
```

### 5. Remove Old Code (Future)
Once fully migrated:
1. Remove `Lang.Accounts.APIUsage` resource
2. Remove `Lang.Accounts.APIUsageLogger` module
3. Remove `Lang.APIUsage` wrapper (update all refs to `Lang.Events.ApiUsageLogger`)
4. Drop old `api_usage` table

## Benefits

1. **Better Architecture**: Events belong in Events domain, not Accounts
2. **Consistency**: Aligns with other event tracking (UserActivityEvent)
3. **Extensibility**: Easier to add new event types and metadata
4. **Organization Support**: New schema includes organization_id
5. **Performance**: Same Redis caching, better schema design

## API Compatibility

The new system maintains full API compatibility:
- Same function names and signatures
- Same return values
- Same Redis caching behavior
- Same PubSub notifications

## Testing

Run the full test suite to ensure compatibility:
```bash
mix test test/lang/accounts/api_usage_test.exs
mix test test/lang/events/api_usage_event_test.exs
```