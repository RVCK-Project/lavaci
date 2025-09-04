#!/usr/bin/env python3

import sys
import json


def print_thread_res(tid, res, key):
    print("t{}-{}-latency pass {} us".format(tid, key, res[key]))


def print_irq_res(iid, res, key):
    print("i{}-{}-latency pass {} us".format(iid, key, res[key]))


def parse_threads(rawdata):
    num_threads = int(rawdata["num_threads"])
    for thread_id in range(num_threads):
        tid = str(thread_id)
        if "receiver" in rawdata["thread"][tid]:
            data = rawdata["thread"][tid]["receiver"]
        else:
            data = rawdata["thread"][tid]

        for key in ["min", "avg", "max"]:
            print_thread_res(tid, data, key)


def parse_irqs(rawdata):
    num_irqs = int(rawdata["num_irqs"])
    for irq_id in range(num_irqs):
        iid = str(irq_id)
        data = rawdata["irq"][iid]
        for key in ["min", "avg", "max"]:
            print_irq_res(iid, data, key)


def parse_json(testname, filename):
    with open(filename) as file:
        rawdata = json.load(file)

    if "num_threads" in rawdata:
        # most rt-tests have generic per thread results
        parse_threads(rawdata)
    if "num_irqs" in rawdata:
        # rlta timertat also knows about irqs
        parse_irqs(rawdata)

    elif "inversion" in rawdata:
        # pi_stress
        print("inversion pass {} count\n".format(rawdata["inversion"]))

    if int(rawdata["return_code"]) == 0:
        print("{} pass".format(testname))
    else:
        print("{} fail".format(testname))


def main():
    parse_json(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()