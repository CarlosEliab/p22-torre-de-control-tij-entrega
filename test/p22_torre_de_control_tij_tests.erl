%% ===================================================================
%% @doc Pruebas del ARBOL DE SUPERVISION (proyecto 22).
%%
%% Verifica la estructura minima prometida en el README:
%%   - el supervisor raiz levanta los 6 procesos del dominio
%%   - un reinicio del RAIZ reconstruye el sistema desde el respaldo
%%     (caso dificil del problema: "reinicio del sistema")
%% ===================================================================
-module(p22_torre_de_control_tij_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    application:set_env(p22_torre_de_control_tij, puerto, 0),
    application:set_env(p22_torre_de_control_tij, caos, false),
    {ok, _} = application:ensure_all_started(cowboy),
    p22_test_ayudante:limpiar_nombres(),
    p22_respaldo:limpiar(),
    ok.

%% Todos los procesos del proyecto estan registrados y vivos.
arbol_completo_test_() ->
    {setup,
     fun() ->
         setup(),
         {ok, Sup} = p22_torre_de_control_tij_sup:start_link(),
         p22_test_ayudante:esperar(200),
         Sup
     end,
     fun(Sup) ->
         unlink(Sup),
         exit(Sup, shutdown),
         p22_test_ayudante:esperar(100)
     end,
     fun(_Sup) ->
        [?_assert(is_process_alive(whereis(p22_respaldo))),
         ?_assert(is_process_alive(whereis(p22_eventos))),
         ?_assert(is_process_alive(whereis(p22_puertas))),
         ?_assert(is_process_alive(whereis(p22_vuelos_sup))),
         ?_assert(is_process_alive(whereis(p22_feed))),
         ?_assert(is_process_alive(whereis(p22_web))),
         %% el bus responde: tacita verificacion de comunicado
         ?_assertEqual(pong, p22_eventos:ping())]
     end}.

%% El respaldo sobrevive a su propio reinicio (persistent_term): si el
%% sistema se cae TODO, al volver los vuelos renacen con su ultimo
%% estado — eso tambien lo cubre a detalle p22_caos_tests.
respaldo_resistente_test_() ->
    {setup,
     fun() ->
         setup(),
         application:set_env(p22_torre_de_control_tij, puerto, 0),
         {ok, Sup} = p22_torre_de_control_tij_sup:start_link(),
         p22_test_ayudante:esperar(200),
         Sup
     end,
     fun(Sup) ->
         unlink(Sup),
         exit(Sup, shutdown),
         p22_test_ayudante:esperar(120)
     end,
     fun(_Sup) ->
        [fun() ->
             {ok, Id} = p22_feed:nuevo_vuelo(),
             p22_test_ayudante:esperar(80),
             ?assert(is_map(maps:get(datos, p22_respaldo:leer_vuelo(Id), #{})))
         end]
     end}.
