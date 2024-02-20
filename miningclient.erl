-module(miningclient).
-export([startClient/0,startSupervisor/3,createSupervisor/1,startMining/6]).

%% Function to start the client process that contacts the server and waits for its response.
startClient() ->
    %% Registered process name of server and server's node name.
    Server = {miner, 'servermining@192.168.0.51'},
    ExecutionStartTime = erlang:monotonic_time(),
    Server ! {i_am, self()},
    messageHandler(Server, ExecutionStartTime, self(), 0).

%% Function to handle the messages that the manager process receives and send the coins that are mined to the server.
messageHandler(Server, ExecutionStartTime, Supervisor_Pid, RequiredNumberOfZeroes) ->
    receive
        {create_supervisor, NumberOfZeroes} ->
            Pid = createSupervisor(NumberOfZeroes),
            Pid ! {self(), {start, NumberOfZeroes}},
            messageHandler(Server, ExecutionStartTime, Pid, NumberOfZeroes);
        {From, {done, HashString, GeneratedHash, Nonce}} ->
            Server ! {From,{done, HashString, GeneratedHash, Nonce}},
            self() ! {create_supervisor, RequiredNumberOfZeroes},
            io:format("~s, ~p in ~s iterations ~p~n",[HashString, GeneratedHash, erlang:integer_to_list(Nonce), erlang:convert_time_unit(erlang:monotonic_time() - ExecutionStartTime, native, seconds)]),
            messageHandler(Server, ExecutionStartTime, From, RequiredNumberOfZeroes);
        {terminate} ->
            io:format("Received terminate~n"),
            Supervisor_Pid ! {terminate_workers},
            exit(Supervisor_Pid, kill),
            Server ! ok
    end.

%% Creates Supervisor nodes and returns their Pids in a list.
createSupervisor(RequiredNumberOfZeroes) ->
    Pid = spawn(?MODULE, startSupervisor, [RequiredNumberOfZeroes,self(), []]),
    Pid.

%% Starting point of execution for the Supervisor process.
startSupervisor(_RequiredNumberOfZeroes, Manager_Pid, Workers_Pids) ->
    Number_Of_Workers_Per_Supervisor = 10000,
    receive
        %% Receive from Manager
        {_From, {start, NumberOfZeroes}} ->
            RandomString = "vnaganaboina" ++ binary_to_list(base64:encode(crypto:strong_rand_bytes(4))),  %% Generate a random string
            Worker_Pids = createWorker(NumberOfZeroes,Number_Of_Workers_Per_Supervisor, RandomString, 0, []),
            startWorker(Worker_Pids,NumberOfZeroes),
            startSupervisor(NumberOfZeroes, Manager_Pid, Worker_Pids);
        %% Receive from Workers
        {From, {done, HashString, GeneratedHash, Nonce}} ->
            Manager_Pid ! {self(), {done, HashString, GeneratedHash, Nonce}},
            terminateWorkers(Workers_Pids --[From]);
        {terminate_workers} ->
            terminateWorkers(Workers_Pids)
    end.

%% Function to create new workers.
createWorker(_,Number_Of_Workers_Per_Supervisor, _, _, Worker_Pids) when Number_Of_Workers_Per_Supervisor == 0-> Worker_Pids;
createWorker(RequiredNumberOfZeroes,Number_Of_Workers_Per_Supervisor, RandomString, Nonce, Worker_Pids) when Number_Of_Workers_Per_Supervisor > 0->
    Step = 1000000,
    Step_Size = Step,
    Nonce_Start = Nonce*Step,
    Pid = spawn(?MODULE, startMining, [RequiredNumberOfZeroes,Number_Of_Workers_Per_Supervisor, RandomString, Nonce_Start, Step, Step_Size]),
    createWorker(RequiredNumberOfZeroes,Number_Of_Workers_Per_Supervisor-1, RandomString, Nonce+1, [Pid|Worker_Pids]).

%% Function to send message workers to start working.
startWorker([],_) -> void;
startWorker(Worker_Pids,RequiredNumberOfZeroes) ->
    [H|T] = Worker_Pids,
    H ! {self(), {start, RequiredNumberOfZeroes}},
    startWorker(T,RequiredNumberOfZeroes).

%% Function that trerminates the workers.
terminateWorkers([]) -> void;
terminateWorkers(Worker_Pids) ->
    [H|T] = Worker_Pids,
    exit(H, kill),
    terminateWorkers(T).

%% Execution starting point of Worker processes.
startMining(_RequiredNumberOfZeroes,Number_Of_Workers_Per_Supervisor, RandomString, Nonce_Start, Step, Step_Size) ->
    receive
        {From, {start, NumberOfZeroes}} ->
            hashContent(NumberOfZeroes,Number_Of_Workers_Per_Supervisor,RandomString, Nonce_Start, Step, Step_Size, From)
    end.

%% Function that mines the coin and returns the result once a coin is mined.
hashContent(RequiredNumberOfZeroes,Number_Of_Workers_Per_Supervisor, RandomString, Nonce, Step, Step_Size, Supervisor_Pid) when Step == 0->
    hashContent(RequiredNumberOfZeroes,Number_Of_Workers_Per_Supervisor, RandomString, (Nonce + (Number_Of_Workers_Per_Supervisor*Step_Size) - Step_Size + 1), Step_Size, Step_Size, Supervisor_Pid);
hashContent(RequiredNumberOfZeroes,Number_Of_Workers_Per_Supervisor, RandomString, Nonce, Step, Step_Size, Supervisor_Pid) when Step > 0->
    HashString = RandomString++ erlang:integer_to_list(Nonce),
    GeneratedHash = sha256StringGenerator(HashString),
    NumberOfTrailingZerosAchieved = leadingZeros(GeneratedHash, RequiredNumberOfZeroes),
    if    
        NumberOfTrailingZerosAchieved == 1->
            Supervisor_Pid ! {self(), {done, HashString, GeneratedHash, Nonce}};
        true ->
            hashContent(RequiredNumberOfZeroes,Number_Of_Workers_Per_Supervisor, RandomString, Nonce+1, Step-1, Step_Size,Supervisor_Pid)
    end.

%% Function to run SHA256 algorithm on the generated string.
sha256StringGenerator(String) ->
    io_lib:format("~64.16.0b", [binary:decode_unsigned(crypto:hash(sha256,String))]).

%% Function to check the number of leading zeroes in the generated hash string.
leadingZeros(Hash, RequiredNumberOfTrailingZeros)->
    NumberOfTrailingZeros = string:length(Hash) - string:length(string:trim(Hash, leading, "0")),
    if
        NumberOfTrailingZeros >= RequiredNumberOfTrailingZeros ->
            1;
        true ->
            void
    end.


