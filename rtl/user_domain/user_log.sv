//################ Corrected Log function with reduced latency ##############
//Valid range:000100 - FFFFFF
//Address mapping:
// 0x4 (addr[3:2] == 2'd1): Single input mode (existing behavior)
// 0x8 (addr[3:2] == 2'd2): Pipelined input (write only)
// 0xC (addr[3:2] == 2'd3): Pipelined output (read only)
//###########################################################################

module user_log #( 
  /// The OBI configuration for all ports.
  parameter obi_pkg::obi_cfg_t           ObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The request struct.
  parameter type                         obi_req_t   = logic,
  /// The response struct.
  parameter type                         obi_rsp_t   = logic,
  /// Pipeline depth for results buffer
  parameter int unsigned                 PIPELINE_DEPTH = 8
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
  logic [ObiCfg.DataWidth-1:0] wdata_d, wdata_q;

  // Signals used to create the response
  logic [ObiCfg.DataWidth-1:0] rsp_data; // Data field of the obi response
  logic rsp_err; // Error field of the obi response
  logic [ObiCfg.DataWidth-1:0] result_d, result_q; // Single mode result

  // Wire the registers holding the request
  assign req_d = obi_req_i.req;
  assign id_d = obi_req_i.a.aid;
  assign we_d = obi_req_i.a.we;
  assign addr_d = obi_req_i.a.addr;
  assign wdata_d = obi_req_i.a.wdata;

  //control logic 
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      req_q <= '0;
      id_q <= '0;
      we_q <= '0;
      addr_q <= '0;
      wdata_q <= 0;
    end else begin
      req_q <= req_d;
      id_q <= id_d;
      we_q <= we_d;
      addr_q <= addr_d;
      wdata_q <= wdata_d;
    end
  end
  
  // LOG COMPUTATION - Fixed and optimized for 3-cycle pipeline
  logic [23:0] DIN;
  logic [11:0] DOUT;

  // Pipeline registers
  logic [3:0] priencout1_d, priencout1_q;
  logic [3:0] priencout2_d, priencout2_q;
  logic [3:0] priencout3_d, priencout3_q;
  logic [5:0] barrelout_d, barrelout_q;
  logic [20:0] barrelin_d, barrelin_q;
  logic [7:0] LUTout_d, LUTout_q;
  logic [20:0] barrel_shifted;

  // Control signals
  logic output_valid_d, output_valid_q;
  logic [1:0] pipeline_stage_d, pipeline_stage_q; // 0=idle, 1=stage1, 2=stage2, 3=stage3
  
  // NEW: Pipelined mode control
  logic pipelined_mode_d, pipelined_mode_q; // 0=single mode, 1=pipelined mode
  logic pipeline_active_d, pipeline_active_q; // Pipeline is running

  // NEW: Results buffer for pipelined mode
  logic [11:0] result_buffer [PIPELINE_DEPTH-1:0];
  logic [$clog2(PIPELINE_DEPTH)-1:0] write_ptr_d, write_ptr_q;
  logic [$clog2(PIPELINE_DEPTH)-1:0] read_ptr_d, read_ptr_q;
  logic [$clog2(PIPELINE_DEPTH):0] buffer_count_d, buffer_count_q; // +1 bit for full detection
  logic buffer_full, buffer_empty;
  logic buffer_write_en, buffer_read_en;

  assign buffer_full = (buffer_count_q == PIPELINE_DEPTH);
  assign buffer_empty = (buffer_count_q == 0);
  assign DIN = wdata_q[23:0]; 
  assign DOUT = {priencout3_q, LUTout_q};
  assign barrel_shifted = (barrelin_q << (4'd15 - priencout1_q));

  // Buffer management - FIXED
  always_comb begin
    write_ptr_d = write_ptr_q;
    read_ptr_d = read_ptr_q;
    buffer_count_d = buffer_count_q;
    buffer_write_en = 1'b0;
    buffer_read_en = 1'b0;

    // Read from buffer when pipelined output is read
    // Add to the buffer read logic
    if (req_q && !we_q && (addr_q[3:2] == 2'd3)) begin
      //$display("LOG_DEBUG: Read attempt - empty=%d, count=%d, read_ptr=%d", 
              //buffer_empty, buffer_count_q, read_ptr_q);
      if (!buffer_empty) begin
        buffer_read_en = 1'b1;
        read_ptr_d = (read_ptr_q + 1) % PIPELINE_DEPTH;
        buffer_count_d = buffer_count_q - 1;
        //$display("LOG_DEBUG: Reading from buffer[%d] = 0x%h, new_count=%d", 
                //read_ptr_q, result_buffer[read_ptr_q], buffer_count_q - 1);
      end else begin
        //$display("LOG_DEBUG: Buffer read failed - buffer empty!");
      end
    end
  end

  // Buffer write - triggered every time we reach stage 3 in pipelined mode
  logic write_to_buffer;
  assign write_to_buffer = pipelined_mode_q && (pipeline_stage_q == 2'd3) && !buffer_full;

  // Buffer write and pointer management
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      write_ptr_q <= '0;
      read_ptr_q <= '0;
      buffer_count_q <= '0;
      for (int i = 0; i < PIPELINE_DEPTH; i++) begin
        result_buffer[i] <= '0;
      end
    end else begin
      // Handle read pointer and count updates
      read_ptr_q <= read_ptr_d;
      
      // Write to buffer every time we're in stage 3 (new output ready)
      if (write_to_buffer) begin
        result_buffer[write_ptr_q] <= DOUT;
        write_ptr_q <= (write_ptr_q + 1) % PIPELINE_DEPTH;
        buffer_count_q <= buffer_count_q + 1;
        //$display("write to buffer with index: %d", buffer_count_q);
        //$display("LOG_DEBUG: Buffer write, ptr=%d, data=0x%h, count=%d", 
                //write_ptr_q, DOUT, buffer_count_q + 1);
      end else begin
        write_ptr_q <= write_ptr_d;
        buffer_count_q <= buffer_count_d;
      end
    end
  end

 // Check for new write requests
  logic new_single_request;
  assign new_single_request = req_q && we_q && (addr_q[3:2] == 2'd1);
  logic new_pipelined_request;
  assign new_pipelined_request = req_q && we_q && (addr_q[3:2] == 2'd2);

  // Enhanced pipeline control logic with separate pipelined addresses
  always_comb begin
    // Default values
    barrelin_d = barrelin_q;
    priencout1_d = priencout1_q;
    priencout2_d = priencout2_q;
    priencout3_d = priencout3_q;
    barrelout_d = barrelout_q;
    LUTout_d = LUTout_q;
    pipeline_stage_d = pipeline_stage_q;
    output_valid_d = output_valid_q;
    pipelined_mode_d = pipelined_mode_q;
    pipeline_active_d = pipeline_active_q;
    
    // Pipeline progression
    case (pipeline_stage_q)
      2'd0: begin
        // Idle - check for new request
        if (new_single_request || new_pipelined_request) begin
          
          barrelin_d = DIN[22:2];
          pipeline_stage_d = 2'd1;
          output_valid_d = 1'b0;
          // $display("DIN stage 0: %h", DIN);
          //$display("Currently at stage 0");
          // Set mode based on address
          if (new_single_request) begin
            pipelined_mode_d = 1'b0; // Single mode
            pipeline_active_d = 1'b1;
          end else if (new_pipelined_request) begin
            pipelined_mode_d = 1'b1; // Pipelined mode
            pipeline_active_d = 1'b1;
          end
          
          // Priority encoder (Stage 1 - combinational)
          casez (DIN[23:8])
            16'b1???????????????: priencout1_d = 4'd15;
            16'b01??????????????: priencout1_d = 4'd14;
            16'b001?????????????: priencout1_d = 4'd13;
            16'b0001????????????: priencout1_d = 4'd12;
            16'b00001???????????: priencout1_d = 4'd11;
            16'b000001??????????: priencout1_d = 4'd10;
            16'b0000001?????????: priencout1_d = 4'd9;
            16'b00000001????????: priencout1_d = 4'd8;
            16'b000000001???????: priencout1_d = 4'd7;
            16'b0000000001??????: priencout1_d = 4'd6;
            16'b00000000001?????: priencout1_d = 4'd5;
            16'b000000000001????: priencout1_d = 4'd4;
            16'b0000000000001???: priencout1_d = 4'd3;
            16'b00000000000001??: priencout1_d = 4'd2;
            16'b000000000000001?: priencout1_d = 4'd1;
            16'b0000000000000001: priencout1_d = 4'd0;
            default: priencout1_d = 4'd0;
          endcase
          
          //$display("LOG_DEBUG: start, Input=0x%h, Priority=%d, Mode=%s", 
                  //DIN, priencout1_d, pipelined_mode_d ? "PIPELINED" : "SINGLE");
        end
      end
      
      2'd1: begin
        // Stage 2: Barrel shifter
        priencout2_d = priencout1_q;
        barrelout_d = barrel_shifted[20:15];
        pipeline_stage_d = 2'd2;
      end
      
      2'd2: begin
        // Stage 3: LUT lookup
        //$display("Currently at stage 2, pipeline_mode: %d, new_request: %d", pipelined_mode_q, new_pipelined_request);
        priencout3_d = priencout2_q;
        pipeline_stage_d = 2'd3;
        
        case (barrelout_q)
          6'd0:  LUTout_d = 8'd0;
          6'd1:  LUTout_d = 8'd6;
          6'd2:  LUTout_d = 8'd11;
          6'd3:  LUTout_d = 8'd17;
          6'd4:  LUTout_d = 8'd22;
          6'd5:  LUTout_d = 8'd28;
          6'd6:  LUTout_d = 8'd33;
          6'd7:  LUTout_d = 8'd38;
          6'd8:  LUTout_d = 8'd44;
          6'd9:  LUTout_d = 8'd49;
          6'd10: LUTout_d = 8'd54;
          6'd11: LUTout_d = 8'd59;
          6'd12: LUTout_d = 8'd63;
          6'd13: LUTout_d = 8'd68;
          6'd14: LUTout_d = 8'd73;
          6'd15: LUTout_d = 8'd78;
          6'd16: LUTout_d = 8'd82;
          6'd17: LUTout_d = 8'd87;
          6'd18: LUTout_d = 8'd92;
          6'd19: LUTout_d = 8'd96;
          6'd20: LUTout_d = 8'd100;
          6'd21: LUTout_d = 8'd105;
          6'd22: LUTout_d = 8'd109;
          6'd23: LUTout_d = 8'd113;
          6'd24: LUTout_d = 8'd118;
          6'd25: LUTout_d = 8'd122;
          6'd26: LUTout_d = 8'd126;
          6'd27: LUTout_d = 8'd130;
          6'd28: LUTout_d = 8'd134;
          6'd29: LUTout_d = 8'd138;
          6'd30: LUTout_d = 8'd142;
          6'd31: LUTout_d = 8'd146;
          6'd32: LUTout_d = 8'd150;
          6'd33: LUTout_d = 8'd154;
          6'd34: LUTout_d = 8'd157;
          6'd35: LUTout_d = 8'd161;
          6'd36: LUTout_d = 8'd165;
          6'd37: LUTout_d = 8'd169;
          6'd38: LUTout_d = 8'd172;
          6'd39: LUTout_d = 8'd176;
          6'd40: LUTout_d = 8'd179;
          6'd41: LUTout_d = 8'd183;
          6'd42: LUTout_d = 8'd186;
          6'd43: LUTout_d = 8'd190;
          6'd44: LUTout_d = 8'd193;
          6'd45: LUTout_d = 8'd197;
          6'd46: LUTout_d = 8'd200;
          6'd47: LUTout_d = 8'd203;
          6'd48: LUTout_d = 8'd207;
          6'd49: LUTout_d = 8'd210;
          6'd50: LUTout_d = 8'd213;
          6'd51: LUTout_d = 8'd216;
          6'd52: LUTout_d = 8'd220;
          6'd53: LUTout_d = 8'd223;
          6'd54: LUTout_d = 8'd226;
          6'd55: LUTout_d = 8'd229;
          6'd56: LUTout_d = 8'd232;
          6'd57: LUTout_d = 8'd235;
          6'd58: LUTout_d = 8'd238;
          6'd59: LUTout_d = 8'd241;
          6'd60: LUTout_d = 8'd244;
          6'd61: LUTout_d = 8'd247;
          6'd62: LUTout_d = 8'd250;
          6'd63: LUTout_d = 8'd253;
          default: LUTout_d = 8'd0;
        endcase
      end
      
      2'd3: begin
        // Stage 4: Output ready
        //$display("Currently at stage 3, pipeline_mode: %d, new_request: %d", pipelined_mode_q, new_pipelined_request);
        output_valid_d = 1'b1;
        //$display("LOG_DEBUG: complete, Output=0x%h, Mode=%s", 
                //DOUT, pipelined_mode_q ? "PIPELINED" : "SINGLE");
        
        if (pipelined_mode_q) begin
          // In pipelined mode, continue to next stage
          if (new_pipelined_request) begin
            pipeline_stage_d = 2'd1; // Continue with new input
            // Start processing new input
            barrelin_d = DIN[22:2];
            //$display("DIN stage 3: %h", DIN);
            // Priority encoder for new input
            casez (DIN[23:8])
              16'b1???????????????: priencout1_d = 4'd15;
              16'b01??????????????: priencout1_d = 4'd14;
              16'b001?????????????: priencout1_d = 4'd13;
              16'b0001????????????: priencout1_d = 4'd12;
              16'b00001???????????: priencout1_d = 4'd11;
              16'b000001??????????: priencout1_d = 4'd10;
              16'b0000001?????????: priencout1_d = 4'd9;
              16'b00000001????????: priencout1_d = 4'd8;
              16'b000000001???????: priencout1_d = 4'd7;
              16'b0000000001??????: priencout1_d = 4'd6;
              16'b00000000001?????: priencout1_d = 4'd5;
              16'b000000000001????: priencout1_d = 4'd4;
              16'b0000000000001???: priencout1_d = 4'd3;
              16'b00000000000001??: priencout1_d = 4'd2;
              16'b000000000000001?: priencout1_d = 4'd1;
              16'b0000000000000001: priencout1_d = 4'd0;
              default: priencout1_d = 4'd0;
            endcase
          end else begin
            pipeline_stage_d = 2'd0; // Go to idle but stay in pipelined mode
          end
        end else begin
          // Single mode: go back to idle
          pipeline_stage_d = 2'd0;
          pipeline_active_d = 1'b0;
          pipelined_mode_d = 1'b0;
        end
      end
      
      default: begin
        pipeline_stage_d = 2'd0;
        output_valid_d = 1'b0;
        pipeline_active_d = 1'b0;
      end
    endcase
  end

  // Enhanced pipeline registers
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      priencout1_q <= 4'd0;
      priencout2_q <= 4'd0;
      priencout3_q <= 4'd0;
      barrelin_q <= 21'd0;
      barrelout_q <= 6'd0;
      LUTout_q <= 8'd0;
      pipeline_stage_q <= 2'd0;
      output_valid_q <= 1'b0;
      pipelined_mode_q <= 1'b0;
      pipeline_active_q <= 1'b0;
    end else begin
      priencout1_q <= priencout1_d;
      priencout2_q <= priencout2_d;
      priencout3_q <= priencout3_d;
      barrelin_q <= barrelin_d;
      barrelout_q <= barrelout_d;
      LUTout_q <= LUTout_d;
      pipeline_stage_q <= pipeline_stage_d;
      output_valid_q <= output_valid_d;
      pipelined_mode_q <= pipelined_mode_d;
      pipeline_active_q <= pipeline_active_d;
    end
  end

  // Result storage for single mode
  always_comb begin
    result_d = result_q;
    if (output_valid_q && !pipelined_mode_q) begin
      result_d = {20'b0, DOUT}; // Store computed 12-bit log (single mode only)
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin 
      result_q <= 32'd0;
    end else begin 
      result_q <= result_d;
    end 
  end 

  // Enhanced response generation with separate pipelined addresses
  always_comb begin 
    rsp_err = 1'b0;
    rsp_data = 32'd0;

    if (req_q) begin 
      if (we_q) begin 
        // Write operation - check for invalid input (zero)
        if ((wdata_q[23:0] == 24'd0)||(wdata_q[23:0]<24'h000100)||(wdata_q>24'hFFFFFF)) begin
          rsp_err = 1'b1;
        end else if (addr_q[3:2] == 2'd2) begin
          // Pipelined input - check if buffer is full
          if (buffer_full) begin
            rsp_err = 1'b1; // Buffer overflow
          end
        end
      end else begin 
        // Read operation
        case (addr_q[3:2])
          2'd1: begin // Single mode read
            if (pipeline_stage_q != 2'd0 && !pipelined_mode_q) begin
              rsp_err = 1'b1; // Computation in progress
            end else begin
              rsp_data = result_q;
            end
          end
          2'd3: begin // Pipelined output read
            if (buffer_empty) begin
              rsp_err = 1'b1; // No data available
            end else begin
              rsp_data = {20'b0, result_buffer[read_ptr_q]};
            end
          end
          default: begin
            rsp_err = 1'b1; // Invalid address
          end
        endcase
      end 
    end 
  end 

  // Wire the OBI response - unchanged
  assign obi_rsp_o.gnt = obi_req_i.req;
  assign obi_rsp_o.rvalid = req_q;
  assign obi_rsp_o.r.rdata = rsp_data;
  assign obi_rsp_o.r.rid = id_q; 
  assign obi_rsp_o.r.err = rsp_err;
  assign obi_rsp_o.r.r_optional = '0;

endmodule


