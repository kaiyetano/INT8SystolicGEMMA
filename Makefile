PROJECT    := INT8SystolicGEMMA
REVISION   := $(PROJECT)

N          ?= 2
TEST       ?= signed_basic
PIPELINE_PRODUCT ?= 0
PIPELINE_DSP ?= 0
ENABLE_BIAS ?= 0
ENABLE_RELU ?= 0

SYNTH_TOP  ?= matrix_accelerator
RTL_TOP    ?= matrix_accelerator
SIM_TOP    := tb_matrix_accelerator
VEC_DIR    = vectors/N$(N)/$(TEST)

RTL_SRCS   := rtl/bram_model.sv rtl/post_process.sv rtl/pe.sv rtl/systolic_array.sv rtl/controller_fsm.sv rtl/matrix_accelerator.sv
TB_SRCS    := tb/tb_matrix_accelerator.sv

CYCLONEV_PART ?= 5CGXFC9E7F35C8
PART          ?= $(CYCLONEV_PART)

PYTHON          ?= python3
VSIM            ?= vsim
# Set QUARTUS_ROOTDIR to your Quartus install root (e.g. C:/intelFPGA_lite/20.1/quartus)
# to avoid needing quartus_sh/quartus on PATH.
QUARTUS_ROOTDIR ?=
QUARTUS_SH      ?= $(if $(QUARTUS_ROOTDIR),$(QUARTUS_ROOTDIR)/bin64/quartus_sh,quartus_sh)
QUARTUS         ?= $(if $(QUARTUS_ROOTDIR),$(QUARTUS_ROOTDIR)/bin64/quartus,quartus)

QUARTUS_ARGS = $(PROJECT) $(REVISION) $(QUARTUS_MODE) $(SYNTH_TOP) $(PART) $(N) $(PIPELINE_PRODUCT) $(PIPELINE_DSP) $(ENABLE_BIAS) $(ENABLE_RELU)

.PHONY: help vectors sim sim-ai wave synth compile quartus rtl regress regress-ai clean
.PHONY: sim-report sweep-sim sweep-reports clean-reports copy-full-report summarize-reports package-reports

help:
	@echo "Targets:"
	@echo "  make sim        - run self-checking simulation for N=$(N), TEST=$(TEST)"
	@echo "  make sim-ai     - run N=4 signed_random_bias_relu with bias/ReLU and DSP pipelining"
	@echo "  make wave       - open ModelSim GUI with current N/TEST"
	@echo "  make synth      - Quartus Analysis & Synthesis for parameterized matrix_accelerator"
	@echo "  make compile    - full Quartus compile for parameterized matrix_accelerator"
	@echo "  make regress    - base matrix-multiply regression"
	@echo "  make regress-ai - AI post-process regression"
	@echo "  make clean      - remove generated build/simulation files"
	@echo ""
	@echo "Useful variables:"
	@echo "  N=2|4|8|16 TEST=signed_basic PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1"
	@echo "  QUARTUS_ROOTDIR=C:/intelFPGA_lite/20.1/quartus  (or add quartus_sh/quartus to PATH)"
	@echo "  PYTHON=python3  VSIM=vsim"

vectors:
	$(PYTHON) scripts/gen_vectors.py --n $(N) --test $(TEST) --out-dir $(VEC_DIR)

sim: vectors
	$(VSIM) -c -do "set TOP $(SIM_TOP); set RTL_SRCS {$(RTL_SRCS)}; set TB_SRCS {$(TB_SRCS)}; set VSIM_ARGS {-gN=$(N) -gPIPELINE_PRODUCT=$(PIPELINE_PRODUCT) -gPIPELINE_DSP=$(PIPELINE_DSP) -gENABLE_BIAS=$(ENABLE_BIAS) -gENABLE_RELU=$(ENABLE_RELU) +TEST=$(TEST) +VEC_DIR=$(VEC_DIR)}; do scripts/run_sim.tcl"

sim-ai:
	$(MAKE) sim N=4 TEST=signed_random_bias_relu PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1

wave: vectors
	$(VSIM) -do "set TOP $(SIM_TOP); set RTL_SRCS {$(RTL_SRCS)}; set TB_SRCS {$(TB_SRCS)}; set VSIM_ARGS {-gN=$(N) -gPIPELINE_PRODUCT=$(PIPELINE_PRODUCT) -gPIPELINE_DSP=$(PIPELINE_DSP) -gENABLE_BIAS=$(ENABLE_BIAS) -gENABLE_RELU=$(ENABLE_RELU) +TEST=$(TEST) +VEC_DIR=$(VEC_DIR)}; do scripts/run_wave.tcl"

synth:
	$(MAKE) QUARTUS_MODE=synth_only quartus-run

compile:
	$(MAKE) QUARTUS_MODE=full_compile quartus-run

quartus-run:
	"$(QUARTUS_SH)" -t scripts/run_quartus.tcl $(QUARTUS_ARGS)

quartus:
	"$(QUARTUS)" $(PROJECT).qpf

rtl:
	$(MAKE) synth SYNTH_TOP=$(RTL_TOP)
	"$(QUARTUS)" $(PROJECT).qpf

regress:
	$(MAKE) sim N=2 TEST=signed_basic ENABLE_BIAS=0 ENABLE_RELU=0
	$(MAKE) sim N=2 TEST=identity ENABLE_BIAS=0 ENABLE_RELU=0
	$(MAKE) sim N=2 TEST=zero ENABLE_BIAS=0 ENABLE_RELU=0
	$(MAKE) sim N=4 TEST=signed_basic ENABLE_BIAS=0 ENABLE_RELU=0
	$(MAKE) sim N=4 TEST=identity ENABLE_BIAS=0 ENABLE_RELU=0
	$(MAKE) sim N=4 TEST=zero ENABLE_BIAS=0 ENABLE_RELU=0
	$(MAKE) sim N=4 TEST=signed_random ENABLE_BIAS=0 ENABLE_RELU=0
	$(MAKE) sim N=4 TEST=int8_minmax_stress ENABLE_BIAS=0 ENABLE_RELU=0

regress-ai:
	$(MAKE) sim N=2 TEST=bias_zero PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1
	$(MAKE) sim N=4 TEST=bias_positive PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1
	$(MAKE) sim N=4 TEST=bias_negative PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1
	$(MAKE) sim N=8 TEST=relu_basic PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1
	$(MAKE) sim N=8 TEST=signed_random_bias_relu PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1
	$(MAKE) sim N=16 TEST=signed_random_bias_relu PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1

sim-report:
	$(MAKE) sim N=$(N) TEST=$(TEST) PIPELINE_PRODUCT=$(PIPELINE_PRODUCT) PIPELINE_DSP=$(PIPELINE_DSP) ENABLE_BIAS=$(ENABLE_BIAS) ENABLE_RELU=$(ENABLE_RELU)
	powershell -NoProfile -ExecutionPolicy Bypass -Command "$$dest = 'reports/sim/N$(N)'; New-Item -ItemType Directory -Path $$dest -Force | Out-Null; if (Test-Path -LiteralPath 'transcript') { Copy-Item -LiteralPath 'transcript' -Destination (Join-Path $$dest '$(TEST)_transcript.txt') -Force }"

sweep-sim:
	$(MAKE) sim-report N=2 TEST=signed_basic
	$(MAKE) sim-report N=4 TEST=signed_basic
	$(MAKE) sim-report N=8 TEST=signed_basic
	$(MAKE) sim-report N=16 TEST=signed_basic

sweep-reports: clean-reports
	$(MAKE) compile N=2 PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1
	$(MAKE) copy-full-report REPORT_DEST=reports/N2
	$(MAKE) compile N=4 PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1
	$(MAKE) copy-full-report REPORT_DEST=reports/N4
	$(MAKE) compile N=8 PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1
	$(MAKE) copy-full-report REPORT_DEST=reports/N8
	$(MAKE) compile N=16 PIPELINE_DSP=1 ENABLE_BIAS=1 ENABLE_RELU=1
	$(MAKE) copy-full-report REPORT_DEST=reports/N16

clean-reports:
	powershell -NoProfile -ExecutionPolicy Bypass -Command "$$root = (Resolve-Path -LiteralPath '.').Path; $$targets = @('reports','reports.zip','reports_archive.zip'); foreach ($$target in $$targets) { $$path = [System.IO.Path]::GetFullPath((Join-Path $$root $$target)); if (-not $$path.StartsWith($$root, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to delete outside workspace' }; if (Test-Path -LiteralPath $$path) { Remove-Item -LiteralPath $$path -Recurse -Force } }"

copy-full-report:
	powershell -NoProfile -ExecutionPolicy Bypass -Command "$$root = (Resolve-Path -LiteralPath '.').Path; $$reports_root = [System.IO.Path]::GetFullPath((Join-Path $$root 'reports')); $$dest = [System.IO.Path]::GetFullPath((Join-Path $$root '$(REPORT_DEST)')); if (-not $$dest.StartsWith($$reports_root, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to delete outside reports directory' }; if (Test-Path -LiteralPath $$dest) { Remove-Item -LiteralPath $$dest -Recurse -Force }; New-Item -ItemType Directory -Path $$dest -Force | Out-Null; $$patterns = @('*.flow.rpt','*.map.rpt','*.map.summary','*.fit.rpt','*.fit.summary','*.sta.rpt','*.sta.summary','*.asm.rpt','*.pin','*.sof'); foreach ($$pattern in $$patterns) { Get-ChildItem -Path 'output_files' -Filter $$pattern -ErrorAction SilentlyContinue | Copy-Item -Destination $$dest -Force }"

summarize-reports:
	$(PYTHON) scripts/parse_quartus_reports.py

package-reports:
	powershell -NoProfile -ExecutionPolicy Bypass -Command "if (-not (Test-Path -LiteralPath 'reports')) { throw 'No reports folder found' }; Compress-Archive -Path 'reports' -DestinationPath 'reports_archive.zip' -Force"

clean:
	powershell -NoProfile -ExecutionPolicy Bypass -Command "$$targets = @('work','incremental_db','db','output_files','vectors','transcript','vsim.wlf','modelsim.ini','c5_pin_model_dump.txt','INT8SystolicGEMMA.qws'); foreach ($$target in $$targets) { if (Test-Path -LiteralPath $$target) { Remove-Item -LiteralPath $$target -Recurse -Force -ErrorAction SilentlyContinue } }; exit 0"
