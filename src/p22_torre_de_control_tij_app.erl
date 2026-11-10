%% ===================================================================
%% @doc p22_torre_de_control_tij_app — aplicacion del proyecto 22.
%%
%% start/2 registra el tiempo de arranque (para /metrics) y levanta el
%% supervisor raiz (arbol OTP del dominio).
%% ===================================================================
-module(p22_torre_de_control_tij_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    application:set_env(p22_torre_de_control_tij, inicio_en,
                        os:system_time(second)),
    p22_torre_de_control_tij_sup:start_link().

stop(_State) ->
    ok.
