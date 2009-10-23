library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sc_pack.all;
use work.sc_arbiter_pack.all;
use work.tm_pack.all;
use work.tm_internal_pack.all;



entity tmif is

generic (
	addr_width		: integer;
	way_bits		: integer
);

port (
	clk					: in std_logic;
	reset				: in std_logic;
	
	--
	--	Commit logic
	--
	
	-- set until transaction finished/aborted
	commit_out_try			: out std_logic;
	commit_in_allow			: in std_logic;

	--
	--	Commit addresses
	--
	broadcast				: in tm_broadcast_type;

	--
	--	Memory IF to cpu
	--
	sc_out_cpu		: in sc_out_type;
	sc_in_cpu		: out sc_in_type;		

	--
	--	Memory IF to arbiter
	--
	sc_out_arb		: out sc_out_type;
	sc_in_arb		: in sc_in_type;

	--
	--	Rollback exception
	--
	exc_tm_rollback	: out std_logic
		
);

end tmif;

architecture rtl of tmif is

		
	signal state, next_state		: state_type;
		
	signal conflict					: std_logic;
	
	-- set asynchronously
	signal tm_cmd					: tm_cmd_type;
	

	signal commit_finished				: std_logic;
	
	signal commit_out_try_internal	: std_logic;
	
	-- filter signals to/from tm module
	
	signal sc_out_cpu_filtered		: sc_out_type;
	
	signal sc_in_cpu_filtered		: sc_in_type;
	signal sc_out_arb_filtered		: sc_out_type;



	signal is_tm_magic_addr_async: std_logic;
	signal is_tm_magic_addr_sync: std_logic;
	
	signal sc_out_cpu_dly: sc_out_type;
	 
	signal transaction_start: std_logic;
	
	
	signal tag_full: std_logic;
	
	-- commit_finished signal is delayed long enough so that other processors
	-- detect conflict before they can obtain commit token
	-- (after commit_finished_dly has caused reset of commit_out_try)		
	signal commit_finished_dly: std_logic;
	signal commit_finished_dly_internal_1: std_logic;
	
	signal rollback_busy: std_logic;
	signal next_rollback_busy: std_logic;
	signal tm_busy: std_logic;
begin

	is_tm_magic_addr_async <= '1' when
		sc_out_cpu.address(TM_MAGIC_DETECT'range) = TM_MAGIC_DETECT else '0';

	cmp_tm: entity work.tm(rtl)
	generic map (
		addr_width => addr_width,
		way_bits => way_bits
	)	
	port map (
		clk => clk,
		reset => reset,
		from_cpu => sc_out_cpu_filtered,
		to_cpu => sc_in_cpu_filtered,
		to_mem => sc_out_arb_filtered,
		from_mem => sc_in_arb,
		
		broadcast => broadcast,
		conflict => conflict,
		
		commit_finished => commit_finished,
		
		tag_full => tag_full,
		
		state => state,
		transaction_start => transaction_start
		);
		
	
	--
	-- TM STATE MACHINE
	--

	sync: process(reset, clk) is
	begin
		if reset = '1' then
			state <= no_transaction;
			
			is_tm_magic_addr_sync <= '0';
			sc_out_cpu_dly <= sc_out_idle;
			
			commit_finished_dly_internal_1 <= '0';
			commit_finished_dly <= '0';
			
			rollback_busy <= '0';
		elsif rising_edge(clk) then
			state <= next_state;
			
			is_tm_magic_addr_sync <= is_tm_magic_addr_async;
			sc_out_cpu_dly <= sc_out_cpu;
			
			commit_finished_dly_internal_1 <= commit_finished;
			commit_finished_dly <= commit_finished_dly_internal_1;
			
			rollback_busy <= next_rollback_busy;
		end if;
	end process sync;
	
	gen_tm_cmd: process (sc_out_cpu_dly, is_tm_magic_addr_sync) is
	begin
		tm_cmd <= none;			
		
		if sc_out_cpu_dly.wr = '1' and is_tm_magic_addr_sync = '1' then
			tm_cmd <= tm_cmd_type'val(to_integer(unsigned(
				sc_out_cpu_dly.wr_data(tm_cmd_raw'range))));
		end if;
	end process gen_tm_cmd;	

	
	-- sets next_state, exc_tm_rollback, tm_cmd_rdy_cnt
	state_machine: process(commit_finished_dly, commit_in_allow, conflict, 
		rollback_busy, state, tag_full, tm_cmd) is
	begin
		next_state <= state;
		exc_tm_rollback <= '0';
		tm_busy <= '0';
		
		next_rollback_busy <= 'X';
		
		transaction_start <= '0';
		
		case state is
			when no_transaction =>
				if tm_cmd = start_transaction then
					next_state <= normal_transaction;
					tm_busy <= '1';
					
					transaction_start <= '1';
				end if;
				
			when normal_transaction =>
				case tm_cmd is
					when end_transaction =>
						next_state <= commit_wait_token;
						tm_busy <= '1';
					when early_commit =>
						next_state <= early_commit_wait_token;
						tm_busy <= '1';
					when abort =>
						next_state <= rollback_signal;
						tm_busy <= '1';
					when others => 
						null;
				end case;						
				
				if tag_full = '1' then
					next_state <= early_commit_wait_token;
					tm_busy <= '1';
				end if;				
				
				if conflict = '1' then
					-- > current transaction will be terminated before
					--   tm command is issued 
					-- > no internal actions until then
					-- => therefore no need to wait
					next_state <= rollback_signal;					
					tm_busy <= '1';
				end if;
				
			when commit_wait_token =>
				tm_busy <= '1';
			
				if conflict = '1' then
					next_state <= rollback_signal;
				elsif commit_in_allow = '1' then
					next_state <= commit;
				end if;
			
			when commit =>
				tm_busy <= '1';
				
				-- TODO check condition
				if commit_finished_dly = '1' then
					next_state <= no_transaction;
				end if;
				
			when early_commit_wait_token =>
				tm_busy <= '1';
			
				if conflict = '1' then
					next_state <= rollback_signal;
				elsif commit_in_allow = '1' then
					next_state <= early_commit;
				end if;
				
			when early_commit =>
				tm_busy <= '1';
			
				-- TODO check condition
				if commit_finished_dly = '1' then
					next_state <= early_committed_transaction;
				end if;
				
			when early_committed_transaction =>
				case tm_cmd is
					when end_transaction =>
						tm_busy <= '1';
						
						next_state <= no_transaction;
					when others =>
						null;
				end case;
				
				
			when rollback_signal =>
				tm_busy <= '1';
				next_rollback_busy <= '1';
			
				next_state <= rollback_wait;
				exc_tm_rollback <= '1';
								
			when rollback_wait =>
				next_rollback_busy <= '0';
			
				-- 1 cycle delay to ensure that exception will be handled when
				-- next bytecode is issued
				-- TODO refer to documentation
				if rollback_busy = '1' then
					tm_busy <= '1';					
				end if;
			
				-- sw ack that exception has been raised
				-- > also implies that a possibly begun memory access has 
				--   finished
				if tm_cmd = aborted then
					next_state <= no_transaction;
				end if;
			
		end case;
	end process state_machine;
	
	
	commit_out_try_internal <= '1' 
		when state = commit_wait_token or state = early_commit_wait_token or
		state = commit or state = early_commit or
		state = early_committed_transaction
		else '0';
	
	commit_out_try <= commit_out_try_internal;		
	
	

	-- sets sc_out_cpu_filtered, sc_out_arb, sc_in_cpu
	process(is_tm_magic_addr_async, sc_in_cpu_filtered, 
		sc_out_arb_filtered, sc_out_cpu, state, tm_busy) is
	begin
		sc_out_cpu_filtered <= sc_out_cpu;
		sc_out_arb <= sc_out_arb_filtered;
		sc_in_cpu <= sc_in_cpu_filtered;
	
		case state is
			when rollback_signal | rollback_wait =>
				-- ignore writes
				sc_out_cpu_filtered.wr <= '0';
				
				-- reads from main memory
				-- TODO reads outside of RAM
				
				assert sc_out_arb_filtered.wr /= '1';
			when no_transaction | early_committed_transaction | 
			normal_transaction | commit_wait_token | 
			commit | early_commit_wait_token | early_commit =>
				null;
		end case;
		
		if tm_busy = '1' then
			sc_in_cpu.rdy_cnt <= "11";
		end if;
		
		-- set broadcast
		case state is
			when commit | early_commit | early_committed_transaction => 
				sc_out_arb.tm_broadcast <= '1';
			when normal_transaction | commit_wait_token | 
			early_commit_wait_token | rollback_signal | rollback_wait =>
				-- TODO no writes to mem should happen 
				sc_out_arb.tm_broadcast <= '0';
			when no_transaction =>
				sc_out_arb.tm_broadcast <= '0';
		end case;
				
		-- overrides when TM command is issued
		if sc_out_cpu.wr = '1' and is_tm_magic_addr_async = '1' then		
			sc_out_cpu_filtered.wr <= '0';
		end if;
	end process; 

end rtl;
