%% ===================================================================
%% @doc p22_torre_de_control_tij_sup — supervisor RAIZ del proyecto 22.
%%
%% Estrategia `rest_for_one`: los hijos se arrancan EN ORDEN y si uno
%% muere se reinician el y TODOS los que dependen de el.
%%
%%   1. p22_respaldo     — tablas ETS: ultimo estado de cada vuelo.
%%                         Si muere, los vuelos necesitan re-anclarse,
%%                         asi que todos los que dependen reinician.
%%   2. p22_eventos      — bus de eventos -> WebSocket + contadores.
%%   3. p22_puertas      — asignador de puertas (recurso compartido).
%%   4. p22_vuelos_sup   — supervisor DINAMICO de vuelos (1 proceso
%%                         gen_statem por vuelo).
%%   5. p22_feed         — operacion simulada (crea/avanza/inyecta).
%%   6. p22_web          — API + WebSocket del tablero.
%%
%% ¿Por que el asignador de puertas DENTRO de la cadena de vuelos?
%% Un vuelo que muere se reconstruye PIDIENDO su puerta de nuevo al
%% asignador; si el asignador muriera y los vuelos no noticieran, las
%% cuentas de ocupacion quedarian sucias. rest_for_one garantiza que,
%% si las puertas reinician, todos los vuelos y el feed re-sincronizan.
%% ===================================================================
-module(p22_torre_de_control_tij_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        #{id => p22_respaldo,
          start => {p22_respaldo, start_link, []},
          restart => permanent, shutdown => 5000, type => worker},
        #{id => p22_eventos,
          start => {p22_eventos, start_link, []},
          restart => permanent, shutdown => 5000, type => worker},
        #{id => p22_puertas,
          start => {p22_puertas, start_link, []},
          restart => permanent, shutdown => 5000, type => worker},
        #{id => p22_vuelos_sup,
          start => {p22_vuelos_sup, start_link, []},
          restart => permanent, shutdown => 5000, type => supervisor},
        #{id => p22_feed,
          start => {p22_feed, start_link, []},
          restart => permanent, shutdown => 5000, type => worker},
        #{id => p22_web,
          start => {p22_web, start_link, []},
          restart => permanent, shutdown => 5000, type => worker}
    ],
    {ok,
     {#{strategy => rest_for_one, intensity => 10, period => 60},
      Children}}.
