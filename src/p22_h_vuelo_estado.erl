%% ===================================================================
%% @doc p22_h_vuelo_estado — `POST /api/vuelos/:id/estado`.
%%
%% Cuerpo JSON: {"accion": "...", "fuente": "torre|aerolinea",
%%               "motivo": "...", "minutos": N,
%%               "puerta": "puerta_5"}
%% Aplica una transicion manual al vuelo (para demo y para que el
%% usuario "sea" la torre). Usa la MISMA maquina de estados que el feed.
%% ===================================================================
-module(p22_h_vuelo_estado).

-export([init/2]).

init(Req0, State) ->
    IdBin = cowboy_req:binding(id, Req0),
    Resp =
        case entero(IdBin) of
            {ok, Id} ->
                case leer_cuerpo(Req0) of
                    {ok, Mapa} -> aplicar(Id, Mapa);
                    error -> #{codigo => 400,
                               cuerpo => #{ok => false, error => <<"cuerpo JSON invalido">>}}
                end;
            _ ->
                #{codigo => 400, cuerpo => #{ok => false, error => <<"id invalido">>}}
        end,
    {ok, p22_http:json(Req0, maps:get(codigo, Resp), maps:get(cuerpo, Resp)), State}.

leer_cuerpo(Req0) ->
    p22_http:cuerpo_json(Req0).

aplicar(Id, Mapa) ->
    Accion = a_accion(maps:get(<<"accion">>, Mapa, undefined)),
    Fuente = a_fuente(maps:get(<<"fuente">>, Mapa, <<"torre">>)),
    case detalle(Mapa) of
        {error, puerta_invalida} ->
            #{codigo => 400,
              cuerpo => #{ok => false,
                          error => <<"puerta invalida (usa puerta_1..puerta_20)">>}};
        {ok, Detalle} ->
            case {Accion, Fuente} of
                {undefined, _} ->
                    #{codigo => 400,
                      cuerpo => #{ok => false,
                                  error => <<"falta \"accion\" valida">>}};
                {_, undefined} ->
                    #{codigo => 400,
                      cuerpo => #{ok => false,
                                  error => <<"fuente invalida (torre|aerolinea|sistema)">>}};
                _ ->
                    transicion(Id, Fuente, Accion, Detalle)
            end
    end.

transicion(Id, Fuente, Accion, Detalle) ->
    case p22_vuelo_statem:transicion(Id, Fuente, seq_nueva(), Accion, Detalle) of
        {ok, Hacia} ->
            #{codigo => 200,
              cuerpo => #{ok => true, vuelo => Id,
                          estado => atom_to_binary(Hacia, utf8)}};
        {error, {transicion_no_legal, Estado, _A}} ->
            #{codigo => 409,
              cuerpo =>
                  #{ok => false,
                    error =>
                        unicode:characters_to_binary(
                          io_lib:format("~ts no permite esa transicion",
                                        [atom_to_binary(Estado, utf8)]))}};
        {error, secuencia_repetida} ->
            #{codigo => 409,
              cuerpo => #{ok => false, error => <<"secuencia repetida">>}};
        {error, autoridad_insuficiente} ->
            #{codigo => 409,
              cuerpo => #{ok => false, error => <<"autoridad insuficiente">>}};
        {error, no_encontrado} ->
            #{codigo => 404,
              cuerpo => #{ok => false, error => <<"vuelo no encontrado">>}};
        {error, timeout} ->
            #{codigo => 503,
              cuerpo => #{ok => false, error => <<"vuelo ocupado, reintenta">>}};
        {error, puerta_invalida} ->
            #{codigo => 400,
              cuerpo => #{ok => false, error => <<"puerta invalida">>}};
        {error, sin_puerta} ->
            #{codigo => 409,
              cuerpo => #{ok => false,
                          error => <<"no hay puertas libres para reasignar">>}};
        {error, puerta_ocupada} ->
            #{codigo => 409,
              cuerpo => #{ok => false, error => <<"la puerta ya esta ocupada">>}};
        {error, {puerta_ocupada, Otro}} ->
            #{codigo => 409,
              cuerpo => #{ok => false,
                          error => <<"la puerta ya esta ocupada por otro vuelo">>,
                          vuelo_ocupante => Otro}};
        {error, Razon} ->
            #{codigo => 409,
              cuerpo => #{ok => false, error => a_bin(Razon)}}
    end.

detalle(Mapa) ->
    D0 = #{},
    D1 = case maps:get(<<"motivo">>, Mapa, undefined) of
             undefined -> D0;
             M -> D0#{motivo => M}
         end,
    D2 = case maps:get(<<"minutos">>, Mapa, undefined) of
             undefined -> D1;
             N when is_integer(N) -> D1#{minutos => N}
         end,
    D3 = case maps:get(<<"mensaje">>, Mapa, undefined) of
             undefined -> D2;
             Msg -> D2#{mensaje => Msg}
         end,
    case maps:get(<<"puerta">>, Mapa, undefined) of
        undefined -> {ok, D3};
        P when is_binary(P) ->
            case a_puerta(P) of
                {ok, Puerta} -> {ok, D3#{puerta => Puerta}};
                error -> {error, puerta_invalida}
            end;
        _ -> {error, puerta_invalida}
    end.

%% Solo atomos que YA existen y que ademas son puertas de ESTE
%% aeropuerto (p22_puertas las crea en su init).
a_puerta(B) ->
    try binary_to_existing_atom(B, utf8) of
        P ->
            try p22_puertas:es_puerta(P) of
                true -> {ok, P};
                false -> error
            catch _:_ -> error
            end
    catch _:_ -> error
    end.

seq_nueva() ->
    %% desde la API, la fuente "torre" ES el operador humano: una seq
    %% distinta cada vez (microsegundos) para no chocar con el dedupe.
    os:system_time(microsecond).

%% Solo atomos que YA existen en el sistema: `binary_to_atom/2' con
%% entrada del usuario permitiria agotar la tabla de atomos (fuga de
%% memoria) con acciones inventadas. Lo desconocido se rechaza.
a_accion(undefined) ->
    undefined;
a_accion(B) when is_binary(B) ->
    try binary_to_existing_atom(B, utf8)
    catch _:_ -> undefined
    end;
a_accion(A) when is_atom(A) ->
    A;
a_accion(_) ->
    undefined.

a_fuente(B) when is_binary(B) ->
    case a_accion(B) of
        torre -> torre;
        aerolinea -> aerolinea;
        sistema -> sistema;
        _ -> undefined
    end;
a_fuente(torre) -> torre;
a_fuente(aerolinea) -> aerolinea;
a_fuente(sistema) -> sistema;
a_fuente(_) -> undefined.

a_bin(B) when is_binary(B) -> B;
a_bin(I) when is_integer(I) -> integer_to_binary(I);
a_bin(A) when is_atom(A) -> atom_to_binary(A, utf8).

entero(Bin) when is_binary(Bin) ->
    try
        {ok, binary_to_integer(Bin)}
    catch
        _:_ -> error
    end;
entero(_) ->
    error.
