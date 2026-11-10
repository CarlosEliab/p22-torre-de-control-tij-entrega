%% ===================================================================
%% @doc p22_puertas — gen_server asignador de puertas del aeropuerto.
%%
%% Recurso critico de un digito finito: el escenario habla de puertas
%% limitadas (configurable en sys.config, default 20). Reglas:
%%   - asignar puertas solo a vuelos que van a ABORDAR;
%%   - asignar una puerta CONCRETA cuando la torre la cambia;
%%   - liberar en despegue, cancelacion o cambio de puerta;
%%   - si no hay puerta disponible, el vuelo entra en DEMORADO con
%%     motivo "sin_puerta" (+15 min estimados), tal como se pide en
%%     los casos dificiles.
%%
%% Reconstruccion: si el proceso muere (y su supervisor lo re-crea),
%% lee la ocupacion persistida en p22_respaldo, asi que las puertas
%% siguen ligadas a los vuelos que las tenian.
%% ===================================================================
-module(p22_puertas).

-behaviour(gen_server).

-export([start_link/0, asignar/1, asignar/2, liberar/1, liberar/2,
         es_puerta/1, disponibles/0, ocupadas/0, estado_completo/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Asigna una puerta libre al vuelo Id. Devuelve {ok, Puerta} o
%% {error, no_disponible}.
asignar(IdVuelo) ->
    gen_server:call(?MODULE, {asignar, IdVuelo}).

%% @doc Asigna una puerta CONCRETA al vuelo IdVuelo. Es la operacion
%% que usa el cambio de puerta: valida que exista y que este libre (o
%% que ya sea suya). Devuelve {ok, Puerta} o {error, Razon}.
asignar(Puerta, IdVuelo) ->
    gen_server:call(?MODULE, {asignar_en, Puerta, IdVuelo}).

%% @doc Libera la puerta de un vuelo (despegue o cancelacion).
liberar(IdVuelo) ->
    gen_server:call(?MODULE, {liberar, IdVuelo}).

%% @doc Libera la puerta indicada SOLO si pertenece a IdVuelo. Se usa
%% al cambiar de puerta para no soltar la nueva por error.
liberar(Puerta, IdVuelo) ->
    gen_server:call(?MODULE, {liberar_en, Puerta, IdVuelo}).

%% @doc true si la puerta existe en este aeropuerto.
es_puerta(Puerta) ->
    gen_server:call(?MODULE, {es_puerta, Puerta}).

%% @doc Lista de puertas libres (atomos).
disponibles() ->
    gen_server:call(?MODULE, disponibles).

%% @doc Mapa puerta -> id de vuelo.
ocupadas() ->
    maps:from_list(p22_respaldo:puertas_ocupadas()).

%% @doc Mapa completo para la API: {libres, ocupadas, total}.
estado_completo() ->
    gen_server:call(?MODULE, estado_completo).

%% --- gen_server ----------------------------------------------------

init([]) ->
    Total = application:get_env(p22_torre_de_control_tij, puertas_total, 20),
    Puertas = [list_to_atom("puerta_" ++ integer_to_list(I)) || I <- lists:seq(1, Total)],
    %% Re-hidratacion desde el respaldo (tras caida de este proceso).
    Ocupadas0 = maps:from_list(p22_respaldo:puertas_ocupadas()),
    Ocupadas = maps:with(Puertas, Ocupadas0),
    logger:info("~s listo con ~p puertas (~p ya ocupadas)",
                [?MODULE, Total, maps:size(Ocupadas)]),
    {ok, #{puertas => Puertas, ocupadas => Ocupadas}}.

handle_call({asignar, IdVuelo}, _From,
            #{puertas := Puertas, ocupadas := Ocup} = State) ->
    case puerta_libre(Puertas, Ocup) of
        {ok, Puerta} ->
            case p22_respaldo:tomar_puerta(Puerta, IdVuelo) of
                ok ->
                    NuevaOcup = Ocup#{Puerta => IdVuelo},
                    p22_eventos:publicar(#{tipo => puerta_asignada,
                                           vuelo => IdVuelo, puerta => Puerta}),
                    {reply, {ok, Puerta}, State#{ocupadas := NuevaOcup}};
                {error, ocupada} ->
                    %% carrera defensiva: reintenta con la siguiente
                    case puerta_libre(Puertas, Ocup) of
                        {ok, Otra} ->
                            p22_respaldo:tomar_puerta(Otra, IdVuelo),
                            p22_eventos:publicar(#{tipo => puerta_asignada,
                                                   vuelo => IdVuelo, puerta => Otra}),
                            {reply, {ok, Otra},
                             State#{ocupadas := Ocup#{Otra => IdVuelo}}};
                        _ ->
                            {reply, {error, no_disponible}, State}
                    end
            end;
        _ ->
            {reply, {error, no_disponible}, State}
    end;

handle_call({asignar_en, Puerta, IdVuelo}, _From,
            #{puertas := Puertas, ocupadas := Ocup} = State) ->
    case lists:member(Puerta, Puertas) of
        false ->
            {reply, {error, puerta_invalida}, State};
        true ->
            case maps:get(Puerta, Ocup, undefined) of
                IdVuelo ->
                    %% ya es suya: idempotente (cambiar solo la hora)
                    {reply, {ok, Puerta}, State};
                undefined ->
                    case p22_respaldo:tomar_puerta(Puerta, IdVuelo) of
                        ok ->
                            p22_eventos:publicar(#{tipo => puerta_asignada,
                                                   vuelo => IdVuelo,
                                                   puerta => Puerta}),
                            {reply, {ok, Puerta},
                             State#{ocupadas := Ocup#{Puerta => IdVuelo}}};
                        {error, ocupada} ->
                            {reply, {error, puerta_ocupada}, State}
                    end;
                Otro ->
                    {reply, {error, {puerta_ocupada, Otro}}, State}
            end
    end;

handle_call({liberar, IdVuelo}, _From, #{ocupadas := Ocup} = State) ->
    {Puerta, NuevaOcup} = liberar_por_idvuelo(IdVuelo, Ocup),
    case Puerta of
        no_hay ->
            {reply, {error, sin_puerta}, State};
        _ ->
            p22_respaldo:soltar_puerta(Puerta),
            p22_eventos:publicar(#{tipo => puerta_liberada,
                                   vuelo => IdVuelo, puerta => Puerta}),
            {reply, {ok, Puerta}, State#{ocupadas := NuevaOcup}}
    end;

handle_call({liberar_en, Puerta, IdVuelo}, _From, #{ocupadas := Ocup} = State) ->
    case maps:get(Puerta, Ocup, undefined) of
        IdVuelo ->
            p22_respaldo:soltar_puerta(Puerta),
            p22_eventos:publicar(#{tipo => puerta_liberada,
                                   vuelo => IdVuelo, puerta => Puerta}),
            {reply, {ok, Puerta}, State#{ocupadas := maps:remove(Puerta, Ocup)}};
        _ ->
            {reply, {error, no_es_tuya}, State}
    end;

handle_call({es_puerta, Puerta}, _From, #{puertas := Puertas} = State) ->
    {reply, lists:member(Puerta, Puertas), State};

handle_call(disponibles, _From, #{puertas := Puertas, ocupadas := Ocup} = State) ->
    {reply, Puertas -- maps:keys(Ocup), State};

handle_call(estado_completo, _From, #{puertas := Puertas, ocupadas := Ocup} = State) ->
    {reply,
     #{total => length(Puertas),
       libres => Puertas -- maps:keys(Ocup),
       ocupadas => maps:to_list(Ocup)},
     State};

handle_call(_Otro, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

%% --- interno -------------------------------------------------------

puerta_libre(Puertas, Ocup) ->
    case Puertas -- maps:keys(Ocup) of
        [] -> {error, no_disponible};
        [Libre | _] -> {ok, Libre}
    end.

liberar_por_idvuelo(IdVuelo, Ocup) ->
    maps:fold(
      fun(Puerta, Id, Acc) ->
         if
             Id =:= IdVuelo andalso element(1, Acc) =:= no_hay ->
                 {Puerta, maps:remove(Puerta, Ocup)};
             true ->
                 Acc
         end
      end,
      {no_hay, Ocup},
      Ocup).
