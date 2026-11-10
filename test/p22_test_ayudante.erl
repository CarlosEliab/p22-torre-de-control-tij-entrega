%% ===================================================================
%% @doc p22_test_ayudante — fixture comun de las pruebas.
%%
%% Levanta el "tripod" minimo del dominio SIN enlazar los procesos al
%% proceso de EUnit (EUnit cancelaria el grupo con cada 'EXIT'). Lo
%% hace un pequeño proceso "jefe", con el MISMO orden del arbol real
%% (rest_for_one): respaldo -> eventos -> puertas -> vuelos_sup.
%%
%% Si una prueba mata a uno de estos procesos, el jefe solo se entera
%% (trap_exit) y NO reinicia nada automaticamente; la prueba decide
%% re-arrancar con `arrancar/1' — exactamente lo que un supervisor
%% haria — y valida la reconstruccion.
%% ===================================================================
-module(p22_test_ayudante).

-export([levantar_dominio/0, bajar_dominio/0, arrancar/1, esperar/1,
         limpiar_nombres/0]).

%% @doc Mata con fuerza cualquier proceso del dominio que haya quedado
%% registrado de una corrida anterior (defensivo para eunit).
limpiar_nombres() ->
    lists:foreach(
      fun(Nombre) ->
         case whereis(Nombre) of
             undefined -> ok;
             Pid -> unlink(Pid), exit(Pid, kill)
         end
      end,
      [p22_respaldo, p22_eventos, p22_puertas, p22_vuelos_sup,
       p22_feed, p22_web, p22_torre_de_control_tij_sup]),
    esperar(80).

%% @doc Crea el jefe y arranca los procesos del dominio en orden.
levantar_dominio() ->
    limpiar_nombres(),
    p22_respaldo:limpiar(),
    Jefe = spawn(fun jefe_bucle/0),
    persistent_term:put(p22_test_jefe, Jefe),
    [begin
         {ok, _} = arrancar(M),
         esperar(30)
     end
     || M <- [p22_respaldo, p22_eventos, p22_puertas, p22_vuelos_sup]],
    Jefe.

%% @doc Arranca un proceso del dominio DESDE EL JEFE (no desde la
%% prueba): sin enlaces con EUnit. Devuelve {ok, Pid}.
arrancar(Mod) ->
    Jefe = persistent_term:get(p22_test_jefe),
    Jefe ! {arrancar, Mod, self()},
    receive
        {arrancado, Respuesta} -> Respuesta
    after 5000 ->
        {error, jefe_no_responde}
    end.

%% @doc Mata al jefe (y con el, a los procesos del dominio, ya que el
%% jefe los enlaza al arrancarlos) y espera a que los nombres queden libres.
bajar_dominio() ->
    case persistent_term:get(p22_test_jefe, no_hay) of
        no_hay ->
            ok;
        Jefe ->
            MonRef = erlang:monitor(process, Jefe),
            exit(Jefe, shutdown),
            receive
                {'DOWN', MonRef, process, Jefe, _} -> ok
            after 5000 ->
                ok
            end,
            persistent_term:erase(p22_test_jefe)
    end,
    esperar(100).

%% Bucle del jefe: arranca lo que se le pide y traga los exits de los
%% hijos (mas alla del 'shutdown' que es la senal de apagar TODO).
jefe_bucle() ->
    process_flag(trap_exit, true),
    jefe_loop().

jefe_loop() ->
    receive
        {'EXIT', _Desde, shutdown} ->
            ok_fin;
        {arrancar, Mod, Quien} ->
            Respuesta = try Mod:start_link()
                        catch Clase:Razon -> {error, {Clase, Razon}}
                        end,
            Quien ! {arrancado, Respuesta},
            jefe_loop();
        _Otro ->
            jefe_loop()
    end.

%% @doc Espera `Ms' milisegundos (drenando mensajes pero sin colarlos)
%% sin bloquear los reintentos de las pruebas.
esperar(Ms) ->
    receive
        _ -> esperar(Ms)
    after Ms ->
        ok
    end.
