%% ===================================================================
%% @doc p22_vuelo_statem — UN gen_statem por vuelo (proyecto 22).
%%
%% Es el nucleo del dominio: cada vuelo del aeropuerto es UN proceso con
%% maquina de estados explicita, de modo que las transiciones ilegales
%% se rechazan por diseño y no por disciplina de codigo.
%%
%% Estados:  programado -> abordando -> despego -> aterrizado
%%           demorado: pausa de programado (demora senalada, vuelve a
%%                     programado o sigue hacia abordando)
%%           cancelado: terminal, desde cualquier estado no terminal
%%
%% Transiciones legales por estado ( tabla `legal/1` ):
%%   programado: empezar_abordaje | demorar | cancelar
%%   demorado:   empezar_abordaje | fin_demora | cancelar
%%   abordando:  despegar | cancelar
%%   despego:    aterrizar            (el vuelo ya salio: solo aterriza)
%%   aterrizado: (terminal: todo se rechaza con explicacion)
%%   cancelado:  (terminal: todo se rechaza con explicacion)
%%
%% Casos dificiles del problema resueltos aqui:
%%   1. Mensajes FUERA DE ORDEN (fuentes distintas): cada evento trae
%%      {Fuente, Seq}; si su Seq es menor o igual que la ultima vista
%%      de esa fuente, se IGNORA (dedupe por secuencia).
%%   2. Dos fuentes contradictorias: jerarquia de autoridad
%%      torre(3) > aerolinea(2) > sistema/feed(1). Un cambio con
%%      autoridad MENOR que la del estado vigente se ignora; la torre
%%      siempre manda. (Ver "preguntas guia" del problema.)
%%   3. Reinicio del sistema / prueba de caos: en init consulta
%%      `p22_respaldo`; si hay ultimo estado conocido, entra DIRECTO en
%%      ese estado con sus datos (puerta incluida). Tras un
%%      `exit(Pid, kill)` el tablero sigue mostrando "abordando":
%%      /api/vuelos y el resync del WebSocket leen del respaldo
%%      mientras el proceso esta entre reinicios.
%%
%% Efectos colaterales por transicion:
%%   empezar_abordaje -> asigna puerta; SIN puerta disponible -> demora
%%   despegar, cancelar -> libera la puerta (la pista queda libre)
%%   cancelar -> avisa al feed la aeronave para cancelar su vuelo de
%%               regreso (efecto cascada pedido en el problema)
%% ===================================================================
-module(p22_vuelo_statem).

-behaviour(gen_statem).

-export([start_link/1, estado/1, completo/1, transicion/4, transicion/5,
         consulta_raw/1, pid_de/1]).
-export([init/1, callback_mode/0, handle_event/4, terminate/3]).

-define(MOD, ?MODULE).

%% Jerarquia de autoridades de las fuentes de informacion.
autoridad(torre) -> 3;
autoridad(aerolinea) -> 2;
autoridad(sistema) -> 1;
autoridad(_) -> 0.

%% Tabla de transiciones legales por estado (referencia al doc arriba).
legal('programado') -> [empezar_abordaje, demorar, cambiar_puerta, cancelar];
legal('demorado') -> [empezar_abordaje, fin_demora, cambiar_puerta, cancelar];
legal('abordando') -> [despegar, cambiar_puerta, cancelar];
legal('despego') -> [aterrizar];
legal('aterrizado') -> [];
legal('cancelado') -> [].

%% --- API publica ---------------------------------------------------

%% @doc Arranca el vuelo. Lo llama el supervisor dinamico con [Spec].
start_link(Spec) ->
    Id = maps:get(id, Spec),
    gen_statem:start_link({local, nombre(Id)}, ?MODULE, Spec, []).

nombre(Id) ->
    list_to_atom("p22_vuelo_" ++ integer_to_list(Id)).

%% @doc Pid del proceso de un vuelo (undefined si no existe).
pid_de(Id) ->
    whereis(nombre(Id)).

%% Todas las consultas van con proteccion: si el vuelo no existe o
%% esta repartiendo (entre reinicios), devolvemos {'error', no_encontrado}
%% en vez de tumbar al que pregunta.
%%
%% El case de `whereis' NO basta: entre el whereis y el call el proceso
%% puede morir (justo lo que hace la prueba de caos), y gen_statem:call
%% saldria con `noproc' tumbando al handler HTTP o al feed. Por eso el
%% call va dentro de try/catch: el tablero lee del respaldo y no
%% parpadea.
llamar_seguro(Id, Mensaje) ->
    case pid_de(Id) of
        undefined ->
            {error, no_encontrado};
        _Pid ->
            try gen_statem:call(nombre(Id), Mensaje) of
                Respuesta -> Respuesta
            catch
                exit:{timeout, _} -> {error, timeout};
                exit:_ -> {error, no_encontrado}
            end
    end.

%% Solo el nombre del estado, para el tablero y las metricas.
estado(Id) ->
    case llamar_seguro(Id, estado) of
        Estado when is_atom(Estado) -> Estado;
        {'error', _} = Err -> Err
    end.

%% @doc Vista completa para API/tablero (con historial truncado).
completo(Id) ->
    llamar_seguro(Id, todo).

%% @doc Estado crudo: {Estado, Datos} (para pruebas).
consulta_raw(Id) ->
    llamar_seguro(Id, datos).

%% @doc Aplica una transicion con fuente y secuencia (fuera de orden ok).
%% Fuente: torre | aerolinea | sistema.  Seq: entero monotono por fuente.
transicion(Id, Fuente, Seq, Accion) ->
    transicion(Id, Fuente, Seq, Accion, #{}).

transicion(Id, Fuente, Seq, Accion, Detalle) ->
    llamar_seguro(Id, {transicion, {Fuente, Seq}, Accion, Detalle}).

%% --- arranque y callbacks ------------------------------------------

%% Callback unico con el estado como quarto parametro: cada vuelo es el
%% mismo modulo; la logica no se repite 6 veces.
callback_mode() ->
    [handle_event_function, state_enter].

init(Spec) ->
    Id = maps:get(id, Spec),
    Hora0 = maps:get(hora_programada, Spec, os:system_time(second) + 3600),
    Datos = Spec#{hora_programada => Hora0,
                  puerta => undefined,
                  demora_min => 0,
                  motivos => [],
                  hora_estimada => undefined,
                  fuentes_seq => #{},
                  autoridad_actual => 0,
                  fuente_ultima => arranque,
                  historial => [#{ts => os:system_time(second),
                                  desde => arranque,
                                  hacia => 'programado',
                                  detalle => <<"alta del vuelo">>}]},
    %% Resiliencia: ¿hay un ultimo estado conocido? -> entra directo en el
    %% (Estado, Datos) guardados. OJO: el estado de gen_statem DEBE ser el
    %% atomo de la maquina; antes merge_guardado devolvia solo el mapa de
    %% datos, el proceso arrancaba con un mapa como estado y CUALQUIER
    %% transicion fallaba: el vuelo entraba en bucle de reinicios.
    {Estado, Datos2} =
        case p22_respaldo:leer_vuelo(Id) of
            #{estado := EGuardado, datos := DatosGuardados} ->
                merge_guardado(Datos, DatosGuardados, EGuardado);
            no_encontrado ->
                p22_respaldo:guardar_vuelo(Id, 'programado', Datos),
                {'programado', Datos}
        end,
    logger:info("vuelo ~p en estado ~p", [Id, Estado]),
    {ok, Estado, Datos2}.

%% Mezcla los datos guardados en el respaldo sobre los de arranque y
%% valida que el guardado sea un estado de maquina conocida.
merge_guardado(DatosArranque, DatosGuardados, EGuardado) ->
    case maps:is_key(EGuardado, base_tabla()) of
        true ->
            {EGuardado,
             DatosArranque#{
               %% los datos de identidad viajan en la foto: al recuperar
               %% la VM el spec solo trae el id
               identificacion => maps:get(identificacion, DatosGuardados,
                                          maps:get(identificacion, DatosArranque, <<>>)),
               aeronave => maps:get(aeronave, DatosGuardados,
                                    maps:get(aeronave, DatosArranque, <<>>)),
               aerolinea => maps:get(aerolinea, DatosGuardados,
                                     maps:get(aerolinea, DatosArranque, <<>>)),
               destino => maps:get(destino, DatosGuardados,
                                   maps:get(destino, DatosArranque, <<>>)),
               origen => maps:get(origen, DatosGuardados, <<"TIJ">>),
               hora_programada => maps:get(hora_programada, DatosGuardados,
                                           maps:get(hora_programada, DatosArranque)),
               puerta => maps:get(puerta, DatosGuardados, undefined),
               demora_min => maps:get(demora_min, DatosGuardados, 0),
               motivos => maps:get(motivos, DatosGuardados, []),
               hora_estimada => maps:get(hora_estimada, DatosGuardados, undefined),
               fuentes_seq => maps:get(fuentes_seq, DatosGuardados, #{}),
               autoridad_actual => maps:get(autoridad_actual, DatosGuardados, 0),
               fuente_ultima => maps:get(fuente_ultima, DatosGuardados, arranque),
               historial => maps:get(historial, DatosGuardados, [])}};
        false ->
            %% estado corrupto: parte del ciclo normal, sin datos viejos
            {'programado', DatosArranque}
    end.

%% mini tabla para validar estados (los mismo que legal/1)
base_tabla() ->
    #{'programado' => 1, 'demorado' => 1, 'abordando' => 1,
      'despego' => 1, 'aterrizado' => 1, 'cancelado' => 1}.

%% Jamas hay estado a limpiar al morir el proceso: todo quedo en respaldo.
terminate(_Razon, _Estado, _Datos) ->
    ok.

%% --- ENTER por estado (callback modo state_enter) -------------------

handle_event(enter, Prev, _Estado, Datos) ->
    _ = Prev,
    {keep_state, Datos};

%% --- consultas (cualquier estado) -----------------------------------

handle_event({call, From}, estado, Estado, _Datos) ->
    {keep_state_and_data, [{reply, From, Estado}]};
handle_event({call, From}, datos, Estado, Datos) ->
    {keep_state_and_data, [{reply, From, {Estado, Datos}}]};
handle_event({call, From}, todo, Estado, Datos) ->
    {keep_state_and_data, [{reply, From, vista(Estado, Datos)}]};

%% --- transiciones (cualquier estado) --------------------------------

handle_event({call, From}, {transicion, {Fuente, Seq}, Accion, Detalle},
             Estado, Datos) ->
    %% 1. dedupe de mensajes fuera de orden (por fuente).
    %%    Las secuencias arrancan en 1, asi que 0 es SIEMPRE vieja.
    %%    Comparar contra 0 por defecto elimina el caso "primer mensaje
    %%    de una fuente con seq 0", que antes se colaba.
    FuentesSeq = maps:get(fuentes_seq, Datos, #{}),
    UltimaSeq = maps:get(Fuente, FuentesSeq, 0),
    if
        Seq =< UltimaSeq ->
            %% FUERA DE ORDEN: seq vieja o repetida de la misma fuente
            aviso(#{tipo => evento_ignorado, vuelo => maps:get(id, Datos),
                    razon => <<"secuencia_repetida">>, fuente => Fuente, seq => Seq}),
            {keep_state_and_data, [{reply, From, {error, secuencia_repetida}}]};
        true ->
            %% 2. jerarquía de fuentes: la torre prevalece (pregunta guia #2)
            case autoridad(Fuente) < maps:get(autoridad_actual, Datos, 0) of
                true ->
                    aviso(#{tipo => evento_ignorado, vuelo => maps:get(id, Datos),
                            razon => <<"autoridad_menor">>, fuente => Fuente,
                            accion => Accion}),
                    {keep_state_and_data,
                     [{reply, From, {error, autoridad_insuficiente}}]};
                false ->
                    %% 3. tabla de transiciones legales
                    case lists:member(Accion, legal(Estado)) of
                        true ->
                            aplicar({Fuente, Seq}, Accion, Detalle, From,
                                    Estado, Datos);
                        false ->
                            %% 4. transicion ilegal: rechazo con razón
                            aviso(#{tipo => transicion_rechazada,
                                    vuelo => maps:get(id, Datos),
                                    estado => Estado, accion => Accion,
                                    fuente => Fuente}),
                            {keep_state_and_data,
                             [{reply, From,
                               {error, {transicion_no_legal, Estado, Accion}}}]}
                    end
            end
    end;

handle_event(_Tipo, _Mensaje, _Estado, _Datos) ->
    %% cualquier otra cosa (cast, info, enter no tratado) se descarta
    {keep_state_and_data, []}.

%% --- aplicacion de transiciones -------------------------------------

%% Aplica la accion legal: efectos colaterales, nuevo estado, persistencia
%% y publicacion del evento en el bus (WebSocket + metricas).
aplicar({Fuente, Seq}, Accion, Detalle, From, Estado, Datos0) ->
    Id = maps:get(id, Datos0),
    Ts = os:system_time(second),
    %% --- efectos colaterales (pueden CAMBIAR al estado destino) ---
    case efecto(Accion, Detalle, Estado, Datos0) of
        {error, Razon} ->
            %% p.ej. la puerta pedida ya la ocupa otro vuelo: no se
            %% consume la secuencia y el vuelo queda intacto.
            {keep_state_and_data, [{reply, From, {error, Razon}}]};
        {Hacia, Datos1} ->
            %% --- historia y datos derivados ---
            Historial = [#{ts => Ts, desde => Estado, hacia => Hacia,
                           fuente => Fuente,
                           detalle => detalle_de(Accion, Detalle)}
                         | maps:get(historial, Datos0, [])],
            %% Se guarda la secuencia aplicada: sin esto el dedupe por fuente no
            %% recordaba nada y aceptaba mensajes repetidos/viejos.
            Datos2 = Datos1#{historial => lists:sublist(Historial, 50),
                             autoridad_actual => autoridad(Fuente),
                             fuente_ultima => Fuente,
                             fuentes_seq =>
                                 (maps:get(fuentes_seq, Datos1, #{}))#{Fuente => Seq}},
            %% --- persistencia ANTES de publicar: si matan el proceso ahora
            %%     mismo, la proxima init arranca en el ultimo estado valido ---
            p22_respaldo:guardar_vuelo(Id, Hacia, Datos2),
            aviso(evento_de(Accion, Fuente, Seq, Estado, Hacia,
                            Detalle, Datos0, Datos2)),
            {next_state, Hacia, Datos2, [{reply, From, {ok, Hacia}}]}
    end.

%% Evento al bus. El cambio de puerta usa su propio tipo para que el
%% tablero no lo confunda con un cambio de estado (el estado se conserva).
evento_de(cambiar_puerta, Fuente, Seq, Estado, Hacia, Detalle, Datos0, Datos2) ->
    #{tipo => cambio_puerta, vuelo => maps:get(id, Datos2),
      desde => Estado, hacia => Hacia, fuente => Fuente, seq => Seq,
      puerta_anterior => maps:get(puerta, Datos0, undefined),
      puerta_nueva => maps:get(puerta, Datos2, undefined),
      hora_anterior => maps:get(hora_estimada, Datos0, undefined),
      hora_nueva => maps:get(hora_estimada, Datos2, undefined),
      demora_min => maps:get(demora_min, Datos2, 0),
      motivos => maps:get(motivos, Datos2, []),
      motivo => maps:get(motivo, Detalle, undefined),
      identificacion => maps:get(identificacion, Datos2, <<>>)};
evento_de(_Accion, Fuente, Seq, Estado, Hacia, Detalle, _Datos0, Datos2) ->
    #{tipo => cambio_estado, vuelo => maps:get(id, Datos2),
      desde => Estado, hacia => Hacia, fuente => Fuente, seq => Seq,
      puerta => maps:get(puerta, Datos2, undefined),
      demora_min => maps:get(demora_min, Datos2, 0),
      hora_estimada => maps:get(hora_estimada, Datos2, undefined),
      motivos => maps:get(motivos, Datos2, []),
      motivo => maps:get(motivo, Detalle, undefined),
      identificacion => maps:get(identificacion, Datos2, <<>>),
      aeronave => maps:get(aeronave, Datos2, <<>>),
      destino => maps:get(destino, Datos2, <<>>)}.

%% Efectos por tipo de accion; devuelve {Hacia, Datos} o {error, Razon}.
efecto(empezar_abordaje, _D, _Estado, Datos) ->
    Id = maps:get(id, Datos),
    case maps:get(puerta, Datos, undefined) of
        undefined ->
            case p22_puertas:asignar(Id) of
                {ok, Puerta} ->
                    {'abordando', Datos#{puerta => Puerta}};
                {error, no_disponible} ->
                    %% Sin puerta: el aeropuerto no puede abordar. La operacion
                    %% manda la demora ACTIVA (+15 min) y se publica alerta.
                    aviso(#{tipo => alerta, vuelo => Id,
                            mensaje => <<"sin puertas disponibles: demora automatica">>}),
                    demora(Datos, 15, <<"sin_puerta">>)
            end;
        _Puerta ->
            %% Ya tenia puerta (cambio de puerta previo): no pedir otra.
            {'abordando', Datos}
    end;
efecto(cambiar_puerta, Detalle, Estado, Datos) ->
    Id = maps:get(id, Datos),
    Vieja = maps:get(puerta, Datos, undefined),
    case puerta_destino(Detalle, Id, Vieja) of
        {error, Razon} ->
            {error, Razon};
        {ok, Nueva} ->
            %% Primero se toma la nueva y solo despues se suelta la vieja:
            %% si la nueva esta ocupada, el vuelo conserva la que tenia.
            Datos1 =
                case Vieja =/= undefined andalso Vieja =/= Nueva of
                    true ->
                        _ = p22_puertas:liberar(Vieja, Id),
                        Datos#{puerta => Nueva};
                    false ->
                        Datos#{puerta => Nueva}
                end,
            Min = maps:get(minutos, Detalle, 0),
            Motivo = maps:get(motivo, Detalle, <<"cambio de puerta">>),
            Datos2 =
                case Min > 0 of
                    true -> demora_datos(Datos1, Min, Motivo);
                    false -> Datos1
                end,
            %% El estado NO cambia: el vuelo sigue donde estaba; cambia
            %% la puerta y, si hay minutos, la hora estimada.
            {Estado, Datos2}
    end;
efecto(despegar, _D, _Estado, Datos) ->
    _ = p22_puertas:liberar(maps:get(id, Datos)),
    {'despego', Datos#{puerta => undefined}};
efecto(aterrizar, _D, _Estado, Datos) ->
    {'aterrizado', Datos};
efecto(demorar, Detalle, _Estado, Datos) ->
    Min = maps:get(minutos, Detalle, 20),
    Motivo = maps:get(motivo, Detalle, <<"causa operativa">>),
    demora(Datos, Min, Motivo);
efecto(fin_demora, _D, _Estado, Datos) ->
    {'programado', Datos#{hora_estimada => undefined}};
efecto(cancelar, Detalle, _Estado, Datos) ->
    Id = maps:get(id, Datos),
    _ = p22_puertas:liberar(Id),
    Motivo = maps:get(motivo, Detalle, <<"operativa">>),
    %% Efecto cascada (caso dificil del problema): la misma aeronave ya
    %% no llega al siguiente vuelo — el feed cancela su regreso.
    %% (Si el feed no corre, no pasa nada: the mensaje se omite.)
    case whereis(p22_feed) of
        undefined -> ok;
        FeedPid -> FeedPid ! {aeronave_cancelada, Id,
                              maps:get(aeronave, Datos, <<>>), Motivo}
    end,
    {'cancelado', Datos#{motivos =>
                           [Motivo | maps:get(motivos, Datos, [])],
                         puerta => undefined}}.

%% Construye el estado 'demorado' con los minutos y motivo correctos.
demora(Datos, Min, Motivo) ->
    {'demorado', demora_datos(Datos, Min, Motivo)}.

%% Aplica la demora a los datos SIN cambiar de estado (lo usa el
%% cambio de puerta, que conserva el estado actual).
demora_datos(Datos, Min, Motivo) ->
    Minutos = maps:get(demora_min, Datos, 0) + Min,
    Datos#{demora_min => Minutos,
           hora_estimada => maps:get(hora_programada, Datos) + Minutos * 60,
           motivos => [Motivo | maps:get(motivos, Datos, [])]}.

%% Puerta destino del cambio: la pedida, la actual si no se pide otra,
%% o una libre si el vuelo aun no tenia.
puerta_destino(Detalle, Id, Vieja) ->
    case maps:get(puerta, Detalle, undefined) of
        undefined when Vieja =/= undefined ->
            {ok, Vieja};
        undefined ->
            case p22_puertas:asignar(Id) of
                {ok, Puerta} -> {ok, Puerta};
                {error, no_disponible} -> {error, sin_puerta}
            end;
        Puerta ->
            p22_puertas:asignar(Puerta, Id)
    end.

%% Vista "completa" que consume la API y el detalle del tablero.
vista(Estado, Datos) ->
    #{estado => Estado,
      id => maps:get(id, Datos),
      identificacion => maps:get(identificacion, Datos, <<>>),
      aeronave => maps:get(aeronave, Datos, <<>>),
      aerolinea => maps:get(aerolinea, Datos, <<>>),
      destino => maps:get(destino, Datos, <<>>),
      puerta => maps:get(puerta, Datos, undefined),
      hora_programada => maps:get(hora_programada, Datos),
      hora_estimada => maps:get(hora_estimada, Datos, undefined),
      demora_min => maps:get(demora_min, Datos, 0),
      motivos => maps:get(motivos, Datos, []),
      fuente_ultima => maps:get(fuente_ultima, Datos, arranque),
      autoridad => maps:get(autoridad_actual, Datos, 0),
      historial => maps:get(historial, Datos, [])}.

%% Publica + persiste NO aqui: aviso ES SOLO publicar al bus.
aviso(Evento) ->
    p22_eventos:publicar(Evento).

detalle_de(cambiar_puerta, Detalle) ->
    Min = maps:get(minutos, Detalle, 0),
    P = maps:get(puerta, Detalle, <<"libre">>),
    unicode:characters_to_binary(
      io_lib:format("cambio de puerta a ~ts (+~p min)", [a_texto(P), Min]));
detalle_de(demorar, Detalle) ->
    Min = maps:get(minutos, Detalle, 20),
    Motivo = a_texto(maps:get(motivo, Detalle, <<"causa operativa">>)),
    unicode:characters_to_binary(
      io_lib:format("demora ~p min: ~ts", [Min, Motivo]));
detalle_de(Accion, Detalle) ->
    case maps:get(mensaje, Detalle, undefined) of
        undefined -> atom_to_binary(Accion, utf8);
        Msg -> a_texto(Msg)
    end.

a_texto(A) when is_binary(A) -> A;
a_texto(A) when is_atom(A) -> atom_to_binary(A, utf8);
a_texto(I) when is_integer(I) -> integer_to_binary(I).
