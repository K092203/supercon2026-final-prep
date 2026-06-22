# =====================================================================
# SuperCon2026 final-prep — Makefile
#   ローカル (g++): make          → build/skeleton, build/stencil, build/search
#   富岳 (mpiFCC) : make fugaku   → build/fugaku/{skeleton,stencil,search}
# =====================================================================

# ---------- ローカル検証用 (MPI なし) ----------
CXX_LOCAL    = g++
FLAGS_LOCAL  = -std=c++17 -O2 -fopenmp -Wall -Wextra -Isrc

# ---------- 富岳提出用 (mpiFCC / DUSE_MPI) ----------
CXX_FUGAKU   = mpiFCC
FLAGS_FUGAKU = -Nclang -Ofast -Kfast,openmp,simd -msve-vector-bits=512 -DUSE_MPI -Isrc

.PHONY: all fugaku \
        skeleton stencil search \
        test-skeleton test-stencil test-search \
        fast naive run test stress bench clean

# ---------- デフォルト: ローカル 3 バイナリ ----------
all: skeleton stencil search

skeleton:
	mkdir -p build
	$(CXX_LOCAL) $(FLAGS_LOCAL) src/skeleton.cpp -o build/skeleton

stencil:
	mkdir -p build
	$(CXX_LOCAL) $(FLAGS_LOCAL) src/stencil.cpp -o build/stencil

search:
	mkdir -p build
	$(CXX_LOCAL) $(FLAGS_LOCAL) src/search.cpp -o build/search

# ---------- 富岳提出ビルド ----------
fugaku:
	mkdir -p build/fugaku
	$(CXX_FUGAKU) $(FLAGS_FUGAKU) src/skeleton.cpp -o build/fugaku/skeleton
	$(CXX_FUGAKU) $(FLAGS_FUGAKU) src/stencil.cpp  -o build/fugaku/stencil
	$(CXX_FUGAKU) $(FLAGS_FUGAKU) src/search.cpp   -o build/fugaku/search

# ---------- 個別テスト (シングルプロセス / MPI ランタイム不要) ----------
test-skeleton: skeleton
	./build/skeleton

test-stencil: stencil
	./build/stencil

test-search: search
	./build/search

# ---------- stress.py / benchmark.py との互換維持 ----------
# build/fast = build/skeleton のシム (tools/stress.py が参照)
fast: skeleton
	mkdir -p build
	cp build/skeleton build/fast

naive:
	mkdir -p build
	$(CXX_LOCAL) $(FLAGS_LOCAL) src/solver_naive.cpp -o build/naive

run: test-skeleton

test: fast
	./build/fast < cases/sample.in

stress: fast naive
	python3 tools/stress.py

bench: fast
	python3 tools/benchmark.py

# ---------- clean ----------
clean:
	rm -rf build
