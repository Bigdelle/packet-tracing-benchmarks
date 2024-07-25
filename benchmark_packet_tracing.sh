#!/bin/bash

# Usage: ./benchmark_packet_tracing.sh <target_ip> <num_with_options> <num_without_options>
# Example: sudo ./benchmark_packet_tracing.sh 192.168.1.1 100 200

TARGET_IP=$1
NUM_WITH_OPTIONS=$2
NUM_WITHOUT_OPTIONS=$3

# Validate input
if [ -z "$TARGET_IP" ] || [ -z "$NUM_WITH_OPTIONS" ] || [ -z "$NUM_WITHOUT_OPTIONS" ]; then
  echo "Usage: $0 <target_ip> <num_with_options> <num_without_options>"
  exit 1
fi

# Get container and pid
container=$(crictl ps | grep "$(crictl pods | grep client | awk '{ print $1 }')" | awk '{ print $1 }')
pid=$(crictl inspect "${container}" | grep pid | head -1 | grep -Eo "[0-9]+")

if [ -z "$pid" ]; then
  echo "Failed to get the PID of the container."
  exit 1
fi

echo "Switching to the network namespace of the container with PID ${pid}"

# Run the rest of the script in the container's network namespace
nsenter -t "${pid}" -n /bin/bash << EOF

# Function to send packets with IP options
send_packets_with_options() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Sending $NUM_WITH_OPTIONS packets WITH IP options trace_id"
  nping --tcp -p 80 --ip-options='\x88\x04\x34\x21' -c "$NUM_WITH_OPTIONS" --rate 1000 --debug "$TARGET_IP" >> nping_output_with_options.log 2>&1
}

# Function to send packets without IP options
send_packets_without_options() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Sending $NUM_WITHOUT_OPTIONS packets WITHOUT IP options trace_id"
  nping --tcp -p 80 -c "$NUM_WITHOUT_OPTIONS" --rate 1000 --debug "$TARGET_IP" >> nping_output_without_options.log 2>&1
}

# Start traffic generation
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting traffic generation to $TARGET_IP"
send_packets_with_options
send_packets_without_options

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Traffic generation completed."
EOF
