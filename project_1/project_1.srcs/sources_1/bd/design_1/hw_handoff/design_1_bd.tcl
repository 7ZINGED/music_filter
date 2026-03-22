
################################################################
# This is a generated script based on design: design_1
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2018.3
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   catch {common::send_msg_id "BD_TCL-109" "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source design_1_script.tcl

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7vx485tffg1157-1
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name design_1

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_msg_id "BD_TCL-001" "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_msg_id "BD_TCL-002" "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_msg_id "BD_TCL-004" "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_msg_id "BD_TCL-005" "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_msg_id "BD_TCL-114" "ERROR" $errMsg}
   return $nRet
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_msg_id "BD_TCL-100" "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_msg_id "BD_TCL-101" "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports

  # Create ports
  set clk [ create_bd_port -dir I clk ]
  set m_axis_data_tvalid [ create_bd_port -dir O m_axis_data_tvalid ]
  set s_axis_data_tready [ create_bd_port -dir O s_axis_data_tready ]
  set s_axis_data_tvalid [ create_bd_port -dir I s_axis_data_tvalid ]
  set signal1 [ create_bd_port -dir I -from 23 -to 0 signal1 ]
  set signal2 [ create_bd_port -dir O -from 23 -to 0 signal2 ]

  # Create instance: fir_compiler_0, and set properties
  set fir_compiler_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 fir_compiler_0 ]
  set_property -dict [ list \
   CONFIG.BestPrecision {true} \
   CONFIG.Clock_Frequency {300.0} \
   CONFIG.CoefficientVector {0.000612974239942341,0,-0.00139927880755410,0,0.00289011036039714,0,-0.00530600611043049,0,0.00899517643394189,0,-0.0144020336153547,0,0.0221312072433480,0,-0.0330994168638488,0,0.0489140807287789,0,-0.0729290333901684,0,0.113859905464638,0,-0.203879380688593,0,0.633801416611840,1,0.633801416611840,0,-0.203879380688593,0,0.113859905464638,0,-0.0729290333901684,0,0.0489140807287789,0,-0.0330994168638488,0,0.0221312072433480,0,-0.0144020336153547,0,0.00899517643394189,0,-0.00530600611043049,0,0.00289011036039714,0,-0.00139927880755410,0,0.000612974239942341} \
   CONFIG.Coefficient_Fractional_Bits {22} \
   CONFIG.Coefficient_Sets {1} \
   CONFIG.Coefficient_Sign {Signed} \
   CONFIG.Coefficient_Structure {Inferred} \
   CONFIG.Coefficient_Width {24} \
   CONFIG.Data_Width {24} \
   CONFIG.Decimation_Rate {1} \
   CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
   CONFIG.Filter_Type {Interpolation} \
   CONFIG.Interpolation_Rate {2} \
   CONFIG.Number_Channels {1} \
   CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
   CONFIG.Output_Width {24} \
   CONFIG.Quantization {Quantize_Only} \
   CONFIG.RateSpecification {Frequency_Specification} \
   CONFIG.Sample_Frequency {0.001} \
   CONFIG.Zero_Pack_Factor {1} \
 ] $fir_compiler_0

  # Create port connections
  connect_bd_net -net clk_1 [get_bd_ports clk] [get_bd_pins fir_compiler_0/aclk]
  connect_bd_net -net fir_compiler_0_m_axis_data_tdata [get_bd_ports signal2] [get_bd_pins fir_compiler_0/m_axis_data_tdata]
  connect_bd_net -net fir_compiler_0_m_axis_data_tvalid [get_bd_ports m_axis_data_tvalid] [get_bd_pins fir_compiler_0/m_axis_data_tvalid]
  connect_bd_net -net fir_compiler_0_s_axis_data_tready [get_bd_ports s_axis_data_tready] [get_bd_pins fir_compiler_0/s_axis_data_tready]
  connect_bd_net -net s_axis_data_tvalid_1 [get_bd_ports s_axis_data_tvalid] [get_bd_pins fir_compiler_0/s_axis_data_tvalid]
  connect_bd_net -net signal1_1 [get_bd_ports signal1] [get_bd_pins fir_compiler_0/s_axis_data_tdata]

  # Create address segments


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


