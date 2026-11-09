# The worst hold and setup paths, with their start and end points (for when the summary shows a negative slack)
project_open C64 -revision C64
create_timing_netlist
read_sdc
update_timing_netlist
foreach corner {slow_100c fast_100c slow_-40c fast_-40c} {
    catch {set_operating_conditions $corner}
    update_timing_netlist
    report_timing -hold -npaths 8 -detail summary -file output_files/worst_hold_$corner.txt
}
delete_timing_netlist
project_close
