# Vector Kafka Data Loss Bug - Reproduction Summary

## Bug Description

Vector commits Kafka offsets even when HTTP sink requests fail with 4xx errors (like 401 Unauthorized), causing permanent data loss.

## Reproduction Results

### Test Scenario
1. Send 3 messages to Kafka topic
2. Configure Vector with valid auth token
3. Send message 1 → Success (200 OK)
4. Switch to invalid auth token
5. Send message 2 → Failure (401 Unauthorized)
6. Switch back to valid auth token
7. Send message 3 → Success (200 OK)

### Observed Behavior (BUG)

```
Event 1 (offset 0): ✅ SUCCESS - Delivered to sink
Event 2 (offset 1): ❌ REJECTED (401) - BUT OFFSET WAS COMMITTED
Event 3 (offset 2): ✅ SUCCESS - Delivered to sink
```

**Result**: Event 2 is permanently lost. The mock sink only received events 1 and 3.

### Expected Behavior

Event 2 should either:
1. Be retried until it succeeds, OR
2. Be sent to a dead-letter queue, OR
3. Cause Vector to stop processing (fail-fast)

The offset should NOT be committed until the event is successfully delivered.

## Root Cause

Vector's HTTP sink treats 4xx errors as "successful" from an offset commit perspective, even though the data was never delivered to the destination.

## Impact

- **Data Loss**: Events are silently dropped when authentication fails
- **Silent Failure**: No alerts or errors indicate data was lost
- **Unrecoverable**: Once the offset is committed, the lost events cannot be recovered

## Reproduction Environment

- Vector version: 0.53.0 (built from source)
- Kafka: Confluent Platform 7.5.0
- Platform: Docker Compose on macOS (ARM64)

## How to Reproduce

```bash
cd reproduction
./reproduce.sh
```

The script will:
1. Start Kafka, Zookeeper, Vector, and a mock HTTP sink
2. Send 3 test messages with alternating valid/invalid auth tokens
3. Show that event 2 is lost while events 1 and 3 are delivered

## Files

- `reproduce.sh` - Main reproduction script
- `docker-compose.yml` - Service definitions
- `mock_sink.py` - HTTP server that validates auth tokens
- `good_token.yaml` - Vector config with valid token
- `bad_token.yaml` - Vector config with invalid token
- `Dockerfile.local` - Custom Vector build

## Next Steps

1. Investigate Vector's HTTP sink error handling
2. Determine if 4xx errors should prevent offset commits
3. Add configuration option for error handling strategy
4. Consider implementing dead-letter queue for failed events

