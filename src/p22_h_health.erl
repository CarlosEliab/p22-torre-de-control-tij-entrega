%% ===================================================================
%% @doc p22_h_health — `GET /health`.
%%
%% Sonda barata para AWS (Target Group / systemd / curl). No consulta
%% el respaldo ni bloquea: solo confirma que el nodo y el listener
%% estan vivos. Para metricas completas usar `GET /metrics`.
%% ===================================================================
-module(p22_h_health).

-export([init/2]).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            {UptimeMs, _DesdeUltimaLlamada} = erlang:statistics(wall_clock),
            Cuerpo = #{ok => true,
                       servicio => <<"p22-torre-de-control-tij">>,
                       uptime_ms => UptimeMs},
            {ok, p22_http:json(Req0, 200, Cuerpo), State};
        _ ->
            {ok, p22_http:json(Req0, 405,
                               #{ok => false, error => <<"metodo no permitido">>}),
             State}
    end.
