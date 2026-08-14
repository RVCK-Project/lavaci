#!/bin/bash

set -x

source ../../lib/sh-test-lib.sh

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TEST_TMPDIR="/root/sysbench"

TESTS="percpu cpu memory threads mutex fileio"
NUM_THREADS="NPROC"

usage() {
    echo "usage: $0 [-n <num-threads>] [-t <test>] [-s <true|false>] 1>&2"
    exit 1
}

while getopts "n:t:" arg; do
    case "${arg}" in
        n) NUM_THREADS="${OPTARG}" ;;
        t) TESTS="${OPTARG}" ;;
        *) usage ;;
    esac
done
if [ -z "${NUM_THREADS}" ] || [ "${NUM_THREADS}" = "NPROC" ]; then
    NUM_THREADS=$(nproc)
fi

if [ -z "${TESTS}" ]; then
   TESTS="percpu cpu memory threads mutex fileio"
fi

general_parser() {
    # if $1 is there, let's append to test name in the result file
    local tc="$tc$1"
    ms=$(grep -m 1 "total time" "${logfile}" | awk '{print substr($NF,1,length($NF)-1)}')
    add_metric "${tc}-total-time" "pass" "${ms}" "s"

    ms=$(grep "total number of events" "${logfile}" | awk '{print $NF}')
    add_metric "${tc}-total-number-of-events" "pass" "${ms}" "times"

    ranges=("min" "avg" "max" "95th percentile")
    for i in "${ranges[@]}"; do
        ms=$(grep -m 1 "$i" "${logfile}" | awk '{print $NF}')
        add_metric "${tc}-Latency-$i" "pass" "${ms}" "ms"
    done

    ms=$(grep "events (avg/stddev)" "${logfile}" |  awk '{print $NF}')
    ms_avg=$(echo "${ms}" | awk -F'/' '{print $1}')
    ms_stddev=$(echo "${ms}" | awk -F'/' '{print $2}')
    add_metric "${tc}-events-avg" "pass" "${ms_avg}" "times"
    add_metric "${tc}-events-stddev" "pass" "${ms_stddev}" "times"

    ms=$(grep "execution time (avg/stddev)" "${logfile}" |  awk '{print $NF}')
    ms_avg=$(echo "${ms}" | awk -F'/' '{print $1}')
    ms_stddev=$(echo "${ms}" | awk -F'/' '{print $2}')
    add_metric "${tc}-execution-time-avg" "pass" "${ms_avg}" "s"
    add_metric "${tc}-execution-time-stddev" "pass" "${ms_stddev}" "s"
}


dnf install -y sysbench
mkdir -p "${OUTPUT}"
mkdir -p "${TEST_TMPDIR}"
cd "${TEST_TMPDIR}"
for tc in ${TESTS}; do
    echo "Running sysbench ${tc} test..."
    logfile="${OUTPUT}/sysbench-${tc}.txt"
    case "${tc}" in
        percpu)
            processor_id="$(awk '/^processor/{print $3}' /proc/cpuinfo)"
            for i in ${processor_id}; do
                taskset -c "$i" sysbench --threads=1 --test=cpu run | tee "${logfile}"
                general_parser "$i"
            done
            ;;
        cpu|threads|mutex)
            sysbench --threads="${NUM_THREADS}" --test="${tc}" run | tee "${logfile}"
            general_parser
            ;;
        memory)
            sysbench --threads="${NUM_THREADS}" --test=memory run | tee "${logfile}"
            general_parser

            ms=$(grep "Total operations" "${logfile}" | awk '{print substr($4,2)}')
            add_metric "${tc}-total-operations" "pass" "${ms}" "ops"

            ms=$(grep "transferred" "${logfile}" | awk '{print substr($4, 2)}')
            units=$(grep "transferred" "${logfile}" | awk '{print substr($5,1,length($NF)-1)}')
            add_metric "${tc}-transferred" "pass" "${ms}" "${units}"
            ;;
        fileio)
            mkdir fileio && cd fileio
            for mode in seqwr seqrewr seqrd rndrd rndwr rndrw; do
                tc="fileio-${mode}"
                logfile="${OUTPUT}/sysbench-${tc}.txt"
                sync
                echo 3 > /proc/sys/vm/drop_caches
                sleep 8
                sysbench --threads="${NUM_THREADS}" --test=fileio --file-total-size=2G --file-test-mode="${mode}" prepare
                # --file-extra-flags=direct is needed when file size is smaller then RAM.
                sysbench --threads="${NUM_THREADS}" --test=fileio --file-extra-flags=direct --file-total-size=2G --file-test-mode="${mode}" run | tee "${logfile}"
                sysbench --threads="${NUM_THREADS}" --test=fileio --file-total-size=2G --file-test-mode="${mode}" cleanup
                general_parser

                ops=("reads/s" "writes/s" "fsyncs/s")
                for i in "${ops[@]}"; do
                    ms=$(grep "$i" "${logfile}" | awk '{print $NF}')
                    add_metric "${tc}-file-operations-$i" "pass" "${ms}" "times"
                done
                
                tp=("read, MiB/s" "written, MiB/s")
                for i in "${tp[@]}"; do
                    str=$(grep "$i" "${logfile}" | awk '{print substr($1, 1, length($1)-1)}')
                    ms=$(grep "$i" "${logfile}" | awk '{print $NF}')
                    units=$(grep "$i" "${logfile}" | awk '{print substr($2, 1, length($2)-1)}')
                    add_metric "${tc}-throughtput-${str}" "pass" "${ms}" "${units}"
                done
            done
            ;;
    esac
done