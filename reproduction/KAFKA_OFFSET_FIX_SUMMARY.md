# Kafka Offset Commit Fix - Summary and Analysis

## Problem Statement
Vector's Kafka source commits offsets immediately after consuming messages, BEFORE waiting for acknowledgment from downstream sinks. This causes data loss when messages are rejected by sinks because:
1. Message is consumed from Kafka
2. Offset is committed immediately
3. Message is sent to sink
4. Sink rejects the message (e.g., HTTP 400)
5. Message is lost forever (offset already committed)

## Root Cause Analysis
The issue is in `src/sources/kafka.rs` in the `partition_consumer` function. The code structure is:
1. Consume message from Kafka
2. **Immediately commit offset** via `consumer.store_offset()`
3. Send message to sink via `out.send_event()`
4. Later receive acknowledgment via `ack_stream.next()`

The offset commit happens in step 2, but the acknowledgment doesn't arrive until step 4.

## Solution Approach
Move offset commits to AFTER receiving successful acknowledgments:
1. Consume message from Kafka
2. Send message to sink
3. Wait for acknowledgment
4. **Only commit offset if acknowledgment is successful** (BatchStatus::Delivered)
5. If acknowledgment fails (BatchStatus::Rejected/Errored), do NOT commit offset

## Changes Made

### File: `src/sources/kafka.rs`

#### Change 1: Removed immediate offset commit (lines ~680-682)
**REMOVED:**
```rust
if let Err(error) = consumer.store_offset(&topic, partition, offset) {
    emit!(KafkaOffsetUpdateError { error });
}
```

#### Change 2: Added offset commit on successful acknowledgment (lines 625-657)
**MODIFIED** the acknowledgment handling to:
```rust
ack = ack_stream.next() => match ack {
    Some((ack_status, entry)) => {
        match ack_status {
            BatchStatus::Delivered => {
                // Message was successfully delivered, commit the offset
                if let Err(error) = consumer.store_offset(&entry.topic, entry.partition, entry.offset) {
                    emit!(KafkaOffsetUpdateError { error });
                }
                pause_consuming = false;
            }
            BatchStatus::Errored | BatchStatus::Rejected => {
                // Message failed to deliver - do NOT commit offset
                // Exit the consumer loop to trigger a restart
                error!(
                    "Message delivery failed with status {:?} for {}:{}:{}, exiting consumer to retry from last committed offset",
                    ack_status, &entry.topic, entry.partition, entry.offset
                );
                status = PartitionConsumerStatus::NormalExit;
                finalizer.take();
                break;
            }
        }
    }
    // ... rest of match arms
}
```

## Testing Status

### Build Status
✅ Code compiles successfully with `cargo build --release`

### Test Environment Setup
- Kafka running in Docker (port 9092)
- HTTP server rejecting all requests (port 9090)
- Test messages in topic `test-topic`

### Test Results
❌ **FIX NOT WORKING AS EXPECTED**

**Observed Behavior:**
1. Vector consumes messages from Kafka
2. HTTP sink rejects messages with 400 Bad Request
3. Vector logs show: "Events dropped" with `count=1`
4. **Vector continues running** (should have exited)
5. No error log about "Message delivery failed" (my code not executing)

**Expected Behavior:**
1. Vector consumes message
2. HTTP sink rejects message
3. Vector receives `BatchStatus::Rejected` acknowledgment
4. Vector logs error and exits the consumer loop
5. Vector restarts and re-reads from last committed offset

## Critical Issue Identified

**The acknowledgment handling code is NOT being executed!**

The error log I added at line 640-643 never appears in the output, which means:
- Either `BatchStatus::Rejected` is not being sent through `ack_stream`
- Or the acknowledgment stream is not being processed correctly
- Or there's a different code path being used

## Next Steps for Investigation

1. **Verify acknowledgment flow**: Check how `BatchStatus::Rejected` is propagated from the HTTP sink back to the Kafka source
   - Look at `src/sinks/http/` to see how it reports failures
   - Check if HTTP 400 errors actually result in `BatchStatus::Rejected`

2. **Add more debug logging**: Add debug logs at multiple points to trace the acknowledgment flow:
   - When message is sent to sink
   - When acknowledgment is received
   - What status is in the acknowledgment

3. **Check if there are multiple code paths**: The Kafka source might have different modes or configurations that use different acknowledgment mechanisms

4. **Verify the acknowledgment stream**: Ensure `ack_stream` is actually connected to the sink's acknowledgment channel

## Files Modified
- `src/sources/kafka.rs` (lines ~625-657, ~680-682)

## Build Command
```bash
cargo build --release
```

## Test Command
```bash
VECTOR_LOG=info ./target/release/vector --config test-vector.toml
```

## Test Config Location
`test-vector.toml` in project root

