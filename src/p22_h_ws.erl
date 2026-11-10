%% ===================================================================
%% @doc p22_h_ws — WebSocket `/ws`.
%%
%% Cada tablero conectado entra AQUI. Al abrir:
%%   - se suscribe al bus (p22_eventos) y recibe cada evento DEL
%%     MOMENTO en adelante (el historial pasado se pide con
%%     GET /api/vuelos, que es lo que el frontend hace al reconectar);
%%   - se manda inmediatamente el snapshot inicial (resync) para que
%%     el tablero pinte de una vez sin esperar al primer evento.
%% Al cerrar (o morir), el bus lo quita solo (monitor DOWN).
%% El tablero NUNCA parpadea: reconecta cada 2 s y pide un resync.
%% ===================================================================
-module(p22_h_ws).

-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2,
         terminate/3]).

init(Req, State) ->
    {cowboy_websocket, Req, State}.

websocket_init(State) ->
    ok = p22_eventos:suscribir(self()),
    %% Snapshot inicial al conectar: una unica "accion" resync que el
    %% frontend aplica reemplazando su vista completa.
    Snapshot =
        p22_util:json_a_texto(#{tipo => resync,
                                vuelos => listas_del_tablero(),
                                clientes => length(p22_eventos:clientes())}),
    {[{text, Snapshot}], State}.

websocket_handle({text, <<>>}, State) ->
    %% ping del navegador -> respuesta viva (keepalive)
    {[{text, <<"{\"tipo\":\"pong\"}">>}], State};
websocket_handle(_Mensaje, State) ->
    {[], State}.

%% Los mensajes del BUS llegan por websocket_info (cowboy 2).
websocket_info({evento_json, Json}, State) ->
    {[{text, Json}], State};
websocket_info(_Info, State) ->
    {[], State}.

terminate(_Razon, _Req, _State) ->
    p22_eventos:desuscribir(self()),
    ok.

listas_del_tablero() ->
    [vista_para_ws(Id, Info)
     || {Id, Info} <- p22_respaldo:todos_vuelos()].

vista_para_ws(Id, Info) ->
    Datos = maps:get(datos, Info, #{}),
    case p22_vuelo_statem:completo(Id) of
        {error, _} ->
            #{id => Id,
              estado => maps:get(estado, Info, nada),
              de_respaldo => true,
              identificacion => maps:get(identificacion, Datos, <<>>),
              aeronave => maps:get(aeronave, Datos, <<>>),
              aerolinea => maps:get(aerolinea, Datos, <<>>),
              destino => maps:get(destino, Datos, <<>>),
              puerta => maps:get(puerta, Datos, undefined),
              demora_min => maps:get(demora_min, Datos, 0),
              hora_programada => maps:get(hora_programada, Datos, 0),
              hora_estimada => maps:get(hora_estimada, Datos, undefined)};
        Vista ->
            Vista#{de_respaldo => false}
    end.
