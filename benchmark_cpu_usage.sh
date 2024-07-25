#!/bin/bash

TARGET_IP=$1
NUM_PACKETS=10000
RATE=1000

if [ -z "$TARGET_IP" ]; then
  echo "Usage: $0 <target_ip>"
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
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Sending $NUM_PACKETS packets WITH IP options trace_id"
  nping --tcp -p 80 --ip-options='\x88\x04\x34\x21' -c "$NUM_PACKETS" --rate "$RATE" --debug "$TARGET_IP" >> nping_output_with_options.log 2>&1 &
  NPID=\$!
}

# Function to send packets without IP options
send_packets_without_options() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Sending $NUM_PACKETS packets WITHOUT IP options trace_id"
  nping --tcp -p 80 -c "$NUM_PACKETS" --rate "$RATE" --debug "$TARGET_IP" >> nping_output_without_options.log 2>&1 &
  NPID=\$!
}

# Function to log CPU and memory usage for packets with options
log_resource_usage_with_options() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Logging resource usage with IP options"
  pidstat -u -r 1 >> resource_usage_with_options.log &
  PIDSTAT_PID=\$!
}

# Function to log CPU and memory usage for packets without options
log_resource_usage_without_options() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Logging resource usage without IP options"
  pidstat -u -r 1 >> resource_usage_without_options.log &
  PIDSTAT_PID=\$!
}

# Start traffic generation with IP options and logging resource usage
log_resource_usage_with_options
send_packets_with_options
wait \$NPID
kill \$PIDSTAT_PID

# Start traffic generation without IP options and logging resource usage
log_resource_usage_without_options
send_packets_without_options
wait \$NPID
kill \$PIDSTAT_PID

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Traffic generation completed and resource logging stopped."

# Print the last 50 lines of the log files
tail -n 50 nping_output_with_options.log
tail -n 50 nping_output_without_options.log
tail -n 50 resource_usage_with_options.log
tail -n 50 resource_usage_without_options.log
EOF