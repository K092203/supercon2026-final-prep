# =====================================================================
# SuperCon2026 final-prep — Makefile
#   ローカル (g++): make          → build/{skeleton,stencil,stencil_blocked,search}
#   富岳 (mpiFCC) : make fugaku   → build/fugaku/{skeleton,stencil,stencil_blocked,search}
#   掃引リハ      : make tune-local CONFIGS=<configs.tsv>  (詳細 docs/autotune.md)
# =====================================================================

# ---------- 時間予算オーバーライド: make fugaku BUDGET_SEC=1750 ----------
BUDGET_OVERRIDE = $(if $(BUDGET_SEC),-DBUDGET_SEC=$(BUDGET_SEC),)

# ---------- ローカル検証用 (MPI なし) ----------
CXX_LOCAL    = g++
FLAGS_LOCAL  = -std=c++17 -O2 -fopenmp -Wall -Wextra -Isrc $(BUDGET_OVERRIDE)

# ---------- 富岳提出用 (mpiFCC / DUSE_MPI) ----------
CXX_FUGAKU   = mpiFCC
# -Kzfill: 書き込み専用ストリーム(ステンシルの出力配列)で read-for-ownership を省きHBM帯域を節約
FLAGS_FUGAKU = -Nclang -Ofast -Kfast,openmp,simd,zfill -msve-vector-bits=512 -DUSE_MPI -Isrc $(BUDGET_OVERRIDE)

.PHONY: all fugaku fugaku-run \
        skeleton stencil stencil-blocked search \
        test-skeleton test-stencil test-search \
        local-mpi test-mpi \
        contest contest-fugaku test-contest \
        tune-local \
        fast naive run test stress bench clean

# ---------- デフォルト: ローカル 4 バイナリ ----------
all: skeleton stencil stencil-blocked search

skeleton:
	mkdir -p build
	$(CXX_LOCAL) $(FLAGS_LOCAL) src/skeleton.cpp -o build/skeleton

stencil:
	mkdir -p build
	$(CXX_LOCAL) $(FLAGS_LOCAL) src/stencil.cpp -o build/stencil

# 温度ブロッキング版 (メモリ律速ステンシルの伸び代。BT/RB/CB は実機で調整)
stencil-blocked:
	mkdir -p build
	$(CXX_LOCAL) $(FLAGS_LOCAL) src/stencil_blocked.cpp -o build/stencil_blocked

search:
	mkdir -p build
	$(CXX_LOCAL) $(FLAGS_LOCAL) src/search.cpp -o build/search

# ---------- 本選当日用: 新規ファイルを書いたときのビルド先 ----------
# 使い方: src/contest.cpp を作成してから make contest
# utilities.hpp (fastio/Budget/Rng) は自由に #include できる
contest:
	mkdir -p build
	$(CXX_LOCAL) $(FLAGS_LOCAL) src/contest.cpp -o build/contest

contest-fugaku:
	mkdir -p build/fugaku
	$(CXX_FUGAKU) $(FLAGS_FUGAKU) src/contest.cpp -o build/fugaku/contest

test-contest: contest
	./build/contest < tests/sample_01.in

# ---------- ローカル MPI 検証 (富岳前に MPI 経路を 4 ランクで確認) ----------
# 要 OpenMPI: sudo apt-get install -y openmpi-bin libopenmpi-dev
#   make local-mpi  → build/mpi/{skeleton,stencil,search} (mpic++ / -DUSE_MPI)
#   make test-mpi   → 4 ランクでハロ交換 / MAXLOC+Bcast / Allreduce を自動検証
CXX_MPI    = mpic++
FLAGS_MPI  = -std=c++17 -O2 -fopenmp -Wall -Wextra -DUSE_MPI -Isrc $(BUDGET_OVERRIDE)

local-mpi:
	mkdir -p build/mpi
	$(CXX_MPI) $(FLAGS_MPI) src/skeleton.cpp        -o build/mpi/skeleton
	$(CXX_MPI) $(FLAGS_MPI) src/stencil.cpp         -o build/mpi/stencil
	$(CXX_MPI) $(FLAGS_MPI) src/stencil_blocked.cpp -o build/mpi/stencil_blocked
	$(CXX_MPI) $(FLAGS_MPI) src/search.cpp          -o build/mpi/search

test-mpi:
	bash tools/check-mpi.sh

# ---------- 富岳提出ビルド ----------
fugaku:
	mkdir -p build/fugaku
	$(CXX_FUGAKU) $(FLAGS_FUGAKU) src/skeleton.cpp        -o build/fugaku/skeleton
	$(CXX_FUGAKU) $(FLAGS_FUGAKU) src/stencil.cpp         -o build/fugaku/stencil
	$(CXX_FUGAKU) $(FLAGS_FUGAKU) src/stencil_blocked.cpp -o build/fugaku/stencil_blocked
	$(CXX_FUGAKU) $(FLAGS_FUGAKU) src/search.cpp          -o build/fugaku/search

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

# 注意: test / stress は課題確定後に gen_case() と solver を実装してから使う。
# 現状の build/fast (skeleton) は stdin を無視するため有意なテストにならない。
test: fast
	./build/fast < cases/sample.in

stress: fast naive
	python3 tools/stress.py

bench: fast
	python3 tools/benchmark.py

# ---------- 富岳 ワンショット実行 (要: tools/fugaku-config.env) ----------
# 使い方: make fugaku-run TARGET=skeleton BUDGET_SEC=1750
fugaku-run:
	tools/fugaku-run.sh $(or $(TARGET),skeleton) $(or $(BUDGET_SEC),1750)

# ---------- ローカル掃引リハ (富岳経路の予行演習。要 OpenMPI) ----------
# 使い方: make tune-local CONFIGS=/tmp/c.tsv BUDGET_SEC=1
tune-local:
	tools/tune-local.sh $(CONFIGS) $(or $(BUDGET_SEC),2)

# ---------- clean ----------
clean:
	rm -rf build
