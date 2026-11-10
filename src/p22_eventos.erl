%% ===================================================================
%% @doc p22_eventos — bus de eventos y canal para el tablero (WebSocket).
%%
%% Cualquier cambio de estado de un vuelo, alerta o mensaje de sistema
%% llega aqui con `publicar/1`. El bus:
%%   1. manda el mapa a cada cliente suscrito (handler WebSocket),
%%   2. destapa el dato a texto JSON de una vez (una codificacion para
%%      los 300 clientes del escenario, no una por cliente),
%%   3. conta el evento en el respaldo para /metrics.
%%
%% Los clientes se registran con `suscribir/1` y se desregistran
%% automaticamente: monitoreamos su pid, asi que si la conexion muere
%% el bus lo limpia solo (DOWN). Eso es lo que hace que el tablero "no
%% parpadee" cuando alguien refresca.
%% ===================================================================
-module(p22_eventos).

-behaviour(gen_server).

-export([start_link/0, ping/0, publicar/1, suscribir/1, desuscribir/1, clientes/0,
         emitir_json/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Health-check para pruebas y para el endpoint /metrics.
ping() ->
    gen_server:call(?MODULE, ping).

%% @doc Evento = mapa de Erlang. Ej:
%%  #{tipo => cambio_estado, vuelo => 7, desde => programado,
%%    hacia => abordando, puerta => puerta_3}
publicar(Evento) when is_map(Evento) ->
    gen_server:cast(?MODULE, {publicar, maps:merge(#{ts => os:system_time(second)},
                                                   Evento)}).

%% Suscripcion desde el handler WebSocket: el pid del socket.
suscribir(Pid) ->
    gen_server:call(?MODULE, {suscribir, Pid}).

desuscribir(Pid) ->
    gen_server:cast(?MODULE, {desuscribir, Pid}).

clientes() ->
    gen_server:call(?MODULE, clientes).

%% @doc Codifica un mapa de evento a JSON binario (punto unico de
%% serializacion, lo usa el bus y los handlers de la API).
emitir_json(Evento) ->
    p22_util:json_a_texto(Evento).

%% --- gen_server ----------------------------------------------------

init([]) ->
    process_flag(trap_exit, true),
    {ok, #{clientes => #{}, cliente_ultimo_id => 0}}.

handle_call(ping, _From, State) ->
    {reply, pong, State};

handle_call({suscribir, Pid}, _From, #{clientes := Cli, cliente_ultimo_id := N} = State) ->
    Ref = erlang:monitor(process, Pid),
    NuevoCli = Cli#{Pid => {Ref, N + 1}},
    %% Aviso para /metrics: cuantos tableros conectados ahora.
    p22_respaldo:contador(clientes_tablero, 1),
    {reply, ok, State#{clientes := NuevoCli, cliente_ultimo_id := N + 1}};

handle_call(clientes, _From, #{clientes := Cli} = State) ->
    {reply, maps:keys(Cli), State}.

%% Publicacion: una sola serializacion, un broadcast a cada cliente.
handle_cast({publicar, Evento}, #{clientes := Cli} = State) ->
    Json = emitir_json(Evento),
    maps:foreach(
      fun(Pid, _) -> Pid ! {evento_json, Json} end,
      Cli),
    Tipo = maps:get(tipo, Evento, evento),
    %% Contadores que /metrics usa despues:
    %%   - eventos_min : ventana de 60 s computada en el handler metrics
    %%   - {tipo, T}   : cuantos eventos de cada tipo han pasado
    p22_respaldo:contador(eventos_min, 1),
    p22_respaldo:contador({tipo, Tipo}, 1),
    {noreply, State};
handle_cast({desuscribir, Pid}, #{clientes := Cli} = State) ->
    case Cli of
        #{Pid := {Ref, _}} ->
            erlang:demonitor(Ref, [flush]),
            p22_respaldo:contador(clientes_tablero, -1),
            {noreply, State#{clientes := maps:remove(Pid, Cli)}};
        _ ->
            {noreply, State}
    end;
handle_cast(_Otro, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, Pid, _Razon}, #{clientes := Cli} = State) ->
    case Cli of
        #{Pid := {Ref, _}} ->
            p22_respaldo:contador(clientes_tablero, -1),
            {noreply, State#{clientes := maps:remove(Pid, Cli)}};
        _ ->
            {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.
