%% ===================================================================
%% @doc Pruebas de INTEGRACION (proyecto 22): arbol completo incluido
%% el servidor web, feed simulado y la API HTTP real.
%%
%% Se arranca el supervisor RAIZ (rest_for_one) con puerto EFIMERO
%% (puerto 0) para no chocar con nada en la maquina de pruebas, y
%% se disparan peticiones HTTP de verdad con httpc (incluido en OTP).
%% ===================================================================
-module(p22_integracion_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    %% puerto 0 => el sistema operativo asigna uno libre
    application:set_env(p22_torre_de_control_tij, puerto, 0),
    application:set_env(p22_torre_de_control_tij, caos, false),
    %% Ritmo de prueba: perfil personalizado con tiempos minimos para
    %% que las pruebas no esperen los 15 s del perfil lento real.
    application:set_env(p22_torre_de_control_tij, perfil_simulacion,
                        personalizado),
    application:set_env(p22_torre_de_control_tij, feed_ms, 300),
    application:set_env(p22_torre_de_control_tij, nuevo_vuelo_cada_ms, 0),
    application:set_env(p22_torre_de_control_tij, espera_entrada_ms, 0),
    application:set_env(p22_torre_de_control_tij, abordaje_ms, 0),
    application:set_env(p22_torre_de_control_tij, vuelo_ms, 0),
    %% ranch/cowboy deben estar arriba (en la app real los monta OTP)
    {ok, _} = application:ensure_all_started(cowboy),
    p22_test_ayudante:limpiar_nombres(),
    p22_respaldo:limpiar(),
    {ok, _} = application:ensure_all_started(inets),
    {ok, Sup} = p22_torre_de_control_tij_sup:start_link(),
    p22_test_ayudante:esperar(300),
    Sup.

teardown(Sup) ->
    unlink(Sup),
    exit(Sup, shutdown),
    p22_test_ayudante:esperar(120).

puerto() ->
    ranch:get_port(p22_listener).

%% ----------------------------------------------------------------------
%% el arbol completo arriba + web: API, metricas y tablero
%% ----------------------------------------------------------------------
arbol_completo_web_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun(_Sup) ->
          [fun() ->
               _ = p22_feed:nuevo_vuelo(),
               p22_test_ayudante:esperar(100),

               %% GET /api/vuelos: lista con al menos un vuelo
               R = consultar(<<"GET">>, <<"/api/vuelos">>, <<>>),
               ?assertEqual(200, status(R)),
               Cuerpo = contenido(R),
               ?assertEqual(true, maps:get(<<"ok">>, Cuerpo)),
               ?assert(length(maps:get(<<"vuelos">>, Cuerpo)) >= 1),

               %% GET /metrics: responde con vuelos y puertas
               RM = consultar(<<"GET">>, <<"/metrics">>, <<>>),
               ?assertEqual(200, status(RM)),
               ?assert(maps:is_key(<<"vuelos">>, contenido(RM))),
               ?assert(maps:is_key(<<"puertas">>, contenido(RM))),
               %% demora promedio (la pide la rubrica del curso)
               ?assert(maps:is_key(<<"demoras">>, contenido(RM))),
               Demoras = maps:get(<<"demoras">>, contenido(RM)),
               ?assert(maps:is_key(<<"promedio_min">>, Demoras)),
               %% demora promedio (la pide la rubrica del curso)
               ?assert(maps:is_key(<<"demoras">>, contenido(RM))),
               Demoras = maps:get(<<"demoras">>, contenido(RM)),
               ?assert(maps:is_key(<<"promedio_min">>, Demoras)),

               %% GET /health: sonda de AWS/systemd
               RH = consultar(<<"GET">>, <<"/health">>, <<>>),
               ?assertEqual(200, status(RH)),
               ?assertEqual(true, maps:get(<<"ok">>, contenido(RH))),

               %% GET /: el tablero HTML
               RX = consultar(<<"GET">>, <<"/">>, <<>>),
               ?assertEqual(200, status(RX)),
               ?assertEqual(<<"text/html; charset=utf-8">>,
                            cabecera(RX, <<"content-type">>))
           end]
      end]}.

%% ----------------------------------------------------------------------
%% POST /api/vuelos/:id/estado: legal->200, ilegal->409, 404 si no existe
%% ----------------------------------------------------------------------
api_transicion_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun(_Sup) ->
          [fun() ->
               {ok, Id} = p22_feed:nuevo_vuelo(),
               p22_test_ayudante:esperar(80),
               IdBin = integer_to_binary(Id),

               %% transicion legal: empezar abordaje
               R = consultar(<<"POST">>,
                             <<"/api/vuelos/", IdBin/binary, "/estado">>,
                             <<"{\"accion\": \"empezar_abordaje\"}">>),
               ?assertEqual(200, status(R)),

               %% transicion ilegal: aterrizar sin haber despegado
               R2 = consultar(<<"POST">>,
                              <<"/api/vuelos/", IdBin/binary, "/estado">>,
                              <<"{\"accion\": \"aterrizar\"}">>),
               ?assertEqual(409, status(R2)),

               %% vuelo inexistente: 404
               R3 = consultar(<<"POST">>, <<"/api/vuelos/99999/estado">>,
                              <<"{\"accion\": \"cancelar\"}">>),
               ?assertEqual(404, status(R3))
           end]
      end]}.

%% ----------------------------------------------------------------------
%% el feed avanza vuelos por su cuenta (operacion simulada en vivo)
%% ----------------------------------------------------------------------
feed_avanza_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun(_Sup) ->
          [fun() ->
               {ok, Id} = p22_feed:nuevo_vuelo(),
               cambia_con_reintentos(Id, 20)
           end]
      end]}.

%% Espera con reintentos a que el feed mueva el vuelo del estado inicial.
%% `no_encontrado' es valido en la primera vuelta: el guardado inicial
%% del vuelo viaja como cast al respaldo y puede no estar procesado
%% todavia cuando la prueba recien arranca a mirar.
cambia_con_reintentos(_Id, 0) ->
    erlang:exit(feed_no_avanza);
cambia_con_reintentos(Id, N) ->
    case p22_respaldo:leer_vuelo(Id) of
        #{estado := 'programado'} ->
            p22_test_ayudante:esperar(500),
            cambia_con_reintentos(Id, N - 1);
        #{estado := _Otro} ->
            ok;
        no_encontrado ->
            p22_test_ayudante:esperar(100),
            cambia_con_reintentos(Id, N - 1)
    end.

%% ----------------------------------------------------------------------
%% API de simulacion: consultar estado, cambiar ritmo, pausar y reanudar
%% ----------------------------------------------------------------------
simulacion_api_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun(_Sup) ->
          [fun() ->
               %% estado inicial: el fixture usa perfil personalizado
               R = consultar(<<"GET">>, <<"/api/simulacion">>, <<>>),
               ?assertEqual(200, status(R)),
               S = maps:get(<<"simulacion">>, contenido(R)),
               ?assertEqual(<<"personalizado">>, maps:get(<<"perfil">>, S)),
               ?assertEqual(false, maps:get(<<"pausado">>, S)),

               %% cambiar a un perfil listo
               R2 = consultar(<<"POST">>, <<"/api/simulacion/ritmo">>,
                              <<"{\"perfil\":\"rapido\"}">>),
               ?assertEqual(200, status(R2)),
               S2 = maps:get(<<"simulacion">>, contenido(R2)),
               ?assertEqual(<<"rapido">>, maps:get(<<"perfil">>, S2)),
               ?assertEqual(3000, maps:get(<<"feed_ms">>, S2)),

               %% tiempo personalizado en segundos -> milisegundos
               R3 = consultar(<<"POST">>, <<"/api/simulacion/ritmo">>,
                              <<"{\"nuevo_vuelo_cada_seg\":2}">>),
               ?assertEqual(200, status(R3)),
               S3 = maps:get(<<"simulacion">>, contenido(R3)),
               ?assertEqual(2000, maps:get(<<"nuevo_vuelo_cada_ms">>, S3)),
               ?assertEqual(<<"personalizado">>,
                            maps:get(<<"perfil">>, S3)),

               %% valor fuera de rango: 409 y no se aplica
               R4 = consultar(<<"POST">>, <<"/api/simulacion/ritmo">>,
                              <<"{\"feed_ms\":1}">>),
               ?assertEqual(409, status(R4)),

               %% pausar / reanudar
               R5 = consultar(<<"POST">>, <<"/api/simulacion/pausar">>, <<>>),
               ?assertEqual(200, status(R5)),
               ?assertEqual(true,
                            maps:get(<<"pausado">>,
                                     maps:get(<<"simulacion">>, contenido(R5)))),
               R6 = consultar(<<"POST">>, <<"/api/simulacion/reanudar">>, <<>>),
               ?assertEqual(200, status(R6)),
               ?assertEqual(false,
                            maps:get(<<"pausado">>,
                                     maps:get(<<"simulacion">>, contenido(R6))))
           end]
      end]}.

%% ----------------------------------------------------------------------
%% POST /api/vuelos con entrada_seg / hora_programada: el vuelo NO debe
%% avanzar antes de su hora de entrada.
%% ----------------------------------------------------------------------
entrada_programada_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [fun(_Sup) ->
          [fun() ->
               R = consultar(<<"POST">>, <<"/api/vuelos">>,
                             <<"{\"destino\":\"CDMX\",\"entrada_seg\":60}">>),
               ?assertEqual(201, status(R)),
               Id = maps:get(<<"vuelo">>, contenido(R)),
               p22_test_ayudante:esperar(900),
               case p22_respaldo:leer_vuelo(Id) of
                   #{estado := Estado, datos := Datos} ->
                       ?assertEqual('programado', Estado),
                       ?assert(maps:get(hora_programada, Datos) >
                               os:system_time(second));
                   no_encontrado ->
                       ?assert(false)
               end,

               %% hora_programada explicita (Unix, segundos)
               Futuro = os:system_time(second) + 600,
               Cuerpo = io_lib:format("{\"hora_programada\":~p}", [Futuro]),
               R2 = consultar(<<"POST">>, <<"/api/vuelos">>,
                              unicode:characters_to_binary(Cuerpo)),
               ?assertEqual(201, status(R2)),
               Id2 = maps:get(<<"vuelo">>, contenido(R2)),
               case p22_respaldo:leer_vuelo(Id2) of
                   #{datos := D2} ->
                       ?assertEqual(Futuro, maps:get(hora_programada, D2));
                   no_encontrado ->
                       ?assert(false)
               end
           end]
      end]}.

%% --- utilidades ------------------------------------------------------

%% HTTP de verdad con httpc (incluido en OTP).
consultar(Metodo, Ruta, Cuerpo) ->
    Puerto = puerto(),
    Url =
        unicode:characters_to_list(
          io_lib:format("http://~ts:~p~ts", ["127.0.0.1", Puerto, Ruta])),
    Cabezas = [{"content-type", "application/json"}],
    Respuesta =
        case Metodo of
            <<"GET">> ->
                httpc:request(get, {Url, Cabezas}, [], []);
            <<"POST">> ->
                httpc:request(post,
                              {Url, Cabezas, "application/json",
                               binary_to_list(Cuerpo)},
                              [], [])
        end,
    case Respuesta of
        {ok, {{_Vs, Codigo, _Frase}, CabezasR, CuerpoR}} ->
            #{codigo => Codigo,
              cabezas =>
                  [{unicode:characters_to_binary(string:casefold(K)),
                    unicode:characters_to_binary(V)}
                   || {K, V} <- CabezasR],
              body =>
                  case CuerpoR of
                      <<>> ->
                          #{};
                      _ ->
                          try
                              json:decode(unicode:characters_to_binary(CuerpoR))
                          catch
                              _:_ ->
                                  unicode:characters_to_binary(CuerpoR)
                          end
                  end}
    end.

status(R) -> maps:get(codigo, R).
contenido(R) -> maps:get(body, R).

cabecera(R, Nombre) ->
    Lista = maps:get(cabezas, R),
    case [V || {K, V} <- Lista, K =:= Nombre] of
        [V | _] -> V;
        [] -> undefined
    end.
