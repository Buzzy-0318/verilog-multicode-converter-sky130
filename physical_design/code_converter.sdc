
# Clock definition
create_clock -name core_clock -period 10.0 [get_ports clk]

# Clock uncertainty
set_clock_uncertainty 0.2 [get_clocks core_clock]

# Input delays
set_input_delay 1.0 -clock core_clock [all_inputs]

# Output delays
set_output_delay 1.0 -clock core_clock [all_outputs]

