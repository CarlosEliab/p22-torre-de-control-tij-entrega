%% ===================================================================
%% @doc p22_vuelos_sup — supervisor DINAMICO de vuelos (simple_one_for_one).
%%
%% ¿Por que simple_one_for_one?
%%   - El numero de vuelos cambia todo el tiempo (120/dia en el
%%     escenario, picos de 10 movimientos/hora); no conocemos la lista
%%     de hijos en compilacion.
%%   - Todos los vuelos arrancan con la MISMA estructura de argumentos
%%     y comportamiento (mismo modulo gen_statem).
%%   - Con `restart => permanent` un vuelo que muera se reconstruye
%%     automaticamente con sus mismos argumentos de arranque; el
%%     modulo `p22_vuelo_statem` consulta el respaldo en su init para
%%     re-entrar en el ULTIMO estado conocido (no el inicial).
%%
%% Orden de arranque en el arbol (supervisor raiz, rest_for_one):
%%   p22_respaldo -> p22_eventos -> p22_puertas -> ESTE -> p22_feed -> p22_web
%% Asi los vuelos siempre tienen respaldo, bus y puertas vivos.
%% ===================================================================
-module(p22_vuelos_sup).

-behaviour(supervisor).

-export([start_link/0, iniciar/1, terminar/1, contar/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Arranca UN vuelo. Spec es el mapa de datos del vuelo:
%%   #{id => Entero, identificacion => binario, aeronave => binario,
%%     aerolinea => binario, destino => binario, hora_programada => segs}
%% El hijo es `permanent`: aunque su vida es dinamica, el supervisor
%% DEBE volver a arrancarlo si muere (resiliencia frente al caos).
iniciar(Spec) ->
    supervisor:start_child(?MODULE, [Spec]).

%% @doc Detiene definitivamente un vuelo (terminal: aterrizado o
%% cancelado) y borra su imagen del respaldo. El supervisor dinamico lo
%% elimina sin reiniciarlo, aunque su restart sea `permanent'.
terminar(Id) ->
    case p22_vuelo_statem:pid_de(Id) of
        undefined ->
            p22_respaldo:borrar_vuelo(Id),
            ok;
        Pid ->
            _ = supervisor:terminate_child(?MODULE, Pid),
            p22_respaldo:borrar_vuelo(Id),
            ok
    end.

%% @doc Cuantos vuelos vivos hay ahora mismo.
contar() ->
    case supervisor:which_children(?MODULE) of
        L when is_list(L) -> length(L);
        _ -> 0
    end.

init([]) ->
    SupFlags =
        #{strategy => simple_one_for_one,
          intensity => 20,        % hasta 20 reinicios en 60 s: los vuelos son muchos
          period => 60},
    Child =
        #{id => p22_vuelo_statem,
          start => {p22_vuelo_statem, start_link, []},
          restart => permanent,
          shutdown => brutal_kill,   % al reiniciar el sup no esperamos a los vuelos
          type => worker},
    {ok, {SupFlags, [Child]}}.
