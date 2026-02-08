#!/bin/sh

add_metric() {
    if [ "$#" -lt 3 ]; then
        warn_msg "The number of parameters less then 3"
        error_msg "Usage: add_metric test_case result measurement [units]"
    fi
    
    local test_case="$1"
    local result="$2"
    local measurement="$3"
    local units="$4"

    echo "${test_case} ${result} ${measurement} ${units}" | tee -a "${RESULT_FILE}"
}

report_pass() {
    [ "$#" -ne 1 ] && error_msg "Usage: report_pass test_case"
    # shellcheck disable=SC2039
    local test_case="$1"
    echo "${test_case} pass" | tee -a "${RESULT_FILE}"
}

report_fail() {
    [ "$#" -ne 1 ] && error_msg "Usage: report_fail test_case"
    # shellcheck disable=SC2039
    local test_case="$1"
    echo "${test_case} fail" | tee -a "${RESULT_FILE}"
}

pipe_status() {
    if [ $# -ne 2 ]; then
       echo "Usage: pipe_status cmd1 cmd2" >&2
       return 1
    fi
    
    local cmd1="$1"
    local cmd2="$2"

    exec 4>&1
    
    local ret_val
    ret_val=$({ { eval "${cmd1}" 3>&-; echo "$?" 1>&3; } 4>&- \
              | eval "${cmd2}" 1>&4; } 3>&1)
    exec 4>&-

    return "${ret_val}"
}