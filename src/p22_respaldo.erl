%% ===================================================================
%% @doc p22_respaldo — dueño de las tablas ETS de recuperación.
%%
%% ¿Por que existe este proceso?
%%
%% La prueba de caos pide que, al morir un proceso de vuelo, este se
%% reconstruya con su ULTIMO estado conocido y sin que el tablero
%% parpadee. Un gen_statem reconfigurado por su supervisor arranca con
%% los datos de arranque (estado inicial), asi que el ultimo estado
%% tiene que vivir FUERA del vuelo.
%%
%% Ademas resuelve el caso dificil "reinicio del sistema" en dos niveles:
%%   - proceso: cada escritura deja una foto en `persistent_term`; si el
%%     respaldo (o todo el arbol) se reinicia, re-hidrata las ETS de ahi;
%%   - nodo/VM: con `{persistir, true}` la foto tambien se escribe en
%%     disco (archivo_respaldo) y al arrancar una VM nueva se recupera.
%%     El feed luego re-arranca un gen_statem por cada vuelo guardado.
%%
%% Orden en el arbol: es el PRIMER hijo del supervisor raiz
%% (rest_for_one), asi que si este proceso muere, todo lo que depende de
%% el (eventos, puertas, vuelos) se reinicia en orden y puede leer el
%% respaldo ya reconstruido.
%%
%% Tablas ETS publicas (las leen vuelos, feed y handlers sin pasar por
%% aqui, solo las escrituras viajan por este proceso):
%%   p22_vuelos   (set) id -> #{estado, datos, tocado}
%%   p22_puertas_oc (set) puerta -> id de vuelo
%%   p22_stats    (set) nombre -> contador
%% ===================================================================
-module(p22_respaldo).

-behaviour(gen_server).

-export([start_link/0]).
-export([guardar_vuelo/3, leer_vuelo/1, borrar_vuelo/1, todos_vuelos/0,
         tomar_puerta/2, soltar_puerta/1, puertas_ocupadas/0,
         contador/2, leer_contador/1, leer_todos_los_contadores/0,
         limpiar/0, mostrar/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TAB_VUELOS, p22_vuelos).
-define(TAB_PUERTAS, p22_puertas_oc).
-define(TAB_STATS, p22_stats).
-define(KEY_FOTO, p22_foto).
-define(ARCHIVO_DEFECTO, "data/p22_respaldo.bin").

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% --- API -----------------------------------------------------------

%% Guarda la ultima imagen conocida de un vuelo (para reconstruccion).
guardar_vuelo(Id, Estado, Datos) ->
    gen_server:cast(?MODULE, {guardar_vuelo, Id, Estado, Datos}).

leer_vuelo(Id) ->
    case ets:lookup(?TAB_VUELOS, Id) of
        [{_, Info}] -> Info;
        [] -> no_encontrado
    end.

borrar_vuelo(Id) ->
    gen_server:cast(?MODULE, {borrar_vuelo, Id}).

todos_vuelos() ->
    ets:tab2list(?TAB_VUELOS).

%% Ocupacion de puertas, para que las puertas reconstruyan su estado.
tomar_puerta(Puerta, IdVuelo) ->
    gen_server:call(?MODULE, {tomar_puerta, Puerta, IdVuelo}).

soltar_puerta(Puerta) ->
    gen_server:call(?MODULE, {soltar_puerta, Puerta}).

puertas_ocupadas() ->
    ets:tab2list(?TAB_PUERTAS).

%% Contadores de eventos (para /metrics).
contador(Nombre, Delta) ->
    gen_server:cast(?MODULE, {contador, Nombre, Delta}).

leer_contador(Nombre) ->
    case ets:lookup(?TAB_STATS, Nombre) of
        [{_, V}] -> V;
        [] -> 0
    end.

leer_todos_los_contadores() ->
    ets:tab2list(?TAB_STATS).

%% @doc Mapa con todo el respaldo, para auditoria/diagnostico (recon).
mostrar() ->
    gen_server:call(?MODULE, mostrar).

%% @doc Borra TODO el respaldo (para pruebas aisladas). Seguro de
%% llamar aunque el proceso no exista aun.
limpiar() ->
    borrar_archivo(),
    case whereis(?MODULE) of
        undefined ->
            persistent_term:erase(?KEY_FOTO),
            ok;
        _ ->
            gen_server:call(?MODULE, limpiar)
    end.

%% --- gen_server ----------------------------------------------------

init([]) ->
    ets:new(?TAB_VUELOS, [named_table, public, set]),
    ets:new(?TAB_PUERTAS, [named_table, public, set]),
    ets:new(?TAB_STATS, [named_table, public, set]),
    %% Re-hidratacion: proceso (persistent_term) o VM (archivo).
    case foto_inicial() of
        #{vuelos := Vuelos, puertas := Puertas, stats := Stats} ->
            ets:insert(?TAB_VUELOS, Vuelos),
            ets:insert(?TAB_PUERTAS, Puertas),
            ets:insert(?TAB_STATS, Stats),
            logger:info("~s re-hidratado: ~p vuelos, ~p puertas, ~p contadores",
                        [?MODULE, length(Vuelos), length(Puertas), length(Stats)]);
        no_hay ->
            logger:info("~s arranque limpio (sin foto previa)", [?MODULE])
    end,
    {ok, #{}}.

handle_cast({guardar_vuelo, Id, Estado, Datos}, State) ->
    Info = #{estado => Estado, datos => Datos, tocado => os:system_time(second)},
    ets:insert(?TAB_VUELOS, {Id, Info}),
    _ = tomar_foto(),
    {noreply, State};
handle_cast({borrar_vuelo, Id}, State) ->
    ets:delete(?TAB_VUELOS, Id),
    _ = tomar_foto(),
    {noreply, State};
handle_cast({contador, Nombre, Delta}, State) ->
    ets:insert(?TAB_STATS,
               {Nombre, leer_contador(Nombre) + Delta}),
    {noreply, State};
handle_cast(_Otro, State) ->
    {noreply, State}.

handle_call({tomar_puerta, Puerta, IdVuelo}, _From, State) ->
    case ets:insert_new(?TAB_PUERTAS, {Puerta, IdVuelo}) of
        true ->
            _ = tomar_foto(),
            {reply, ok, State};
        false ->
            {reply, {error, ocupada}, State}
    end;
handle_call({soltar_puerta, Puerta}, _From, State) ->
    ets:delete(?TAB_PUERTAS, Puerta),
    _ = tomar_foto(),
    {reply, ok, State};
handle_call(mostrar, _From, State) ->
    {reply,
     #{vuelos => ets:tab2list(?TAB_VUELOS),
       puertas => ets:tab2list(?TAB_PUERTAS),
       stats => ets:tab2list(?TAB_STATS)},
     State};
handle_call(limpiar, _From, State) ->
    ets:delete_all_objects(?TAB_VUELOS),
    ets:delete_all_objects(?TAB_PUERTAS),
    ets:delete_all_objects(?TAB_STATS),
    persistent_term:erase(?KEY_FOTO),
    borrar_archivo(),
    {reply, ok, State};
handle_call(_Otros, _From, State) ->
    {reply, ok, State}.

handle_info(_Info, State) ->
    {noreply, State}.

%% --- interno -------------------------------------------------------

%% Guarda una foto completa del respaldo: en persistent_term (reinicio
%% de procesos) y, si esta configurado, en disco (reinicio de la VM).
tomar_foto() ->
    Foto = #{vuelos => ets:tab2list(?TAB_VUELOS),
             puertas => ets:tab2list(?TAB_PUERTAS),
             stats => ets:tab2list(?TAB_STATS)},
    persistent_term:put(?KEY_FOTO, Foto),
    persistir_foto(Foto).

%% La foto vigente: primero memoria (mas nueva), luego disco (VM nueva).
foto_inicial() ->
    case persistent_term:get(?KEY_FOTO, no_hay) of
        no_hay -> leer_archivo();
        Foto -> Foto
    end.

leer_archivo() ->
    case persistir() of
        false ->
            no_hay;
        true ->
            case file:read_file(archivo()) of
                {ok, Bin} ->
                    %% Sin [safe]: la foto incluye atomos creados en
                    %% runtime (p. ej. puerta_7 o los estados) que en
                    %% una VM recien arrancada todavia no existen, y
                    %% [safe] los rechaza. Es un archivo local propio,
                    %% no entrada de usuario.
                    try binary_to_term(Bin) of
                        #{vuelos := _, puertas := _, stats := _} = Foto ->
                            logger:info("~s foto recuperada de ~s",
                                        [?MODULE, archivo()]),
                            Foto;
                        _ ->
                            no_hay
                    catch _:_ ->
                        logger:warning("~s: archivo de respaldo corrupto", [?MODULE]),
                        no_hay
                    end;
                {error, _} ->
                    no_hay
            end
    end.

persistir_foto(Foto) ->
    case persistir() of
        false ->
            ok;
        true ->
            Ruta = archivo(),
            try
                ok = filelib:ensure_dir(Ruta),
                case file:write_file(Ruta, term_to_binary(Foto, [compressed])) of
                    ok ->
                        ok;
                    {error, Razon} ->
                        logger:warning("~s: no se pudo escribir ~s: ~p",
                                       [?MODULE, Ruta, Razon]),
                        ok
                end
            catch ClaseC:RazonC ->
                logger:warning("~s: fallo al persistir ~s: ~p:~p",
                               [?MODULE, Ruta, ClaseC, RazonC]),
                ok
            end
    end.

borrar_archivo() ->
    case persistir() of
        false ->
            ok;
        true ->
            case file:delete(archivo()) of
                ok -> ok;
                {error, enoent} -> ok;
                {error, Razon} ->
                    logger:warning("~s: no se pudo borrar ~s: ~p",
                                   [?MODULE, archivo(), Razon]),
                    ok
            end
    end.

persistir() ->
    application:get_env(p22_torre_de_control_tij, persistir, false).

archivo() ->
    application:get_env(p22_torre_de_control_tij, archivo_respaldo,
                        ?ARCHIVO_DEFECTO).
