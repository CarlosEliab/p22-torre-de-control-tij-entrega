%% ===================================================================
%% @doc Pruebas del ASIGNADOR DE PUERTAS (proyecto 22).
%%
%% El escenario del problema habla de un recurso criticos y finito:
%% aqui validamos asignacion, liberacion, idempotencia y
%% AGOTAMIENTO (la 21a puerta no existe).
%% ===================================================================
-module(p22_puertas_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    p22_test_ayudante:levantar_dominio().

teardown(_X) ->
    p22_test_ayudante:bajar_dominio().

total() ->
    application:get_env(p22_torre_de_control_tij, puertas_total, 20).

%% Asignacion normal: cuenta disponible decrece.
%% Agotamiento: pedir UNA mas que el total falla con no_disponible.
asignar_y_agotamiento_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun() ->
         Total = total(),
         Res = [p22_puertas:asignar(99000 + I) || I <- lists:seq(1, Total)],
         Ocupadas = [ok || {ok, _} <- Res],
         ?assertEqual(Total, length(Ocupadas)),
         %% el saco esta vacio
         ?assertEqual({error, no_disponible}, p22_puertas:asignar(99999)),
         %% liberar una y volver a pedir ya funciona
         VueloLibre = 99000 + 1,
         {ok, _Puerta} = p22_puertas:liberar(VueloLibre),
         {ok, _} = p22_puertas:asignar(99999)
      end]}.

%% distintos vuelos NUNCA comparten puerta (insert_new lo garantiza,
%% y lo verificamos con respaldo: mapa puerta->vuelo sin colisiones)
sin_colisiones_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun() ->
         Res = [p22_puertas:asignar(99000 + I) || I <- lists:seq(1, 10)],
         Lista = [{ok, P} || {ok, P} <- Res],
         Puertas = [P || {ok, P} <- Lista],
         ?assertEqual(10, length(Puertas)),
         ?assertEqual(length(Puertas),
                      length(lists:usort(Puertas)))   % todas distintas
      end]}.

%% liberar un vuelo que no tiene puerta responde sin explotar.
liberar_sin_puerta_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun() ->
          ?assertEqual({error, sin_puerta}, p22_puertas:liberar(31337))
      end]}.

%% reconstruccion: si matan a p22_puertas, al volver a arrancarlo
%% (lo que hace el supervisor rest_for_one), la ocupacion se debe
%% recuperar desde el respaldo.
recuperacion_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun() ->
          {ok, P1} = p22_puertas:asignar(99001),
          Old = whereis(p22_puertas),
          %% desembarcamo: quitamos el enlace para que la muerte NO
          %% tumbe al proceso de prueba (como hace el supervisor real)
          unlink(Old),
          exit(Old, kill),
          p22_test_ayudante:esperar(50),
          %% el proceso muerto ya no existe,
          ?assertEqual(undefined, whereis(p22_puertas)),
          %% re-arranque desde el jefe (lo que hace el supervisor al reiniciar)
          {ok, _} = p22_test_ayudante:arrancar(p22_puertas),
          %% y la ocupacion de esa puerta sigue ahi (desde el respaldo)
          Ocupadas = p22_puertas:ocupadas(),
          ?assert(maps:is_key(P1, Ocupadas)),
          ?assertEqual(99001, maps:get(P1, Ocupadas))
      end]}.

%% pruebas de nombre del supervisor cultural: p22_eventos responde.
bus_responde_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun() ->
          ?assertEqual(pong, p22_eventos:ping()),
          ok = p22_eventos:suscribir(self()),
          ?assertEqual([self()], p22_eventos:clientes()),
          ok = p22_eventos:desuscribir(self()),
          ?assertEqual([], p22_eventos:clientes())
      end]}.

%% Asignacion de una puerta CONCRETA (cambio de puerta): idempotente
%% para el mismo vuelo, rechaza la de otro y valida que exista.
asignar_puerta_concreta_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun() ->
          {ok, A} = p22_puertas:asignar(99101),
          {ok, B} = p22_puertas:asignar(99102),
          ?assertNotEqual(A, B),
          %% A es de 99101: no se puede dar a 99102
          ?assertEqual({error, {puerta_ocupada, 99101}},
                       p22_puertas:asignar(A, 99102)),
          %% pedir la propia es idempotente
          ?assertEqual({ok, B}, p22_puertas:asignar(B, 99102)),
          %% liberar SOLO la propia
          ?assertEqual({error, no_es_tuya}, p22_puertas:liberar(A, 99102)),
          ?assertEqual({ok, B}, p22_puertas:liberar(B, 99102)),
          ?assertNot(maps:is_key(B, p22_puertas:ocupadas())),
          %% puerta que no existe en el aeropuerto
          ?assertEqual({error, puerta_invalida},
                       p22_puertas:asignar(puerta_999, 99103))
      end]}.
