CXX = g++
CXXFLAGS = -std=gnu++20 -O2 -Wall -Wextra -Wshadow

FAST = build/fast
NAIVE = build/naive

.PHONY: all fast naive run test stress bench clean

all: fast naive

fast:
	mkdir -p build
	$(CXX) $(CXXFLAGS) src/main.cpp -o $(FAST)

naive:
	mkdir -p build
	$(CXX) $(CXXFLAGS) src/solver_naive.cpp -o $(NAIVE)

run: fast
	./$(FAST)

test: fast
	./$(FAST) < cases/sample.in

stress: fast naive
	python3 tools/stress.py

bench: fast
	python3 tools/benchmark.py

clean:
	rm -rf build
