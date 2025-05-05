--+----------------------------------------------------------------------------
--|
--| NAMING CONVENSIONS :
--|
--|    xb_<port name>           = off-chip bidirectional port ( _pads file )
--|    xi_<port name>           = off-chip input port         ( _pads file )
--|    xo_<port name>           = off-chip output port        ( _pads file )
--|    b_<port name>            = on-chip bidirectional port
--|    i_<port name>            = on-chip input port
--|    o_<port name>            = on-chip output port
--|    c_<signal name>          = combinatorial signal
--|    f_<signal name>          = synchronous signal
--|    ff_<signal name>         = pipeline stage (ff_, fff_, etc.)
--|    <signal name>_n          = active low signal
--|    w_<signal name>          = top level wiring signal
--|    g_<generic name>         = generic
--|    k_<constant name>        = constant
--|    v_<variable name>        = variable
--|    sm_<state machine type>  = state machine type definition
--|    s_<signal name>          = state name
--|
--+----------------------------------------------------------------------------
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;


entity top_basys3 is
    port(
        -- inputs
        clk     :   in std_logic; -- native 100MHz FPGA clock
        sw      :   in std_logic_vector(7 downto 0); -- operands and opcode
        btnU    :   in std_logic; -- reset
        btnC    :   in std_logic; -- fsm cycle
        btnL    :   in std_logic;
        
        -- outputs
        led :   out std_logic_vector(15 downto 0);
        -- 7-segment display segments (active-low cathodes)
        seg :   out std_logic_vector(6 downto 0);
        -- 7-segment display active-low enables (anodes)
        an  :   out std_logic_vector(3 downto 0)
    );
end top_basys3;

architecture top_basys3_arch of top_basys3 is 
  
	-- declare components and signals
component  controller_fsm is
    Port ( i_reset : in STD_LOGIC;
           i_adv : in STD_LOGIC;
           o_cycle : out STD_LOGIC_VECTOR (3 downto 0));
end component controller_fsm;

component  sevenseg_decoder is
    Port ( i_hex : in STD_LOGIC_VECTOR (3 downto 0);
           o_seg_n : out STD_LOGIC_VECTOR (6 downto 0));
end component  sevenseg_decoder;

component TDM4 is
	generic ( constant k_WIDTH : natural  := 4); -- bits in input and output
    Port ( i_clk		: in  STD_LOGIC;
           i_reset		: in  STD_LOGIC; -- asynchronous
           i_D3 		: in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
		   i_D2 		: in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
		   i_D1 		: in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
		   i_D0 		: in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
		   o_data		: out STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
		   o_sel		: out STD_LOGIC_VECTOR (3 downto 0)	-- selected data line (one-cold)
	);
end component TDM4;

component twos_comp is
    port (
        i_bin: in std_logic_vector(7 downto 0);
        o_sign: out std_logic;
        o_hund: out std_logic_vector(3 downto 0);
        o_tens: out std_logic_vector(3 downto 0);
        o_ones: out std_logic_vector(3 downto 0)
    );
end component twos_comp;

component  ALU is
    Port ( i_A : in STD_LOGIC_VECTOR (7 downto 0);
           i_B : in STD_LOGIC_VECTOR (7 downto 0);
           i_op : in STD_LOGIC_VECTOR (2 downto 0);
           o_result : out STD_LOGIC_VECTOR (7 downto 0);
           o_flags : out STD_LOGIC_VECTOR (3 downto 0));
end component  ALU;

component  clock_divider is
	generic ( constant k_DIV : natural := 200000	); -- How many clk cycles until slow clock toggles
											   -- Effectively, you divide the clk double this 
											   -- number (e.g., k_DIV := 2 --> clock divider of 4)
	port ( 	i_clk    : in std_logic;
			i_reset  : in std_logic;		   -- asynchronous
			o_clk    : out std_logic		   -- divided (slow) clock
	);
end component  clock_divider;
  
  signal w_cycle: std_logic_vector (3 downto 0);
  signal displayMux: std_logic_vector (7 downto 0);
  signal twosSign: std_logic;
  signal twosHund: std_logic_vector (3 downto 0);
  signal twosTens: std_logic_vector (3 downto 0);
  signal twosOnes: std_logic_vector (3 downto 0);
  signal clkTDM: std_logic;
  signal dataTDM: std_logic_vector (3 downto 0);
  signal selTDM: std_logic_vector (3 downto 0);
  signal decoderSeg: std_logic_vector (6 downto 0);
  signal reg1: std_logic_vector (7 downto 0);
  signal reg2: std_logic_vector (7 downto 0);
  signal resultALU: std_logic_vector  (7 downto 0);
  signal flags: std_logic_vector  (3 downto 0);
  signal negSign: std_logic_vector (6 downto 0);
  signal Ain: std_logic_vector (7 downto 0);
  signal Bin: std_logic_vector (7 downto 0);
  signal OpIn: std_logic_vector (2 downto 0);

begin
	-- PORT MAPS ----------------------------------------
    FSM : controller_fsm
        port map (
        i_reset => btnU,
        i_adv => btnC,
        o_cycle => w_cycle
        );
   twos : twos_comp
        port map (
        i_bin => displayMux,
        o_sign => twosSign,
        o_hund => twosHund,
        o_tens => twosTens,
        o_ones => twosOnes
        );
      
    TDMCLOCK : clock_divider
        port map (
        i_clk => clk,
        i_reset => btnL,
        o_clk => clkTDM
        );
    TDM : TDM4
        port map (
        i_clk => clkTDM,
        i_reset => btnU,
        i_D3 => "0000",
        i_D2 => twosHund,
        i_D1 => twosTens,
        i_D0 => twosOnes,
        o_data => dataTDM,
        o_sel => selTDM
        );
        
    finalSeg: sevenseg_decoder
        port map ( 
        i_hex => dataTDM,
        o_seg_n => decoderSeg
        );
    register1 : process(w_cycle(0))
	begin
		if rising_edge (w_cycle(0))then
			reg1 <= Ain;
		else 
		    reg1 <= reg1;
		end if;
	end process register1;
	
	register2 : process(w_cycle(1))
	begin
		if rising_edge (w_cycle(1)) then
			reg2 <= Bin;
		else 
		    reg2 <= reg2;
		end if;
	end process register2;
	
	operator: ALU 
	    port map (
	    i_A => reg1,
        i_B => reg2,
        i_op => OpIn,
        o_result => resultALU,
        o_flags => flags
	    );
	
	-- CONCURRENT STATEMENTS ----------------------------
	--Set input wires
	Ain <= sw(7 downto 0);
	Bin <= sw( 7 downto 0);
	OpIn <= sw( 2 downto 0);
	
	--display mux
	displayMux <= reg1 when w_cycle = "0001" else
	              reg2 when w_cycle = "0010" else
	              resultALU when w_cycle = "0100" else
	              resultALU;
	--Drive anodes off when on clear state           
	an <= "1111" when w_cycle = "1000" else
	      selTDM;
	      
    --Negative sign logic
	negSign(6) <= not twosSign;
	negSign(5 downto 0) <= "111111";
--    negSign <= "0111111";
	
	--Seg mux
	seg <= negSign when selTDM = "0111" else
	       decoderSeg;
	       
	--LED flags
    led (15 downto 12) <= flags;
    
    --LED FSM
    led(3 downto 0) <= w_cycle;
    
	--ground rest of leds
	led(11 downto 4) <= "00000000";
end top_basys3_arch;
