%% ===================================================================
%% @doc p22_h_vuelo — handler de `GET /api/vuelos/:id`.
%% Devuelve el detalle completo del vuelo: datos, puerta, demoras,
%% motivos e historial de cambios de estado (bitacora).
%% ===================================================================
-module(p22_h_vuelo).

-export([init/2]).

init(Req0, State) ->
    IdBin = cowboy_req:binding(id, Req0),
    Resp =
        case entero(IdBin) of
            {ok, Id} ->
                case p22_vuelo_statem:completo(Id) of
                    {error, no_encontrado} ->
                        #{codigo => 404,
                          cuerpo => #{ok => false, error => <<"vuelo no encontrado">>,
                                      id => Id}};
                    {error, timeout} ->
                        #{codigo => 503,
                          cuerpo => #{ok => false, error => <<"vuelo ocupado, reintenta">>,
                                      id => Id}};
                    Vista ->
                        #{codigo => 200, cuerpo => Vista#{ok => true}}
                end;
            _ ->
                #{codigo => 400, cuerpo => #{ok => false, error => <<"id invalido">>}}
        end,
    {ok, p22_http:json(Req0, maps:get(codigo, Resp), maps:get(cuerpo, Resp)), State}.

entero(Bin) when is_binary(Bin) ->
    try
        {ok, binary_to_integer(Bin)}
    catch
        _:_ -> error
    end;
entero(_) ->
    error.
