%% ===================================================================
%% @doc p22_web — servidor cowboy del proyecto 22 (torre de control).
%%
%% Levanta UN listener con las rutas:
%%   GET  /                     -> tablero (priv/index.html)
%%   GET  /api/vuelos           -> lista completa (GET)
%%   POST /api/vuelos           -> crea un vuelo (demo manual)
%%   GET  /api/vuelos/:id       -> detalle con historial
%%   POST /api/vuelos/:id/estado -> aplica una transicion manual
%%   POST /api/demo/:accion     -> niebla | caos | fuera_de_orden | pausar | reanudar
%%   GET  /ws                   -> WebSocket: eventos de la torre
%%   GET  /metrics              -> metricas para monitoreo
%%
%% El puerto viene de `p22_torre_de_control_tij.puerto` (sys.config).
%% ===================================================================
-module(p22_web).

-behaviour(gen_server).

-export([start_link/0, terminate/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    %% trap: para poder desmontar el listener en terminate (shutdown)
    process_flag(trap_exit, true),
    Puerto = application:get_env(p22_torre_de_control_tij, puerto, 8080),
    Rutas =
        [{"/api/demo/:accion", p22_h_demo, []},
         {"/api/vuelos/:id/estado", p22_h_vuelo_estado, []},
         {"/api/vuelos/:id", p22_h_vuelo, []},
         {"/api/vuelos", p22_h_vuelos, []},
         {"/ws", p22_h_ws, []},
         {"/metrics", p22_h_metrics, []},
         {"/", p22_h_index, []}],
    Despacho = cowboy_router:compile([{'_', Rutas}]),
    {ok, _} = cowboy:start_clear(p22_listener,
                                 [{port, Puerto}],
                                 #{env => #{dispatch => Despacho}}),
    logger:info("~s escuchando en http://0.0.0.0:~p", [?MODULE, Puerto]),
    {ok, #{puerto => Puerto}}.

%% Al morir el proceso (reinicio del supervisor o shutdown), el
%% listener de ranch NO es hijo nuestro: hay que desmontarlo aqui para
%% que el reinicio lo pueda recrear limpio.
terminate(Razon, #{puerto := _}) ->
    logger:info("~s: desmontando listener en terminate (~p)", [?MODULE, Razon]),
    try cowboy:stop_listener(p22_listener)
    catch _:_ -> ok
    end,
    ok.

handle_call(_Msg, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.
