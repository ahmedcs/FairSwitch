///////////////////////////////////////////////////////////////////////////////
// 
// Author: Ahmed M. Abdelmoniem <ahmedcs982@gmail.com>
// Date: 15 MAY 2016
// Module:main.v
// Project: FairQ AQM
// Description: Applies FairQ AQM to modify Receive window of ACKs.
//
///////////////////////////////////////////////////////////////////////////////
//`timescale 1ns/100ps
`timescale 1ns/1ps

module fairq_main #(
      parameter DATA_WIDTH = 64, 
      parameter CTRL_WIDTH          = 8,
      parameter NUM_OUTPUT_QUEUES   = 8,
      parameter SRAM_ADDR_WIDTH     = 19,   
      parameter NUM_OQ_WIDTH       = log2(NUM_OUTPUT_QUEUES),  
      parameter PKT_WORDS_WIDTH     = 8
   )
   (

    // --- Interface to the previous stage
     /*input  [DATA_WIDTH+CTRL_WIDTH-1:0] in_data_ctrl,
     output [DATA_WIDTH+CTRL_WIDTH-1:0] out_data_ctrl,
     output                              out_wr,*/
     input                              in_wr,
     input  [CTRL_WIDTH-1:0]		in_ctrl,
     input  [DATA_WIDTH-1:0]            in_data,
     output  [DATA_WIDTH-1:0]		out_data,

     /***********************Queue Occupany of src and dst queue*****************************/
      input [NUM_OQ_WIDTH-1:0]    	  dst_oq,
      input [NUM_OUTPUT_QUEUES-1:0]       dst_oq_full,
      input 			       	  dst_oq_avail,

      input 			       	  rd_dst_addr,
      input  [SRAM_ADDR_WIDTH-1:0] 	  dst_oq_high_addr,
      input  [SRAM_ADDR_WIDTH-1:0] 	  dst_oq_low_addr,
      input  [SRAM_ADDR_WIDTH-1:0] 	  dst_num_words_left,
      input  [SRAM_ADDR_WIDTH-1:0] 	  dst_full_thresh,

      input                                pkt_stored,
      input                                pkt_dropped,
      input [PKT_WORDS_WIDTH-1:0]          stored_pkt_total_word_length,

      input                                pkt_removed,
      input [PKT_WORDS_WIDTH-1:0]          removed_pkt_total_word_length,
      input [NUM_OQ_WIDTH-1:0]             removed_oq, 
  
      
      /********************Queue Occupany of src and dst queue**********************************/
    
     //output                          is_fairq,
     //output reg [31:0] 		     synack_count, fin_count;

    // --- Misc
    input                              reset,
    input                              clk
   );

   //---------------------Functions ------------------------------
      function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
      endfunction // log2
   
   //------------------ Internal Parameter ---------------------------
   parameter MIN_PKT             = 60/CTRL_WIDTH + 1;
   parameter MAX_NUM_PKTS_WIDTH = SRAM_ADDR_WIDTH-MIN_PKT; // SRAM_WIDTH - min pkt size
   parameter MAX_WORDS_WIDTH    = SRAM_ADDR_WIDTH;   // SRAM_WIDTH
   parameter NUM_MAC_OUTPUT_QUEUES    = NUM_OUTPUT_QUEUES/2;   // # of MAC Output queues
   parameter MAX_PKT             = 2048/CTRL_WIDTH;   // allow for 2K bytes
   parameter PKTS_IN_RAM_WIDTH   = log2((2**SRAM_ADDR_WIDTH)/MIN_PKT);
   parameter WORD_IN_BYTES 	 =  CTRL_WIDTH; //4; 
   parameter MAX_BYTES_WIDTH 	 =  MAX_WORDS_WIDTH + log2(WORD_IN_BYTES);
   
   localparam PKT_CLKS		 =  1000  ; //each 1000bytes packet requires 8 microsecond transmission
	
   localparam NUM_STATES 	 = 9;
   localparam CTRL_WORD		 = 1;
   localparam WORD_1		 = 2;
   localparam WORD_2		 = 4;
   localparam WORD_3             = 8;
   localparam WORD_4		= 16;
   localparam WORD_5	        = 32;
   localparam WORD_6            = 64;
   localparam WORD_7            = 128;
   localparam WAIT_EOP          = 256;
   
   localparam MINWINVAL	        = 2048;
   localparam MAX_WINDOW 	= 16'hFFFF; //new window of 10000 bytes
   localparam max_pkts_in_q 	= 16'hFFFF; //new window of 10000 bytes
   
   localparam IP                = 16'h0800;
   localparam TCP                = 8'h06;
   localparam HTTP               = 16'h0050;    // port 80
   localparam IPERF               = 16'h1389;    // port 5001
   //localparam WIN_TCP_HDR_LEN1    = 4'b0101;     // 5 * 32b = 20B
   //localparam WIN_TCP_HDR_LEN2   = 4'b1000;     // 8 * 32b = 32B
   //---------------------- Wires/Regs -------------------------------
   reg [NUM_STATES-1:0]                   state, state_next;
   
   reg                                   update_window;
   reg [31:0] 		     		 rtt_timer;  
   wire [31:0] 		     		 synack_count [NUM_OUTPUT_QUEUES-1:0];
   reg [31:0]				 fin_count [NUM_OUTPUT_QUEUES-1:0];
   reg [31:0]				 synack_src  [NUM_OUTPUT_QUEUES-1:0], synack_dst  [NUM_OUTPUT_QUEUES-1:0] ;

   reg [15:0]  				local_window [NUM_OUTPUT_QUEUES-1:0], local_window_incr[NUM_OUTPUT_QUEUES-1:0];
   wire [15:0]				 div_wire, rem_wire, flow_num; 
  
   //wire [MAX_BYTES_WIDTH-NUM_OQ_WIDTH-1:0]  local_window;
   wire 		                 tcp_syn, tcp_fin, tcp_ack, tcp_rst, single_out, valid_synack;
   wire [15:0]                           ether_type;
   wire [3:0]                            tcp_hdr_len;
   wire [7:0]                            ip_proto;
   wire [15:0]                           ip_len;
   wire [15:0]                           tcp_dst_port;
   wire [15:0]                           tcp_src_port;
   wire [15:0] 				 checksum,  window;
   wire [15:0]				 new_checksum , window_diff, sum;
   wire [15:0]    			 new_window;
   wire [MAX_WORDS_WIDTH-NUM_OQ_WIDTH-1:0]    	max_buff_ratio;

   reg [NUM_OQ_WIDTH-1:0]    	 	dst_port;
   reg 					enable_divide_count;
   reg [5:0] 				divide_count, incr_counter;
   reg [NUM_OUTPUT_QUEUES-1:0]    	dst_ports;//, src_port_next;
   reg [NUM_OQ_WIDTH-1:0]    	 	src_port;//, src_port_next;
   reg [NUM_OQ_WIDTH-1:0]    	 	src_port_old;
   reg [MAX_NUM_PKTS_WIDTH-1:0] 	num_pkts  [NUM_OUTPUT_QUEUES-1:0];
   reg [MAX_WORDS_WIDTH-1:0]    	num_words [NUM_OUTPUT_QUEUES-1:0];
   reg [SRAM_ADDR_WIDTH-1:0]   		num_words_left [NUM_OUTPUT_QUEUES-1:0];
   reg [MAX_WORDS_WIDTH-NUM_OQ_WIDTH-1:0]    	num_max_words [NUM_OUTPUT_QUEUES-1:0]; 

   //reg [SRAM_ADDR_WIDTH-1:0]    	words_full_thresh [NUM_OUTPUT_QUEUES-1:0];


   integer 				 i;

   //------------------------intial----------------------------------
 
   //------------------------ Logic ----------------------------------

   //----------------Assign Wires--------------

   assign valid_synack =  ( synack_count[src_port] - fin_count[src_port]  > 0 );   
   assign flow_num = valid_synack ? synack_count[src_port] - fin_count[src_port] : 1;
	
   assign new_window =  (((local_window[src_port] + local_window_incr[src_port]) * WORD_IN_BYTES) > MAX_WINDOW) ? MAX_WINDOW : ((local_window[src_port] + local_window_incr[src_port]) * WORD_IN_BYTES);

   assign out_data = (new_window>0 && new_window<MAX_WINDOW+1  && update_window) ? {new_window, new_checksum, in_data[31:0]} : in_data;

   //assign  dst_oq =  (state_next == WORD_2 && dst_oq_avail) ? in_dst_oq : 4'b1111;

   assign   ether_type = in_data[31:16];

   assign   ip_proto = in_data[7:0];
   assign   ip_len = in_data[63:48];
   
   assign  tcp_dst_port = in_data[31:16];
   assign  tcp_src_port = in_data[47:32];

   assign  tcp_hdr_len = in_data[15:12];
   assign  tcp_syn = in_data[1];
   assign  tcp_rst = in_data[2];
   assign  tcp_ack = in_data[4];
   assign  tcp_fin = in_data[0];

   assign  window = in_data[63:48];
   assign  checksum = in_data[47:32];

   assign single_out = (dst_ports > 0 && (dst_ports & dst_ports-1) == 0) ? 1 : 0;

   assign synack_count[0] = synack_src[0] + synack_dst[0];
   assign synack_count[1] = synack_src[1] + synack_dst[1];
   assign synack_count[2] = synack_src[2] + synack_dst[2];
   assign synack_count[3] = synack_src[3] + synack_dst[3];
   assign synack_count[4] = synack_src[4] + synack_dst[4];
   assign synack_count[5] = synack_src[5] + synack_dst[5];
   assign synack_count[6] = synack_src[6] + synack_dst[6];
   assign synack_count[7] = synack_src[7] + synack_dst[7];

   assign max_buff_ratio = num_max_words[src_port]>>2;   

   //----------------State Mschine--------------  

   always@(*) begin
      state_next = state;

      case(state)
        /* read the input source header and get the first word */
	CTRL_WORD: begin
	  if(in_wr && in_ctrl==`IO_QUEUE_STAGE_NUM) begin
//                src_port = in_data[`IOQ_SRC_PORT_POS + NUM_OQ_WIDTH  - 1 : `IOQ_SRC_PORT_POS];
//		dst_port = in_data[`IOQ_DST_PORT_POS + NUM_OUTPUT_QUEUES - 1:`IOQ_DST_PORT_POS];
		update_window = 0;               
		state_next = WORD_1;
            end
	end // case: READ_CTRL_WORD

        WORD_1: begin
           if(in_wr && in_ctrl==0) begin
              //dst_mac_next          = in_data[63:16] ;
              //src_mac_next[47:32]   = in_data[15:0];
	      update_window = 0;
	      state_next = WORD_2;	             	  
	    end    	
	    /*else begin
 		update_window = 0;
		state_next  = WAIT_EOP;
	    end*/
        end // case: READ_WORD_1
	
	WORD_2: begin
           if(in_wr) begin
             // src_mac_next [31:0]   = in_data[63:32];
	      update_window = 0;
	      if(ether_type  == IP) begin
		     state_next  = WORD_3;
	      end
	      else
		     state_next  = WAIT_EOP;
           end
        end

        WORD_3: begin
	   if(in_wr) begin
	      update_window = 0;
              if (ip_proto == TCP) begin         
		  state_next = WORD_4;
              end
              else 
		 state_next = WAIT_EOP;           	
            end
         end

         WORD_4: begin
            if (in_wr) begin
	       update_window = 0;
               state_next = WORD_5;
            end
         end

         WORD_5: begin
            if (in_wr) begin
		update_window = 0;
               if (tcp_dst_port == HTTP || tcp_dst_port == IPERF || tcp_src_port == HTTP || tcp_src_port == IPERF) begin
                  state_next = WORD_6;
               end
               else begin
                  state_next = WAIT_EOP;
               end
            end
         end

         WORD_6: begin		
            if (in_wr) begin
		update_window = 0;
               if (!tcp_syn && !tcp_fin && !tcp_rst && tcp_ack) begin   
		  state_next = WORD_7;
               end	       
               else begin
                  state_next = WAIT_EOP;
               end
            end
         end

         WORD_7: begin
            if (in_wr) begin
		  update_window = 1;
                  state_next = WAIT_EOP;	
            end
         end

	WAIT_EOP: begin
           if(in_wr) begin
	      update_window = 0;
	      if(in_ctrl!=0)
	              state_next  = CTRL_WORD;
           end
        end


      endcase // case(state)
   end // always@ (*)

//----------------Register manipulation and keeping value-------------------
  always @(posedge clk) begin
	if (reset) 		
	 	for(i = 0 ; i < 8 ; i = i+1) 
			local_window_incr[i] <= 0;
	else begin
		if(incr_counter == PKT_CLKS) begin // every to 1000byte PKT clock cycle update the increment 
		    for(i = 0 ; i < 8 ; i = i+1) begin
			if (synack_count[i] - fin_count[i]  > 0) begin 
				if( num_words[i] > 10 && num_words[i] < (num_max_words[i]>>2) - 10 && local_window_incr[i] < num_max_words[i] )
					local_window_incr[i] <= local_window_incr[i] + 1;
				else if (num_words[i] > 10 && num_words[i] > (num_max_words[i]>>2) + 10 && local_window_incr[i] > 0)
					local_window_incr[i] <= local_window_incr[i] - 1;
			end else
				local_window_incr[i] <= 0;
		    end	
		end		
	end
  end


  always @(posedge clk) begin
	if (state == WORD_5) begin
		src_port_old <= src_port;
		enable_divide_count <= 0;
	end else if (state == WORD_6)
		enable_divide_count <= 1;
	else if (divide_count == 19) begin
		enable_divide_count <= 0;
	end
  end


  always @(posedge clk) begin
	if ((state == WORD_5) || (divide_count == 19)) begin
		divide_count <= 0;
	end else if (enable_divide_count)
		divide_count <= divide_count + 1;
  end


  always @(posedge clk) begin
	if(reset) 
	 	for(i = 0 ; i < 8 ; i = i+1)             
			local_window[i]     <= 0;
	if (divide_count == 18) begin
		if(div_wire > MAX_PKT) //0)
			local_window [src_port_old] <= div_wire;
		else
			local_window [src_port_old] <= MAX_PKT; //0;
	end
		
  end

   always @(posedge clk) begin //, reset, dst_oq, dst_oq_high_addr,  dst_oq_low_addr, rd_dst_addr, pkt_stored, dst_full_thresh) begin 
   if(reset) begin
	for (i = 0 ; i < 8 ; i = i+1) begin: init_maxthresh
		num_max_words[i] = 0;
		//words_full_thresh[i]  = 0;
	end
   end else begin
       if(num_max_words[dst_oq] != (dst_oq_high_addr -  dst_oq_low_addr) && rd_dst_addr) begin
	//if(num_max_words[dst_oq] == 0 && rd_dst_addr) begin  
	 num_max_words[dst_oq] = dst_oq_high_addr -  dst_oq_low_addr;
	 $display("%t DST Queue: %d MAX: %x", $time, dst_oq, num_max_words[dst_oq]);
        end
	
      //thresh_ready <= pkt_stored;
      /*if(words_full_thresh[dst_oq] != dst_full_thresh && pkt_stored) begin
       //if(words_full_thresh[dst_oq] == 0 && pkt_stored) begin
	 words_full_thresh[dst_oq]  = dst_full_thresh; 
	 $display("%t DST Queue: %d THRESH: %x", $time, dst_oq,  words_full_thresh[dst_oq]);
      end*/
    end

   if((state == CTRL_WORD) && in_wr && (in_ctrl==`IO_QUEUE_STAGE_NUM) ) begin	
                src_port <= in_data[`IOQ_SRC_PORT_POS + NUM_OQ_WIDTH  - 1 : `IOQ_SRC_PORT_POS];
		dst_ports <= in_data[`IOQ_DST_PORT_POS + NUM_OUTPUT_QUEUES - 1:`IOQ_DST_PORT_POS];
   end

   

  end

   always @(posedge clk) begin

	if(update_window)
		  $display("%t UPDATE this word, old_word %x new_word %x, old_window %d new_window %d, old_checksum %x, new_checksum %x src:%u dst:%u SYN:%d FIN:%d MAX:%d flow:%d localwnd:%d", $time, in_data, out_data, window, new_window, checksum, new_checksum, src_port, dst_port , synack_count[src_port], fin_count[src_port], num_max_words[src_port], flow_num, local_window[src_port]);
    

      if(reset) begin
         state 			     <= CTRL_WORD;
	 rtt_timer		     <= 0;
	 incr_counter 		     <= 0;
	 for(i = 0 ; i < 8 ; i = i+1) begin: initial_regs             
	        //synack_count[i]       <= 0;
		synack_src[i]           <= 0;
		synack_dst[i]           <= 0;
                fin_count[i] 	    	<= 0;
		num_pkts[i]     	<= 0;
		num_words[i]   	   	<= 0;
	 end
       end else begin
        state 			   <= state_next;
	rtt_timer		   <= rtt_timer + 1;
	

	if(incr_counter == PKT_CLKS)
		incr_counter 	   <= 0;
	else
		incr_counter 		   <= incr_counter + 1;

        if (tcp_fin && single_out && state == WORD_6) begin
		   fin_count[dst_port] <= fin_count[dst_port] + 1;
		    $display("%t FIN packet %x at queue %u total %x", $time, in_data, dst_port, fin_count[dst_port]);
	end


	if (tcp_syn && tcp_ack && single_out && state == WORD_6) begin
		   //synack_count[dst_port] <= synack_count[dst_port] + 1;
		   //synack_count[src_port] <= synack_count[src_port] + 1;
		   synack_src[src_port] <= synack_src[src_port] + 1;
		   synack_dst[dst_port] <= synack_dst[dst_port] + 1;
		    $display("%t SYN ACK packet %x at src:%u dst:%u SYN src:%u dst:%u", $time, in_data, src_port, dst_port, synack_count[src_port], synack_count[dst_port]);		
	end

	/*if (tcp_rst && single_out && state == WORD_6) begin
		   fin_count[dst_port] <= fin_count[dst_port] + 1;
		   fin_count[src_port] <= fin_count[src_port] + 1;
		    $display("%t RST packet %x at src:%u dst:%u SYN src:%u dst:%u", $time, in_data, src_port, dst_port, synack_count_next[src_port], synack_count_next[dst_port]);
		
	end*/

	 if(dst_oq==removed_oq && pkt_stored && pkt_removed) begin
            num_words[dst_oq] <= num_words[dst_oq] +  stored_pkt_total_word_length - removed_pkt_total_word_length;
         end
	 else begin
		  if(pkt_stored) begin
		       num_pkts[dst_oq]  <= num_pkts[dst_oq] + 1'b1;
		       num_words[dst_oq] <= num_words[dst_oq] + stored_pkt_total_word_length;
		       num_words_left[dst_oq]  <= dst_num_words_left;	    	   
      			// synthesis translate_off
	  		$display("%t FairQ: q:%u ADDED  p:%x qp:%x qw:%x qmax:%x left:%x localwnd:%d ", $time, dst_oq, stored_pkt_total_word_length, num_pkts[dst_oq], num_words[dst_oq], num_max_words[dst_oq], num_words_left[dst_oq], local_window[dst_oq] );
     			 // synthesis translate_on
		    end

		  if(pkt_removed) begin
		       num_pkts[removed_oq]  <= num_pkts[removed_oq] - 1'b1;
		       num_words[removed_oq] <= num_words[removed_oq] - removed_pkt_total_word_length;		   
		       // synthesis translate_off
		       $display("%t FairQ: q:%u REMOVED  p:%x qp:%x qw:%x qmax:%x left:%x ", $time, removed_oq, removed_pkt_total_word_length, num_pkts[removed_oq], num_words[removed_oq], num_max_words[removed_oq], num_words_left[removed_oq], local_window[removed_oq] );
		       // synthesis translate_on
		  end
	 end
	
      end
   end


 //----------------------- Modules ---------------------------------
ones_complement_add ones_complement_add_inst1 (
	.a(~window),
	.b(new_window),
	.result(window_diff)
);

ones_complement_add ones_complement_add_inst2 (
	.a(window_diff),
	.b(~checksum),
	.result(sum)
);

assign new_checksum = ~sum;

div_gen_v2_0 div_gen_v2_0_inst1 (
	.clk(clk),
	.dividend(max_buff_ratio),
	.divisor(flow_num),
	.quotient(div_wire),
	.fractional(rem_wire)
);

 //----------------------- Modules ---------------------------------
/*
    * get the binary form of the destination port
    */

   always @(*) begin
      dst_port = 'h0;
      case(dst_ports)
        'h0:    dst_port   = 'h0;
        'h1:    dst_port   = 'h0;
        'h2:    dst_port   = 'h1;
        'h4:    dst_port   = 'h2;
        'h8:    dst_port   = 'h3;
        'h10:   dst_port   = 'h4;
        'h20:   dst_port   = 'h5;
        'h40:   dst_port   = 'h6;
        'h80:   dst_port   = 'h7;
        'h100:  dst_port   = 'h8;
        'h200:  dst_port   = 'h9;
        'h400:  dst_port   = 'ha;
        'h800:  dst_port   = 'hb;
        'h1000: dst_port   = 'hc;
        'h2000: dst_port   = 'hd;
        'h4000: dst_port   = 'he;
        'h8000: dst_port   = 'hf;
      endcase // case(in_data[NUM_OQ_WIDTH-1:0])
   end

   /*always @(*) begin
      local_window = 'h0;
      case(flow_num)
        'h0:    local_window   = 'hFFFF;
        'h1:    local_window   = 'hFFFF;
        'h2:    local_window   = 'h7FFF;
        'h3:    local_window   = 'h5555;
        'h4:    local_window   = 'h3FFF;
        'h5:    local_window   = 'h3333;
        'h6:    local_window   = 'h2AAA;
        'h7:    local_window   = 'h2492;
        'h8:    local_window   = 'h1FFF;
        'h9:    local_window   = 'h1C71;
        'hA:   local_window   = 'h1999;
        'hB:   local_window   = 'h1745;
        'hC:   local_window   = 'h1555;
        'hD:   local_window   = 'h13B1;
        'hE:   local_window   = 'h1249;
        'hF:   local_window   = 'h1111;
      endcase // case(in_data[NUM_OQ_WIDTH-1:0])

      if (flow_num >= 16 && flow_num  < 32)
	local_window = 'h0AAA;
      if (flow_num  >= 32 && flow_num  < 64)
	local_window = 'h0555;
      if (flow_num  >= 64 && flow_num  < 128)
	local_window = 'h02AA;
       if (flow_num  >= 128 && flow_num  < 256)
	local_window = 'h0155;
   end*/


endmodule // rwndq_main

