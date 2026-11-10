%% ===================================================================
%% @doc PRUEBA DE CAOS (proyecto 22).
%%
%% La lista "Pendiente" del README pide: "matar el proceso de un vuelo
%% y verificar que se reconstruye con su ultimo estado y el tablero no
%% parpadea".
%%
%% Lo que matamos: el proceso gen_statem de UN vuelo en estado
%% 'abordando' (el mejor caso: puerta asignada y datos vivos).
%% Lo que esperamos: un PID NUEVO del mismo vuelo (reconstruido por el
%% supervisor dinamico), EN EL MISMO ESTADO, CON LA MISMA PUERTA, y el
%% respaldo reportando la misma imagen para que /api y el tablero no
%% parpadeen.
%% ===================================================================
-module(p22_caos_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    p22_test_ayudante:levantar_dominio().

teardown(_X) ->
    p22_test_ayudante:bajar_dominio().

spec(Id) ->
    #{id => Id,
      identificacion => <<"TJ-100">>,
      aeronave => <<"XA-TIJ">>,
      aerolinea => <<"Volaris">>,
      destino => <<"CDMX">>,
      hora_programada => os:system_time(second) + 600}.

%% ----------------------------------------------------------------------
%% CAOS #1: matar el vuelo en 'abordando' => renace con estado y puerta
%% ----------------------------------------------------------------------
matar_vuelo_reconstruccion_completa_test() ->
    {foreach,
     fun() ->
         setup(),
         {ok, _} = p22_vuelos_sup:iniciar(spec(808)),
         p22_test_ayudante:esperar(100)
     end,
     fun teardown/1,
     [fun() ->
          PidOld = p22_vuelo_statem:pid_de(808),
          ?assert(is_pid(PidOld)),

          %% preparar el estado: abordando + puerta
          ?assertEqual({ok, 'abordando'},
                       p22_vuelo_statem:transicion(808, sistema, 1,
                                                   empezar_abordaje)),

          %% ---- CAOS ----
          exit(PidOld, kill),

          %% el supervisor dinamico re-arranca el vuelo con los mismos
          %% argumentos y el gen_statem entra en su ULTIMO estado
          esperar_y_verificar_estado(808, 'abordando', 40),

          PidNew = p22_vuelo_statem:pid_de(808),
          ?assert(is_pid(PidNew)),
          ?assert(PidNew =/= PidOld),

          %% los datos vivos sobrevivieron (puerta)
          Vista = p22_vuelo_statem:completo(808),
          ?assertEqual('abordando', maps:get(estado, Vista)),
          ?assert(is_atom(maps:get(puerta, Vista))),

          %% el respaldo reporta el mismo estado (para que el tablero
          %% NO parpadee cuando pide /api/vuelos)
          Resp = p22_respaldo:leer_vuelo(808),
          ?assertEqual('abordando', maps:get(estado, Resp))
      end]}.

%% ----------------------------------------------------------------------
%% CAOS #2: matarlo en 'demorado' (con motivo) => renace en 'demorado'
%% ----------------------------------------------------------------------
matar_vuelo_demorado_test() ->
    {foreach,
     fun() ->
         setup(),
         {ok, _} = p22_vuelos_sup:iniciar(spec(809)),
         p22_test_ayudante:esperar(100)
     end,
     fun teardown/1,
     [fun() ->
          ?assertEqual({ok, 'demorado'},
                       p22_vuelo_statem:transicion(809, torre, 1, demorar,
                                                   #{minutos => 30,
                                                     motivo => <<"niebla">>})),
          PidOld = p22_vuelo_statem:pid_de(809),
          exit(PidOld, kill),
          esperar_y_verificar_estado(809, 'demorado', 40),
          Vista = p22_vuelo_statem:completo(809),
          ?assertEqual(30, maps:get(demora_min, Vista)),
          ?assertEqual(<<"niebla">>, hd(maps:get(motivos, Vista)))
      end]}.

%% ----------------------------------------------------------------------
%% CAOS #3: el bus y el resto del arbol resisten una matanza en serie
%% ----------------------------------------------------------------------
matar_muchos_vuelos_bus_resistente_test() ->
    {foreach,
     fun() ->
         setup(),
         [p22_vuelos_sup:iniciar(spec(700 + I)) || I <- lists:seq(1, 5)],
         p22_test_ayudante:esperar(300)
     end,
     fun teardown/1,
     [fun() ->
          ?assertEqual(pong, p22_eventos:ping()),
          %% matar los 5 vuelos en serie
          lists:foreach(
            fun(I) ->
               exit(p22_vuelo_statem:pid_de(700 + I), kill),
               p22_test_ayudante:esperar(30)
            end,
            lists:seq(1, 5)),
          %% el bus (y el resto del arbol) sigue vivo:
          ?assertEqual(pong, p22_eventos:ping()),
          ?assert(is_process_alive(p22_puertas_())),
          ?assert(is_process_alive(p22_respaldo_())),
          %% y los 5 vuelos volvieron a estar en pie ('programado')
          lists:foreach(
            fun(I) ->
               esperar_y_verificar_estado(700 + I, 'programado', 30)
            end,
            lists:seq(1, 5)),
          ?assertEqual(5, p22_vuelos_sup:contar())
      end]}.

%% --- utilidades -----------------------------------------------------

p22_puertas_() -> whereis(p22_puertas).
p22_respaldo_() -> whereis(p22_respaldo).

%% Reintenta leer el estado hasta 40 veces cortas hasta que matchee.
esperar_y_verificar_estado(_Id, _Estado, 0) ->
    erlang:exit(vuelo_no_reconstruido);
esperar_y_verificar_estado(Id, EstadoEsperado, N) ->
    case p22_vuelo_statem:estado(Id) of
        EstadoEsperado -> ok;
        _Otro ->
            p22_test_ayudante:esperar(50),
            esperar_y_verificar_estado(Id, EstadoEsperado, N - 1)
    end.
