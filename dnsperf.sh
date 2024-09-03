#!/bin/bash
# Enhanced DNS Server Performance Test Script with Parallel Processing and Graphical Output
# This script tests the performance of multiple DNS servers in parallel and ranks them

set -euo pipefail

# Configuration
DNS_SERVERS_FILE="servers.txt"
DOMAINS_FILE="domains.txt"
RESULTS_FILE="dns_server_results.txt"
QUERY_COUNT=10
TIMEOUT=2
LOG_FILE="dns_test_log.txt"
GRAPH_FILE="dns_performance_graph.png"

# Check for required tools
for cmd in parallel gnuplot bc dig; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is required but not installed. Please install it and try again."
        exit 1
    fi
done

# ANSI color codes
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'

# Function to display usage information
usage() {
    echo -e "${BOLD}Usage:${RESET} $0 [-s dns_servers_file] [-d domains_file] [-o output_file] [-c query_count] [-t timeout] [-l log_file] [-g graph_file]"
    echo "  -s: Specify input file with DNS server IPs (default: $DNS_SERVERS_FILE)"
    echo "  -d: Specify input file with domain names to test (default: $DOMAINS_FILE)"
    echo "  -o: Specify output file for results (default: $RESULTS_FILE)"
    echo "  -c: Specify number of queries per domain (default: $QUERY_COUNT)"
    echo "  -t: Specify timeout in seconds for each query (default: $TIMEOUT)"
    echo "  -l: Specify log file (default: $LOG_FILE)"
    echo "  -g: Specify graph output file (default: $GRAPH_FILE)"
    exit 1
}

# Parse command-line options
while getopts ":s:d:o:c:t:l:g:h" opt; do
    case ${opt} in
        s ) DNS_SERVERS_FILE=$OPTARG ;;
        d ) DOMAINS_FILE=$OPTARG ;;
        o ) RESULTS_FILE=$OPTARG ;;
        c ) QUERY_COUNT=$OPTARG ;;
        t ) TIMEOUT=$OPTARG ;;
        l ) LOG_FILE=$OPTARG ;;
        g ) GRAPH_FILE=$OPTARG ;;
        h ) usage ;;
        \? ) echo "Invalid option: $OPTARG" 1>&2; usage ;;
        : ) echo "Invalid option: $OPTARG requires an argument" 1>&2; usage ;;
    esac
done

# Check if input files exist
for file in "$DNS_SERVERS_FILE" "$DOMAINS_FILE"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: Input file $file not found." >&2
        exit 1
    fi
done

# Function to test a single DNS server
test_dns_server() {
    local dns_server=$1
    local total_time=0
    local successful_queries=0
    local failed_queries=0

    echo "Testing DNS server: $dns_server" >&2

    while IFS= read -r domain || [[ -n "$domain" ]]; do
        echo "  Querying domain: $domain" >&2
        for ((i=1; i<=QUERY_COUNT; i++)); do
            echo "    Query attempt $i" >&2
            result=$(dig @"$dns_server" +time="$TIMEOUT" +tries=1 "$domain" 2>>$LOG_FILE | grep "Query time:")
            if [[ $? -eq 0 ]]; then
                query_time=$(echo "$result" | awk '{print $4}')
                total_time=$((total_time + query_time))
                ((successful_queries++))
                echo "      Success: Query time $query_time ms" >&2
            else
                ((failed_queries++))
                echo "      Failed query: $dns_server $domain (Attempt $i)" | tee -a $LOG_FILE >&2
            fi
        done
    done < "$DOMAINS_FILE"

    if [[ $successful_queries -gt 0 ]]; then
        avg_time=$(echo "scale=2; $total_time / $successful_queries" | bc)
        echo "DNS server $dns_server: Average time $avg_time ms, $successful_queries successful, $failed_queries failed" >&2
        echo "$dns_server $avg_time $successful_queries $failed_queries"
    else
        echo "DNS server $dns_server: All queries failed" >&2
        echo "$dns_server 999999 0 $failed_queries"
    fi
}

# Export the function and variables so they're available to GNU Parallel
export -f test_dns_server
export DOMAINS_FILE QUERY_COUNT TIMEOUT LOG_FILE

# Function to print a horizontal line
print_line() {
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
}

# Function to print centered text
print_centered() {
    local text="$1"
    local color="${2:-$RESET}"
    local width="${COLUMNS:-$(tput cols)}"
    local padding=$(( (width - ${#text}) / 2 ))
    printf "${color}%*s%s%*s${RESET}\n" $padding '' "$text" $padding ''
}

# Main execution
echo "Testing DNS servers in parallel..."
> "$RESULTS_FILE"
> "$LOG_FILE"

# Use GNU Parallel to run tests in parallel
parallel --will-cite test_dns_server :::: "$DNS_SERVERS_FILE" > "$RESULTS_FILE"

echo "Testing complete. Sorting results..."

# Sort results by average query time
sort -k2 -n "$RESULTS_FILE" > "${RESULTS_FILE}.sorted"

# Check if sorted file exists and has content
if [[ ! -s "${RESULTS_FILE}.sorted" ]]; then
    echo "Error: No results to display. Check the log file for details."
    exit 1
fi

# Display results
{
    clear  # Clear the terminal screen
    print_centered "DNS Server Performance Results" "${BOLD}${BLUE}"
    print_line
    printf "${BOLD}%-4s | %-15s | %14s | %18s | %14s${RESET}\n" "Rank" "DNS Server" "Avg Time (ms)" "Successful Queries" "Failed Queries"
    print_line

    # Read and display sorted results with color coding
    rank=0
    while IFS=' ' read -r ip avg_time success fail; do
        # Validate numeric values
        if ! [[ "$avg_time" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$success" =~ ^[0-9]+$ ]] || ! [[ "$fail" =~ ^[0-9]+$ ]]; then
            echo "Error: Invalid data for IP $ip. Skipping." >&2
            continue
        fi

        if (( $(echo "$avg_time < 50" | bc -l) )); then
            color=$GREEN
        elif (( $(echo "$avg_time < 100" | bc -l) )); then
            color=$YELLOW
        else
            color=$RED
        fi

        if [[ "$avg_time" != "999999" ]]; then
            printf "${color}%4d | %-15s | %14.2f | %18d | %14d${RESET}\n" "$((++rank))" "$ip" "$avg_time" "$success" "$fail"
        else
            printf "${RED}%4d | %-15s | %14s | %18d | %14d${RESET}\n" "$((++rank))" "$ip" "FAILED" "$success" "$fail"
        fi
    done < "${RESULTS_FILE}.sorted"

    print_line
    echo -e "\n${BOLD}${MAGENTA}Detailed results saved in ${RESULTS_FILE}.report${RESET}"
    echo -e "${BOLD}${CYAN}Log file saved as $LOG_FILE${RESET}"
    echo -e "${BOLD}${GREEN}Performance graph saved as $GRAPH_FILE${RESET}\n"
} | tee "${RESULTS_FILE}.report"

# Generate graphical output using gnuplot, excluding non-responding servers
gnuplot <<EOF
set terminal pngcairo enhanced font "arial,10" size 1600,800  # Increase the plot size further for more space
set output "$GRAPH_FILE"
set title "DNS Server Performance Comparison"
set style fill solid 1.00 border -1
set xlabel ""
set ylabel "Average Query Time (ms)"
set grid
set key off
set boxwidth 0.6 relative
set auto x  # Enable autoscaling for the x-axis

# Adjust margins for better fitting
set lmargin 15  # Increase left margin to fit rotated labels
set rmargin 5  # Adjust the right margin
set bmargin 5  # Bottom margin
set tmargin 5  # Top margin

# Rotate the labels on the y-axis to avoid overlap
set ytics nomirror rotate by 45 right  # Rotate y-axis labels 45 degrees for better fit
set xtics nomirror rotate by 45 right
set border 3

# Plot horizontal bars using 'boxes'
plot "${RESULTS_FILE}.sorted" using (\$2 < 999999 ? \$2 : 1/0):xtic(1) with boxes notitle linecolor rgb "#00A5E3"
EOF


# Cleanup
rm -f "$RESULTS_FILE" "${RESULTS_FILE}.sorted"

echo "Script execution completed. Check ${RESULTS_FILE}.report for results and $GRAPH_FILE for the performance graph."

exit 0