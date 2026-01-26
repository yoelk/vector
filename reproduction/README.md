# Vector Kafka Data Loss Bug Reproduction

This directory contains a **complete, working reproduction setup** for demonstrating a critical data loss bug in Vector's Kafka source when using end-to-end acknowledgements with sinks that return authentication errors (401/403).

## ✅ Bug Successfully Reproduced

This reproduction has been **tested and confirmed working**. It successfully demonstrates that Vector loses messages when:
- Kafka source has acknowledgements enabled
- HTTP sink receives 401/403 authentication errors
- Subsequent messages with valid credentials are processed

## Prerequisites

- Docker and Docker Compose
- `jq` (for parsing JSON in the test script)
- `curl` (for health checks)

## Quick Start

```bash
cd reproduction
chmod +x reproduce.sh
./reproduce.sh
```

The script will:
1. Start all services (Kafka, Vector, mock HTTP sink)
2. Send 3 messages in 3 phases:
   - **Phase 1**: 1 message with valid token → ✅ Successfully delivered
   - **Phase 2**: 1 message with invalid token → ❌   - **Phase 2**: 1 message with invalidage with valid token → ✅ Successfully delivered
3. Display results showing only 2 messages received (message 2 is permanently lost)

## Actual Test Output

```
Expected: 3 messages sent (IDs 1, 2, 3)
Actual:   2 messages received

✗ BUG CONFIRMED: Only 2 messages received!
  Message 2 (sent with invalid token) was PERMANENTLY LOST

Received message IDs:
1 3 

This demonstrates the data loss bug in Vector's Kafka source.
Even though acknowledgements are enabled, rejected events are lost.
```

### Mock Sink Logs
```
✅ SUCCESS: Received ✅ SUCCESS: Reali✅ SUCCESS: Received ✅ en✅ SUCCESS: Received ✅ SUCCESS: Reali✅� ✅ SUCCESS: Received ✅ Swith valid token
```````` V```````` V````
ERROR: Not retriable; dERROR: Not reeqERst.ERROR: Not retrtaERROR: Not retriable; dERROR: Not reeqERst.ERROR: Noonal=false count=1 reason="Service call failed..."
```

## The Bug

When Vector's Kafka source has acknowledgeWhen Vector's Kafka source has acknowledgeWhen Vector's Kafka source has acknowledgeWhen Vector's Kafka source has acknowledgeWhen Vector's KafkecWhen Vector's Kafka source has acknowledgeWhen Vector's Kafka source has acknowledcorWhen Vector's Kafka seqWhntWhen Vector's Kafka source has acknowlets
5. Kafka's auto-commit commit5. Kafka's auto-commit commit5. Kafka's auvel5. Kafka's auto-commit commit5. Kafka's auto-commit commiage5. Kafka's auto-commst** ❌

## How It Works

The reproduction script:
1. Starts Vector with `--watch-config` flag to enable automatic config reload
2. Edits the Vector config file **inside the container** to change the authentication token
3. Vector detects the file change and reloads the configuration
4. The HTTP sink picks up the new token and uses it for subsequent requests
5. This allows us to trigger 401 errors in Phase 2 while keeping Vector running

## Components

- **docker-compose.yml**: Defines all services (Kafka, Zookeeper, Vector, mock HTTP sink)
- **vector.yaml**: Vector configuration with Kafka source and HTTP sink with acknowledgements enabled
- **mock_sink.py**: Simple HTTP server that returns 200 for valid tokens, 401 for invalid tokens
- **reproduce.sh**: Automated test script that edits config inside container to trigger reloads

## Root Cause

The bug is The bug is The bug is The bug is The bug is The bug is The bug is The bug is The bug is The bug is The bug is The bug is The bug is The bug is The bug is The bugatches from advancinThe bug is The bug is T bThe bug is The bug is The bug is The bug is The bug is The bug is The bug isafka source, similar to the existing Pulsar source implementation, to handle rejected events without losing data.

## Environment

- **Vector**: v0.52.0-debian
- **Kafka**: confluentinc/cp-kafka:7.5.0
- **Zookeeper**: confluentinc/cp-zookeeper:7.5.0
- **Python**: 3.11 (for mock sink)
