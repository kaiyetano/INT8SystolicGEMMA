# INT8SystolicGEMMA RTL Views

- `01_matrix_accelerator_top.svg` - Shows the top-level matrix accelerator hierarchy connecting host writes, A/B/C BRAMs, the controller, systolic array, and post-processing path.
- `02_systolic_array.svg` - Shows the output-stationary PE mesh where A moves horizontally, B moves vertically, and each PE accumulates one C element.
- `03_controller_fsm.svg` - Shows the controller sequence that clears the array, runs skewed operand scheduling, writes outputs, drains the post-process pipeline, and asserts done.
- `04_pe_datapath.svg` - Shows the processing element datapath for signed INT8 multiplication, optional pipelining, accumulation, and operand forwarding.
- `05_bram_model.svg` - Shows the dual-port memory abstraction used for operand and output storage, including behavioral simulation and M10K synthesis paths.
- `06_post_process.svg` - Shows the output bias-add and optional ReLU clamp before final result storage.
