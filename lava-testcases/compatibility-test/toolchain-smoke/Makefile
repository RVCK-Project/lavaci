CC ?= gcc
CXX ?= g++
BUILD_DIR ?= build
CFLAGS ?= -Wall -Wextra
CXXFLAGS ?= -Wall -Wextra

.PHONY: all
all: $(BUILD_DIR)/hello_c_make $(BUILD_DIR)/hello_cpp_make

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/hello_c_make: hello.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $<

$(BUILD_DIR)/hello_cpp_make: hello.cpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $<
