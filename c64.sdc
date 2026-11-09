# OCTOPHONIC: the core's own timing exceptions (sys/sys_top.sdc has the MiSTer framework's).
#
# io_cycle_data / io_cycle_addr / io_cycle_we -> the SDRAM controller (clk32 -> clk64): they are written on the same clk32 edge that raises
# io_cycle_ce, while io_cycle is low; the SDRAM controller only latches din (wrdata <= din, on ce && !last_ce) once
# io_cycle has gone high and switched the address/ce/din mux over - many clk64 cycles later - and io_cycle_data does
# not change again until the next io_cycle falling edge. So the data is long stable at the capture edge: the hold
# check (0.4 ns short with the bigger design, 93% full) is against an edge pair that never carries a transfer.
# Setup is still checked.
set_false_path -hold -from [get_registers {emu:emu|io_cycle_data[*]}] -to [get_registers {emu:emu|sdram:sdram|*}]
set_false_path -hold -from [get_registers {emu:emu|io_cycle_addr[*]}] -to [get_registers {emu:emu|sdram:sdram|*}]
set_false_path -hold -from [get_registers {emu:emu|io_cycle_we}]      -to [get_registers {emu:emu|sdram:sdram|*}]
# (io_cycle_ce is the request itself and stays fully checked)
