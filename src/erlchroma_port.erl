-module(erlchroma_port).

-export([]).

-export([start/0,check_multiple/2,start/1, stop/1, init/1,decode_batch/0,create_fingerprints/0,load_fingerprints_ets/0]).


%% @doc 
%% 1  write code to decode media file into a pcm format
%% 	  code to then create fingreprint
%%	  code to store fingerprints in binary file/code to also load fingerprints into ets file
%% 	  code to then store in ets along with pseudo id of artist
%% 2. code to then be finding songs as i stream the data from a url and calculate length of song which is being played/streamed
%%	  calculation is done by finding songs which are being played and then using the timestamp to increase  duration of track 





%% @doc

-spec decode_batch()-> list().
decode_batch()->
    %%ffmpeg -i out/open_gate.mp3 -acodec pcm_s16le out/open_gate_new.wav
	{ok,Temp_folder} = application:get_env(erlchroma,temp_folder),
	{ok,Decoded_folder} = application:get_env(erlchroma,decoded_folder),
	{ok,Directlist} =file:list_dir(Temp_folder),
	lists:map(
		fun(File_name)-> 
			Path_track = lists:concat([Temp_folder,"/",File_name]),
			Decode_name = lists:concat([Decoded_folder,"/",lists:nth(1,string:tokens(File_name,"."))]),
			Command_Exec = ["/usr/bin/ffmpeg","-i",Path_track,"-f","wav",Decode_name],
			io:format("~ncommand to be executed is ~p",[Command_Exec]),
			case exec:run(Command_Exec, [sync,{stdout,print}]) of 
				{ok,Res} ->
				   io:format("~n status after executation is ~p",[Res]);
				{error,Res}->
				   io:format("~n error converting file ~p",[Res])	
		end	
    end,Directlist).



-spec create_fingerprints()-> list().
create_fingerprints()->
	{ok,Track_converted_folder} = application:get_env(erlchroma,decoded_folder),
	{ok,Finpgerprint_folder} = application:get_env(erlchroma,finpgerprint_folder),
	{ok,Directlist} =file:list_dir(Track_converted_folder),
	lists:map(
		fun(File_name)-> 
			Path_convert_track = lists:concat([Track_converted_folder,"/",File_name]),
			Command_Exec = ["/usr/bin/fpcalc","-chunk","2","-json","-overlap",Path_convert_track],
			Fingerprint_name = erlang:binary_to_list(uuid:uuid_to_string(uuid:get_v4(), binary_standard)),
			Proplist_binary = [{name_file,File_name},{id_file,Fingerprint_name}],
			io:format("~ncommand to be executed is ~p",[Command_Exec]),
			case exec:run(Command_Exec, [sync,stdout]) of 
				{ok,[{stdout,List_fingerprint}]} ->
				   ok = file:write_file(lists:concat([Finpgerprint_folder,"/",File_name]), io_lib:format("~p.", [[{fingerprint,List_fingerprint}|Proplist_binary]]));
				{error,Res}->
				   io:format("~n error converting file ~p",[Res])	
			end	
		end,
    Directlist).	


%% @doc this is for loading fingerprints int the ets 
-spec load_fingerprints_ets()->list()|atom().
load_fingerprints_ets()->
	case ets:info(fingerprint) of 
		undefined ->
			ets:new(fingerprints, [duplicate_bag, named_table]);
		_ ->
			ok
	end,
	{ok,Fingerprint_folder} = application:get_env(erlchroma,finpgerprint_folder),
	{ok,Directlist} = file:list_dir(Fingerprint_folder),
	io:format("~njson data is ~p",[Directlist]),
	lists:map(
		fun(File_name)->
			{ok,[Data]} = file:consult(lists:concat([Fingerprint_folder,"/",File_name])),
			Id_track =  proplists:get_value(id_file,Data),
			Fingerprint_data = proplists:get_value(fingerprint,Data),
			%%io:format("~nfdata is ~p~p~p",[Data,Id_artist,Fingerprint_data]),
			lists:map(
				fun(Fdata)->
					Json_data = jsx:decode(unicode:characters_to_binary(Fdata)),
					io:format("~njson data is ~p",[Json_data]),
					Fprint = proplists:get_value(<<"fingerprint">>,Json_data),
					ets:insert(fingerprints,{Fprint,Id_track})
				end,
			Fingerprint_data),
			io:format("~nfingperprint data is ~p",[Data])
		end,
	Directlist),
	ok.


-spec compare_fingerprint(binary())->list().
compare_fingerprint(Fprint)->
	ok.

%% @doc for testing for running multiple instances of a command 
%%Command = "/usr/bin/fpcalc -ts -chunk 2 -overlap -json http://yfm1079accra.atunwadigital.streamguys1.com/yfm1079accra",
-spec check_multiple(integer(),binary()|string())->list().
check_multiple(N,Command)->
	List_pids = lists:map(fun(_) -> start(Command) end,lists:seq(1,N)).


%% @doc for starting the port command
-spec start()->error_no_prog_specified | pid().
start() ->
    error_no_prog_specified.


start(ExtPrg) ->
    spawn(?MODULE, init, [ExtPrg]).


%% @doc for stopping the port program
-spec stop(pid())-> stop.
stop(Pid) ->
    Pid ! stop.


%%for initilizing the port for runnig commands
-spec init([string() | char()]) -> pid().
init(ExtPrg) ->
    process_flag(trap_exit, true),
    {ok,Pid,Ospid} = exec:run(ExtPrg, [stdout, stderr,monitor]),
    loop(Pid,Ospid,ExtPrg).


%%for looping and execting main function
-spec loop(pid(),integer(),[string() | char()]) -> pid().
loop(Pid,Ospid,ExtPrg) ->
    receive
		{'DOWN',Ospid,process,Pid,normal}->
			io:format("~n os process ~p with process ~p is down ~n",[Ospid,Pid]),
			start(ExtPrg);
		{'EXIT', Port, Reason} ->
			io:format("~n Port was killed for reason ~p ~p ~nrestarting port~n",[Port,Reason]),
			exit(processexited);
		Data ->
			io:format("~ndata received is ~p",[Data]),
			loop(Pid,Ospid,ExtPrg)

    end.
