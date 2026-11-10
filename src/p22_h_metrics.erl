%% ===================================================================
%% @doc p22_h_metrics — `GET /metrics`.
%%
%% Mapa de monitoreo con:
%%   - vuelos por estado (desde el respaldo, compatible con lo vivo),
%%   - puertas libres/ocupadas/total,
%%   - eventos por minuto (ventana del feed),
%%   - clientes de tablero conectados,
%%   - contadores acumulados de eventos por tipo,
%%   - ping del bus (resiliencia) y uptime.
%% Formato: JSON (facil de presentar el dia de la demo).
%% ===================================================================
-module(p22_h_metrics).

-export([init/2]).

init(Req0, State) ->
    %% Conteo de vuelos por estado, con todos los estados del dominio
    %% presentes (aunque esten en cero) para que el panel sea estable.
    Cero = [{E, 0} || E <- p22_util:camelize_estados()],
    Cuenta =
        lists:foldl(
          fun(Estado, Acc) ->
             maps:update_with(Estado, fun(N) -> N + 1 end, 0, Acc)
          end,
          maps:from_list(Cero),
          [maps:get(estado, Info)
           || {_, Info} <- p22_respaldo:todos_vuelos(),
              maps:is_key(estado, Info)]),
    Puertas = seguro(fun p22_puertas:estado_completo/0,
                     #{total => 0, libres => [], ocupadas => []}),
    EventosMin =
        case seguro(fun p22_feed:metricas/0, #{}) of
            #{eventos_por_minuto := N} -> N;
            _ -> 0
        end,
    Contadores =
        [#{nombre => nombre_legible(Clave), valor => Valor}
         || {Clave, Valor} <- p22_respaldo:leer_todos_los_contadores()],
    Uptime =
        case application:get_env(p22_torre_de_control_tij, inicio_en) of
            {ok, S} -> os:system_time(second) - S;
            _ -> 0
        end,
    Metricas =
        #{ok => true,
          vuelos =>
              #{total => length(p22_respaldo:todos_vuelos()),
                por_estado => Cuenta},
          puertas =>
              #{total => maps:get(total, Puertas),
                libres => length(maps:get(libres, Puertas)),
                ocupadas => maps:size(maps:from_list(maps:get(ocupadas, Puertas)))},
          eventos_por_minuto => EventosMin,
          clientes_tablero =>
              max(0, p22_respaldo:leer_contador(clientes_tablero)),
          contadores => Contadores,
          bus => bus_estado(),
          sistema => diagnostico(),
          uptime_segundos => Uptime},
    {ok, p22_http:json(Req0, Metricas), State}.

%% Estado del bus sin tumbar /metrics si esta reiniciando.
bus_estado() ->
    try p22_eventos:ping() of
        pong -> <<"ok">>;
        _ -> <<"sin respuesta">>
    catch _:_ -> <<"sin respuesta">>
    end.

%% Diagnostico ligero con recon: los procesos que mas memoria y
%% reducciones consumen. Util para explicar el arbol OTP en la demo.
diagnostico() ->
    #{procesos => erlang:system_info(process_count),
      memoria_total => erlang:memory(total),
      top_memoria => top(seguro(fun() -> recon:proc_count(memory, 5) end, [])),
      top_reducciones =>
          top(seguro(fun() -> recon:proc_count(reductions, 5) end, []))}.

%% recon:proc_count/2 devuelve {Pid, Valor, Info}; el tercer campo no
%% se publica (solo el nombre del proceso y el valor).
top(Lista) ->
    [#{proceso => list_to_binary(pid_to_list(Pid)), valor => Valor}
     || {Pid, Valor, _Info} <- Lista].

%% Llama a un servicio del dominio sin tumbar el handler si esta entre
%% reinicios (p. ej. durante la prueba de caos).
seguro(Fun, PorDefecto) ->
    try Fun()
    catch _:_ -> PorDefecto
    end.

%% Los contadores con clave compuesta {tipo, T} se muestran como
%% "tipo_T" para que JSON sea plano.
nombre_legible({tipo, T}) ->
    unicode:characters_to_binary("tipo_" ++ atom_to_list(T));
nombre_legible(T) when is_atom(T) ->
    atom_to_binary(T, utf8).
