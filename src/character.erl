-module(character).
-export([init/1]).

-include("realm_records.hrl").
-include("database_records.hrl").

% network defines
-define(I, /unsigned-little-integer).
-define(O, /unsigned-big-integer).
-define(b,  /bytes).                   % that's for plain text
-define(f,  /float-little).            % float values obviously
-define(SH, :160?I).                   % SH is for sha1
-define(Q,   :64?I).                   % uint64 - Q for quad
-define(L,   :32?I).                   % uint32 - L for long
-define(W,   :16?I).                   % uint16 - W for word
-define(B,    :8).                     % byte (doesn't need to be endianated)

init(State) ->
    not_in_world(State).

not_in_world(#client_state{receiver=R, sender=S}=State) ->
    receive
    {R, cmsg_ping, D} ->
        {Sequence, Latency} = realm_patterns:cmsg_ping(D),
        S ! {self(), smsg_pong, <<Sequence?L>>},
        not_in_world(State#client_state{latency=Latency});
        
    {R, cmsg_char_enum, _} ->
        Data = realm_patterns:smsg_char_enum(State#client_state.account, State#client_state.realm),
        S ! {self(), smsg_char_enum, Data},
        not_in_world(State);
    
    {R, cmsg_realm_split, _} ->
        Date = list_to_binary("01/01/01"),
        S ! {self(), smsg_realm_split, <<16#FFFFFFFF?L, 0?L, Date/binary, 0?B>>},
        not_in_world(State);
    
    {R, cmsg_whois, _} ->
        Whois = account_helper:get_whois(State#client_state.account),
        S ! {self(), smsg_whois, <<Whois/bytes, 0?B>>},
        not_in_world(State);
    
    {R, cmsg_voice_session_enable, _} ->
        not_in_world(State);
    
    {R, msg_query_guild_bank_text, _} ->
        not_in_world(State);
    
    {R, cmsg_player_login, D} ->
        {ok, CharId} = realm_patterns:cmsg_player_login(D),
        Char = char_helper:find(CharId),
        ok = set_dungeon_difficulty(S, -1),
        ok = verify_world(S, Char),
        ok = send_account_data(S),
        ok = set_rest_start(S),
        ok = set_tutorial_flags(S),
        ok = send_spells_and_cooldowns(S),
        ok = send_action_buttons(S),
        ok = send_factions(S),
        ok = send_timespeed(S),
        ok = send_status(S),
        ok = send_self(S, Char),
        in_world(State, Char);
    
    {R, Handler, Data} ->
        io:format("unhandled: ~p~n~p~n", [Handler, Data]),
        not_in_world(State);
    
    Any ->
        io:format("unauthorized: ~p~n", [Any]),
        not_in_world(State)
    end.

in_world(#client_state{receiver=R, sender=S}=State, _Char) ->
    receive
    {R, cmsg_ping, D} ->
        {Sequence, Latency} = realm_patterns:cmsg_ping(D),
        S ! {self(), smsg_pong, <<Sequence?L>>},
        not_in_world(State#client_state{latency=Latency});
    
    {R, Handler, Data} ->
        io:format("unhandled: ~p~n~p~n", [Handler, Data]),
        not_in_world(State);
    
    Any ->
        io:format("unauthorized: ~p~n", [Any]),
        not_in_world(State)
    end.

set_dungeon_difficulty(S, -1) ->
    S ! {self(), msg_set_dungeon_difficulty, <<0?L, 1?L, 0?L>>},
    ok;
set_dungeon_difficulty(S, Difficulty) ->
    S ! {self(), msg_set_dungeon_difficulty, <<Difficulty?L>>},
    ok.

verify_world(S, Char) ->
    S ! { self(), smsg_login_verify_world, 
          <<(Char#char.map_id)?f, (Char#char.position_x)?f, 
            (Char#char.position_y)?f, (Char#char.position_z)?f,
            (Char#char.orientation)?f>> },
    ok.

send_account_data(S) ->
    S ! {self(), smsg_account_data_times, <<0:1024>>},
    ok.

set_rest_start(S) ->
    GameTime = common_helper:game_time(common_helper:now()),
    S ! {self(), smsg_set_rest_start, <<GameTime?L>>},
    ok.

set_tutorial_flags(S) ->
    S ! {self(), smsg_tutorial_flags, <<0:256>>},
    ok.

send_spells_and_cooldowns(S) ->
    S ! {self(), smsg_initial_spells, <<0?B, 0?W, 0?W>>},
    ok.

send_action_buttons(S) ->
    S ! {self(), smsg_action_buttons, <<>>},
    ok.

send_factions(S) ->
    S ! {self(), smsg_initialize_factions, <<128?L, 0:5120>>},
    ok.

send_timespeed(S) ->
    GameTime = common_helper:game_time(common_helper:now()),
    S ! {self(), smsg_login_settimespeed, <<GameTime?L, (0.0166666669777748)?f>>},
    ok.

send_status(S) ->
    S ! {self(), smsg_feature_system_status, <<2?B, 0?B>>},
    ok.

send_self(S, Char) ->
    GameTime = common_helper:game_time(common_helper:now()),
    <<RCG:24/binary, SFHsHcFh/binary>> = Char#char.player_bytes, 
    Update = <<1?L,                      % blocks count
               3?B,                      % create self
                
               255?B,                    % guid packing mask
               (Char#char.id)?L, 0?L,    % player guid
               4?B,                      % object type player

               16#61?B,                  % update flags
               0?L,                      % move flags
               0?W,                      % unknown flags

               GameTime?L,               % current time

               (Char#char.position_x)?f, % position x
               (Char#char.position_y)?f, % position y
               (Char#char.position_z)?f, % position z
               (Char#char.orientation)?f,% orientation

               0?L,                      % unknown

               2.5?f,                    % walk speed
               2.5?f,                    % walk back speed
               7?f,                      % run speed
               4.5?f,                    % run back speed
               4.722222?f,               % swim speed
               2.5?f,                    % swim back speed
               7?f,                      % fly speed
               4.5?f,                    % fly back speed
               3.141593?f,               % turn speed
               8?B,                      % length of bitmask (x * 32)
               23?B, 0?B, 64?B, 16?B,    % mask 1
               28?B, 0?B, 0?B, 0?B,      % mask 2
               0?B, 0?B, 0?B, 0?B,       % mask 3
               0?B, 0?B, 0?B, 0?B,       % mask 4
               0?B, 0?B, 0?B, 1?B,       % mask 5
               16?B, 0?B, 0?B, 0?B,      % mask 6
               0?L,                      % mask 7
               0?B, 128?B, 1?B, 0?B,     % mask 8
               (Char#char.id)?L, 0?L,    % player guid
               25?L,                     % player type
               1.0?f,                    % scale
               1000?L,                   % health
               1000?L,                   % max health
               (Char#char.level)?L,
               4?L,                      % factiontemplate
               RCG/binary, 0?B,          % race, class, gender, power
               60?L,                     % display ID
               0?L,                      % dynamic flag (0 = alive)
               SFHsHcFh/binary,          % skin, face, hair style, hair color facial hair
               238?B, 0?B, 2?B           % unknown
               >>,
    S ! {self(), smsg_update_object, Update},
    ok.