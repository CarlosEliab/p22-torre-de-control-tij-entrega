%% ===================================================================
%% @doc p22_feed — feed simulado de la torre de control (proyecto 22).
%%
%% Simula la operación del aeropuerto: crea vuelos, los hace avanzar
%% por transiciones LEGALES del statem, inyecta demoras, niebla,
%% mensajes FUERA DE ORDEN y prueba de caos (mata procesos de vuelos
%% para validar la reconstrucción del sistema).
%%
%% Cada `feed_ms` (sys.config, default 2000 ms) corre un "tick":
%%   1. muestrea el contador acumulado de eventos (ventana ~1 min) para
%%      calcular "eventos por minuto" en /metrics;
%%   2. a veces inyecta: caos / mensaje fuera de orden / niebla;
%%   3. hace avanzar los vuelos operativos;
%%   4. crea vuelos nuevos si estamos debajo del tope de vivos.
%%
%% Atiende {aeronave_cancelada, IdOrigen, Matricula, Motivo} que emite
%% el statem al CANCELAR un vuelo: cancela el vuelo de REGRESO de la
%% misma aeronave (efecto cascada, caso dificil del problema).
%%
%% Controles para demo en vivo (también llamables desde la API):
%%   nuevo_vuelo(), niebla(), inyectar_caos(), mensaje_fuera_de_orden(),
%%   pausar(), reanudar(), metricas().
%% ===================================================================
-module(p22_feed).

-behaviour(gen_server).

-export([start_link/0, pausar/0, reanudar/0, nuevo_vuelo/0, nuevo_vuelo/1,
         niebla/0, inyectar_caos/0, mensaje_fuera_de_orden/0, metricas/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(MATRICULAS, [<<"XA-TIJ">>, <<"XA-VOL">>, <<"XA-AMX">>,
                     <<"XA-ALA">>, <<"XA-TUS">>, <<"XA-BCN">>]).

-define(AEROLINEAS, [<<"Volaris">>, <<"Aeromexico">>, <<"American">>,
                     <<"Alaska">>, <<"Frontier">>, <<"United">>]).

-define(DESTINOS, [<<"CDMX">>, <<"GDL">>, <<"SJD">>, <<"MTY">>,
                   <<"LAX">>, <<"DFW">>, <<"SEA">>, <<"DEN">>,
                   <<"HNL">>, <<"ORD">>]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% --- API de demo / control manual ----------------------------------

%% @doc Crea un vuelo nuevo ahora mismo (lo llama la API y la demo).
nuevo_vuelo() ->
    gen_server:call(?MODULE, nuevo_vuelo).

%% @doc Igual que nuevo_vuelo/0 pero permite fijar campos del vuelo.
%% Opciones (claves atomo): destino, aerolinea, aeronave, identificacion,
%% hora_programada. Lo usa POST /api/vuelos con un cuerpo JSON opcional.
nuevo_vuelo(Opciones) when is_map(Opciones) ->
    gen_server:call(?MODULE, {nuevo_vuelo, Opciones}).

%% @doc Demora 20 min TODOS los vuelos programados (niebla matutina).
niebla() ->
    gen_server:call(?MODULE, niebla).

%% @doc Mata UN vuelo operativo al azar para validar la reconstrucción.
inyectar_caos() ->
    gen_server:call(?MODULE, inyectar_caos).

%% @doc Manda un evento con secuencia VIEJA; el statem DEBE ignorarlo.
mensaje_fuera_de_orden() ->
    gen_server:call(?MODULE, mensaje_fuera_de_orden).

pausar() ->
    gen_server:call(?MODULE, pausar).

reanudar() ->
    gen_server:call(?MODULE, reanudar).

%% @doc Metricas del muestreo: eventos por minuto.
metricas() ->
    gen_server:call(?MODULE, metricas).

%% --- gen_server ----------------------------------------------------

init([]) ->
    Intervalo = application:get_env(p22_torre_de_control_tij, feed_ms, 2000),
    Caos = application:get_env(p22_torre_de_control_tij, caos, true),
    %% Reinicio del sistema: re-arranca un proceso por cada vuelo de
    %% la foto guardada (memoria o disco). Si la foto esta vacia, siembra
    %% el escenario inicial.
    _ = arrancar_vuelos_guardados(),
    Timer = erlang:send_after(Intervalo, self(), tick),
    Estado = #{intervalo => Intervalo,
               pausado => false,
               caos => Caos,
               ventana => [],
               timer => Timer},
    logger:info("~s listo (tick ~p ms, caos ~p)", [?MODULE, Intervalo, Caos]),
    {ok, Estado}.

handle_call(nuevo_vuelo, _From, State) ->
    {reply, crear_uno(#{}), State};
handle_call({nuevo_vuelo, Opciones}, _From, State) ->
    {reply, crear_uno(Opciones), State};
handle_call(niebla, _From, State) ->
    {ok, N} = demorar_programados(20, <<"niebla matutina">>),
    p22_eventos:publicar(#{tipo => alerta,
                           mensaje => <<"niebla costera: salidas demoradas 20 min">>}),
    {reply, {ok, N}, State};
handle_call(inyectar_caos, _From, State) ->
    case maps:get(caos, State, true) of
        false ->
            {reply, {error, caos_desactivado}, State};
        true ->
            {reply, inyectar_caos_base(), State}
    end;
handle_call(mensaje_fuera_de_orden, _From, State) ->
    {reply, fuera_de_orden_base(), State};
handle_call(pausar, _From, #{timer := Timer} = State) ->
    %% Se cancela la cadena de ticks: al reanudar se arranca UNA sola.
    _ = case Timer of
            undefined -> ok;
            _ -> erlang:cancel_timer(Timer)
        end,
    {reply, ok, State#{pausado => true, timer => undefined}};
handle_call(reanudar, _From, #{pausado := true, intervalo := I} = State) ->
    Timer = erlang:send_after(I, self(), tick),
    {reply, ok, State#{pausado => false, timer => Timer}};
handle_call(reanudar, _From, State) ->
    %% ya estaba corriendo: no duplicar la cadena de ticks
    {reply, ok, State};
handle_call(metricas, _From, #{ventana := Ventana} = State) ->
    {reply, #{eventos_por_minuto => tasa_por_minuto(Ventana)}, State};
handle_call(_Otro, _From, State) ->
    {reply, ok, State}.

handle_cast(_Otro, State) ->
    {noreply, State}.

handle_info(tick, #{pausado := true} = State) ->
    {noreply, State#{timer => undefined}};

handle_info(tick, #{intervalo := I} = State) ->
    Timer = erlang:send_after(I, self(), tick),
    {noreply, tick(State#{timer => Timer})};

%% Efecto cascada: aeronave cancelada => su vuelo de regreso se cancela.
handle_info({aeronave_cancelada, _IdOrigen, Matricula, _Motivo}, State) ->
    lists:foreach(
      fun(Id) ->
         _ = p22_vuelo_statem:transicion(
               Id, torre, sig(), cancelar,
               #{motivo => <<"aeronave anterior cancelada (efecto cascada)">>})
      end,
      regreso_de_aeronave(Matricula)),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%% --- ciclo del tick -------------------------------------------------

tick(State) ->
    %% 1. muestreo para eventos/minuto
    Ventana = muestrear(maps:get(ventana, State, [])),
    State2 = State#{ventana => Ventana},
    Vivos = vivos_operativos(),
    %% 2. inyecciones raras (caos, fuera de orden, niebla)
    sorteos(State2, Vivos),
    %% 3. avanzar vuelos operativos
    lists:foreach(fun avanza/1, Vivos),
    %% 4. crear vuelos nuevos si hay presupuesto
    Tope = tope_vuelos(),
    case length(Vivos) < Tope of
        true ->
            crear_vuelo(siguiente_id());
        false ->
            ok
    end,
    %% 5. retirar vuelos terminales viejos para que el tablero no
    %%    acumule cientos de tarjetas en una demo larga.
    limpiar_terminales(),
    State2.

%% Inyecciones con pequeñas probabilidades por tick.
sorteos(_State, []) ->
    ok;
sorteos(#{caos := Caos}, _Vivos) ->
    Suerte = rand:uniform(100),
    if
        Caos andalso Suerte =< 3 ->
            _ = inyectar_caos_base(),
            ok;
        Suerte > 3 andalso Suerte =< 6 ->
            _ = fuera_de_orden_base(),
            ok;
        Suerte > 6 andalso Suerte =< 8 ->
            _ = demorar_programados(20, <<"niebla matutina">>),
            p22_eventos:publicar(#{tipo => alerta,
                                   mensaje =>
                                     <<"visibilidad cae: niebla costera matutina">>}),
            ok;
        true ->
            ok
    end.

%% Avanza un vuelo con transiciones legales (como la operacion real),
%% con algo de aleatoriedad para no mover todo en pasa sincronizada.
%% NOTA de autoridad: el feed representa a la TORRE (su sistema
%% operativo), por eso emite como `torre'. Si emitiera como `sistema',
%% despues de una demora declarada por la torre la jerarquia lo
%% rechazaria para siempre y el vuelo quedaria congelado.
avanza(Id) ->
    case p22_respaldo:leer_vuelo(Id) of
        #{estado := Estado} ->
            Sorteo = rand:uniform(10),
            Accion =
                case {Estado, Sorteo} of
                    {'despego', _} -> aterrizar;
                    {'abordando', S} when S =< 8 -> despegar;
                    {'programado', S} when S =< 6 -> empezar_abordaje;
                    {'demorado', S} when S =< 6 -> empezar_abordaje;
                    _ -> ninguna
                end,
            case Accion of
                ninguna -> ok;
                _ ->
                    _ = p22_vuelo_statem:transicion(Id, torre, sig(), Accion),
                    ok
            end;
        _ ->
            %% el vuelo esta entre reinicios: el siguiente tick lo vera
            ok
    end.

%% --- internos -------------------------------------------------------

%% Demora a TODOS los vuelos programados. Devuelve {ok, N}.
demorar_programados(Minutos, Motivo) ->
    Ids = [Id || {Id, Info} <- p22_respaldo:todos_vuelos(),
                 maps:get(estado, Info, nada) =:= 'programado',
                 p22_vuelo_statem:pid_de(Id) =/= undefined],
    _ = [p22_vuelo_statem:transicion(Id, torre, sig(), demorar,
                                     #{minutos => Minutos, motivo => Motivo})
         || Id <- Ids],
    {ok, length(Ids)}.

inyectar_caos_base() ->
    case vivos_operativos() of
        [] ->
            {error, sin_vuelos_operativos};
        Vivos ->
            %% OJO: vivos_operativos() devuelve IDs, no PIDs. Antes se
            %% hacia exit(Id, kill) con un entero (badarg) y el caos
            %% automatico nunca llegaba a matar nada.
            Id = al_azar(Vivos),
            case p22_vuelo_statem:pid_de(Id) of
                undefined ->
                    {error, sin_vuelos_operativos};
                Pid ->
                    p22_eventos:publicar(#{tipo => caos, vuelo => Id,
                                           mensaje =>
                                               <<"prueba de caos: proceso eliminado">>}),
                    exit(Pid, kill),
                    {ok, Id}
            end
    end.

fuera_de_orden_base() ->
    Vivos = [Id || {Id, _} <- p22_respaldo:todos_vuelos(),
                   p22_vuelo_statem:pid_de(Id) =/= undefined],
    case Vivos of
        [] ->
            {error, sin_vuelos};
        _ ->
            Id = al_azar(Vivos),
            %% seq = 0 es SIEMPRE vieja (las secuencias arrancan en 1):
            %% el statem la ignora y muestra la cuenta en evento_ignorado.
            Resp = p22_vuelo_statem:transicion(
                     Id, aerolinea, 0, empezar_abordaje,
                     #{mensaje => <<"mensaje fuera de orden">>}),
            {ok, {Id, Resp}}
    end.

%% Tras reiniciar la VM, el supervisor dinamico arranca vacio: hay que
%% crear un gen_statem por cada vuelo guardado y cada uno restaura su
%% estado/datos desde el respaldo en init. Si el arbol se reinicia pero
%% los vuelos siguen vivos, no se duplican.
arrancar_vuelos_guardados() ->
    case p22_respaldo:todos_vuelos() of
        [] ->
            [crear_vuelo(I) || I <- lists:seq(1, 8)];
        Vuelos ->
            lists:foreach(
              fun({Id, _Info}) ->
                  case p22_vuelo_statem:pid_de(Id) of
                      undefined -> _ = p22_vuelos_sup:iniciar(#{id => Id});
                      _Pid -> ok
                  end
              end,
              Vuelos),
            logger:info("feed: ~p vuelos recuperados del respaldo",
                        [length(Vuelos)]),
            ok
    end.

%% Crear un vuelo: lo registra en el supervisor dinamico. Los datos de
%% arranque son exactamente los que renacen tras un caos.
crear_vuelo(Id) ->
    crear_vuelo(Id, #{}).

crear_vuelo(Id, Opciones) when is_map(Opciones) ->
    Base = #{id => Id,
             identificacion => identificacion_de(Id),
             aeronave => al_azar(?MATRICULAS),
             aerolinea => al_azar(?AEROLINEAS),
             destino => al_azar(?DESTINOS),
             origen => <<"TIJ">>,
             hora_programada => os:system_time(second) + 10 * 60},
    %% Solo se permiten los campos conocidos del vuelo: nada de meter
    %% claves arbitrarias (id incluido) en el spec del gen_statem.
    Permitidas = maps:with([identificacion, aeronave, aerolinea,
                            destino, hora_programada], Opciones),
    Spec = maps:merge(Base, Permitidas),
    case p22_vuelos_sup:iniciar(Spec) of
        {ok, _Pid} ->
            p22_eventos:publicar(#{tipo => vuelo_creado, vuelo => Id,
                                   identificacion => maps:get(identificacion, Spec),
                                   destino => maps:get(destino, Spec),
                                   aeronave => maps:get(aeronave, Spec),
                                   hora_programada => maps:get(hora_programada, Spec)}),
            Id;
        {error, Razon} ->
            logger:warning("no se pudo crear el vuelo ~p: ~p", [Id, Razon]),
            {error, Razon}
    end.

%% Crea un vuelo y devuelve {ok, Id} SOLO si el proceso arranco. Antes
%% se respondia {ok, Id} siempre: si el nombre ya estaba registrado, el
%% cliente creia que el vuelo existia y luego /api/vuelos daba 404
%% (justo lo que detecto la suite).
crear_uno(Opciones) ->
    Id = siguiente_id(),
    case crear_vuelo(Id, Opciones) of
        Id -> {ok, Id};
        {error, Razon} -> {error, Razon}
    end.

%% Siguiente id libre: maximo del respaldo + 1, saltando nombres que
%% sigan registrados por un proceso huerfano entre reinicios.
siguiente_id() ->
    Max = case p22_respaldo:todos_vuelos() of
              [] -> 0;
              L -> lists:max([Id || {Id, _} <- L])
          end,
    id_libre(Max + 1).

id_libre(Id) ->
    case p22_vuelo_statem:pid_de(Id) of
        undefined -> Id;
        _ -> id_libre(Id + 1)
    end.

identificacion_de(Id) ->
    unicode:characters_to_binary("TJ-" ++ integer_to_list(100 + Id)).

%% Vuelos de la misma aeronave que AUN no salen: candidatos al efecto
%% cascada (solo en terminal: ni abordando ni despegando).
regreso_de_aeronave(Matricula) ->
    [Id || {Id, #{estado := 'programado', datos := Datos}}
               <- p22_respaldo:todos_vuelos(),
           maps:get(aeronave, Datos, nada) =:= Matricula,
           p22_vuelo_statem:pid_de(Id) =/= undefined].

vivos_operativos() ->
    [Id
     || {Id, Info} <- p22_respaldo:todos_vuelos(),
        estado_operativo(maps:get(estado, Info, nada)),
        p22_vuelo_statem:pid_de(Id) =/= undefined].

estado_operativo('programado') -> true;
estado_operativo('demorado') -> true;
estado_operativo('abordando') -> true;
estado_operativo('despego') -> true;
estado_operativo(_) -> false.

tope_vuelos() ->
    application:get_env(p22_torre_de_control_tij, max_vuelos_vivos, 14).

%% Ventana de muestreo para metricas: guarda ~30 muestras (~60 s).
muestrear(Ventana) ->
    Ts = os:system_time(second),
    lists:sublist([{Ts, p22_respaldo:leer_contador(eventos_min)} | Ventana], 30).

%% Eventos POR MINUTO a partir de la ventana de muestras acumuladas.
tasa_por_minuto([]) ->
    0;
tasa_por_minuto(Ventana) ->
    [{TsN, CN} | _] = Ventana,
    {Ts0, C0} = lists:last(Ventana),
    Span = max(TsN - Ts0, 1),
    round((CN - C0) * 60 / Span).

%% Seq monotona para fuentes del feed (>=1 SIEMPRE; el receptor trata
%% seq 0 como mensaje viejo).
sig() ->
    os:system_time(microsecond).

%% Retira del supervisor y del respaldo los vuelos que ya terminaron
%% (aterrizado/cancelado) hace mas de 2 minutos. Conserva los recientes
%% para que el tablero muestre el historial inmediato.
limpiar_terminales() ->
    Ahora = os:system_time(second),
    Viejos =
        [Id
         || {Id, #{estado := E, tocado := T}} <- p22_respaldo:todos_vuelos(),
            (E =:= aterrizado orelse E =:= cancelado),
            Ahora - T > 120],
    lists:foreach(fun p22_vuelos_sup:terminar/1, lists:sublist(Viejos, 20)),
    ok.

al_azar(L) ->
    lists:nth(rand:uniform(length(L)), L).
