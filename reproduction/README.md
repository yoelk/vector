# Vector Kafka Data Loss Bug Reproduction

This directory contains a complete, automated reproduction of a critical data loss bug in Vector where Kafka offsets are committed even when HTTP sink requests fail with 4xx errors.

## Quick Start

### Using DockerHub Image (Default)

```bash
cd reproduction
./reproduce.sh
```

### Using Locally-Built Vector

```bash
cd reproduction
./reproduce.sh --local
```

The script will automatically:
1. Start Vector (either from DockerHub or build from local source)
2. Start all required services (Kafka, Zookeeper, Mock HTTP Sink)
3. Send 3 test messages with alternating valid/invalid auth tokens
4. Demonstrate that message 2 is permanently lost
5. Save detailed logs to `reproduction_debug_output.txt`

### Options

- **Default mode**: Uses Vector 0.52.0 from DockerHub (faster, no build required)
- **`--local` mode**: Builds Vector from your local source code (useful for testing fixes)

## Expected Output

```
Event 1 (offset 0): ✅ SUCCESS - Delivered to sink
Event 2 (offset 1): ❌ REJECTED (401) - BUT OFFSET WAS COMMITTED
Event 3 (offset 2): ✅ SUCCESS - Delivered to sink
```

**Result**: The mock sink only receives events 1 and 3. Event 2 is permanently lost.

## Architecture

```
┌─────────┐     ┌────────┐     ┌────────┐     ┌───────────┐
│ Kafka   │────▶│ Vector │────▶│  HTTP  │────▶│ Mock Sink │
│ Topic   │     │        │     │  Sink  │     │ (Python)  │
└─────────┘     └────────┘     └────────┘     └───────────┘
                    │                               │
                    │                               │
                    └──── Config Reload ────────────┘
                          (good/bad token)
```

## Files

- **`reproduce.sh`** - Main reproduction script
- **`docker-compose.yml`** - Service definitions
- **`Dockerfile.local`** - Builds Vector from local source
- **`mock_sink.py`** - HTTP server that validates auth tokens
- **`good_token.yaml`** - Vector config with valid token
- **`bad_token.yaml`** - Vector config with invalid token

## How It Works

1. **Phase 1**: Vector starts with valid token, message 1 is delivered successfully
2. **Phase 2**: Config is reloaded with invalid token, message 2 is rejected (401)
3. **Phase 3**: Config is reloaded with valid token, message 3 is delivered successfully

The bug: Vector commits the Kafka offset for message 2 even though it was rejected, causing permanent data loss.

## Requirements

- Docker and Docker Compose
- Rust toolchain (for building Vector)
- ~10GB disk space for Docker images
- ~5 minutes for first run (includes Vector build)

## Cleanup

```bash
cd reproduction
docker compose down -v
```

## Troubleshooting

### Vector container exits immediately
Check logs: `docker compose logs vector`

### Kafka not ready
The script waits up to 60 seconds for Kafka. If it times out, try:
```bash
docker compose down -v
./reproduce.sh
```

### Build fails
Ensure you have the Rust toolchain installed and enough disk space.

## Next Steps

See `BUG_REPRODUCTION_SUMMARY.md` for detailed analysis and proposed solutions.

