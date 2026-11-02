 
 
module video_reset_bridge (
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 high_reset RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input wire i_reset,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 low_reset RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    output wire o_rstn
);
    assign o_rstn = !i_reset;
endmodule
