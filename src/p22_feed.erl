%% ===================================================================
%% @doc p22_feed — feed simulado de la torre de control (proyecto 22).
%%
%% Simula la operacion del aeropuerto: crea vuelos, los hace avanzar
%% por transiciones LEGALES del statem, inyecta demoras, niebla,
%% mensajes FUERA DE ORDEN y prueba de caos (mata procesos de vuelos
%% para validar la reconstruccion del sistema).
%%
%% El ritmo es configurable EN CALIENTE con `ajustar_ritmo/1`:
%%   - feed_ms               cada cuanto corre un tick
%%   - nuevo_vuelo_cada_ms   separacion entre altas automaticas
%%   - espera_entrada_ms     tiempo en 'programado' antes de abordar
%%   - abordaje_ms           tiempo en 'abordando' antes de despegar
%%   - vuelo_ms              tiempo en 'despego' antes de aterrizar
%%
%% Perfiles listos: muy_lento | lento | normal | rapido | personalizado.
%% El perfil por defecto es `lento` (config/sys.config).
%%
%% Atiende {aeronave_cancelada, IdOrigen, Matricula, Motivo} que emite
%% el statem al CANCELAR un vuelo: cancela el vuelo de REGRESO de la
%% misma aeronave (efecto cascada, caso dificil del problema).
%%
%% Controles para demo en vivo (también llamables desde la API):
%%   nuevo_vuelo(), niebla(), inyectar_caos(), mensaje_fuera_de_orden(),
%%   pausar(), reanudar(), ajustar_ritmo/1, estado_simulacion().
%% ===================================================================
-module(p22_feed).

-behaviour(gen_server).

-export([start_link/0, pausar/0, reanudar/0, nuevo_vuelo/0, nuevo_vuelo/1,
         niebla/0, inyectar_caos/0, mensaje_fuera_de_orden/0, metricas/0,
         ajustar_ritmo/1, estado_simulacion/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(APP, p22_torre_de_control_tij).

-define(MATRICULAS, [<<"XA-TIJ">>, <<"XA-VOL">>, <<"XA-AMX">>,
                     <<"XA-ALA">>, <<"XA-TUS">>, <<"XA-BCN">>]).

-define(AEROLINEAS, [<<"Volaris">>, <<"Aeromexico">>, <<"American">>,
                     <<"Alaska">>, <<"Frontier">>, <<"United">>]).

-define(DESTINOS, [<<"CDMX">>, <<"GDL">>, <<"SJD">>, <<"MTY">>,
                   <<"LAX">>, <<"DFW">>, <<"SEA">>, <<"DEN">>,
                   <<"HNL">>, <<"ORD">>]).

%% Campos del ritmo que se pueden ajustar en caliente.
-define(CAMPOS_RITMO, [feed_ms, nuevo_vuelo_cada_ms, espera_entrada_ms,
                       abordaje_ms, vuelo_ms]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% --- API de demo / control manual ----------------------------------

%% @doc Crea un vuelo nuevo ahora mismo (lo llama la API y la demo).
nuevo_vuelo() ->
    gen_server:call(?MODULE, nuevo_vuelo).

%% @doc Igual que nuevo_vuelo/0 pero permite fijar campos del vuelo.
%% Opciones (claves atomo): destino, aerolinea, aeronave, identificacion,
%% hora_programada, entrada_seg. Lo usa POST /api/vuelos.
nuevo_vuelo(Opciones) when is_map(Opciones) ->
    gen_server:call(?MODULE, {nuevo_vuelo, Opciones}).

%% @doc Demora 20 min TODOS los vuelos programados (niebla matutina).
niebla() ->
    gen_server:call(?MODULE, niebla).

%% @doc Mata UN vuelo operativo al azar para validar la reconstruccion.
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

%% @doc Estado actual del simulador (perfil, pausa y tiempos).
estado_simulacion() ->
    gen_server:call(?MODULE, estado_simulacion).

%% @doc Cambia el ritmo en caliente. Ejemplos:
%%   ajustar_ritmo(#{perfil => lento})
%%   ajustar_ritmo(#{nuevo_vuelo_cada_ms => 60000})
ajustar_ritmo(Cambios) when is_map(Cambios) ->
    gen_server:call(?MODULE, {ajustar_ritmo, Cambios}).

%% --- gen_server ----------------------------------------------------

init([]) ->
    Perfil = perfil_inicial(),
    Ritmo = ritmo_inicial(Perfil),
    publicar_ritmo(Ritmo, Perfil),
    Caos = application:get_env(?APP, caos, true),
    %% Reinicio del sistema: re-arranca un proceso por cada vuelo de
    %% la foto guardada (memoria o disco). Si la foto esta vacia, siembra
    %% el escenario inicial.
    _ = arrancar_vuelos_guardados(),
    State0 = #{perfil => Perfil,
               ritmo => Ritmo,
               pausado => false,
               caos => Caos,
               ventana => [],
               timer => undefined,
               gen => 0,
               ultimo_nuevo => monotonic_ms()},
    State = programar(State0),
    logger:info("~s listo (perfil ~p, tick ~p ms, caos ~p)",
                [?MODULE, Perfil, feed_ms(State), Caos]),
    {ok, State}.

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
handle_call(pausar, _From, State) ->
    %% Se cancela la cadena de ticks: al reanudar se arranca UNA sola.
    State2 = cancelar_timer(State),
    {reply, ok, State2#{pausado => true, timer => undefined}};
handle_call(reanudar, _From, #{pausado := true} = State) ->
    State2 = programar(State#{pausado => false}),
    {reply, ok, State2};
handle_call(reanudar, _From, State) ->
    %% ya estaba corriendo: no duplicar la cadena de ticks
    {reply, ok, State};
handle_call(metricas, _From, #{ventana := Ventana} = State) ->
    {reply, #{eventos_por_minuto => tasa_por_minuto(Ventana)}, State};
handle_call(estado_simulacion, _From, State) ->
    {reply, estado_simulacion(State), State};
handle_call({ajustar_ritmo, Cambios}, _From, State) ->
    case aplicar_cambios(Cambios, State) of
        {ok, State2} ->
            State3 = cancelar_timer(State2),
            State4 = case maps:get(pausado, State3) of
                         true -> State3#{timer => undefined};
                         false -> programar(State3)
                     end,
            {reply, {ok, estado_simulacion(State4)}, State4};
        {error, Razon} ->
            {reply, {error, Razon}, State}
    end;
handle_call(_Otro, _From, State) ->
    {reply, ok, State}.

handle_cast(_Otro, State) ->
    {noreply, State}.

%% Cada cadena de ticks lleva un numero de generacion: si se cambia el
%% ritmo mientras un tick viejo ya venia en el buzon, ese tick se ignora
%% y no se duplica la cadena.
handle_info({tick, Gen}, #{gen := Gen, pausado := false} = State) ->
    State2 = tick(State),
    {noreply, programar(State2)};
handle_info({tick, _Viejo}, State) ->
    {noreply, State};

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
    State1 = State#{ventana => Ventana},
    Vivos = vivos_operativos(),
    %% 2. inyecciones raras (caos, fuera de orden, niebla)
    sorteos(State1, Vivos),
    %% 3. avanzar vuelos operativos respetando el ritmo
    Ritmo = maps:get(ritmo, State1),
    lists:foreach(fun(Id) -> avanza(Id, Ritmo) end, Vivos),
    %% 4. crear un vuelo nuevo solo si ya paso el intervalo configurado
    State2 = quizas_crear(State1, Vivos),
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

%% Avanza un vuelo con transiciones legales, pero solo cuando su
%% tiempo de permanencia en el estado ya se cumplio. El feed representa
%% a la TORRE (su sistema operativo), por eso emite como `torre'.
avanza(Id, Ritmo) ->
    case p22_respaldo:leer_vuelo(Id) of
        #{estado := Estado, datos := Datos} ->
            case accion_automatica(Estado, Datos, Ritmo) of
                ninguna ->
                    ok;
                Accion ->
                    _ = p22_vuelo_statem:transicion(Id, torre, sig(), Accion),
                    ok
            end;
        _ ->
            %% el vuelo esta entre reinicios: el siguiente tick lo vera
            ok
    end.

%% ¿Que accion automatica toca segun el estado y el tiempo transcurrido?
accion_automatica('programado', Datos, _Ritmo) ->
    case hora_llegada(Datos) =< os:system_time(millisecond) of
        true -> con_suerte(empezar_abordaje, 7);
        false -> ninguna
    end;
accion_automatica('demorado', Datos, Ritmo) ->
    case transcurrido(Datos) >= maps:get(espera_entrada_ms, Ritmo) of
        true -> con_suerte(empezar_abordaje, 6);
        false -> ninguna
    end;
accion_automatica('abordando', Datos, Ritmo) ->
    case transcurrido(Datos) >= maps:get(abordaje_ms, Ritmo) of
        true -> con_suerte(despegar, 8);
        false -> ninguna
    end;
accion_automatica('despego', Datos, Ritmo) ->
    case transcurrido(Datos) >= maps:get(vuelo_ms, Ritmo) of
        true -> aterrizar;
        false -> ninguna
    end;
accion_automatica(_Estado, _Datos, _Ritmo) ->
    ninguna.

%% Pequeña dispersion para que no todos los vuelos cambien a la vez.
con_suerte(Accion, Umbral) ->
    case rand:uniform(10) =< Umbral of
        true -> Accion;
        false -> ninguna
    end.

%% Hora programada del vuelo en milisegundos. Si no existe, se toma
%% como "ya puede entrar".
hora_llegada(Datos) ->
    case maps:get(hora_programada, Datos, 0) of
        H when is_integer(H), H > 0 -> H * 1000;
        _ -> 0
    end.

%% Milisegundos desde el ultimo cambio de estado (historial[0].ts).
transcurrido(Datos) ->
    case maps:get(historial, Datos, []) of
        [#{ts := Ts} | _] when is_integer(Ts) ->
            max(0, os:system_time(second) - Ts) * 1000;
        _ ->
            %% sin historial: se permite avanzar (vuelo recuperado viejo)
            999999999
    end.

%% Crea un vuelo automatico solo si hay espacio y ya paso el intervalo.
quizas_crear(State, Vivos) ->
    Ritmo = maps:get(ritmo, State),
    Tope = tope_vuelos(),
    Ahora = monotonic_ms(),
    Ultimo = maps:get(ultimo_nuevo, State, Ahora),
    Cada = maps:get(nuevo_vuelo_cada_ms, Ritmo),
    if
        length(Vivos) < Tope andalso (Ahora - Ultimo) >= Cada ->
            _ = crear_vuelo(siguiente_id()),
            State#{ultimo_nuevo => Ahora};
        true ->
            State
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
            %% Siembra escalonada: no todos entran al mismo tiempo.
            [crear_vuelo(I, #{entrada_seg => (I - 1) * 10})
             || I <- lists:seq(1, 8)];
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
    Hora = hora_de_entrada(Opciones),
    Base = #{id => Id,
             identificacion => identificacion_de(Id),
             aeronave => al_azar(?MATRICULAS),
             aerolinea => al_azar(?AEROLINEAS),
             destino => al_azar(?DESTINOS),
             origen => <<"TIJ">>,
             hora_programada => Hora},
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

%% Hora de entrada: si viene hora_programada se respeta; si viene
%% entrada_seg se suma al reloj; si no, se usa el tiempo de espera del
%% perfil activo.
hora_de_entrada(Opciones) ->
    case maps:get(hora_programada, Opciones, undefined) of
        H when is_integer(H), H > 0 ->
            H;
        _ ->
            Seg = case maps:get(entrada_seg, Opciones, undefined) of
                      E when is_integer(E), E >= 0 -> E;
                      _ -> env_int(espera_entrada_ms, 60000) div 1000
                  end,
            os:system_time(second) + Seg
    end.

%% Crea un vuelo y devuelve {ok, Id} SOLO si el proceso arranco.
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
    application:get_env(?APP, max_vuelos_vivos, 14).

%% Ventana de muestreo para metricas: guarda ~30 muestras.
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

%% --- perfiles y configuracion del ritmo -----------------------------

perfil_inicial() ->
    case application:get_env(?APP, perfil_simulacion, lento) of
        P when is_atom(P) ->
            case perfil_valido(P) of
                {ok, Perfil} -> Perfil;
                error -> lento
            end;
        _ ->
            lento
    end.

ritmo_inicial(personalizado) ->
    #{feed_ms => env_int(feed_ms, 15000),
      nuevo_vuelo_cada_ms => env_int(nuevo_vuelo_cada_ms, 90000),
      espera_entrada_ms => env_int(espera_entrada_ms, 60000),
      abordaje_ms => env_int(abordaje_ms, 60000),
      vuelo_ms => env_int(vuelo_ms, 120000)};
ritmo_inicial(Perfil) ->
    preset(Perfil).

preset(muy_lento) ->
    #{feed_ms => 20000,
      nuevo_vuelo_cada_ms => 120000,
      espera_entrada_ms => 90000,
      abordaje_ms => 60000,
      vuelo_ms => 150000};
preset(lento) ->
    #{feed_ms => 15000,
      nuevo_vuelo_cada_ms => 90000,
      espera_entrada_ms => 60000,
      abordaje_ms => 60000,
      vuelo_ms => 120000};
preset(normal) ->
    #{feed_ms => 8000,
      nuevo_vuelo_cada_ms => 45000,
      espera_entrada_ms => 45000,
      abordaje_ms => 40000,
      vuelo_ms => 90000};
preset(rapido) ->
    #{feed_ms => 3000,
      nuevo_vuelo_cada_ms => 15000,
      espera_entrada_ms => 15000,
      abordaje_ms => 12000,
      vuelo_ms => 30000};
preset(_) ->
    preset(lento).

perfil_valido(muy_lento) -> {ok, muy_lento};
perfil_valido(lento) -> {ok, lento};
perfil_valido(normal) -> {ok, normal};
perfil_valido(rapido) -> {ok, rapido};
perfil_valido(personalizado) -> {ok, personalizado};
perfil_valido(_) -> error.

%% Aplica un cambio de perfil y/o tiempos. Si se cambia un tiempo
%% suelto, el perfil pasa a `personalizado'. Devuelve {ok, State2}
%% para que el gen_server conserve ritmo/perfil en su estado.
aplicar_cambios(Cambios, State) ->
    PerfilBase = maps:get(perfil, State),
    RitmoBase = maps:get(ritmo, State),
    case maps:get(perfil, Cambios, undefined) of
        undefined ->
            aplicar_campos(maps:without([perfil], Cambios), RitmoBase,
                           PerfilBase, State);
        Perfil0 ->
            case perfil_valido(Perfil0) of
                {ok, Perfil} ->
                    Base = case Perfil of
                               personalizado -> RitmoBase;
                               _ -> preset(Perfil)
                           end,
                    aplicar_campos(maps:without([perfil], Cambios), Base,
                                   Perfil, State);
                error ->
                    {error, perfil_invalido}
            end
    end.

aplicar_campos(Cambios, RitmoBase, PerfilBase, State) ->
    case validar_campos(?CAMPOS_RITMO, Cambios, RitmoBase) of
        {ok, Ritmo} ->
            TieneCampos = lists:any(fun(K) -> maps:is_key(K, Cambios) end,
                                    ?CAMPOS_RITMO),
            Perfil = case TieneCampos of
                         true -> personalizado;
                         false -> PerfilBase
                     end,
            publicar_ritmo(Ritmo, Perfil),
            {ok, State#{ritmo => Ritmo, perfil => Perfil}};
        {error, Razon} ->
            {error, Razon}
    end.

validar_campos([], _Cambios, Acc) ->
    {ok, Acc};
validar_campos([Campo | Resto], Cambios, Acc) ->
    case maps:get(Campo, Cambios, undefined) of
        undefined ->
            validar_campos(Resto, Cambios, Acc);
        Valor when is_integer(Valor), Valor >= 0, Valor =< 3600000 ->
            case Campo of
                feed_ms when Valor < 100 ->
                    {error, {valor_invalido, Campo}};
                _ ->
                    validar_campos(Resto, Cambios, Acc#{Campo => Valor})
            end;
        _ ->
            {error, {valor_invalido, Campo}}
    end.

publicar_ritmo(Ritmo, Perfil) ->
    application:set_env(?APP, perfil_simulacion, Perfil),
    lists:foreach(
      fun(Campo) ->
          application:set_env(?APP, Campo, maps:get(Campo, Ritmo))
      end,
      ?CAMPOS_RITMO),
    ok.

env_int(Clave, Defecto) ->
    case application:get_env(?APP, Clave, Defecto) of
        V when is_integer(V) -> V;
        _ -> Defecto
    end.

estado_simulacion(State) ->
    Ritmo = maps:get(ritmo, State),
    Ahora = monotonic_ms(),
    Ultimo = maps:get(ultimo_nuevo, State, Ahora),
    Cada = maps:get(nuevo_vuelo_cada_ms, Ritmo),
    Proximo = max(0, Cada - (Ahora - Ultimo)),
    Ritmo#{perfil => maps:get(perfil, State),
           pausado => maps:get(pausado, State),
           vuelos_vivos => length(vivos_operativos()),
           max_vuelos => tope_vuelos(),
           proximo_vuelo_ms => Proximo}.

feed_ms(State) ->
    maps:get(feed_ms, maps:get(ritmo, State)).

programar(State) ->
    Gen = maps:get(gen, State, 0) + 1,
    Timer = erlang:send_after(feed_ms(State), self(), {tick, Gen}),
    State#{timer => Timer, gen => Gen}.

cancelar_timer(#{timer := undefined} = State) ->
    State;
cancelar_timer(#{timer := Timer} = State) ->
    _ = erlang:cancel_timer(Timer),
    State#{timer => undefined}.

monotonic_ms() ->
    erlang:monotonic_time(millisecond).
