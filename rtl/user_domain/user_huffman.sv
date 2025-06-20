// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// gives us the `FF(...) macro making it easy to have properly defined flip-flops
`include "common_cells/registers.svh"

// simple ROM
module user_huffman #(
  /// The OBI configuration for all ports.
  parameter obi_pkg::obi_cfg_t           ObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The request struct.
  parameter type                         obi_req_t   = logic,
  /// The response struct.
  parameter type                         obi_rsp_t   = logic
) (
  /// Clock
  input  logic clk_i,
  /// Active-low reset
  input  logic rst_ni,

  /// OBI request interface
  input  obi_req_t obi_req_i,
  /// OBI response interface
  output obi_rsp_t obi_rsp_o
);

  // Define some registers to hold the requests fields
  logic req_d, req_q; // Request valid
  logic we_d, we_q; // Write enable
  logic [ObiCfg.AddrWidth-1:0] addr_d, addr_q; // Internal address of the word to read
  logic [ObiCfg.IdWidth-1:0] id_d, id_q; // Id of the request, must be same for the response

  // Signals used to create the response
  logic [ObiCfg.DataWidth-1:0] rsp_data; // Data field of the obi response
  logic rsp_err; // Error field of the obi response

  // Wire the registers holding the request
  // TODO 1 : Modify the code such that the ROM will respond after 2 cycles instead of 1
  assign req_d = obi_req_i.req;
  assign id_d = obi_req_i.a.aid;
  assign we_d = obi_req_i.a.we;
  assign addr_d = obi_req_i.a.addr;

  logic req_int, we_int;
  logic [ObiCfg.AddrWidth-1:0] addr_int;
  logic [ObiCfg.IdWidth-1:0] id_int;
  
  // Comprises 4 main blocks: priority encoder, barrel shifter, LUT, and adder.

    reg	[3:0]	priencout1;
    reg	[3:0]	priencout2;
    reg	[3:0]	priencout3;
    reg	[5:0]	barrelout;
    reg	[20:0]	barrelin;
    reg	[7:0]	LUTout;

    assign	DOUT	=	{priencout3, LUTout};	// Basic top-level connectivity

    always @(posedge clk) 					
    begin
        priencout2	<=	priencout1;
        priencout3	<=	priencout2;
        barrelin	<=	DIN[22:2];
    end


    wire [20:0] tmp1 =	(barrelin << ~priencout1);	// Barrel shifter - OMG, it's a primitive in Verilog!
    always @(posedge clk)
    begin
        barrelout	<=	tmp1[20:15];
    end


    wire	[15:0]	priencin = DIN[23:8];

    always @(posedge clk)						// Priority encoder

    casex (priencin)

        16'b1xxxxxxxxxxxxxxx:	priencout1	<=	15;
        16'b01xxxxxxxxxxxxxx:	priencout1	<=	14;
        16'b001xxxxxxxxxxxxx:	priencout1	<=	13;	
        16'b0001xxxxxxxxxxxx:	priencout1	<=	12;	
        16'b00001xxxxxxxxxxx:	priencout1	<=	11;	
        16'b000001xxxxxxxxxx:	priencout1	<=	10;	
        16'b0000001xxxxxxxxx:	priencout1	<=	9;	
        16'b00000001xxxxxxxx:	priencout1	<=	8;	
        16'b000000001xxxxxxx:	priencout1	<=	7;	
        16'b0000000001xxxxxx:	priencout1	<=	6;	
        16'b00000000001xxxxx:	priencout1	<=	5;	
        16'b000000000001xxxx:	priencout1	<=	4;	
        16'b0000000000001xxx:	priencout1	<=	3;	
        16'b00000000000001xx:	priencout1	<=	2;	
        16'b000000000000001x:	priencout1	<=	1;	
        16'b000000000000000x:	priencout1	<=	0;
        
    endcase



    /*
    LUT for log fraction lookup
    - can be done with array or case:

    case (addr)
    0:out=0;
    .
    31:out=15;
    endcase

        OR
        
    wire [3:0] lut [0:31];
    assign lut[0] = 0;
    .
    assign lut[31] = 15;

    Are there any better ways?
    */

    // Let's try "case".
    // The equation is: output = log2(1+input/64)*256
    // For larger tables, better to generate a separate data file using a program!

    always @(posedge clk)
    case (barrelout)

        0:	LUTout	<=	0;
        1:	LUTout	<=	6;
        2:	LUTout	<=	11;
        3:	LUTout	<=	17;
        4:	LUTout	<=	22;
        5:	LUTout	<=	28;
        6:	LUTout	<=	33;
        7:	LUTout	<=	38;
        8:	LUTout	<=	44;
        9:	LUTout	<=	49;
        10:	LUTout	<=	54;
        11:	LUTout	<=	59;
        12:	LUTout	<=	63;
        13:	LUTout	<=	68;
        14:	LUTout	<=	73;
        15:	LUTout	<=	78;
        16:	LUTout	<=	82;
        17:	LUTout	<=	87;
        18:	LUTout	<=	92;
        19:	LUTout	<=	96;
        20:	LUTout	<=	100;
        21:	LUTout	<=	105;
        22:	LUTout	<=	109;
        23:	LUTout	<=	113;
        24:	LUTout	<=	118;
        25:	LUTout	<=	122;
        26:	LUTout	<=	126;
        27:	LUTout	<=	130;
        28:	LUTout	<=	134;
        29:	LUTout	<=	138;
        30:	LUTout	<=	142;
        31:	LUTout	<=	146;
        32:	LUTout	<=	150;
        33:	LUTout	<=	154;
        34:	LUTout	<=	157;
        35:	LUTout	<=	161;
        36:	LUTout	<=	165;
        37:	LUTout	<=	169;
        38:	LUTout	<=	172;
        39:	LUTout	<=	176;
        40:	LUTout	<=	179;
        41:	LUTout	<=	183;
        42:	LUTout	<=	186;
        43:	LUTout	<=	190;
        44:	LUTout	<=	193;
        45:	LUTout	<=	197;
        46:	LUTout	<=	200;
        47:	LUTout	<=	203;
        48:	LUTout	<=	207;
        49:	LUTout	<=	210;
        50:	LUTout	<=	213;
        51:	LUTout	<=	216;
        52:	LUTout	<=	220;
        53:	LUTout	<=	223;
        54:	LUTout	<=	226;
        55:	LUTout	<=	229;
        56:	LUTout	<=	232;
        57:	LUTout	<=	235;
        58:	LUTout	<=	238;
        59:	LUTout	<=	241;
        60:	LUTout	<=	244;
        61:	LUTout	<=	247;
        62:	LUTout	<=	250;
        63:	LUTout	<=	253;

    endcase
  // Wire the response
  // A channel
  assign obi_rsp_o.gnt = obi_req_i.req;
  // R channel:
  assign obi_rsp_o.rvalid = req_q;
  assign obi_rsp_o.r.rdata = rsp_data;
  assign obi_rsp_o.r.rid = id_q;
  assign obi_rsp_o.r.err = rsp_err;
  assign obi_rsp_o.r.r_optional = '0;

endmodule
