%% ===================================================================
%% @doc Pruebas de la MAQUINA DE ESTADOS (proyecto 22).
%%
%% Cubre:
%%   - el ciclo de vida legal completo (programado->...->aterrizado)
%%   - el rechazo de transiciones ilegales (con la razon exacta)
%%   - la demora AUTOMATICA cuando no hay puertas disponibles
%%   - los casos dificiles: mensajes fuera de orden y jerarquia de
%%     fuentes (una "aerolinea" no puede descarrilar un estado
%%     emitido por la "torre")
%%   - la liberacion de la puerta en despegue y cancelacion
%%   - la bitacora (historial) del vuelo
%% ===================================================================
-module(p22_vuelo_statem_tests).

-include_lib("eunit/include/eunit.hrl").

%% Helpers -----------------------------------------------------------

spec(Id) ->
    #{id => Id,
      identificacion => <<"TJ-100">>,
      aeronave => <<"XA-TIJ">>,
      aerolinea => <<"Volaris">>,
      destino => <<"CDMX">>,
      hora_programada => os:system_time(second) + 600}.

iniciar_vuelo(Id) ->
    {ok, _Pid} = p22_vuelos_sup:iniciar(spec(Id)),
    p22_test_ayudante:esperar(100).

setup() ->
    p22_test_ayudante:levantar_dominio(),
    ok.

teardown(_X) ->
    p22_test_ayudante:bajar_dominio().

asignar(Id, Seq, Accion) ->
    p22_vuelo_statem:transicion(Id, sistema, Seq, Accion).

puerta_de(Id) ->
    Ocupadas = maps:to_list(p22_puertas:ocupadas()),
    case [P || {P, V} <- Ocupadas, V =:= Id] of
        [P | _] -> {ok, P};
        [] -> {error, sin_puerta}
    end.

%% --------------------------------------------------------------------
%% 1. ciclo de vida completo
%% --------------------------------------------------------------------

ciclo_completo_test() ->
    {foreach,
     fun() -> setup(), iniciar_vuelo(101) end,
     fun teardown/1,
     [fun() ->
          ?assertEqual('programado', p22_vuelo_statem:estado(101)),
          ?assertEqual({ok, 'abordando'}, asignar(101, 1, empezar_abordaje)),
          ?assertEqual({ok, 'despego'}, asignar(101, 2, despegar)),
          ?assertEqual({ok, 'aterrizado'}, asignar(101, 3, aterrizar)),
          ?assertEqual('aterrizado', p22_vuelo_statem:estado(101))
      end]}.

%% --------------------------------------------------------------------
%% 2. puertas: asignar al abordar, liberar al despegar
%% --------------------------------------------------------------------

puerta_en_abordaje_test() ->
    {foreach,
     fun() -> setup(), iniciar_vuelo(102) end,
     fun teardown/1,
     [fun() ->
          ?assertEqual({ok, 'abordando'}, asignar(102, 1, empezar_abordaje)),
          {ok, Puerta} = puerta_de(102),
          ?assert(is_atom(Puerta)),
          %% al despegar la puerta SE LIBERA
          ?assertEqual({ok, 'despego'}, asignar(102, 2, despegar)),
          ?assertEqual({error, sin_puerta}, puerta_de(102))
      end]}.

%% --------------------------------------------------------------------
%% 3. sin puertas el abordaje se convierte en DEMORA automatica
%% --------------------------------------------------------------------

sin_puertas_demora_test() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun() ->
          %% ocupamos TODAS las puertas con "vuelos" de soporte
          Asignadas = [p22_puertas:asignar(99000 + I)
                       || I <- lists:seq(1, 20)],
          ?assertEqual(20, length([ok || {ok, _} <- Asignadas])),
          iniciar_vuelo(103),
          {ok, 'demorado'} = asignar(103, 1, empezar_abordaje),
          Vista = p22_vuelo_statem:completo(103),
          ?assertEqual(15, maps:get(demora_min, Vista)),
          ?assertEqual(<<"sin_puerta">>, hd(maps:get(motivos, Vista)))
      end]}.

%% --------------------------------------------------------------------
%% 4. transiciones ilegales (con razon)
%% --------------------------------------------------------------------

transiciones_ilegales_test() ->
    {foreach,
     fun() -> setup(), iniciar_vuelo(104) end,
     fun teardown/1,
     [fun() ->
          %% desde 'programado' no se puede despegar directo
          ?assertEqual({error, {transicion_no_legal, 'programado', despegar}},
                       asignar(104, 1, despegar)),
          ?assertEqual('programado', p22_vuelo_statem:estado(104)),
          %% una demora NO puede saltar directo a despegar
          ?assertEqual({ok, 'demorado'},
                       p22_vuelo_statem:transicion(104, torre, 2, demorar,
                                                   #{minutos => 5,
                                                     motivo => <<"prueba">>})),
          ?assertEqual({error, {transicion_no_legal, 'demorado', despegar}},
                       asignar(104, 3, despegar)),
          ?assertEqual('demorado', p22_vuelo_statem:estado(104))
      end]}.

%% --------------------------------------------------------------------
%% 5. caso dificil: mensajes FUERA DE ORDEN
%% --------------------------------------------------------------------

fuera_de_orden_test() ->
    {foreach,
     fun() -> setup(), iniciar_vuelo(105) end,
     fun teardown/1,
     [fun() ->
          ?assertEqual({ok, 'abordando'}, asignar(105, 1, empezar_abordaje)),
          %% seq 0 SIEMPRE es vieja (secuencias arrancan en 1)
          ?assertEqual({error, secuencia_repetida},
                       p22_vuelo_statem:transicion(105, aerolinea, 0, despegar)),
          %% repetir la misma seq de la misma fuente NO pasa
          ?assertEqual({error, secuencia_repetida},
                       asignar(105, 1, despegar)),
          %% el estado sigue intacto
          ?assertEqual('abordando', p22_vuelo_statem:estado(105)),
          %% una secuencia nueva de la misma fuente si avanza
          ?assertEqual({ok, 'despego'}, asignar(105, 2, despegar))
      end]}.

%% --------------------------------------------------------------------
%% 6. caso dificil: jerarquia de fuentes
%% --------------------------------------------------------------------

autoridad_de_fuentes_test() ->
    {foreach,
     fun() -> setup(), iniciar_vuelo(106) end,
     fun teardown/1,
     [fun() ->
          %% la TORRE declara la demora (autoridad 3)
          ?assertEqual({ok, 'demorado'},
                       p22_vuelo_statem:transicion(106, torre, 1, demorar,
                                                   #{minutos => 10,
                                                     motivo => <<"pista">>})),
          %% la AEROLINEA (2) no puede revocar el estado de la torre
          ?assertEqual({error, autoridad_insuficiente},
                       p22_vuelo_statem:transicion(106, aerolinea, 2,
                                                   empezar_abordaje)),
          ?assertEqual('demorado', p22_vuelo_statem:estado(106)),
          %% la TORRE si puede terminar la demora
          ?assertEqual({ok, 'programado'},
                       p22_vuelo_statem:transicion(106, torre, 3, fin_demora)),
          ?assertEqual('programado', p22_vuelo_statem:estado(106))
      end]}.

%% --------------------------------------------------------------------
%% 7. cancelar: terminal + puerta liberada
%% --------------------------------------------------------------------

cancelar_test() ->
    {foreach,
     fun() -> setup(), iniciar_vuelo(107) end,
     fun teardown/1,
     [fun() ->
          ?assertEqual({ok, 'abordando'}, asignar(107, 1, empezar_abordaje)),
          {ok, Puerta} = puerta_de(107),
          ?assert(is_atom(Puerta)),
          ?assertEqual({ok, 'cancelado'},
                       p22_vuelo_statem:transicion(107, torre, 2, cancelar,
                                                   #{motivo => <<"demo">>})),
          %% terminal: NADA mas se acepta
          ?assertEqual('cancelado', p22_vuelo_statem:estado(107)),
          ?assertEqual({error,
                        {transicion_no_legal, 'cancelado', empezar_abordaje}},
                       p22_vuelo_statem:transicion(107, torre, 3,
                                                   empezar_abordaje)),
          %% la puerta quedo libre
          ?assertEqual({error, sin_puerta}, puerta_de(107))
      end]}.

%% --------------------------------------------------------------------
%% 8. historial: todo lo dicho queda en la bitacora del vuelo
%% --------------------------------------------------------------------

historial_test() ->
    {foreach,
     fun() -> setup(), iniciar_vuelo(108) end,
     fun teardown/1,
     [fun() ->
          _ = asignar(108, 1, empezar_abordaje),
          _ = asignar(108, 2, despegar),
          Vista = p22_vuelo_statem:completo(108),
          H = maps:get(historial, Vista),
          ?assert(length(H) >= 3),      % + la "alta del vuelo"
          [Ultimo | _] = H,
          ?assertEqual(despego, maps:get(hacia, Ultimo)),
          ?assert(is_integer(maps:get(ts, Ultimo))),
          ?assert(is_binary(maps:get(detalle, Ultimo)))
      end]}.

%% --------------------------------------------------------------------
%% 9. caso dificil: cambia de PUERTA y de HORA a la vez
%% --------------------------------------------------------------------

cambio_puerta_y_hora_test() ->
    {foreach,
     fun() -> setup(), iniciar_vuelo(109) end,
     fun teardown/1,
     [fun() ->
          ?assertEqual({ok, 'abordando'}, asignar(109, 1, empezar_abordaje)),
          {ok, Vieja} = puerta_de(109),
          [Nueva | _] = [P || P <- p22_puertas:disponibles(), P =/= Vieja],
          %% UNA sola transicion cambia puerta y suma 15 min
          ?assertEqual({ok, 'abordando'},
                       p22_vuelo_statem:transicion(
                         109, torre, 2, cambiar_puerta,
                         #{puerta => Nueva, minutos => 15,
                           motivo => <<"cambio de puerta">>})),
          %% la vieja quedo libre y la nueva es suya
          ?assertEqual({ok, Nueva}, puerta_de(109)),
          ?assertNot(maps:is_key(Vieja, p22_puertas:ocupadas())),
          ?assertEqual(109, maps:get(Nueva, p22_puertas:ocupadas())),
          Vista = p22_vuelo_statem:completo(109),
          ?assertEqual('abordando', maps:get(estado, Vista)),
          ?assertEqual(Nueva, maps:get(puerta, Vista)),
          ?assertEqual(15, maps:get(demora_min, Vista)),
          ?assertEqual(maps:get(hora_programada, Vista) + 15 * 60,
                       maps:get(hora_estimada, Vista)),
          ?assert(lists:member(<<"cambio de puerta">>,
                               maps:get(motivos, Vista)))
      end]}.

%% La puerta pedida ya es de OTRO vuelo: se rechaza y no se toca nada.
cambio_puerta_ocupada_test() ->
    {foreach,
     fun() -> setup(), iniciar_vuelo(110), iniciar_vuelo(111) end,
     fun teardown/1,
     [fun() ->
          ?assertEqual({ok, 'abordando'}, asignar(110, 1, empezar_abordaje)),
          ?assertEqual({ok, 'abordando'}, asignar(111, 1, empezar_abordaje)),
          {ok, P110} = puerta_de(110),
          {ok, P111} = puerta_de(111),
          ?assertNotEqual(P110, P111),
          ?assertEqual({error, {puerta_ocupada, 111}},
                       p22_vuelo_statem:transicion(
                         110, torre, 2, cambiar_puerta,
                         #{puerta => P111, minutos => 10})),
          ?assertEqual({ok, P110}, puerta_de(110)),
          ?assertEqual({ok, P111}, puerta_de(111)),
          ?assertEqual('abordando', p22_vuelo_statem:estado(110))
      end]}.

%% Puerta inexistente y accion ilegal despues de despegar.
cambio_puerta_rechazos_test() ->
    {foreach,
     fun() -> setup(), iniciar_vuelo(112) end,
     fun teardown/1,
     [fun() ->
          ?assertEqual({error, puerta_invalida},
                       p22_vuelo_statem:transicion(
                         112, torre, 1, cambiar_puerta,
                         #{puerta => puerta_999})),
          ?assertEqual('programado', p22_vuelo_statem:estado(112)),
          ?assertEqual({ok, 'abordando'}, asignar(112, 2, empezar_abordaje)),
          ?assertEqual({ok, 'despego'}, asignar(112, 3, despegar)),
          ?assertEqual({error, {transicion_no_legal, 'despego', cambiar_puerta}},
                       p22_vuelo_statem:transicion(
                         112, torre, 4, cambiar_puerta, #{minutos => 5}))
      end]}.
