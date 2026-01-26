#!/bin/bash

set -e

# Output file for debug logs
OUTPUT_FILE="reproduction_debug_output.txt"

echo "=========================================="
echo "Vector Kafka Data Loss Bug Reproduction"
echo "=========================================="
echo ""
echo "Debug output will be saved to: $OUTPUT_FILE"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to the reproduction directory
cd "$(dirname "$0")"

# Start logging to file
exec > >(tee -a "$OUTPUT_FILE") 2>&1

echo "=========================================="
echo "Debug Reproduction Run"
echo "Started at: $(date)"
echo "=========================================="
echo ""

echo "Step 1: Starting Docker Compose services..."
docker-compose down -v 2>/dev/null || true
docker-compose up -d

echo ""
echo "Step 2: Waiting for services to be ready..."
echo -n "  - Waiting for Kafka..."
for i in {1..30}; do
    if docker-compose exec -T kafka kafka-topics --bootstrap-server localhost:9092 --list &>/dev/null; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    sleep 1
    echo -n "."
done

echo -n "  - Waiting for mock sink..."
for i in {1..30}; do
    if curl -s http://localhost:8080/health &>/dev/null; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    sleep 1
    echo -n "."
done

echo -n "  - Waiting for Vector..."
sleep 5
echo -e " ${GREEN}✓${NC}"

echo ""
echo "Step 3: Creating Kafka topic..."
docker-compose exec -T kafka kafka-topics \
    --bootstrap-server localhost:9092 \
    --create \
    --if-not-exists \
    --topic test-topic \
    --partitions 1 \
    --replication-factor 1

echo ""
echo "Step 4: Initialize Vector with good token config..."
docker-compose exec -T vector cp /etc/vector/configs/good_token.yaml /etc/vector/vector.yaml
echo "Waiting for Vector to load config..."
sleep 5
echo -e "${GREEN}✓${NC} Vector ready (started with good token config)"

echo ""
echo "=========================================="
echo "Starting Reproduction Test"
echo "=========================================="
echo ""

# Global variable to track last log line count
LAST_LOG_LINE_COUNT=0

# Function to initialize reload detection (capture current log state)
init_wait_for_reload() {
    LAST_LOG_LINE_COUNT=$(docker-compose logs vector 2>/dev/null | wc -l)
}

# Function to wait for Vector reload (only look for new logs)
wait_for_reload() {
    echo "  Waiting for Vector to reload..."
    local timeout=30
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        # Get only new logs since last checkpoint
        local new_logs=$(docker-compose logs vector 2>/dev/null | tail -n +$((LAST_LOG_LINE_COUNT + 1)))
        if echo "$new_logs" | grep -q "Vector has reloaded"; then
            echo -e "  ${GREEN}✓${NC} Vector reloaded"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo -e "  ${YELLOW}⚠${NC} Timeout waiting for reload (continuing anyway)"
    return 1
}

# Function to switch config
switch_config() {
    local config_file=$1
    local description=$2

    echo -e "${YELLOW}Switching to $description...${NC}"

    # Capture current log state before making changes
    init_wait_for_reload

    docker-compose exec -T vector cp /etc/vector/configs/$config_file /etc/vector/vector.yaml

    echo "  Verifying config change..."
    docker-compose exec -T vector grep "token:" /etc/vector/vector.yaml

    wait_for_reload
}

# Function to send messages to Kafka
send_messages() {
    local count=$1
    local start_id=$2
    local description=$3

    echo -e "${YELLOW}Sending $count messages ($description)...${NC}"

    for i in $(seq 1 $count); do
        local id=$((start_id + i - 1))
        local message="{\"id\": $id, \"message\": \"Test message $id\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
        echo "$message" | docker-compose exec -T kafka kafka-console-producer \
            --bootstrap-server localhost:9092 \
            --topic test-topic
    done

    echo "  Sent $count messages (IDs $start_id-$((start_id + count - 1)))"
    sleep 3
}

# Phase 1: Send 1 message with VALID token
echo -e "${GREEN}Phase 1: Sending 1 message with VALID token${NC}"
send_messages 1 1 "valid token"
sleep 5

# Phase 2: Send 1 message with INVALID token
echo ""
echo -e "${RED}Phase 2: Sending 1 message with INVALID token${NC}"
switch_config "bad_token.yaml" "INVALID token config"
send_messages 1 2 "invalid token - THIS WILL BE LOST"
sleep 5

# Phase 3: Send 1 message with VALID token again
echo ""
echo -e "${GREEN}Phase 3: Sending 1 message with VALID token again${NC}"
switch_config "good_token.yaml" "VALID token config"
send_messages 1 3 "valid token"
sleep 10

echo ""
echo "=========================================="
echo "Test Results"
echo "=========================================="
echo ""

# Get stats from mock sink
echo "Querying mock sink for received events..."
STATS=$(curl -s http://localhost:8080/stats)
TOTAL_RECEIVED=$(echo "$STATS" | jq -r '.total_received')

echo ""
echo "Expected: 3 messages sent (IDs 1, 2, 3)"
echo "Actual:   $TOTAL_RECEIVED messages received"
echo ""

if [ "$TOTAL_RECEIVED" -eq 2 ]; then
    echo -e "${RED}✗ BUG CONFIRMED: Only 2 messages received!${NC}"
    echo -e "${RED}  Message 2 (sent with invalid token) was PERMANENTLY LOST${NC}"
    echo ""
    echo "Received message IDs:"
    echo "$STATS" | jq -r '.events[].id' | sort -n | tr '\n' ' '
    echo ""
    echo ""
    echo -e "${YELLOW}This demonstrates the data loss bug in Vector's Kafka source.${NC}"
    echo -e "${YELLOW}Even though acknowledgements are enabled, rejected events are lost.${NC}"
elif [ "$TOTAL_RECEIVED" -eq 3 ]; then
    echo -e "${GREEN}✓ All 3 messages received - bug may be fixed!${NC}"
else
    echo -e "${YELLOW}⚠ Unexpected result: $TOTAL_RECEIVED messages received${NC}"
fi

echo ""
echo "=========================================="
echo "Logs"
echo "=========================================="
echo ""
echo "Mock sink logs (showing rejections):"
docker-compose logs mock-sink | grep -E "(SUCCESS|REJECTED)" | tail -20

echo ""
echo "Vector logs (showing dropped events):"
docker-compose logs vector | grep -i "drop" | tail -10

echo ""
echo "=========================================="
echo "Full Vector Debug Logs"
echo "=========================================="
echo ""
echo "Capturing full Vector logs with debug output..."
echo ""
docker-compose logs vector

echo ""
echo "=========================================="
echo "Full Mock Sink Logs"
echo "=========================================="
echo ""
docker-compose logs mock-sink

echo ""
echo "=========================================="
echo "Cleanup"
echo "=========================================="
echo ""
echo "Completed at: $(date)"
echo ""
echo "Debug output saved to: $OUTPUT_FILE"
echo ""
echo "To view full logs: docker-compose logs"
echo "To stop services: docker-compose down -v"
echo ""

